//! CLI for the noevia repository split (#952). See docs/repo-split-cutover.md.

use repo_split::{
    extract, list_files, push, verify, Error, ExtractOptions, Pushed, Result, Target,
};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
usage:
  repo-split extract --source <noevia checkout> --sha <40-hex> [--target web|core|services|all]
                     [--out <dir>] [--scaffold <dir>] [--force] [--push [--replace-remote <sha>]]
      Writes <out>/<repo> (default out: tools/repo-split/out under the source checkout).
      --scaffold defaults to <source>/tools/repo-split/scaffold; each repo gets <scaffold>/<repo>.
      --push replaces main of https://github.com/sbstndalton/<repo>.git, but only if the remote main
      is missing, already the new head, or itself an extraction (Split-Source trailer); the push
      uses --force-with-lease. --replace-remote <sha> (single target only) deliberately replaces a
      remote main that is exactly <sha>, e.g. after someone committed there.
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
    replace_remote: Option<String>,
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
        replace_remote: None,
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
            "--replace-remote" => a.replace_remote = Some(val()?),
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
            let ts = targets(a.target.as_deref())?;
            if a.replace_remote.is_some() && (!a.push || ts.len() != 1) {
                return Err(Error(
                    "--replace-remote needs --push and a single --target".to_string(),
                ));
            }
            for t in ts {
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
                    match push(&r.repo_dir, &url, a.replace_remote.as_deref())? {
                        Pushed::Created => println!("{}: created main at {url}", t.repo()),
                        Pushed::UpToDate => {
                            println!("{}: {url} main is already {}", t.repo(), r.head)
                        }
                        Pushed::Replaced(old) => {
                            println!("{}: replaced {url} main {old} with {}", t.repo(), r.head)
                        }
                    }
                } else {
                    println!(
                        "  publish: re-run with --push (guarded, --force-with-lease) for {}",
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
