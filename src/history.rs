use crate::{
    manage,
    process::{Identity, Process},
};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    fs,
    path::PathBuf,
    time::{Instant, SystemTime, UNIX_EPOCH},
};
pub struct History {
    rows: BTreeMap<String, Value>,
    previous: HashMap<Identity, (u64, Option<u64>, Option<u64>)>,
    last: Instant,
    path: PathBuf,
    since: u64,
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
        let v = fs::read(&path)
            .ok()
            .filter(|v| v.len() < 8 * 1024 * 1024)
            .and_then(|v| serde_json::from_slice::<Value>(&v).ok())
            .unwrap_or_default();
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
            let _ = self.save();
            self.last = Instant::now();
        }
    }
    pub fn view(&self) -> Value {
        json!({"rows":self.rows.values().collect::<Vec<_>>(),"since":self.since,"note":"Your processes grouped by executable. CPU time and disk I/O accumulate only while this monitor is sampling. Network history per app is not available from procfs."})
    }
    pub fn reset(&mut self) -> Result<String, String> {
        self.rows.clear();
        self.previous.clear();
        self.since = now();
        self.save()?;
        Ok("Usage history reset".into())
    }
    fn save(&self) -> Result<(), String> {
        manage::atomic_write(
            &self.path,
            serde_json::to_string(&self.view())
                .map_err(|e| e.to_string())?
                .as_bytes(),
        )
    }
}
impl Drop for History {
    fn drop(&mut self) {
        let _ = self.save();
    }
}
