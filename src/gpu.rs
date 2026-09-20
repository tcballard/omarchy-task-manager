//! Unprivileged GPU adapters. Absence of driver counters is not reported as zero.
use crate::{manage, process::Process};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs,
};
#[derive(Default, Debug)]
struct Client {
    device: String,
    id: String,
    engines: BTreeMap<String, u64>,
    capacity: BTreeMap<String, u64>,
    memory: Option<u64>,
}
fn parse(text: &str) -> Option<Client> {
    let mut c = Client::default();
    let mut driver = false;
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        match key {
            "drm-driver" => driver = true,
            "drm-pdev" => c.device = value.into(),
            "drm-client-id" => c.id = value.into(),
            _ => {
                let n = value
                    .split_whitespace()
                    .next()
                    .and_then(|s| s.parse::<u64>().ok());
                if let Some(n) = n {
                    if let Some(k) = key.strip_prefix("drm-engine-capacity-") {
                        c.capacity.insert(k.into(), n.max(1));
                    } else if let Some(k) = key.strip_prefix("drm-engine-") {
                        if value.ends_with(" ns") {
                            c.engines.insert(k.into(), n);
                        }
                    } else if key.starts_with("drm-resident-") {
                        let n = if value.ends_with("KiB") {
                            n.saturating_mul(1024)
                        } else if value.ends_with("MiB") {
                            n.saturating_mul(1024 * 1024)
                        } else {
                            n
                        };
                        c.memory = Some(c.memory.unwrap_or(0).saturating_add(n));
                    }
                }
            }
        }
    }
    if driver && !c.id.is_empty() {
        Some(c)
    } else {
        None
    }
}
#[derive(Default)]
pub struct Gpu {
    previous: HashMap<String, u64>,
}
impl Gpu {
    pub fn sample(&mut self, processes: &mut [Process], seconds: Option<f64>) -> Vec<Value> {
        let mut seen = HashSet::new();
        let mut next = HashMap::new();
        let mut engine_totals: BTreeMap<String, BTreeMap<String, f64>> = BTreeMap::new();
        for p in processes {
            let mut engines: BTreeMap<String, f64> = BTreeMap::new();
            let mut memory = None;
            for f in fs::read_dir(format!("/proc/{}/fdinfo", p.id.pid))
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .take(4096)
            {
                let Some(c) = fs::read_to_string(f.path()).ok().and_then(|s| parse(&s)) else {
                    continue;
                };
                let client = format!("{}:{}", c.device, c.id);
                if !seen.insert(client.clone()) {
                    continue;
                }
                if let Some(m) = c.memory {
                    memory = Some(memory.unwrap_or(0u64).saturating_add(m));
                }
                for (engine, n) in c.engines {
                    let key = format!("{client}:{engine}");
                    let prev = self.previous.get(&key);
                    let high = prev.copied().unwrap_or(n).max(n);
                    next.insert(key, high);
                    if let Some((old, s)) = prev.zip(seconds) {
                        let usage = 100.0 * high.saturating_sub(*old) as f64
                            / (s * 1e9 * c.capacity.get(&engine).copied().unwrap_or(1) as f64);
                        *engines.entry(engine.clone()).or_default() += usage;
                        *engine_totals
                            .entry(c.device.clone())
                            .or_default()
                            .entry(engine)
                            .or_default() += usage;
                    }
                }
            }
            p.gpu = engines
                .values()
                .copied()
                .reduce(f64::max)
                .map(|n| n.min(100.0));
            p.gpu_memory = memory;
        }
        self.previous = next;
        let mut devices = Vec::new();
        for e in fs::read_dir("/sys/class/drm")
            .into_iter()
            .flatten()
            .filter_map(Result::ok)
        {
            let name = e.file_name().to_string_lossy().to_string();
            if !name
                .strip_prefix("card")
                .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
            {
                continue;
            }
            let d = e.path().join("device");
            let read = |file: &str| {
                fs::read_to_string(d.join(file))
                    .unwrap_or_default()
                    .trim()
                    .to_string()
            };
            let number = |file: &str| read(file).parse::<f64>().ok();
            let driver = fs::read_link(d.join("driver"))
                .ok()
                .and_then(|p| p.file_name().map(|s| s.to_string_lossy().to_string()))
                .unwrap_or_default();
            let pci = fs::canonicalize(&d)
                .ok()
                .and_then(|p| p.file_name().map(|s| s.to_string_lossy().to_string()))
                .unwrap_or_default();
            let observed = engine_totals.get(&pci);
            let usage = number("gpu_busy_percent");
            devices.push(json!({"name":name,"driver":driver,"device":pci,"usage":usage.or_else(||observed.and_then(|v|v.values().copied().reduce(f64::max)).map(|n|n.min(100.0))),"memory_used":number("mem_info_vram_used"),"memory_total":number("mem_info_vram_total"),"frequency_mhz":number("gt_cur_freq_mhz"),"engines":observed,"source":if usage.is_some(){"Driver device counter"}else{"Visible DRM clients only; shared clients counted once"}}));
        }
        if PathExists::nvidia() {
            if let Ok(output)=manage::run("/usr/bin/nvidia-smi", &["--query-gpu=pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw", "--format=csv,noheader,nounits"]){
   for line in output.lines(){let cols:Vec<_>=line.split(',').map(str::trim).collect();if cols.len()!=7{continue;}let n=|i:usize|cols[i].parse::<f64>().ok();
    devices.retain(|v|v["driver"]!="nvidia");devices.push(json!({"name":cols[1],"driver":"nvidia","device":cols[0],"usage":n(2),"memory_used":n(3).map(|v|v*1048576.0),"memory_total":n(4).map(|v|v*1048576.0),"temperature":n(5),"power_watts":n(6),"source":"NVIDIA device counters"}));
   }
  }
        }
        devices
    }
}
struct PathExists;
impl PathExists {
    fn nvidia() -> bool {
        std::path::Path::new("/usr/bin/nvidia-smi").exists()
            && std::path::Path::new("/proc/driver/nvidia").exists()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn drm_units_and_capacity() {
        let c=parse("drm-driver: xe\ndrm-client-id: 8\ndrm-pdev: 0000:00:02.0\ndrm-engine-render: 500 ns\ndrm-engine-capacity-render: 2\ndrm-resident-system: 128 KiB\n").unwrap();
        assert_eq!(c.engines["render"], 500);
        assert_eq!(c.capacity["render"], 2);
        assert_eq!(c.memory, Some(131072));
        assert!(parse("pos: 0").is_none());
    }
}
