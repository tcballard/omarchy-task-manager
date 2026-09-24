use crate::{
    process::{Identity, Process},
    storage,
};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    io::Read,
    path::PathBuf,
    time::{Instant, SystemTime, UNIX_EPOCH},
};
pub struct History {
    rows: BTreeMap<String, Value>,
    previous: HashMap<Identity, (u64, Option<u64>, Option<u64>)>,
    last: Instant,
    path: PathBuf,
    since: u64,
    save_error: Option<String>,
    preserve_unreadable: bool,
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
impl History {
    pub fn new() -> Self {
        let path = std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
            })
            .join("omarchy-task-manager/history.json");
        Self::at_path(path)
    }
    pub(crate) fn at_path(path: PathBuf) -> Self {
        let loaded = (|| -> Result<Value, String> {
            let file = match fs::File::open(&path) {
                Ok(file) => file,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    return Ok(json!({"rows":[]}))
                }
                Err(e) => return Err(e.to_string()),
            };
            let mut bytes = Vec::new();
            file.take(8 * 1024 * 1024 + 1)
                .read_to_end(&mut bytes)
                .map_err(|e| e.to_string())?;
            if bytes.len() > 8 * 1024 * 1024 {
                return Err("History file exceeds 8 MiB".into());
            }
            let value: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
            if !value["rows"]
                .as_array()
                .is_some_and(|rows| rows.iter().all(|row| row["key"].is_string()))
            {
                return Err("Invalid history rows".into());
            }
            Ok(value)
        })();
        let save_error = loaded.as_ref().err().map(|e| format!("Saved history could not be loaded: {e}. Original file preserved; reset history to replace it."));
        let preserve_unreadable = save_error.is_some();
        let v = loaded.unwrap_or_default();
        let rows = v["rows"]
            .as_array()
            .map(|r| {
                r.iter()
                    .filter_map(|v| Some((v["key"].as_str()?.to_string(), v.clone())))
                    .take(4096)
                    .collect()
            })
            .unwrap_or_default();
        Self {
            rows,
            previous: HashMap::new(),
            last: Instant::now(),
            path,
            since: v["since"].as_u64().unwrap_or_else(now),
            save_error,
            preserve_unreadable,
        }
    }
    pub fn sample(&mut self, processes: &[Process], continuous: bool) {
        let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
        for p in processes
            .iter()
            .filter(|p| p.uid == unsafe { libc::getuid() })
        {
            let key = fs::read_link(format!("/proc/{}/exe", p.id.pid))
                .map(|s| s.display().to_string())
                .unwrap_or_else(|_| p.name.clone());
            if self.rows.len() >= 4096 && !self.rows.contains_key(&key) {
                continue;
            }
            let row=self.rows.entry(key.clone()).or_insert_with(||json!({"key":key,"name":p.name,"cpu_seconds":0.0,"read":0u64,"write":0u64,"peak_memory":0u64,"last_seen":now()}));
            if continuous {
                if let Some((ticks, read, write)) = self.previous.get(&p.id) {
                    row["cpu_seconds"] = json!(
                        row["cpu_seconds"].as_f64().unwrap_or(0.0)
                            + p.ticks.saturating_sub(*ticks) as f64 / hz
                    );
                    for (field, cur, prev) in [("read", p.read, *read), ("write", p.write, *write)]
                    {
                        if let (Some(a), Some(b)) = (cur, prev) {
                            row[field] = json!(row[field]
                                .as_u64()
                                .unwrap_or(0)
                                .saturating_add(a.saturating_sub(b)));
                        }
                    }
                }
            }
            row["peak_memory"] = json!(row["peak_memory"].as_u64().unwrap_or(0).max(p.memory));
            row["last_seen"] = json!(now());
        }
        self.previous = processes
            .iter()
            .map(|p| (p.id.clone(), (p.ticks, p.read, p.write)))
            .collect();
        if self.last.elapsed().as_secs() >= 30 {
            self.persist();
            self.last = Instant::now();
        }
    }
    pub fn view(&self) -> Value {
        json!({"rows":self.rows.values().collect::<Vec<_>>(),"since":self.since,"error":self.save_error,"note":"Your processes grouped by executable. CPU time and disk I/O accumulate only while this monitor is sampling. Network history per app is not available from procfs."})
    }
    pub fn reset(&mut self) -> Result<String, String> {
        let since = now();
        // Commit the reset before changing memory; a failed save must not erase the visible history.
        let bytes =
            serde_json::to_vec(&json!({"rows":[],"since":since})).map_err(|e| e.to_string())?;
        storage::atomic_write(&self.path, &bytes)?;
        self.rows.clear();
        self.previous.clear();
        self.since = since;
        self.save_error = None;
        self.preserve_unreadable = false;
        self.last = Instant::now();
        Ok("Usage history reset".into())
    }
    fn persist(&mut self) {
        if self.preserve_unreadable {
            return;
        }
        self.save_error = self
            .save()
            .err()
            .map(|e| format!("Usage history could not be saved: {e}"));
    }

    fn save(&self) -> Result<(), String> {
        storage::atomic_write(
            &self.path,
            serde_json::to_string(
                &json!({"rows":self.rows.values().collect::<Vec<_>>(), "since":self.since}),
            )
            .map_err(|e| e.to_string())?
            .as_bytes(),
        )
    }
}
impl Drop for History {
    fn drop(&mut self) {
        self.persist();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unreadable_history_is_preserved_until_explicit_reset() {
        let dir = std::env::temp_dir().join(format!(
            "task-manager-history-corrupt-{}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("history.json");
        fs::write(&path, b"broken JSON").unwrap();
        {
            let mut h = History::at_path(path.clone());
            assert!(h.view()["error"].is_string());
            h.persist();
        }
        assert_eq!(fs::read(&path).unwrap(), b"broken JSON");
        {
            let mut h = History::at_path(path.clone());
            h.reset().unwrap();
            assert!(h.view()["error"].is_null());
        }
        let h = History::at_path(path.clone());
        assert_eq!(h.view()["rows"], json!([]));
        drop(h);
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn failed_reset_preserves_rows_and_reports_save_failure() {
        let dir = std::env::temp_dir().join(format!(
            "task-manager-history-failed-{}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("history.json");
        fs::write(
            &path,
            br#"{"rows":[{"key":"app","cpu_seconds":12}],"since":1}"#,
        )
        .unwrap();
        let mut h = History::at_path(path.clone());
        fs::remove_file(&path).unwrap();
        fs::create_dir(&path).unwrap();
        assert!(h.reset().is_err());
        assert_eq!(h.view()["rows"][0]["cpu_seconds"], 12);
        h.persist();
        assert!(h.view()["error"].is_string());
        drop(h);
        fs::remove_dir_all(dir).unwrap();
    }
}
