//! End-to-end extraction against a synthetic noevia-shaped repo (no network, no real data).
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::indexing_slicing
)]

use repo_split::{extract, git, list_files, verify, ExtractOptions, Target};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn have_filter_repo() -> bool {
    let ok = Command::new("git")
        .args(["filter-repo", "--version"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    if !ok && std::env::var_os("REPO_SPLIT_REQUIRE_FILTER_REPO").is_some() {
        panic!("git filter-repo is required (REPO_SPLIT_REQUIRE_FILTER_REPO is set)");
    }
    ok
}

fn scratch(name: &str) -> PathBuf {
    let p = Path::new(env!("CARGO_TARGET_TMPDIR")).join(name);
    let _ = fs::remove_dir_all(&p);
    fs::create_dir_all(&p).unwrap();
    p
}

fn write(root: &Path, rel: &str, body: &str) {
    let p = root.join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(p, body).unwrap();
}

fn commit(repo: &Path, msg: &str) -> String {
    let id = [
        ("GIT_AUTHOR_NAME", "t"),
        ("GIT_AUTHOR_EMAIL", "t@example.invalid"),
        ("GIT_AUTHOR_DATE", "2026-10-06T00:00:00Z"),
        ("GIT_COMMITTER_NAME", "t"),
        ("GIT_COMMITTER_EMAIL", "t@example.invalid"),
        ("GIT_COMMITTER_DATE", "2026-10-06T00:00:00Z"),
    ];
    let st = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["add", "-A"])
        .status()
        .unwrap();
    assert!(st.success());
    let st = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["-c", "commit.gpgsign=false", "commit", "-qm", msg])
        .envs(id)
        .status()
        .unwrap();
    assert!(st.success());
    git(repo, &["rev-parse", "HEAD"]).unwrap()
}

/// A noevia-shaped repo with two commits; returns (repo, first sha, second sha).
fn synthetic_noevia(root: &Path) -> (PathBuf, String, String) {
    let repo = root.join("noevia");
    fs::create_dir_all(&repo).unwrap();
    git(&repo, &["init", "-q", "-b", "main"]).unwrap();
    // Before the monorepo move the client and server lived in ui/ (history aliases).
    write(&repo, "ui/src/main.tsx", "synthetic old\n");
    write(&repo, "ui/server/index.cjs", "synthetic old server\n");
    write(&repo, "ui/Dockerfile", "FROM scratch\n");
    commit(&repo, "zero: ui/");
    fs::remove_dir_all(repo.join("ui")).unwrap();
    let w = "apps/web";
    for f in [
        "src/main.tsx",
        "public/icon.svg",
        "scripts/build.cjs",
        "contracts/project-limits.json",
        "qa/q.cjs",
        "tests/client/a.test.cjs",
        "tests/server/b.test.cjs",
        "tests/fixtures/f.json",
        "tests/hermetic-network.cjs",
        "server/index.cjs",
        "server/package.json",
        "index.html",
        "vite.config.ts",
        "tsconfig.json",
        "package.json",
        "package-lock.json",
        ".gitignore",
        ".dockerignore",
        "Dockerfile",
    ] {
        write(&repo, &format!("{w}/{f}"), &format!("synthetic {f}\n"));
    }
    for s in [
        "code-sandbox",
        "diary",
        "docling",
        "laya",
        "model-manager",
        "ocr",
    ] {
        write(&repo, &format!("services/{s}/Dockerfile"), "FROM scratch\n");
    }
    write(&repo, "docs/readme.md", "integration docs stay\n");
    write(&repo, "release/versions.lock", "NOEVIA_WEB_REF=self\n");
    let one = commit(&repo, "one");
    write(&repo, "apps/web/src/main.tsx", "synthetic v2\n");
    write(&repo, "services/diary/agent.py", "print('synthetic')\n");
    write(&repo, "docs/readme.md", "changed docs\n");
    let two = commit(&repo, "two");
    (repo, one, two)
}

fn scaffold(root: &Path, repo: &str) -> PathBuf {
    let s = root.join("scaffold").join(repo);
    write(&s, ".github/workflows/ci.yml", "name: CI\n");
    write(&s, "README.md", &format!("# {repo}\n"));
    s
}

fn run(source: &Path, sha: &str, t: Target, out: &Path, scaffold: Option<&Path>) -> String {
    extract(&ExtractOptions {
        source,
        sha,
        target: t,
        out,
        scaffold,
        force: true,
    })
    .unwrap()
    .head
}

#[test]
fn extracts_each_target_with_history_and_byte_identity() {
    if !have_filter_repo() {
        eprintln!("skipping: git filter-repo not installed");
        return;
    }
    let root = scratch("each-target");
    let (src, _one, two) = synthetic_noevia(&root);
    for t in Target::ALL {
        let sc = scaffold(&root, t.repo());
        let out = root.join("out").join(t.repo());
        let head = run(&src, &two, t, &out, Some(&sc));
        let files = list_files(&sc).unwrap();
        verify(&src, &two, t, &out, &head, &files).unwrap();
        // Filtered history keeps only commits that touch the target, plus the scaffold commit:
        // "two" changes src/ and services/diary but nothing of core; "zero" has no services.
        let count = git(&out, &["rev-list", "--count", "HEAD"]).unwrap();
        // "zero" (ui/) reaches web and core through the history aliases.
        let want = match t {
            Target::Web => "4",
            Target::Core => "3",
            Target::Services => "3",
        };
        assert_eq!(count, want, "{}", t.repo());
        let msg = git(&out, &["log", "-1", "--format=%B"]).unwrap();
        assert!(msg.contains(&format!("Split-Source: {two}")));
        let tree = git(&out, &["ls-tree", "-r", "--name-only", "HEAD"]).unwrap();
        assert!(!tree.contains("docs/"), "integration files leaked");
        assert!(!tree.contains("apps/"), "un-renamed path");
        assert_eq!(
            git(&out, &["for-each-ref", "--format=%(refname)"]).unwrap(),
            "refs/heads/main"
        );
    }
    let core = root.join("out/noevia-core");
    assert!(core.join("code-sandbox/Dockerfile").is_file());
    assert!(core.join("server/index.cjs").is_file());
    assert!(!core.join("src").exists());
    let web = root.join("out/noevia-web");
    let first = git(
        &web,
        &["log", "--reverse", "--format=%s", "--", "src/main.tsx"],
    )
    .unwrap();
    assert_eq!(
        first.lines().next(),
        Some("zero: ui/"),
        "ui/src history reaches src/"
    );
    let old = git(&web, &["rev-list", "--all", "--objects"]).unwrap();
    assert!(
        !old.contains("Dockerfile"),
        "ui/Dockerfile is not mapped and must not leak"
    );
    assert_eq!(
        fs::read_to_string(web.join("src/main.tsx")).unwrap(),
        "synthetic v2\n"
    );
    assert!(
        !web.join("Dockerfile").exists(),
        "apps/web/Dockerfile stays in noevia"
    );
    assert!(!web.join("server").exists());
    let svc = root.join("out/noevia-services");
    assert!(svc.join("diary/agent.py").is_file());
    assert!(!svc.join("code-sandbox").exists());
}

#[test]
fn rerun_at_the_same_sha_is_reproducible_and_an_older_sha_differs() {
    if !have_filter_repo() {
        return;
    }
    let root = scratch("rerun");
    let (src, one, two) = synthetic_noevia(&root);
    let sc = scaffold(&root, "noevia-web");
    let out = root.join("out/noevia-web");
    let a = run(&src, &two, Target::Web, &out, Some(&sc));
    let b = run(&src, &two, Target::Web, &out, Some(&sc));
    assert_eq!(a, b);
    let c = run(&src, &one, Target::Web, &out, Some(&sc));
    assert_ne!(a, c);
    assert_eq!(
        fs::read_to_string(out.join("src/main.tsx")).unwrap(),
        "synthetic src/main.tsx\n"
    );
}

#[test]
fn refuses_unmapped_service_scaffold_collision_and_existing_out() {
    if !have_filter_repo() {
        return;
    }
    let root = scratch("refusals");
    let (src, _one, two) = synthetic_noevia(&root);
    let out = root.join("out/noevia-services");

    // existing out without --force
    fs::create_dir_all(&out).unwrap();
    let e = extract(&ExtractOptions {
        source: &src,
        sha: &two,
        target: Target::Services,
        out: &out,
        scaffold: None,
        force: false,
    });
    assert!(e.err().unwrap().0.contains("--force"));

    // scaffold that would overwrite an extracted path
    let bad = root.join("bad-scaffold");
    write(&bad, "diary/README.md", "x\n");
    let e = extract(&ExtractOptions {
        source: &src,
        sha: &two,
        target: Target::Services,
        out: &out,
        scaffold: Some(&bad),
        force: true,
    });
    assert!(e.err().unwrap().0.contains("byte identity"));

    // a new service nobody maps
    write(&src, "services/embed/Dockerfile", "FROM scratch\n");
    let three = commit(&src, "three");
    let e = extract(&ExtractOptions {
        source: &src,
        sha: &three,
        target: Target::Web,
        out: &root.join("out/noevia-web"),
        scaffold: None,
        force: true,
    });
    assert!(e.err().unwrap().0.contains("embed"));

    // short sha
    let e = extract(&ExtractOptions {
        source: &src,
        sha: &two[..12],
        target: Target::Web,
        out: &root.join("out/x"),
        scaffold: None,
        force: true,
    });
    assert!(e.is_err());
}

#[test]
fn verify_catches_a_changed_or_extra_file() {
    if !have_filter_repo() {
        return;
    }
    let root = scratch("tamper");
    let (src, _one, two) = synthetic_noevia(&root);
    let out = root.join("out/noevia-core");
    run(&src, &two, Target::Core, &out, None);
    write(&out, "server/index.cjs", "tampered\n");
    let changed = commit(&out, "tamper");
    let e = verify(&src, &two, Target::Core, &out, &changed, &[]).unwrap_err();
    assert!(e.0.contains("apps/web/server -> server"), "{e}");

    run(&src, &two, Target::Core, &out, None);
    write(&out, "tests/stray.cjs", "x\n");
    let extra = commit(&out, "extra");
    let e = verify(&src, &two, Target::Core, &out, &extra, &[]).unwrap_err();
    assert!(e.0.contains("tests/stray.cjs"), "{e}");
}

#[test]
fn cut_sha_only_on_a_remote_tracking_ref_is_fetched() {
    if !have_filter_repo() {
        return;
    }
    let root = scratch("remote-ref");
    let (src, one, two) = synthetic_noevia(&root);
    // Like origin/main ahead of every local branch: two is only on refs/remotes/origin/main.
    git(&src, &["update-ref", "refs/remotes/origin/main", &two]).unwrap();
    git(&src, &["reset", "-q", "--hard", &one]).unwrap();
    let out = root.join("out/noevia-services");
    run(&src, &two, Target::Services, &out, None);
    assert!(out.join("diary/agent.py").is_file());
}
