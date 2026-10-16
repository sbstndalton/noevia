#![forbid(unsafe_code)]
mod capture;
mod delegate;
mod fs;
mod strict;
use fs::{Evidence, Tree};
use sha1::{Digest, Sha1};
use std::{
    collections::BTreeSet,
    fs::File,
    path::PathBuf,
    time::{Duration, Instant},
};
use strict::Result;
const CORE: &str = "010735c7d86d30269ab3f4a351b2135faea1c8e7";
const WASM: &str = "040738a438de8241bd2cd1558f2b06beaa32c5c9be01c30f09cd87cb2e978575";
const MODULES: &[(&str, &str)] = &[
    ("jobs.cjs", "6ed9cdf7db471e3283debaf14d6734eb5f37008d"),
    ("code-plan.cjs", "503ca1330ce946fc9d1421945625e9a63ea012fe"),
    (
        "code-review-verdict.cjs",
        "0984d58654a768652ffaf6a0a88c4657989fface",
    ),
    (
        "completeness-report.cjs",
        "6b7c810f1036f506a00aa32c49dc2f8d4b5c52fc",
    ),
    (
        "task-lifecycle.cjs",
        "28b252815d17a8fde7feb1eb9e43259651dea7a4",
    ),
    (
        "dav-parse-wasm.cjs",
        "2be1cf13d517b98802aa9a3e2604835bfc7da27a",
    ),
    ("dav-parse.lock", "8ccfdb382e6d026de8215f957a438fcbb86c92ab"),
];
struct Args {
    data: PathBuf,
    evidence: PathBuf,
    source: PathBuf,
    node: PathBuf,
    node_hash: String,
}
fn args() -> Result<Args> {
    let mut a = std::env::args().skip(1);
    if a.next().as_deref() != Some("inspect") {
        return Err("arguments");
    }
    let mut options = std::collections::BTreeMap::new();
    while let Some(k) = a.next() {
        let v = a.next().ok_or("arguments")?;
        if options.insert(k, v).is_some() {
            return Err("arguments");
        }
    }
    if options.len() != 6 || options.get("--expected-core").map(String::as_str) != Some(CORE) {
        return Err("arguments");
    }
    let mut take = |k| options.remove(k).ok_or("arguments");
    let data = PathBuf::from(take("--data-root")?);
    let evidence = PathBuf::from(take("--evidence-dir")?);
    let source = PathBuf::from(take("--source-root")?);
    let node = PathBuf::from(take("--node")?);
    let node_hash = take("--node-sha256")?;
    if [&data, &evidence, &source, &node].iter().any(|p| {
        !p.is_absolute()
            || p.components().any(|c| {
                !matches!(
                    c,
                    std::path::Component::RootDir | std::path::Component::Normal(_)
                )
            })
    }) || evidence.starts_with(&data)
        || evidence.starts_with(&source)
        || data.starts_with(&evidence)
        || source.starts_with(&evidence)
        || data.starts_with(&source)
        || source.starts_with(&data)
    {
        return Err("paths-overlap");
    }
    if node_hash.len() != 64
        || !node_hash
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("arguments");
    }
    Ok(Args {
        data,
        evidence,
        source,
        node,
        node_hash,
    })
}
#[derive(Default)]
struct Counts {
    accounts: usize,
    journals: usize,
    coding_active: usize,
    other_active: usize,
    tuning: usize,
    tuning_active: usize,
    retained: usize,
}
struct Scan<'a> {
    data: Tree,
    ev: &'a Evidence,
    counts: Counts,
    start: Instant,
    jobs: Vec<(usize, String, String)>,
}
impl Scan<'_> {
    fn retain(
        &mut self,
        parent: &File,
        name: &str,
        cap: usize,
        label: &str,
        target: Option<(&File, &str)>,
    ) -> Result<Vec<u8>> {
        self.time()?;
        let mut file = self
            .data
            .child(parent, name, false, false)?
            .ok_or("file-missing")?;
        let m = fs::identity(&file)?;
        if fs::size(&m) > (256 * 1024 * 1024 - self.counts.retained) as u64 {
            return Err("aggregate-cap");
        }
        let raw = fs::bytes(&mut file, cap)?;
        self.counts.retained = self
            .counts
            .retained
            .checked_add(raw.len())
            .ok_or("aggregate-cap")?;
        if self.counts.retained > 256 * 1024 * 1024 {
            return Err("aggregate-cap");
        }
        if let Some((parent, name)) = target {
            Evidence::write(parent, name, &raw)?;
        } else {
            Evidence::write(&self.ev.dir, &format!("{label}.raw"), &raw)?;
        }
        let metadata = format!(
            "{}\nsha256={}\nbytes={}\n",
            fs::metadata(&m),
            fs::digest(&raw),
            raw.len()
        );
        self.counts.retained += metadata.len();
        if self.counts.retained > 256 * 1024 * 1024 {
            return Err("aggregate-cap");
        }
        Evidence::write(&self.ev.dir, &format!("{label}.meta"), metadata.as_bytes())?;
        Ok(raw)
    }
    fn time(&self) -> Result<()> {
        if self.start.elapsed() > Duration::from_secs(60) {
            Err("inspection-timeout")
        } else {
            Ok(())
        }
    }
    fn account(&mut self, dir: &File) -> Result<()> {
        let Some(jobs) = self.data.child(dir, "jobs", true, true)? else {
            return Ok(());
        };
        let names = self.data.enumerate(&jobs, 4096)?;
        for name in names.keys() {
            self.counts.journals += 1;
            if self.counts.journals > 65536 {
                return Err("journals-cap");
            }
            let id = name
                .strip_suffix(".jsonl")
                .filter(|s| strict::id(s, false))
                .ok_or("journal-name")?;
            let ordinal = self.counts.journals;
            let snapshot = Evidence::subdir(&self.ev.dir, &format!("item-{ordinal}"))?;
            let sj = Evidence::subdir(&snapshot, "jobs")?;
            let raw = self.retain(
                &jobs,
                name,
                8 * 1024 * 1024,
                &format!("journal-{ordinal}"),
                Some((&sj, name)),
            )?;
            self.counts.retained += 1024;
            if self.counts.retained > 256 * 1024 * 1024 {
                return Err("aggregate-cap");
            }
            self.ev.bind(
                &format!("item-{ordinal}"),
                vec![(format!("jobs/{name}"), fs::digest(&raw), raw.len())],
            )?;
            let kind = strict::journal(&raw, id)?;
            self.jobs.push((ordinal, id.to_owned(), kind));
        }
        Ok(())
    }
    fn inspect(&mut self) -> Result<()> {
        let root = self.data.root.try_clone().map_err(|_| "fd-clone")?;
        let names = self.data.enumerate(&root, 16384)?;
        self.account(&root)?;
        if let Some(users) = self.data.child(&root, "users", true, true)? {
            let users_list = self.data.enumerate(&users, 16384)?;
            if users_list.len() > 4096 {
                return Err("accounts-cap");
            }
            let mut lower = BTreeSet::new();
            for (name, meta) in &users_list {
                if !strict::id(name, true)
                    || !fs::is_dir(meta)
                    || !lower.insert(name.to_lowercase())
                {
                    return Err("account-entry");
                }
                self.counts.accounts += 1;
                let dir = self
                    .data
                    .child(&users, name, true, false)?
                    .ok_or("account-missing")?;
                self.account(&dir)?;
            }
        }
        for name in names.keys() {
            let cal = name.starts_with("native-calibration-");
            let auto = name.starts_with("native-autotune-");
            if !(cal || auto) {
                continue;
            }
            let prefix = if cal {
                "native-calibration-"
            } else {
                "native-autotune-"
            };
            let hash = name
                .strip_prefix(prefix)
                .and_then(|s| s.strip_suffix(".json"))
                .ok_or("tuning-name")?;
            if hash.len() != 16
                || !hash
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            {
                return Err("tuning-name");
            }
            self.counts.tuning += 1;
            let raw = self.retain(
                &root,
                name,
                1024 * 1024,
                &format!("tuning-{}", self.counts.tuning),
                None,
            )?;
            if strict::tuning(&raw, cal)? {
                self.counts.tuning_active += 1;
            }
        }
        self.data.stable()?;
        Ok(())
    }
}
fn blob(raw: &[u8]) -> String {
    let mut h = Sha1::new();
    h.update(format!("blob {}\0", raw.len()).as_bytes());
    h.update(raw);
    format!("{:x}", h.finalize())
}
fn runtime(args: &Args, ev: &Evidence) -> Result<(Tree, Tree, File, usize)> {
    let mut approved = Vec::new();
    let mut retained = 8192;
    let mut source = Tree::open(&args.source)?;
    let root = source.root.try_clone().map_err(|_| "fd-clone")?;
    let server = source
        .child(&root, "server", true, false)?
        .ok_or("source-missing")?;
    let runtime = Evidence::subdir(&ev.dir, "runtime")?;
    for (name, expected) in MODULES {
        let mut f = source
            .child(&server, name, false, false)?
            .ok_or("source-missing")?;
        let raw = fs::bytes(&mut f, 1024 * 1024)?;
        if blob(&raw) != *expected {
            return Err("source-pin");
        }
        retained += raw.len();
        approved.push(((*name).to_owned(), fs::digest(&raw), raw.len()));
        Evidence::write(&runtime, name, &raw)?;
    }
    let dir = source
        .child(&server, "wasm", true, false)?
        .ok_or("wasm-missing")?;
    let mut wasm = source
        .child(&dir, "dav-parse.wasm", false, false)?
        .ok_or("wasm-missing")?;
    let raw = fs::bytes(&mut wasm, 32 * 1024 * 1024)?;
    if fs::digest(&raw) != WASM {
        return Err("wasm-pin");
    }
    retained += raw.len();
    let wd = Evidence::subdir(&runtime, "wasm")?;
    Evidence::write(&wd, "dav-parse.wasm", &raw)?;
    approved.push(("wasm/dav-parse.wasm".into(), fs::digest(&raw), raw.len()));
    ev.bind("runtime", approved)?;
    let parent = args.node.parent().ok_or("node-path")?;
    let name = args
        .node
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or("node-path")?;
    let mut node = Tree::open(parent)?;
    let parent = node.root.try_clone().map_err(|_| "fd-clone")?;
    let mut nf = node
        .child(&parent, name, false, false)?
        .ok_or("node-missing")?;
    let raw = fs::bytes(&mut nf, 128 * 1024 * 1024)?;
    if fs::digest(&raw) != args.node_hash {
        return Err("node-pin");
    }
    Evidence::write(&ev.dir,"authority.json",serde_json::json!({"core":CORE,"tree":"345adfa12da083eb5888ec232dc2d86b9b0383a5","modules":MODULES,"wasmSha256":WASM,"nodeSha256":args.node_hash}).to_string().as_bytes())?;
    ev.set_node_digest(args.node_hash.clone());
    source.stable()?;
    node.stable()?;
    Ok((source, node, nf, retained))
}
fn run(args: &Args, ev: &Evidence, counts: &mut Counts) -> Result<()> {
    if !cfg!(target_os = "linux") {
        return Err("linux-required");
    }
    let (source, node, node_file, retained) = runtime(args, ev)?;
    let mut scan = Scan {
        data: Tree::open(&args.data)?,
        ev,
        counts: Counts {
            retained,
            ..Counts::default()
        },
        start: Instant::now(),
        jobs: Vec::new(),
    };
    let operation = (|| {
        if ev.tree.contains_directory(&scan.data.root)?
            || scan.data.contains_directory(&ev.dir)?
            || source.contains_directory(&scan.data.root)?
            || scan.data.contains_directory(&source.root)?
            || ev.tree.contains_directory(&source.root)?
            || source.contains_directory(&ev.dir)?
        {
            return Err("roots-overlap");
        }
        scan.inspect()?;
        for (ordinal, id, kind) in &scan.jobs {
            scan.time()?;
            source.stable()?;
            node.stable()?;
            ev.tree.stable()?;
            if scan.counts.retained > 256 * 1024 * 1024 - 16384 {
                return Err("aggregate-cap");
            }
            scan.counts.retained += 16384; // Reserve command, status, snapshot observations and bounded streams.
            let pre = ev.verify_snapshots();
            Evidence::write(
                &ev.dir,
                &format!("delegate-{ordinal}.snapshots-before.json"),
                serde_json::json!({"reason":pre.as_ref().err(),"approvedObservation":pre.is_ok()})
                    .to_string()
                    .as_bytes(),
            )?;
            pre?;
            let child = delegate::get(&node_file, ev, *ordinal, id);
            let post = ev.verify_snapshots();
            Evidence::write(&ev.dir,&format!("delegate-{ordinal}.snapshots-after.json"),serde_json::json!({"reason":post.as_ref().err(),"approvedObservation":post.is_ok(),"childReason":child.as_ref().err()}).to_string().as_bytes())?;
            post?;
            scan.time()?;
            let output = child?;
            if strict::outcome(&output, id, kind)? {
                if kind == "code" {
                    scan.counts.coding_active += 1;
                } else {
                    scan.counts.other_active += 1;
                }
            }
        }
        ev.verify_snapshots()?;
        scan.time()?;
        scan.data.stable()?;
        source.stable()?;
        node.stable()?;
        ev.tree.stable()?;
        Ok(())
    })();
    *counts = scan.counts;
    operation
}
fn evidence_preflight(args: &Args) -> Result<()> {
    let data = Tree::open(&args.data)?;
    let source = Tree::open(&args.source)?;
    let parent = Tree::open(args.evidence.parent().ok_or("evidence-path")?)?;
    if parent.contains_directory(&data.root)?
        || parent.contains_directory(&source.root)?
        || source.contains_directory(&data.root)?
        || data.contains_directory(&source.root)?
    {
        return Err("roots-overlap");
    }
    data.stable()?;
    source.stable()?;
    parent.stable()?;
    Ok(())
}
fn main() {
    let a = match args() {
        Ok(a) => a,
        Err(reason) => {
            println!(
                "{}",
                serde_json::json!({"schemaVersion":1,"scope":"persisted-coding-tuning","decision":"refused","reason":reason})
            );
            std::process::exit(64)
        }
    };
    let mut counts = Counts::default();
    let result = match evidence_preflight(&a).and_then(|()| Evidence::create(&a.evidence)) {
        Ok(ev) => {
            let r = run(&a, &ev, &mut counts);
            let reason = r.as_ref().err().copied().unwrap_or("none");
            let record = serde_json::json!({"reason":reason,"codingActive":counts.coding_active,"otherKnownActive":counts.other_active,"tuningActive":counts.tuning_active,"retainedBytes":counts.retained});
            if Evidence::write(&ev.dir, "result.json", record.to_string().as_bytes()).is_err() {
                Err("evidence-final-write")
            } else {
                r
            }
        }
        Err(e) => Err(e),
    };
    let idle = result.is_ok() && counts.coding_active == 0 && counts.tuning_active == 0;
    println!(
        "{}",
        serde_json::json!({"schemaVersion":1,"scope":"persisted-coding-tuning","decision":if idle{"idle"}else{"refused"},"reason":result.err().unwrap_or(if idle{"none"}else{"active"}),"accounts":counts.accounts,"journals":counts.journals,"codingActive":counts.coding_active,"otherKnownActive":counts.other_active,"tuningFiles":counts.tuning,"tuningActive":counts.tuning_active})
    );
    if !idle {
        std::process::exit(2);
    }
}
