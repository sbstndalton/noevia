//! Extract sbstndalton/noevia-web, noevia-core and noevia-services from one noevia commit
//! (#952, docs/adr-0001-rust-and-repo-split.md, docs/repo-split-cutover.md).
//!
//! The extraction is `git filter-repo` over a fresh `--no-local` clone of the given commit, with
//! path filters plus renames from the table in [`Target::entries`]. On top of the filtered
//! history the tool adds ONE scaffold commit (CI workflow, README) from
//! `tools/repo-split/scaffold/<repo>/`, with a fixed identity and the source commit's date, so
//! re-running at the same noevia SHA yields the same commit SHAs.
//!
//! [`verify`] is the byte-identity check: every mapped path must have the same git mode and object
//! id in the split repo as in noevia at the cut SHA, and the split repo may hold nothing else
//! besides the scaffold files.

use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Identity of the scaffold commit. Fixed so re-runs are reproducible.
pub const SCAFFOLD_NAME: &str = "noevia repo-split";
pub const SCAFFOLD_EMAIL: &str = "repo-split@noevia.invalid";

#[derive(Debug)]
pub struct Error(pub String);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

fn err<T>(msg: impl Into<String>) -> Result<T> {
    Err(Error(msg.into()))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Target {
    Web,
    Core,
    Services,
}

/// One mapped path: `src` in noevia, `dst` in the split repo.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Entry {
    pub src: &'static str,
    pub dst: &'static str,
    pub dir: bool,
}

const fn d(src: &'static str, dst: &'static str) -> Entry {
    Entry {
        src,
        dst,
        dir: true,
    }
}
const fn f(src: &'static str, dst: &'static str) -> Entry {
    Entry {
        src,
        dst,
        dir: false,
    }
}

const WEB: &[Entry] = &[
    d("apps/web/src", "src"),
    d("apps/web/public", "public"),
    d("apps/web/scripts", "scripts"),
    // noevia-core owns contracts/; noevia-web carries a pinned copy (ADR 0001).
    d("apps/web/contracts", "contracts"),
    d("apps/web/qa", "qa"),
    d("apps/web/tests/client", "tests/client"),
    f(
        "apps/web/tests/hermetic-network.cjs",
        "tests/hermetic-network.cjs",
    ),
    f("apps/web/index.html", "index.html"),
    f("apps/web/vite.config.ts", "vite.config.ts"),
    f("apps/web/tsconfig.json", "tsconfig.json"),
    f("apps/web/package.json", "package.json"),
    f("apps/web/package-lock.json", "package-lock.json"),
    f("apps/web/.gitignore", ".gitignore"),
    f("apps/web/.dockerignore", ".dockerignore"),
];

const CORE: &[Entry] = &[
    d("apps/web/server", "server"),
    d("apps/web/contracts", "contracts"),
    d("apps/web/tests/server", "tests/server"),
    d("apps/web/tests/fixtures", "tests/fixtures"),
    f(
        "apps/web/tests/hermetic-network.cjs",
        "tests/hermetic-network.cjs",
    ),
    d("services/code-sandbox", "code-sandbox"),
];

const SERVICES: &[Entry] = &[
    d("services/diary", "diary"),
    d("services/docling", "docling"),
    d("services/laya", "laya"),
    d("services/model-manager", "model-manager"),
    d("services/ocr", "ocr"),
];

/// Earlier locations of mapped paths, kept so `git log` reaches back past the moves. Only used
/// as filter-repo paths/renames; the cut commit itself must not contain them.
/// Before 6a233aec ("make cowork a portable monorepo", 2026-09-03) apps/web was ui/.
const WEB_HISTORY: &[Entry] = &[
    d("ui/src", "src"),
    f("ui/index.html", "index.html"),
    f("ui/vite.config.ts", "vite.config.ts"),
    f("ui/tsconfig.json", "tsconfig.json"),
    f("ui/package.json", "package.json"),
    f("ui/package-lock.json", "package-lock.json"),
    f("ui/.gitignore", ".gitignore"),
    f("ui/.dockerignore", ".dockerignore"),
];
const CORE_HISTORY: &[Entry] = &[d("ui/server", "server")];

/// Directories whose every child must be mapped by some target or listed in [`STAYS`], so a new
/// service or a new apps/web entry fails the extraction instead of being dropped silently.
pub const COVERED_PARENTS: &[&str] = &["apps/web", "apps/web/tests", "services"];

/// Children of [`COVERED_PARENTS`] that deliberately stay in noevia.
pub const STAYS: &[&str] = &[
    // The monorepo image build; the assembled release uses build/web.Dockerfile instead.
    "apps/web/Dockerfile",
];

impl Target {
    pub const ALL: [Target; 3] = [Target::Web, Target::Core, Target::Services];

    pub fn parse(s: &str) -> Result<Target> {
        match s {
            "web" | "noevia-web" => Ok(Target::Web),
            "core" | "noevia-core" => Ok(Target::Core),
            "services" | "noevia-services" => Ok(Target::Services),
            _ => err(format!(
                "unknown target '{s}' (expected web, core or services)"
            )),
        }
    }

    pub fn repo(self) -> &'static str {
        match self {
            Target::Web => "noevia-web",
            Target::Core => "noevia-core",
            Target::Services => "noevia-services",
        }
    }

    pub fn history(self) -> &'static [Entry] {
        match self {
            Target::Web => WEB_HISTORY,
            Target::Core => CORE_HISTORY,
            Target::Services => &[],
        }
    }

    pub fn entries(self) -> &'static [Entry] {
        match self {
            Target::Web => WEB,
            Target::Core => CORE,
            Target::Services => SERVICES,
        }
    }
}

/// `git filter-repo` arguments that keep and rename this target's paths.
pub fn filter_repo_args(target: Target) -> Vec<String> {
    let mut args = Vec::new();
    for e in target.entries().iter().chain(target.history()) {
        let (src, dst) = if e.dir {
            (format!("{}/", e.src), format!("{}/", e.dst))
        } else {
            (e.src.to_string(), e.dst.to_string())
        };
        args.push("--path".to_string());
        args.push(src.clone());
        if src != dst {
            args.push("--path-rename".to_string());
            args.push(format!("{src}:{dst}"));
        }
    }
    args
}

/// Children of `parent` (relative paths) that no target maps and that are not in [`STAYS`].
pub fn unmapped_children(parent: &str, children: &[String]) -> Vec<String> {
    children
        .iter()
        .filter(|child| {
            let full = format!("{parent}/{child}");
            let mapped = Target::ALL.iter().any(|t| {
                t.entries().iter().any(|e| e.src == full)
                    // A parent that is itself covered (apps/web/tests) counts as mapped.
                    || COVERED_PARENTS.contains(&full.as_str())
            });
            !mapped && !STAYS.contains(&full.as_str())
        })
        .cloned()
        .collect()
}

pub fn check_sha(sha: &str) -> Result<()> {
    if sha.len() == 40
        && sha
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        Ok(())
    } else {
        err(format!(
            "'{sha}' is not a 40-character lowercase commit sha"
        ))
    }
}

/// Run git in `dir`; returns trimmed stdout.
pub fn git(dir: &Path, args: &[&str]) -> Result<String> {
    git_env(dir, args, &[])
}

fn git_env(dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Result<String> {
    let mut cmd = Command::new("git");
    cmd.arg("-C").arg(dir).args(args);
    for (k, v) in env {
        cmd.env(k, v);
    }
    let out = cmd
        .output()
        .map_err(|e| Error(format!("could not run git: {e}")))?;
    if !out.status.success() {
        return err(format!(
            "git {} failed in {}: {}",
            args.join(" "),
            dir.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
}

/// `mode type oid` of `path` at `rev`, or None if it does not exist.
fn tree_entry(repo: &Path, rev: &str, path: &str) -> Result<Option<String>> {
    let out = git(repo, &["ls-tree", "--full-tree", rev, "--", path])?;
    let line = out.lines().find(|l| l.ends_with(&format!("\t{path}")));
    Ok(line.and_then(|l| l.split('\t').next()).map(str::to_string))
}

fn ls_names(repo: &Path, rev: &str, dir: &str) -> Result<Vec<String>> {
    let spec = if dir.is_empty() {
        rev.to_string()
    } else {
        format!("{rev}:{dir}")
    };
    Ok(git(repo, &["ls-tree", "--name-only", &spec])?
        .lines()
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect())
}

/// Fail unless every mapped path exists at `sha` and every child of [`COVERED_PARENTS`] is mapped.
pub fn check_source(source: &Path, sha: &str, target: Target) -> Result<()> {
    for e in target.entries() {
        match tree_entry(source, sha, e.src)? {
            None => return err(format!("{} does not exist at {sha}", e.src)),
            Some(entry) => {
                let is_dir = entry.contains(" tree ");
                if is_dir != e.dir {
                    return err(format!(
                        "{} at {sha} is a {}, expected a {}",
                        e.src,
                        if is_dir { "directory" } else { "file" },
                        if e.dir { "directory" } else { "file" }
                    ));
                }
            }
        }
    }
    for e in target.history() {
        if tree_entry(source, sha, e.src)?.is_some() {
            return err(format!(
                "{} exists at {sha} but is mapped only as history; map it in Target::entries",
                e.src
            ));
        }
    }
    for parent in COVERED_PARENTS {
        let missing = unmapped_children(parent, &ls_names(source, sha, parent)?);
        if !missing.is_empty() {
            return err(format!(
                "{parent}/ at {sha} has entries no split repo maps: {}. Add them to a target in \
                 tools/repo-split/src/lib.rs (or to STAYS) before extracting.",
                missing.join(", ")
            ));
        }
    }
    Ok(())
}

/// Every file under `dir`, as '/'-separated paths relative to `dir`, sorted.
pub fn list_files(dir: &Path) -> Result<Vec<String>> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) -> Result<()> {
        let rd = fs::read_dir(dir).map_err(|e| Error(format!("{}: {e}", dir.display())))?;
        for ent in rd {
            let ent = ent.map_err(|e| Error(format!("{}: {e}", dir.display())))?;
            let p = ent.path();
            if p.is_dir() {
                walk(root, &p, out)?;
            } else {
                let rel = p
                    .strip_prefix(root)
                    .map_err(|e| Error(e.to_string()))?
                    .components()
                    .map(|c| c.as_os_str().to_string_lossy().into_owned())
                    .collect::<Vec<_>>()
                    .join("/");
                out.push(rel);
            }
        }
        Ok(())
    }
    let mut out = Vec::new();
    if dir.is_dir() {
        walk(dir, dir, &mut out)?;
    }
    out.sort();
    Ok(out)
}

/// The first path segment of each scaffold file (what the scaffold adds at the repo root).
pub fn scaffold_roots(files: &[String]) -> Vec<String> {
    let mut roots: Vec<String> = files
        .iter()
        .filter_map(|f| f.split('/').next())
        .map(str::to_string)
        .collect();
    roots.sort();
    roots.dedup();
    roots
}

pub struct ExtractOptions<'a> {
    pub source: &'a Path,
    pub sha: &'a str,
    pub target: Target,
    pub out: &'a Path,
    pub scaffold: Option<&'a Path>,
    pub force: bool,
}

/// Result of an extraction: the split repo's main head.
pub struct Extracted {
    pub repo_dir: PathBuf,
    pub head: String,
    pub filtered_head: String,
}

pub fn extract(o: &ExtractOptions<'_>) -> Result<Extracted> {
    check_sha(o.sha)?;
    git(
        o.source,
        &["cat-file", "-e", &format!("{}^{{commit}}", o.sha)],
    )
    .map_err(|_| Error(format!("commit {} is not in {}", o.sha, o.source.display())))?;
    check_source(o.source, o.sha, o.target)?;

    let scaffold_files = match o.scaffold {
        Some(dir) => list_files(dir)?,
        None => Vec::new(),
    };
    for file in &scaffold_files {
        let mapped = o
            .target
            .entries()
            .iter()
            .any(|e| file == e.dst || file.starts_with(&format!("{}/", e.dst)));
        if mapped {
            return err(format!(
                "scaffold file {file} would overwrite an extracted path; byte identity forbids it"
            ));
        }
    }

    if o.out.exists() {
        if !o.force {
            return err(format!(
                "{} exists; pass --force to replace it",
                o.out.display()
            ));
        }
        fs::remove_dir_all(o.out).map_err(|e| Error(format!("{}: {e}", o.out.display())))?;
    }
    let parent = match o.out.parent() {
        Some(p) if !p.as_os_str().is_empty() => p,
        _ => Path::new("."),
    };
    fs::create_dir_all(parent).map_err(|e| Error(format!("{}: {e}", parent.display())))?;
    let parent = parent
        .canonicalize()
        .map_err(|e| Error(format!("{}: {e}", parent.display())))?;
    let name = o
        .out
        .file_name()
        .ok_or_else(|| Error(format!("{} has no final component", o.out.display())))?;
    let out_abs = parent.join(name);
    let parent = parent.as_path();
    let source = o
        .source
        .canonicalize()
        .map_err(|e| Error(format!("{}: {e}", o.source.display())))?;
    let out_str = out_abs.to_string_lossy().into_owned();
    let src_str = source.to_string_lossy().into_owned();
    git(
        parent,
        &[
            "clone",
            "--quiet",
            "--no-local",
            "--no-checkout",
            &src_str,
            &out_str,
        ],
    )?;
    let repo = out_abs.as_path();
    if git(repo, &["cat-file", "-e", &format!("{}^{{commit}}", o.sha)]).is_err() {
        // Only local branches are cloned; the cut sha may sit on a remote-tracking ref
        // (origin/main) of the source. Fetch it by id.
        git(repo, &["fetch", "--quiet", "--no-tags", &src_str, o.sha]).map_err(|_| {
            Error(format!(
                "{} is not reachable from any ref of {}; fetch or branch it first",
                o.sha,
                o.source.display()
            ))
        })?;
    }
    // Keep exactly one ref, main = the cut sha.
    git(repo, &["update-ref", "refs/heads/repo-split-tmp", o.sha])?;
    git(repo, &["symbolic-ref", "HEAD", "refs/heads/repo-split-tmp"])?;
    let _ = git(repo, &["remote", "remove", "origin"]);
    for r in git(repo, &["for-each-ref", "--format=%(refname)"])?.lines() {
        if r != "refs/heads/repo-split-tmp" {
            git(repo, &["update-ref", "-d", r])?;
        }
    }
    git(repo, &["branch", "-m", "repo-split-tmp", "main"])?;

    let mut args: Vec<String> = vec![
        "filter-repo".into(),
        "--force".into(),
        "--quiet".into(),
        "--replace-refs".into(),
        "delete-no-add".into(),
    ];
    args.extend(filter_repo_args(o.target));
    let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
    git(repo, &arg_refs)?;
    git(repo, &["checkout", "--quiet", "main"])?;
    git(repo, &["reset", "--quiet", "--hard", "main"])?;
    let filtered_head = git(repo, &["rev-parse", "HEAD"])?;

    if let Some(dir) = o.scaffold {
        for file in &scaffold_files {
            let from = dir.join(file);
            let to = repo.join(file);
            if let Some(p) = to.parent() {
                fs::create_dir_all(p).map_err(|e| Error(format!("{}: {e}", p.display())))?;
            }
            fs::copy(&from, &to).map_err(|e| Error(format!("{}: {e}", from.display())))?;
        }
        if !scaffold_files.is_empty() {
            let date = git(o.source, &["log", "-1", "--format=%cI", o.sha])?;
            let msg = format!(
                "repo-split: scaffold {} from sbstndalton/noevia@{}\n\nExtracted by \
                 tools/repo-split in sbstndalton/noevia (#952). Everything except this \
                 commit's files is\nnoevia history filtered to the paths in \
                 tools/repo-split/src/lib.rs.\n\nSplit-Source: {}\n",
                o.target.repo(),
                o.sha,
                o.sha
            );
            let env = [
                ("GIT_AUTHOR_NAME", SCAFFOLD_NAME),
                ("GIT_AUTHOR_EMAIL", SCAFFOLD_EMAIL),
                ("GIT_AUTHOR_DATE", date.as_str()),
                ("GIT_COMMITTER_NAME", SCAFFOLD_NAME),
                ("GIT_COMMITTER_EMAIL", SCAFFOLD_EMAIL),
                ("GIT_COMMITTER_DATE", date.as_str()),
            ];
            git(repo, &["add", "--all"])?;
            git_env(
                repo,
                &[
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "--quiet",
                    "--no-verify",
                    "-m",
                    &msg,
                ],
                &env,
            )?;
        }
    }
    let head = git(repo, &["rev-parse", "HEAD"])?;
    verify(o.source, o.sha, o.target, repo, &head, &scaffold_files)?;
    Ok(Extracted {
        repo_dir: out_abs.clone(),
        head,
        filtered_head,
    })
}

/// Byte identity: each mapped path has the same mode and object id at `split_rev` as at `sha`,
/// and the split repo's root holds nothing but mapped paths and the scaffold roots.
pub fn verify(
    source: &Path,
    sha: &str,
    target: Target,
    split: &Path,
    split_rev: &str,
    scaffold_files: &[String],
) -> Result<()> {
    let mut problems = Vec::new();
    for e in target.entries() {
        let want = tree_entry(source, sha, e.src)?;
        let got = tree_entry(split, split_rev, e.dst)?;
        if want.is_none() || want != got {
            problems.push(format!(
                "{} -> {}: noevia {:?}, split {:?}",
                e.src, e.dst, want, got
            ));
        }
    }
    let allowed_roots: Vec<String> = target
        .entries()
        .iter()
        .filter_map(|e| e.dst.split('/').next())
        .map(str::to_string)
        .chain(scaffold_roots(scaffold_files))
        .collect();
    for name in ls_names(split, split_rev, "")? {
        if !allowed_roots.contains(&name) {
            problems.push(format!(
                "unexpected top-level entry in the split repo: {name}"
            ));
        }
    }
    // tests/ is shared by several entries: nothing beyond them may live there.
    for e in target.entries() {
        if let Some((parent, _)) = e.dst.rsplit_once('/') {
            for name in ls_names(split, split_rev, parent)? {
                let full = format!("{parent}/{name}");
                if !target.entries().iter().any(|x| x.dst == full) {
                    problems.push(format!("unexpected entry in the split repo: {full}"));
                }
            }
        }
    }
    problems.sort();
    problems.dedup();
    if problems.is_empty() {
        Ok(())
    } else {
        err(format!(
            "{} at {split_rev} is not byte-identical to noevia {sha}:\n  {}",
            target.repo(),
            problems.join("\n  ")
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn targets_parse_by_short_and_repo_name() {
        for t in Target::ALL {
            assert_eq!(Target::parse(t.repo()).ok(), Some(t));
        }
        assert!(Target::parse("macos").is_err());
    }

    #[test]
    fn dirs_get_trailing_slashes_and_identity_renames_are_skipped() {
        let a = filter_repo_args(Target::Services);
        assert!(a.windows(2).any(|w| w == ["--path", "services/diary/"]));
        assert!(a
            .windows(2)
            .any(|w| w == ["--path-rename", "services/diary/:diary/"]));
        let c = filter_repo_args(Target::Core);
        assert!(c
            .windows(2)
            .any(|w| w == ["--path-rename", "services/code-sandbox/:code-sandbox/"]));
        let w = filter_repo_args(Target::Web);
        assert!(w.windows(2).any(|w| w == ["--path-rename", "ui/src/:src/"]));
        assert!(w
            .windows(2)
            .any(|w| w == ["--path-rename", "apps/web/package.json:package.json"]));
    }

    #[test]
    fn no_destination_is_claimed_twice_within_a_target() {
        for t in Target::ALL {
            let mut dsts: Vec<_> = t.entries().iter().map(|e| e.dst).collect();
            dsts.sort_unstable();
            let n = dsts.len();
            dsts.dedup();
            assert_eq!(n, dsts.len(), "{}", t.repo());
        }
    }

    #[test]
    fn every_service_and_apps_web_child_is_covered() {
        let services: Vec<String> = [
            "code-sandbox",
            "diary",
            "docling",
            "laya",
            "model-manager",
            "ocr",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        assert!(unmapped_children("services", &services).is_empty());
        let new = vec!["diary".to_string(), "embed".to_string()];
        assert_eq!(unmapped_children("services", &new), vec!["embed"]);
        let web: Vec<String> = ["Dockerfile", "server", "src", "tests", "qa"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert!(unmapped_children("apps/web", &web).is_empty());
    }

    #[test]
    fn sha_must_be_full_lowercase_hex() {
        assert!(check_sha(&"a".repeat(40)).is_ok());
        assert!(check_sha(&"A".repeat(40)).is_err());
        assert!(check_sha("abc1234").is_err());
        assert!(check_sha("main").is_err());
    }

    #[test]
    fn scaffold_roots_are_first_segments() {
        let files = vec![
            ".github/workflows/ci.yml".to_string(),
            "README.md".to_string(),
        ];
        assert_eq!(scaffold_roots(&files), vec![".github", "README.md"]);
    }
}
