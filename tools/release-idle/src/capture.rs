//! Finite nonblocking pipe observation and owned child cleanup. No reader threads.
use rustix::{
    fs::{fcntl_getfl, fcntl_setfl, OFlags},
    process::{
        kill_process_group, waitid, waitpid, Pid, Signal, WaitId, WaitIdOptions, WaitOptions,
        WaitStatus,
    },
};
use std::{
    io::{ErrorKind, Read},
    os::fd::AsFd,
    process::{Child, ChildStderr, ChildStdout},
    thread,
    time::{Duration, Instant},
};
/// Fixed slots retain the first returned error, including an explicit missing OS code.
#[derive(Default)]
pub struct OsErrors {
    pub group: Option<Option<i32>>,
    pub leader: Option<Option<i32>>,
    pub observe: Option<Option<i32>>,
    pub reap: Option<Option<i32>>,
    pub stdout_setup: Option<Option<i32>>,
    pub stderr_setup: Option<Option<i32>>,
    pub stdout_read: Option<Option<i32>>,
    pub stderr_read: Option<Option<i32>>,
}
pub fn retain_first(slot: &mut Option<Option<i32>>, code: Option<i32>) {
    slot.get_or_insert(code);
}
#[derive(Default)]
pub struct Observation {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub reason: Option<&'static str>,
    pub cleanup: Vec<&'static str>,
    pub status: Option<WaitStatus>,
    pub pid: Option<u32>,
    pub out_eof: bool,
    pub err_eof: bool,
    pub group_cleanup: Option<&'static str>,
    pub os_errors: OsErrors,
    pub group_target: Option<i32>,
    pub group_signal: Option<i32>,
    pub leader_exit_observed: Option<bool>,
}
impl Observation {
    pub fn fault(&mut self, reason: &'static str) {
        if !self.cleanup.contains(&reason) {
            self.cleanup.push(reason);
        }
    }
    pub fn record(&self) -> serde_json::Value {
        serde_json::json!({"pid":self.pid,"groupRequest":{"target":self.group_target,"signal":self.group_signal,"leaderExitObserved":self.leader_exit_observed},"osErrors":{
            "group":self.os_errors.group.map(|code|serde_json::json!({"rawOsError":code})),
            "leader":self.os_errors.leader.map(|code|serde_json::json!({"rawOsError":code})),
            "observe":self.os_errors.observe.map(|code|serde_json::json!({"rawOsError":code})),
            "reap":self.os_errors.reap.map(|code|serde_json::json!({"rawOsError":code})),
            "stdoutSetup":self.os_errors.stdout_setup.map(|code|serde_json::json!({"rawOsError":code})),
            "stderrSetup":self.os_errors.stderr_setup.map(|code|serde_json::json!({"rawOsError":code})),
            "stdoutRead":self.os_errors.stdout_read.map(|code|serde_json::json!({"rawOsError":code})),
            "stderrRead":self.os_errors.stderr_read.map(|code|serde_json::json!({"rawOsError":code}))},"reason":self.reason,"cleanupFaults":self.cleanup,"groupCleanup":self.group_cleanup,"status":self.status.map(|s|serde_json::json!({"raw":s.as_raw(),"exit":s.exit_status(),"signal":s.terminating_signal()})),"statusUnavailable":if self.pid.is_none(){Some("no-child")}else if self.status.is_none(){Some("actual-status-unavailable")}else{None},"stdoutBytes":self.stdout.len(),"stderrBytes":self.stderr.len(),"stdoutEof":self.out_eof,"stderrEof":self.err_eof})
    }
}
fn nonblocking<F: AsFd>(f: &F) -> rustix::io::Result<()> {
    fcntl_getfl(f).and_then(|flags| fcntl_setfl(f, flags | OFlags::NONBLOCK))
}
fn read_once<R: Read>(
    pipe: &mut Option<R>,
    out: &mut Vec<u8>,
    eof: &mut bool,
    error: &mut Option<Option<i32>>,
) -> Option<&'static str> {
    let Some(p) = pipe else { return None };
    let mut buf = [0; 512];
    match p.read(&mut buf) {
        Ok(0) => {
            *eof = true;
            *pipe = None;
            None
        }
        Ok(n) => {
            let remaining = 4096 - out.len();
            out.extend_from_slice(&buf[..n.min(remaining)]);
            if n > remaining {
                *pipe = None;
                Some("delegate-output-cap")
            } else {
                None
            }
        }
        Err(e) if e.kind() == ErrorKind::WouldBlock || e.kind() == ErrorKind::Interrupted => None,
        Err(e) => {
            retain_first(error, e.raw_os_error());
            *pipe = None;
            Some("delegate-read-error")
        }
    }
}
pub fn observe(mut child: Child, initial: Option<&'static str>, deadline: Duration) -> Observation {
    let mut o = Observation {
        pid: Some(child.id()),
        reason: initial,
        ..Observation::default()
    };
    let pid = Pid::from_raw(child.id() as i32);
    let mut stdout: Option<ChildStdout> = child.stdout.take();
    let mut stderr: Option<ChildStderr> = child.stderr.take();
    for (pipe, slot, reason) in [
        (
            stdout.as_ref().map(nonblocking),
            &mut o.os_errors.stdout_setup,
            "delegate-stdout-setup",
        ),
        (
            stderr.as_ref().map(nonblocking),
            &mut o.os_errors.stderr_setup,
            "delegate-stderr-setup",
        ),
    ] {
        match pipe {
            Some(Ok(())) => {}
            Some(Err(e)) => {
                retain_first(slot, Some(e.raw_os_error()));
                o.reason.get_or_insert(reason);
            }
            None => {
                retain_first(slot, None);
                o.reason.get_or_insert(reason);
            }
        }
    }
    if o.os_errors.stdout_setup.is_some() {
        stdout = None;
    }
    if o.os_errors.stderr_setup.is_some() {
        stderr = None;
    }
    let Some(pid) = pid else {
        o.reason = Some("delegate-pid");
        return o;
    };
    let start = Instant::now();
    let mut cleanup_start = None;
    loop {
        if let Some(r) = read_once(
            &mut stdout,
            &mut o.stdout,
            &mut o.out_eof,
            &mut o.os_errors.stdout_read,
        ) {
            o.reason.get_or_insert(r);
        }
        if let Some(r) = read_once(
            &mut stderr,
            &mut o.stderr,
            &mut o.err_eof,
            &mut o.os_errors.stderr_read,
        ) {
            o.reason.get_or_insert(r);
        }
        // NOWAIT observes the leader without releasing its PID before group cleanup.
        if cleanup_start.is_none() {
            let exited = match waitid(
                WaitId::Pid(pid),
                WaitIdOptions::EXITED | WaitIdOptions::NOHANG | WaitIdOptions::NOWAIT,
            ) {
                Ok(v) => v.is_some(),
                Err(rustix::io::Errno::INTR) => false,
                Err(e @ rustix::io::Errno::CHILD) => {
                    retain_first(&mut o.os_errors.observe, Some(e.raw_os_error()));
                    o.reason = Some("delegate-ownership-lost");
                    o.fault("group-cleanup-unavailable");
                    break;
                }
                Err(e) => {
                    retain_first(&mut o.os_errors.observe, Some(e.raw_os_error()));
                    o.reason.get_or_insert("delegate-wait-observe");
                    false
                }
            };
            if start.elapsed() >= deadline {
                o.reason.get_or_insert("delegate-timeout");
            }
            if exited || o.reason.is_some() {
                o.group_target = Some(pid.as_raw_nonzero().get().wrapping_neg());
                o.group_signal = Some(Signal::KILL.as_raw());
                o.leader_exit_observed = Some(exited);
                match kill_process_group(pid, Signal::KILL) {
                    Ok(()) => {
                        o.group_cleanup = Some("signal-requested");
                    }
                    Err(e @ rustix::io::Errno::SRCH) => {
                        retain_first(&mut o.os_errors.group, Some(e.raw_os_error()));
                        o.group_cleanup = Some("group-already-absent");
                        o.fault("group-already-absent");
                    }
                    Err(e) => {
                        retain_first(&mut o.os_errors.group, Some(e.raw_os_error()));
                        o.group_cleanup = Some("signal-request-failed");
                        o.fault("group-kill-error");
                        o.reason.get_or_insert("delegate-cleanup");
                        if let Err(e) = child.kill() {
                            retain_first(&mut o.os_errors.leader, e.raw_os_error());
                            o.fault("leader-kill-error");
                        }
                    }
                }
                cleanup_start = Some(Instant::now());
            }
        }
        if let Some(cleanup) = cleanup_start {
            if o.status.is_none() {
                match waitpid(Some(pid), WaitOptions::NOHANG) {
                    Ok(Some((actual, status))) if actual == pid => o.status = Some(status),
                    Ok(Some(_)) => {
                        o.reason.get_or_insert("delegate-wrong-pid");
                    }
                    Ok(None) => {}
                    Err(e) => {
                        retain_first(&mut o.os_errors.reap, Some(e.raw_os_error()));
                        o.fault("leader-wait-error");
                        o.reason.get_or_insert("delegate-cleanup");
                    }
                }
            }
            if o.status.is_some() && stdout.is_none() && stderr.is_none() {
                break;
            }
            if cleanup.elapsed() >= Duration::from_secs(1) {
                o.reason.get_or_insert("delegate-cleanup-incomplete");
                if o.status.is_none() {
                    o.fault("leader-not-reaped");
                }
                if stdout.is_some() || stderr.is_some() {
                    o.fault("pipe-writer-remains");
                }
                break;
            }
        }
        thread::sleep(Duration::from_millis(2));
    }
    // Drop pipes rather than block on an inherited/escaped writer. Child::drop does not wait.
    drop(stdout);
    drop(stderr);
    o
}
