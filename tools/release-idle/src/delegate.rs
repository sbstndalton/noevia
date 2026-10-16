use crate::{
    capture,
    fs::{self, Evidence},
    strict::Result,
};
use std::{
    fs::File,
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{Command, Stdio},
    time::Duration,
};
const GLUE: &str = r#"'use strict';
try {
 const base='/proc/self/fd/0';
 const loader=require(base+'/runtime/dav-parse-wasm.cjs');
 loader.verifyAtStartup({DAV_PARSE_WASM:base+'/runtime/wasm/dav-parse.wasm'});
 const {createJobs}=require(base+'/runtime/jobs.cjs');
 const job=createJobs({dir:base+'/'+process.argv[1]}).get(process.argv[2]);
 if(!job || (Object.hasOwn(job,'revision') && job.lifecycle===null))throw Error('unknown');
 process.stdout.write(JSON.stringify({id:job.id,kind:job.kind,status:job.status}));
} catch { process.exitCode=2; }
"#;
pub fn get(node: &File, ev: &Evidence, ordinal: usize, id: &str) -> Result<Vec<u8>> {
    // Fixed command identity is durable before any descriptor setup or spawn.
    let identity = fs::identity(node);
    let command = serde_json::json!({"executable":identity.as_ref().map(fs::metadata).ok(),"executableIdentityFault":identity.as_ref().err(),"descriptor":node.as_raw_fd(),"executableSha256":ev.node_digest(),"glue":GLUE,"glueSha256":fs::digest(GLUE.as_bytes()),"arguments":["--no-addons","--no-warnings","-e","FIXED_GLUE",format!("item-{ordinal}"),id],"environment":{"DAV_PARSE_WASM":"/proc/self/fd/0/runtime/wasm/dav-parse.wasm"},"environmentCleared":true,"processGroup":"new-owned-group","deadlineMillis":5000,"cleanupObservationMillis":1000});
    let command_fault = Evidence::write(
        &ev.dir,
        &format!("delegate-{ordinal}.command.json"),
        command.to_string().as_bytes(),
    )
    .err();
    let mut observation = capture::Observation::default();
    let setup = (|| {
        if command_fault.is_some() {
            return Err("delegate-command-retention");
        }
        identity?;
        let stdin = ev.dir.try_clone().map_err(|_| "delegate-stdin-setup")?;
        rustix::io::fcntl_setfd(node, rustix::io::FdFlags::empty())
            .map_err(|_| "node-descriptor-setup")?;
        let spawned = Command::new(format!("/proc/self/fd/{}", node.as_raw_fd()))
            .env_clear()
            .env(
                "DAV_PARSE_WASM",
                "/proc/self/fd/0/runtime/wasm/dav-parse.wasm",
            )
            .arg("--no-addons")
            .arg("--no-warnings")
            .arg("-e")
            .arg(GLUE)
            .arg(format!("item-{ordinal}"))
            .arg(id)
            .process_group(0)
            .stdin(Stdio::from(stdin))
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let restored = rustix::io::fcntl_setfd(node, rustix::io::FdFlags::CLOEXEC);
        match spawned {
            Ok(child) => {
                observation = capture::observe(
                    child,
                    if restored.is_err() {
                        Some("node-descriptor-restore")
                    } else {
                        None
                    },
                    Duration::from_secs(5),
                );
                Ok(())
            }
            Err(_) => {
                if restored.is_err() {
                    observation.cleanup.push("node-descriptor-restore");
                }
                Err("delegate-spawn")
            }
        }
    })();
    if let Err(reason) = setup {
        observation.reason = Some(reason);
    }
    // Attempt both capped streams and status independently; a retention fault is separate.
    let stdout_fault = Evidence::write(
        &ev.dir,
        &format!("delegate-{ordinal}.stdout"),
        &observation.stdout,
    )
    .err();
    let stderr_fault = Evidence::write(
        &ev.dir,
        &format!("delegate-{ordinal}.stderr"),
        &observation.stderr,
    )
    .err();
    let record = serde_json::json!({"observation":observation.record(),"retentionFaults":{"command":command_fault,"stdout":stdout_fault,"stderr":stderr_fault}});
    let record_fault = Evidence::write(
        &ev.dir,
        &format!("delegate-{ordinal}.status.json"),
        record.to_string().as_bytes(),
    )
    .err();
    if command_fault.is_some()
        || stdout_fault.is_some()
        || stderr_fault.is_some()
        || record_fault.is_some()
    {
        return Err("delegate-retention-fault");
    }
    if let Some(reason) = observation.reason {
        return Err(reason);
    }
    if observation
        .status
        .is_none_or(|s| s.exit_status() != Some(0))
        || !observation.stderr.is_empty()
    {
        return Err("delegate-failed");
    }
    Ok(observation.stdout)
}
