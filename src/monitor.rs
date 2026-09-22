//! Read-only user collector: no process enumeration, GPU helpers or actions.
use crate::{command, metrics, storage};
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs::{self, File, OpenOptions},
    io::{self, Read},
    os::{
        fd::AsRawFd,
        unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    },
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
const LIMIT: u64 = 2 * 1024 * 1024;
fn now_ms() -> io::Result<u64> {
    let mut value: libc::timespec = unsafe { std::mem::zeroed() };
    if unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut value) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(value.tv_sec as u64 * 1000 + value.tv_nsec as u64 / 1_000_000)
}
fn directory() -> io::Result<PathBuf> {
    let root = PathBuf::from(
        std::env::var_os("XDG_RUNTIME_DIR")
            .ok_or_else(|| io::Error::other("XDG_RUNTIME_DIR is unavailable"))?,
    );
    let check = |path: &Path| -> io::Result<()> {
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() || meta.uid() != unsafe { libc::getuid() } || meta.mode() & 0o077 != 0 {
            return Err(io::Error::other(
                "Runtime directory must be private and owned by this user",
            ));
        }
        Ok(())
    };
    check(&root)?;
    let dir = root.join("omarchy-task-manager-monitor");
    match fs::create_dir(&dir) {
        Ok(()) => fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?,
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e),
    }
    check(&dir)?;
    Ok(dir)
}
fn open_lock(dir: &Path) -> io::Result<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(dir.join("collector.lock"))
}
fn locked(file: &File) -> bool {
    unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) == 0 }
}
pub fn run() -> Result<(), String> {
    let dir = directory().map_err(|e| e.to_string())?;
    let lock = open_lock(&dir).map_err(|e| e.to_string())?;
    if !locked(&lock) {
        return Err("A background collector is already running".into());
    }
    let cache = dir.join("history.json");
    let _ = fs::remove_file(&cache);
    let executable = std::env::current_exe().map_err(|e| e.to_string())?;
    let mut sampler = metrics::BasicSampler::default();
    let mut points = VecDeque::new();
    let result = (|| {
        while !command::cancelled() {
            // Removing the package must not leave a collector running indefinitely.
            if !executable.exists() {
                break;
            }
            let started = Instant::now();
            let now = now_ms().map_err(|e| e.to_string())?;
            let (point, continuous) = sampler.sample(now);
            if !continuous {
                points.clear();
            }
            points.push_back(point);
            while points.len() > 61
                || points
                    .front()
                    .is_some_and(|p| now.saturating_sub(p["time"].as_u64().unwrap_or(0)) > 60_000)
            {
                points.pop_front();
            }
            let bytes = serde_json::to_vec(&json!({"version":1,"updated":now,"points":points}))
                .map_err(|e| e.to_string())?;
            if bytes.len() as u64 > LIMIT {
                return Err("Background history exceeds size limit".into());
            }
            storage::atomic_write(&cache, &bytes)?;
            // Start-to-start cadence; no overlap or catch-up burst.
            while started.elapsed() < Duration::from_secs(1) && !command::cancelled() {
                std::thread::sleep(Duration::from_millis(50));
            }
        }
        Ok(())
    })();
    let _ = fs::remove_file(cache);
    drop(lock);
    result
}
fn validate(value: &Value, now: u64) -> bool {
    let Some(updated) = value["updated"].as_u64() else {
        return false;
    };
    let Some(points) = value["points"].as_array() else {
        return false;
    };
    if value["version"] != 1
        || updated > now
        || now - updated > 3000
        || points.is_empty()
        || points.len() > 61
    {
        return false;
    }
    let mut previous = None;
    for point in points {
        let Some(time) = point["time"].as_u64() else {
            return false;
        };
        if time > updated || updated - time > 60_000 || previous.is_some_and(|p| time <= p) {
            return false;
        }
        previous = Some(time);
    }
    previous == Some(updated)
}
pub fn history() -> Option<Value> {
    let dir = directory().ok()?;
    let lock = open_lock(&dir).ok()?;
    if locked(&lock) {
        return None;
    }
    if io::Error::last_os_error().raw_os_error() != Some(libc::EWOULDBLOCK) {
        return None;
    }
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(dir.join("history.json"))
        .ok()?;
    if !file.metadata().ok()?.is_file() {
        return None;
    }
    let mut bytes = Vec::new();
    file.take(LIMIT + 1).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 > LIMIT {
        return None;
    }
    let mut value: Value = serde_json::from_slice(&bytes).ok()?;
    let now = now_ms().ok()?;
    if !validate(&value, now) {
        return None;
    }
    value["now"] = json!(now);
    Some(value)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reject_stale_future_and_disordered_history() {
        let good = json!({"version":1,"updated":2000,"points":[{"time":1000},{"time":2000}]});
        assert!(validate(&good, 2100));
        assert!(!validate(&good, 6000));
        assert!(!validate(&good, 1000));
        let mut bad = good.clone();
        bad["version"] = json!(2);
        assert!(!validate(&bad, 2100));
        bad = good.clone();
        bad["points"][0]["time"] = json!(2000);
        assert!(!validate(&bad, 2100));
        bad = good;
        bad["points"] = json!([]);
        assert!(!validate(&bad, 2100));
    }
}
