//! Deadline and allocation bounds apply while reading, not after collecting output.
use std::{
    io::{self, Read},
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

static CANCELLED: AtomicBool = AtomicBool::new(false);
extern "C" fn cancel(_: libc::c_int) {
    if !CANCELLED.swap(true, Ordering::Relaxed) {
        // Break a blocking stdin read too. The worker accepts no further requests
        // after cancellation; repeated signals must not close a reused descriptor.
        unsafe {
            libc::close(libc::STDIN_FILENO);
        }
    }
}
pub fn install_cancellation() -> io::Result<()> {
    let mut action: libc::sigaction = unsafe { std::mem::zeroed() };
    action.sa_sigaction = cancel as *const () as libc::sighandler_t;
    unsafe {
        libc::sigemptyset(&mut action.sa_mask);
    }
    if unsafe { libc::sigaction(libc::SIGTERM, &action, std::ptr::null_mut()) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
pub fn cancelled() -> bool {
    CANCELLED.load(Ordering::Relaxed)
}

const OUTPUT_LIMIT: usize = 8 * 1024 * 1024;

fn nonblocking(pipe: &impl AsRawFd) -> io::Result<()> {
    let fd = pipe.as_raw_fd();
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    if flags < 0 || unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
fn drain(pipe: &mut impl Read, bytes: &mut Vec<u8>, limit: usize) -> Result<(), String> {
    let mut buffer = [0; 8192];
    loop {
        match pipe.read(&mut buffer) {
            Ok(0) => return Ok(()),
            Ok(n) => {
                if bytes.len() + n > limit {
                    return Err("Command response exceeded limit".into());
                }
                bytes.extend_from_slice(&buffer[..n]);
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
}
pub fn run(program: &str, args: &[&str]) -> Result<String, String> {
    run_for(program, args, Duration::from_secs(4))
}
pub fn run_for(program: &str, args: &[&str], deadline: Duration) -> Result<String, String> {
    capture(program, args, deadline, OUTPUT_LIMIT)
}
fn capture(
    program: &str,
    args: &[&str],
    deadline: Duration,
    limit: usize,
) -> Result<String, String> {
    capture_with_cancel(program, args, deadline, limit, &CANCELLED)
}
fn capture_with_cancel(
    program: &str,
    args: &[&str],
    deadline: Duration,
    limit: usize,
    cancelled: &AtomicBool,
) -> Result<String, String> {
    if cancelled.load(Ordering::Relaxed) {
        return Err("Command cancelled".into());
    }
    let mut child = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .env("SYSTEMD_COLORS", "0")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .map_err(|e| format!("{program}: {e}"))?;
    let mut stdout = child.stdout.take().ok_or("Missing stdout")?;
    let mut stderr = child.stderr.take().ok_or("Missing stderr")?;
    let mut out = Vec::new();
    let mut err = Vec::new();
    let started = Instant::now();
    let result = (|| {
        nonblocking(&stdout)
            .and_then(|_| nonblocking(&stderr))
            .map_err(|e| e.to_string())?;
        loop {
            if cancelled.load(Ordering::Relaxed) {
                return Err("Command cancelled".into());
            }
            drain(&mut stdout, &mut out, limit)?;
            drain(&mut stderr, &mut err, limit.min(64 * 1024))?;
            if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
                drain(&mut stdout, &mut out, limit)?;
                drain(&mut stderr, &mut err, limit.min(64 * 1024))?;
                if status.success() {
                    return Ok(String::from_utf8_lossy(&out).into_owned());
                }
                let error = String::from_utf8_lossy(&err).trim().to_string();
                return Err(if error.is_empty() {
                    format!("{program} failed ({status})")
                } else {
                    error
                });
            }
            if started.elapsed() >= deadline {
                return Err(format!("{program} timed out"));
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    })();
    // If still owned and running, stop its group before reaping the leader.
    // Normal successful commands need no cleanup; a reaped PID is never signalled.
    if result.is_err() && child.try_wait().ok().flatten().is_none() {
        unsafe {
            libc::kill(-(child.id() as i32), libc::SIGKILL);
        }
        let _ = child.wait();
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captures_success_and_failure_without_a_shell_in_production() {
        assert_eq!(
            run("/usr/bin/printf", &["%s", "a;not-a-command"]).unwrap(),
            "a;not-a-command"
        );
        assert!(run("/usr/bin/false", &[]).is_err());
    }
    #[test]
    fn oversized_stdout_and_stderr_are_rejected_while_running() {
        let deadline = Duration::from_secs(2);
        assert!(capture("/usr/bin/yes", &[], deadline, 1024)
            .unwrap_err()
            .contains("limit"));
        assert!(capture(
            "/bin/sh",
            &["-c", "while :; do printf 'stderr output\\n' >&2; done"],
            deadline,
            1024
        )
        .unwrap_err()
        .contains("limit"));
    }
    #[test]
    fn cancellation_stops_a_running_command_promptly() {
        let cancelled = AtomicBool::new(false);
        let start = Instant::now();
        std::thread::scope(|scope| {
            scope.spawn(|| {
                std::thread::sleep(Duration::from_millis(50));
                cancelled.store(true, Ordering::Relaxed);
            });
            assert!(capture_with_cancel(
                "/usr/bin/sleep",
                &["30"],
                Duration::from_secs(30),
                1024,
                &cancelled
            )
            .unwrap_err()
            .contains("cancelled"));
        });
        assert!(start.elapsed() < Duration::from_secs(2));
    }
    #[test]
    fn slow_command_obeys_deadline() {
        let start = Instant::now();
        assert!(
            capture("/usr/bin/sleep", &["30"], Duration::from_millis(50), 1024)
                .unwrap_err()
                .contains("timed out")
        );
        assert!(start.elapsed() < Duration::from_secs(2));
    }
}
