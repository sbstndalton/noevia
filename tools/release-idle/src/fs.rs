use crate::strict::Result;
use rustix::fs::{mkdirat, openat, statat, AtFlags, Dir, Mode, OFlags, CWD};
use sha2::{Digest, Sha256};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    os::unix::fs::MetadataExt,
    path::{Component, Path},
};
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Identity {
    dev: u64,
    ino: u64,
    mode: u32,
    size: u64,
    links: u64,
    uid: u32,
    modified: (i64, i64),
    changed: (i64, i64),
}
pub fn identity(f: &File) -> Result<Identity> {
    let m = f.metadata().map_err(|_| "stat-error")?;
    Ok(Identity {
        dev: m.dev(),
        ino: m.ino(),
        mode: m.mode(),
        size: m.len(),
        links: m.nlink(),
        uid: m.uid(),
        modified: (m.mtime(), m.mtime_nsec()),
        changed: (m.ctime(), m.ctime_nsec()),
    })
}
#[allow(clippy::unnecessary_cast)] // Stat field widths differ on macOS and Linux.
fn entry(parent: &File, name: &str) -> Result<Identity> {
    let s = statat(parent, name, AtFlags::SYMLINK_NOFOLLOW).map_err(|_| "entry-stat-error")?;
    Ok(Identity {
        dev: stat_dev(s.st_dev),
        ino: s.st_ino,
        mode: s.st_mode as u32,
        size: u64::try_from(s.st_size).map_err(|_| "size-invalid")?,
        links: s.st_nlink as u64,
        uid: s.st_uid,
        modified: (s.st_mtime as i64, s.st_mtime_nsec as i64),
        changed: (s.st_ctime as i64, s.st_ctime_nsec as i64),
    })
}
#[cfg(target_os = "macos")]
fn stat_dev(d: i32) -> u64 {
    u64::from(d as u32)
}
#[cfg(not(target_os = "macos"))]
fn stat_dev(d: u64) -> u64 {
    d
}
pub fn size(m: &Identity) -> u64 {
    m.size
}
fn same_directory(a: &Identity, b: &Identity) -> bool {
    a.dev == b.dev && a.ino == b.ino && a.mode == b.mode && a.uid == b.uid
}
fn directory(m: &Identity) -> bool {
    m.mode & 0o170000 == 0o040000
}
fn regular(m: &Identity) -> bool {
    m.mode & 0o170000 == 0o100000 && m.links == 1
}
fn flags(dir: bool) -> OFlags {
    OFlags::RDONLY
        | OFlags::CLOEXEC
        | OFlags::NOFOLLOW
        | OFlags::NONBLOCK
        | if dir {
            OFlags::DIRECTORY
        } else {
            OFlags::empty()
        }
}
pub struct Edge {
    parent: File,
    name: String,
    id: Identity,
}
pub struct Tree {
    pub root: File,
    edges: Vec<Edge>,
    lists: Vec<(File, BTreeMap<String, Identity>, usize)>,
}
impl Tree {
    pub fn open(path: &Path) -> Result<Self> {
        if !path.is_absolute() {
            return Err("path-absolute");
        }
        let mut current =
            File::from(openat(CWD, "/", flags(true), Mode::empty()).map_err(|_| "ancestor-open")?);
        let mut edges = Vec::new();
        for c in path.components() {
            match c {
                Component::RootDir => {}
                Component::Normal(n) => {
                    let name = n.to_str().ok_or("path-encoding")?;
                    let child = File::from(
                        openat(&current, name, flags(true), Mode::empty())
                            .map_err(|_| "ancestor-open")?,
                    );
                    let id = identity(&child)?;
                    if !directory(&id) || entry(&current, name)? != id {
                        return Err("ancestor-changed");
                    }
                    edges.push(Edge {
                        parent: current,
                        name: name.into(),
                        id,
                    });
                    current = child;
                }
                _ => return Err("path-component"),
            }
        }
        Ok(Self {
            root: current,
            edges,
            lists: Vec::new(),
        })
    }
    pub fn child(
        &mut self,
        parent: &File,
        name: &str,
        dir: bool,
        optional: bool,
    ) -> Result<Option<File>> {
        match openat(parent, name, flags(dir), Mode::empty()) {
            Ok(fd) => {
                let f = File::from(fd);
                let m = identity(&f)?;
                if (dir && !directory(&m)) || (!dir && !regular(&m)) || entry(parent, name)? != m {
                    return Err("entry-type-or-changed");
                }
                self.edges.push(Edge {
                    parent: parent.try_clone().map_err(|_| "fd-clone")?,
                    name: name.into(),
                    id: m,
                });
                Ok(Some(f))
            }
            Err(rustix::io::Errno::NOENT) if optional => {
                self.lists.push((
                    parent.try_clone().map_err(|_| "fd-clone")?,
                    listing(parent, 16384)?,
                    16384,
                ));
                Ok(None)
            }
            Err(_) => Err("entry-open-error"),
        }
    }
    pub fn enumerate(&mut self, dir: &File, cap: usize) -> Result<BTreeMap<String, Identity>> {
        let map = listing(dir, cap)?;
        self.lists
            .push((dir.try_clone().map_err(|_| "fd-clone")?, map.clone(), cap));
        Ok(map)
    }
    pub fn contains_directory(&self, other: &File) -> Result<bool> {
        let m = identity(other)?;
        let root = identity(&self.root)?;
        Ok((root.dev == m.dev && root.ino == m.ino)
            || self
                .edges
                .iter()
                .any(|e| directory(&e.id) && e.id.dev == m.dev && e.id.ino == m.ino))
    }
    pub fn stable(&self) -> Result<()> {
        for e in &self.edges {
            let now = entry(&e.parent, &e.name)?;
            if if directory(&e.id) {
                !same_directory(&now, &e.id)
            } else {
                now != e.id
            } {
                return Err("identity-changed");
            }
        }
        for (f, map, cap) in &self.lists {
            if &listing(f, *cap)? != map {
                return Err("namespace-changed");
            }
        }
        Ok(())
    }
}
fn listing(f: &File, cap: usize) -> Result<BTreeMap<String, Identity>> {
    let before = identity(f)?;
    let mut d = Dir::read_from(f).map_err(|_| "directory-open")?;
    let mut out = BTreeMap::new();
    while let Some(e) = d.read() {
        let e = e.map_err(|_| "directory-read")?;
        let n = e.file_name().to_str().map_err(|_| "entry-encoding")?;
        if n == "." || n == ".." {
            continue;
        }
        if out.len() >= cap {
            return Err("directory-cap");
        }
        if out.insert(n.into(), entry(f, n)?).is_some() {
            return Err("directory-duplicate");
        }
    }
    if before != identity(f)? {
        return Err("directory-changed");
    }
    Ok(out)
}
pub fn bytes(f: &mut File, cap: usize) -> Result<Vec<u8>> {
    let before = identity(f)?;
    if !regular(&before) || before.size > cap as u64 {
        return Err("file-type-or-cap");
    }
    let mut out = Vec::new();
    f.take(cap as u64 + 1)
        .read_to_end(&mut out)
        .map_err(|_| "file-read")?;
    if out.len() > cap || out.len() as u64 != before.size || before != identity(f)? {
        return Err("file-changed-or-cap");
    }
    Ok(out)
}
pub fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
struct BoundSnapshot {
    tree: Tree,
    files: Vec<(File, usize, String, String)>,
}
pub struct Evidence {
    pub tree: Tree,
    pub dir: File,
    snapshots: RefCell<Vec<BoundSnapshot>>,
    node_hash: RefCell<Option<String>>,
}
impl Evidence {
    pub fn create(path: &Path) -> Result<Self> {
        let parent = path.parent().ok_or("evidence-path")?;
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .ok_or("evidence-path")?;
        let mut tree = Tree::open(parent)?;
        mkdirat(&tree.root, name, Mode::from_bits_truncate(0o700))
            .map_err(|_| "evidence-create")?;
        let parentfd = tree.root.try_clone().map_err(|_| "fd-clone")?;
        let dir = tree
            .child(&parentfd, name, true, false)?
            .ok_or("evidence-open")?;
        let m = identity(&dir)?;
        if m.mode & 0o777 != 0o700 {
            return Err("evidence-mode");
        }
        Ok(Self {
            tree,
            dir,
            snapshots: RefCell::new(Vec::new()),
            node_hash: RefCell::new(None),
        })
    }
    pub fn set_node_digest(&self, hash: String) {
        *self.node_hash.borrow_mut() = Some(hash);
    }
    pub fn node_digest(&self) -> Option<String> {
        self.node_hash.borrow().clone()
    }
    pub fn bind(&self, name: &str, expected: Vec<(String, String, usize)>) -> Result<()> {
        let mut tree = Tree {
            root: self.dir.try_clone().map_err(|_| "fd-clone")?,
            edges: Vec::new(),
            lists: Vec::new(),
        };
        let parent = tree.root.try_clone().map_err(|_| "fd-clone")?;
        let root = tree
            .child(&parent, name, true, false)?
            .ok_or("snapshot-missing")?;
        let mut expected: BTreeMap<String, (String, usize)> =
            expected.into_iter().map(|(p, h, n)| (p, (h, n))).collect();
        let mut files = Vec::new();
        bind_dir(&mut tree, &root, "", &mut expected, &mut files, 0)?;
        if !expected.is_empty() {
            return Err("snapshot-missing");
        }
        tree.stable()?;
        let mut registered = Vec::new();
        for (file, size, hash, path) in &files {
            registered.push(serde_json::json!({"relativePath":path,"size":size,"sha256":hash,"identity":metadata(&identity(file)?)}));
        }
        let record=serde_json::json!({"subtree":name,"files":registered,"directoryIdentity":metadata(&identity(&root)?)}).to_string();
        let cap = if name == "runtime" { 4096 } else { 1024 };
        if record.len() > cap {
            return Err("snapshot-record-cap");
        }
        Self::write(
            &self.dir,
            &format!("snapshot-{name}.json"),
            record.as_bytes(),
        )?;
        self.snapshots
            .borrow_mut()
            .push(BoundSnapshot { tree, files });
        Ok(())
    }
    pub fn verify_snapshots(&self) -> Result<()> {
        for snapshot in self.snapshots.borrow_mut().iter_mut() {
            snapshot.tree.stable()?;
            for (file, size, hash, _) in &mut snapshot.files {
                file.seek(SeekFrom::Start(0)).map_err(|_| "snapshot-seek")?;
                let raw = bytes(file, *size)?;
                if raw.len() != *size || digest(&raw) != *hash {
                    return Err("snapshot-digest");
                }
            }
            snapshot.tree.stable()?;
        }
        Ok(())
    }
    pub fn subdir(parent: &File, name: &str) -> Result<File> {
        mkdirat(parent, name, Mode::from_bits_truncate(0o700)).map_err(|_| "evidence-create")?;
        Ok(File::from(
            openat(parent, name, flags(true), Mode::empty()).map_err(|_| "evidence-open")?,
        ))
    }
    pub fn write(parent: &File, name: &str, bytes: &[u8]) -> Result<()> {
        let mut f = File::from(
            openat(
                parent,
                name,
                OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL | OFlags::CLOEXEC | OFlags::NOFOLLOW,
                Mode::from_bits_truncate(0o600),
            )
            .map_err(|_| "evidence-file-create")?,
        );
        rustix::fs::fchmod(&f, Mode::from_bits_truncate(0o600)).map_err(|_| "evidence-mode")?;
        f.write_all(bytes).map_err(|_| "evidence-write")?;
        f.sync_all().map_err(|_| "evidence-sync")?;
        if !regular(&identity(&f)?) {
            return Err("evidence-file-type");
        }
        Ok(())
    }
}
pub fn is_dir(m: &Identity) -> bool {
    directory(m)
}
pub fn metadata(m: &Identity) -> String {
    format!("{m:?}")
}

fn bind_dir(
    tree: &mut Tree,
    parent: &File,
    prefix: &str,
    expected: &mut BTreeMap<String, (String, usize)>,
    files: &mut Vec<(File, usize, String, String)>,
    depth: usize,
) -> Result<()> {
    if depth > 2 {
        return Err("snapshot-depth");
    }
    let list = tree.enumerate(parent, 8)?;
    if identity(parent)?.mode & 0o777 != 0o700 {
        return Err("snapshot-directory-mode");
    }
    for (name, meta) in list {
        let path = format!("{prefix}{name}");
        if is_dir(&meta) {
            if !expected.keys().any(|k| k.starts_with(&format!("{path}/"))) {
                return Err("snapshot-extra");
            }
            let dir = tree
                .child(parent, &name, true, false)?
                .ok_or("snapshot-missing")?;
            bind_dir(tree, &dir, &format!("{path}/"), expected, files, depth + 1)?;
        } else {
            let (hash, size) = expected.remove(&path).ok_or("snapshot-extra")?;
            let mut file = tree
                .child(parent, &name, false, false)?
                .ok_or("snapshot-missing")?;
            if identity(&file)?.mode & 0o777 != 0o600 {
                return Err("snapshot-file-mode");
            }
            let raw = bytes(&mut file, size)?;
            if raw.len() != size || digest(&raw) != hash {
                return Err("snapshot-digest");
            }
            files.push((file, size, hash, path));
        }
    }
    Ok(())
}
