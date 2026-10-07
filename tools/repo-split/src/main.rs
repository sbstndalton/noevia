//! CLI for the noevia repository split (#952). See docs/repo-split-cutover.md.

use repo_split::{extract, git, list_files, verify, Error, ExtractOptions, Result, Target};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
usage:
  repo-split extract --source <noevia checkout> --sha <40-hex> [--target web|core|services|all]
                     [--out <dir>] [--scaffold <dir>] [--force] [--push]
      Writes <out>/<repo> (default out: tools/repo-split/out under the source checkout).
      --scaffold defaults to <source>/tools/repo-split/scaffold; each repo gets <scaffold>/<repo>.
      --push force-pushes main to https://github.com/sbstndalton/<repo>.git (replaces its history).
  repo-split verify --source <noevia checkout> --sha <40-hex> --target web|core|services
                    --split <split checkout> [--rev <rev>] [--scaffold <dir>]
      Byte-identity check of an existing split repo against noevia at <sha>.
  repo-split map [--target web|core|services]
      Prints the path map (noevia path -> split repo path).";

struct Args {
    cmd: String,
    source: Option<PathBuf>,
    sha: Option<String>,
    target: Option<String>,
    out: Option<PathBuf>,
    scaffold: Option<PathBuf>,
    split: Option<PathBuf>,
    rev: Option<String>,
    force: bool,
    push: bool,
}

fn parse(argv: &[String]) -> Result<Args> {
    let mut it = argv.iter();
    let cmd = it
        .next()
        .ok_or_else(|| Error(USAGE.to_string()))?
        .to_string();
    let mut a = Args {
        cmd,
        source: None,
        sha: None,
        target: None,
        out: None,
        scaffold: None,
        split: None,
        rev: None,
        force: false,
        push: false,
    };
    while let Some(flag) = it.next() {
        let mut val = || {
            it.next()
                .cloned()
                .ok_or_else(|| Error(format!("{flag} needs a value")))
        };
        match flag.as_str() {
            "--source" => a.source = Some(PathBuf::from(val()?)),
            "--sha" => a.sha = Some(val()?),
            "--target" => a.target = Some(val()?),
            "--out" => a.out = Some(PathBuf::from(val()?)),
            "--scaffold" => a.scaffold = Some(PathBuf::from(val()?)),
            "--split" => a.split = Some(PathBuf::from(val()?)),
            "--rev" => a.rev = Some(val()?),
            "--force" => a.force = true,
            "--push" => a.push = true,
            "-h" | "--help" => return Err(Error(USAGE.to_string())),
            other => return Err(Error(format!("unknown argument {other}\n{USAGE}"))),
        }
    }
    Ok(a)
}

fn need<T: Clone>(v: &Option<T>, name: &str) -> Result<T> {
    v.clone()
        .ok_or_else(|| Error(format!("{name} is required\n{USAGE}")))
}

fn targets(spec: Option<&str>) -> Result<Vec<Target>> {
    match spec {
        None | Some("all") => Ok(Target::ALL.to_vec()),
        Some(s) => Ok(vec![Target::parse(s)?]),
    }
}

fn run(a: &Args) -> Result<()> {
    match a.cmd.as_str() {
        "map" => {
            for t in targets(a.target.as_deref())? {
                println!("# {}", t.repo());
                for e in t.entries() {
                    let slash = if e.dir { "/" } else { "" };
                    println!("{}{slash} -> {}{slash}", e.src, e.dst);
                }
            }
            Ok(())
        }
        "extract" => {
            let source = need(&a.source, "--source")?;
            let sha = need(&a.sha, "--sha")?;
            let out = a
                .out
                .clone()
                .unwrap_or_else(|| source.join("tools/repo-split/out"));
            let scaffold_root = a
                .scaffold
                .clone()
                .unwrap_or_else(|| source.join("tools/repo-split/scaffold"));
            for t in targets(a.target.as_deref())? {
                let scaffold = scaffold_root.join(t.repo());
                let dest = out.join(t.repo());
                let r = extract(&ExtractOptions {
                    source: &source,
                    sha: &sha,
                    target: t,
                    out: &dest,
                    scaffold: scaffold.is_dir().then_some(scaffold.as_path()),
                    force: a.force,
                })?;
                println!(
                    "{}: {} (filtered history {}, byte-identical to noevia {sha})",
                    t.repo(),
                    r.head,
                    r.filtered_head
                );
                if a.push {
                    let url = format!("https://github.com/sbstndalton/{}.git", t.repo());
                    git(&r.repo_dir, &["push", "--force", &url, "main:main"])?;
                    println!("{}: pushed main to {url}", t.repo());
                } else {
                    println!(
                        "  publish: git -C {} push --force https://github.com/sbstndalton/{}.git main:main",
                        r.repo_dir.display(),
                        t.repo()
                    );
                }
            }
            Ok(())
        }
        "verify" => {
            let source = need(&a.source, "--source")?;
            let sha = need(&a.sha, "--sha")?;
            let t = Target::parse(&need(&a.target, "--target")?)?;
            let split = need(&a.split, "--split")?;
            let rev = a.rev.clone().unwrap_or_else(|| "HEAD".to_string());
            let scaffold_root = a
                .scaffold
                .clone()
                .unwrap_or_else(|| source.join("tools/repo-split/scaffold"));
            let files = list_files(&scaffold_root.join(t.repo()))?;
            repo_split::check_sha(&sha)?;
            verify(&source, &sha, t, Path::new(&split), &rev, &files)?;
            println!(
                "{} {rev} is byte-identical to noevia {sha} on every mapped path",
                t.repo()
            );
            Ok(())
        }
        _ => Err(Error(USAGE.to_string())),
    }
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    match parse(&argv).and_then(|a| run(&a)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("repo-split: {e}");
            ExitCode::FAILURE
        }
    }
}
