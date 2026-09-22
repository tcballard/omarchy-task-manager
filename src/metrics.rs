use crate::process::{self, Identity, Process};
use serde_json::{json, Value};
use std::{collections::HashMap, fs, time::Instant};

pub fn delta(now: u64, old: u64, seconds: f64) -> Option<f64> {
    if seconds <= 0.0 || !seconds.is_finite() {
        return None;
    }
    now.checked_sub(old).map(|d| d as f64 / seconds)
}
fn continuous(seconds: f64, boot_delta: f64) -> bool {
    seconds > 0.0 && seconds < 15.0 && (seconds - boot_delta).abs() < 0.5
}
fn process_cpu(rate: f64, hz: f64, cores: f64) -> f64 {
    (100.0 * rate / hz / cores).min(100.0)
}
fn read(path: &str) -> String {
    fs::read_to_string(path).unwrap_or_default()
}
fn cpu_ticks() -> Vec<(String, u64, u64)> {
    read("/proc/stat")
        .lines()
        .filter(|l| l.starts_with("cpu"))
        .filter_map(|l| {
            let mut f = l.split_whitespace();
            let name = f.next()?.to_string();
            let v: Vec<u64> = f.take(8).map(|s| s.parse().unwrap_or(0)).collect();
            if v.len() < 4 {
                return None;
            }
            let total = v.iter().sum();
            let idle = v[3] + v.get(4).copied().unwrap_or(0);
            Some((name, total, idle))
        })
        .collect()
}
fn mem() -> Value {
    let m: HashMap<String, u64> = read("/proc/meminfo")
        .lines()
        .filter_map(|l| {
            let mut s = l.split_whitespace();
            Some((
                s.next()?.trim_end_matches(':').into(),
                s.next()?.parse::<u64>().ok()? * 1024,
            ))
        })
        .collect();
    let n = |s: &str| m.get(s).copied().unwrap_or(0);
    json!({"total":n("MemTotal"),"available":n("MemAvailable"),"used":n("MemTotal").saturating_sub(n("MemAvailable")),"commit_limit":n("CommitLimit"),"committed":n("Committed_AS"),"buffers":n("Buffers"),"slab":n("Slab"),"cache":n("Cached")+n("SReclaimable"),"swap_total":n("SwapTotal"),"swap_used":n("SwapTotal").saturating_sub(n("SwapFree"))})
}
fn net() -> HashMap<String, (u64, u64)> {
    read("/proc/net/dev")
        .lines()
        .filter_map(|l| {
            let (name, values) = l.split_once(':')?;
            let f: Vec<_> = values.split_whitespace().collect();
            Some((
                name.trim().into(),
                (f.first()?.parse().ok()?, f.get(8)?.parse().ok()?),
            ))
        })
        .collect()
}
fn disk() -> HashMap<String, (u64, u64)> {
    read("/proc/diskstats")
        .lines()
        .filter_map(|l| {
            let f: Vec<_> = l.split_whitespace().collect();
            let name = *f.get(2)?;
            if !std::path::Path::new(&format!("/sys/block/{name}")).exists()
                || name.starts_with("loop")
                || name.starts_with("ram")
            {
                return None;
            }
            Some((
                name.into(),
                (
                    f.get(5)?.parse::<u64>().ok()?.saturating_mul(512),
                    f.get(9)?.parse::<u64>().ok()?.saturating_mul(512),
                ),
            ))
        })
        .collect()
}
fn unescape_mount(s: &str) -> String {
    s.replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
        .replace("\\134", "\\")
}
fn mounts() -> Vec<Value> {
    read("/proc/self/mounts").lines().filter_map(|l| {
        let f:Vec<_>=l.split_whitespace().collect();let dev=*f.first()?;let mount=unescape_mount(f.get(1)?);
        if !dev.starts_with("/dev/") {return None;}
        let c=std::ffi::CString::new(mount.as_bytes()).ok()?;let mut s=std::mem::MaybeUninit::<libc::statvfs>::uninit();
        if unsafe{libc::statvfs(c.as_ptr(),s.as_mut_ptr())}!=0{return None;}let s=unsafe{s.assume_init()};
        Some(json!({"name":mount,"device":dev,"total":s.f_blocks*s.f_frsize,"available":s.f_bavail*s.f_frsize,"used":s.f_blocks.saturating_sub(s.f_bfree)*s.f_frsize}))
    }).collect()
}
fn hardware() -> Value {
    let batteries:Vec<Value>=fs::read_dir("/sys/class/power_supply").into_iter().flatten().filter_map(Result::ok).filter_map(|e| {
        let p=e.path(); if fs::read_to_string(p.join("type")).ok()?.trim()!="Battery" {return None;}
        Some(json!({"name":e.file_name().to_string_lossy(),"percent":fs::read_to_string(p.join("capacity")).ok().and_then(|s|s.trim().parse::<u32>().ok()),"status":fs::read_to_string(p.join("status")).unwrap_or_default().trim()}))
    }).collect();
    let mut sensors = Vec::new();
    for e in fs::read_dir("/sys/class/hwmon")
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
    {
        let name = fs::read_to_string(e.path().join("name"))
            .unwrap_or_default()
            .trim()
            .to_string();
        for t in fs::read_dir(e.path())
            .into_iter()
            .flatten()
            .filter_map(Result::ok)
        {
            let file = t.file_name().to_string_lossy().to_string();
            if file.starts_with("temp") && file.ends_with("_input") {
                if let Some(v) = fs::read_to_string(t.path())
                    .ok()
                    .and_then(|s| s.trim().parse::<f64>().ok())
                {
                    if (-50000.0..200000.0).contains(&v) {
                        sensors.push(json!({"name":format!("{} {}",name,file.trim_end_matches("_input")),"celsius":v/1000.0}));
                    }
                }
            }
        }
    }
    json!({"batteries":batteries,"sensors":sensors,"gpu_status":"GPU counters depend on driver support and permissions"})
}
pub struct Sampler {
    mounts: crate::slow::Collector,
    gpu: crate::gpu::Gpu,
    time: Option<Instant>,
    uptime: Option<f64>,
    cpus: Vec<(String, u64, u64)>,
    processes: HashMap<Identity, Process>,
    networks: HashMap<String, (u64, u64)>,
    disks: HashMap<String, (u64, u64)>,
    disk_extra: HashMap<String, (u64, u64, u64)>,
}
impl Sampler {
    pub fn new() -> Self {
        Self {
            mounts: crate::slow::Collector::new(mounts),
            gpu: crate::gpu::Gpu::default(),
            time: None,
            uptime: None,
            cpus: vec![],
            processes: HashMap::new(),
            networks: HashMap::new(),
            disks: HashMap::new(),
            disk_extra: HashMap::new(),
        }
    }
    pub fn invalidate(&mut self) {
        self.time = None;
        self.uptime = None;
    }
    pub fn sample(&mut self) -> (Value, Vec<Process>) {
        let now = Instant::now();
        let seconds = self.time.map(|t| now.duration_since(t).as_secs_f64());
        let uptime = read("/proc/uptime")
            .split_whitespace()
            .next()
            .and_then(|s| s.parse::<f64>().ok());
        let boot_delta = uptime.zip(self.uptime).map(|(a, b)| a - b);
        let valid = seconds.filter(|s| boot_delta.is_some_and(|b| continuous(*s, b)));
        let cpus = cpu_ticks();
        let mut processes = process::list();
        let cores = cpus.len().saturating_sub(1).max(1) as f64;
        let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
        let cpu: Vec<Value> = cpus
            .iter()
            .map(|(name, total, idle)| {
                let usage = if valid.is_some() {
                    self.cpus
                        .iter()
                        .find(|c| &c.0 == name)
                        .and_then(|(_, t, i)| {
                            let dt = total.checked_sub(*t)?;
                            let di = idle.checked_sub(*i)?;
                            if dt == 0 || di > dt {
                                None
                            } else {
                                Some(100.0 * (dt - di) as f64 / dt as f64)
                            }
                        })
                } else {
                    None
                };
                json!({"name":name,"usage":usage})
            })
            .collect();
        for p in &mut processes {
            if let (Some(old), Some(s)) = (self.processes.get(&p.id), valid) {
                p.cpu = delta(p.ticks, old.ticks, s).map(|r| process_cpu(r, hz, cores));
                p.read_rate = p.read.zip(old.read).and_then(|(a, b)| delta(a, b, s));
                p.write_rate = p.write.zip(old.write).and_then(|(a, b)| delta(a, b, s));
            }
        }
        let gpus = self.gpu.sample(&mut processes, valid);
        let networks = net();
        let disks = disk();
        let rates = |new: &HashMap<String, (u64, u64)>,
                     old: &HashMap<String, (u64, u64)>|
         -> Vec<Value> {
            let mut keys: Vec<_> = new.keys().collect();
            keys.sort();
            keys.into_iter().map(|name| {
                let (a,b)=new[name];let r=old.get(name).zip(valid);
                json!({"name":name,"first":a,"second":b,"first_rate":r.and_then(|((o,_),s)|delta(a,*o,s)),"second_rate":r.and_then(|((_,o),s)|delta(b,*o,s))})
            }).collect()
        };
        let disk_extra: HashMap<String, (u64, u64, u64)> = read("/proc/diskstats")
            .lines()
            .filter_map(|l| {
                let f: Vec<_> = l.split_whitespace().collect();
                Some((
                    f.get(2)?.to_string(),
                    (
                        f.get(12)?.parse().ok()?,
                        f.get(3)?
                            .parse::<u64>()
                            .ok()?
                            .saturating_add(f.get(7)?.parse().ok()?),
                        f.get(6)?
                            .parse::<u64>()
                            .ok()?
                            .saturating_add(f.get(10)?.parse().ok()?),
                    ),
                ))
            })
            .collect();
        let mut disk_rates = rates(&disks, &self.disks);
        for d in &mut disk_rates {
            let name = d["name"].as_str().unwrap_or("").to_string();
            if let Some((busy, ops, wait)) = disk_extra.get(&name) {
                if let Some((old, s)) = self.disk_extra.get(&name).zip(valid) {
                    d["active_percent"] =
                        json!(delta(*busy, old.0, s).map(|v| (v / 10.0).min(100.0)));
                    d["response_ms"] = json!(ops
                        .checked_sub(old.1)
                        .filter(|n| *n > 0)
                        .and_then(|n| wait.checked_sub(old.2).map(|v| v as f64 / n as f64)));
                }
            }
            d["model"] = json!(read(&format!("/sys/block/{name}/device/model")).trim());
        }
        let mut networks_view = rates(&networks, &self.networks);
        for n in &mut networks_view {
            let name = n["name"].as_str().unwrap_or("").to_string();
            n["state"] = json!(read(&format!("/sys/class/net/{name}/operstate")).trim());
            n["mac"] = json!(read(&format!("/sys/class/net/{name}/address")).trim());
            n["speed_mbps"] = json!(read(&format!("/sys/class/net/{name}/speed"))
                .trim()
                .parse::<i64>()
                .ok()
                .filter(|n| *n > 0));
        }
        let cpuinfo = read("/proc/cpuinfo");
        let cpu_model = cpuinfo.lines().find_map(|l| {
            l.strip_prefix("model name")
                .and_then(|s| s.split_once(':'))
                .map(|(_, s)| s.trim())
        });
        let mhz: Vec<f64> = cpuinfo
            .lines()
            .filter_map(|l| {
                l.strip_prefix("cpu MHz")
                    .and_then(|s| s.split_once(':'))
                    .and_then(|(_, s)| s.trim().parse().ok())
            })
            .collect();
        let avg_mhz = if mhz.is_empty() {
            None
        } else {
            Some(mhz.iter().sum::<f64>() / mhz.len() as f64)
        };
        let thread_count: u64 = processes.iter().map(|p| p.threads).sum();
        self.disk_extra = disk_extra;
        let capacity = self.mounts.poll();
        let result = json!({"cpu_model":cpu_model,"cpu_mhz":avg_mhz,"process_count":processes.len(),"thread_count":thread_count,"gpus":gpus,"cpu":cpu,"memory":mem(),"network":networks_view,"disks":disk_rates,"mounts":capacity["rows"],"mounts_status":capacity["message"],"hardware":hardware(),"load":read("/proc/loadavg").split_whitespace().take(3).collect::<Vec<_>>().join("  "),"uptime":uptime,"cores":cores,"continuous":valid.is_some()});
        self.time = Some(now);
        self.uptime = uptime;
        self.cpus = cpus;
        self.networks = networks;
        self.disks = disks;
        self.processes = processes
            .iter()
            .map(|p| (p.id.clone(), p.clone()))
            .collect();
        (result, processes)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn suspend_gap_invalidates_rates() {
        assert!(continuous(1.0, 1.01));
        assert!(!continuous(1.0, 301.0));
        assert!(!continuous(20.0, 20.0));
    }
    #[test]
    fn cpu_uses_whole_machine_capacity() {
        assert_eq!(process_cpu(100.0, 100.0, 8.0), 12.5);
    }
    #[test]
    fn counter_reset_and_bad_time() {
        assert_eq!(delta(1, 2, 1.0), None);
        assert_eq!(delta(2, 1, 0.0), None);
        assert_eq!(delta(200, 100, 2.0), Some(50.0));
    }
    #[test]
    fn mount_escapes() {
        assert_eq!(unescape_mount("/a\\040b"), "/a b");
    }
    #[test]
    fn first_sample_pending() {
        let (s, p) = Sampler::new().sample();
        assert!(s["cpu"][0]["usage"].is_null());
        assert!(p.iter().all(|p| p.cpu.is_none()));
        assert!(s["memory"]["total"].as_u64().unwrap() > 0);
    }
}

/// Basic procfs counters only: collected independently of the GUI.
#[derive(Default)]
pub struct BasicSampler {
    time: Option<u64>,
    monotonic: Option<Instant>,
    cpus: Vec<(String, u64, u64)>,
    networks: HashMap<String, (u64, u64)>,
    disks: HashMap<String, (u64, u64)>,
}
impl BasicSampler {
    pub fn sample(&mut self, now: u64) -> (Value, bool) {
        let instant = Instant::now();
        let seconds = self.monotonic.map(|t| instant.duration_since(t).as_secs_f64());
        let boot_delta = self.time.and_then(|t| now.checked_sub(t)).map(|t| t as f64 / 1000.0);
        let valid = seconds.filter(|s| boot_delta.is_some_and(|b| continuous(*s, b)));
        let cpus = cpu_ticks();
        let mut point = json!({"time":now});
        for (name, total, idle) in &cpus {
            let usage = valid.and_then(|_| self.cpus.iter().find(|c| &c.0 == name))
                .and_then(|(_, t, i)| {
                    let dt = total.checked_sub(*t)?;
                    let di = idle.checked_sub(*i)?;
                    (dt > 0 && di <= dt).then(|| 100.0 * (dt - di) as f64 / dt as f64)
                });
            point[name] = json!(usage);
        }
        let memory = mem();
        point["memory"] = json!(memory["total"].as_f64().filter(|v| *v > 0.0)
            .map(|total| 100.0 * memory["used"].as_f64().unwrap_or(0.0) / total));
        let networks = net();
        let disks = disk();
        for (category, new, old) in [("network", &networks, &self.networks), ("disks", &disks, &self.disks)] {
            for (name, (a, b)) in new {
                let prior = old.get(name).zip(valid);
                point[format!("{category}:{name}:first")] = json!(prior.and_then(|((o,_),s)| delta(*a,*o,s)));
                point[format!("{category}:{name}:second")] = json!(prior.and_then(|((_,o),s)| delta(*b,*o,s)));
            }
        }
        self.time = Some(now); self.monotonic = Some(instant);
        self.cpus = cpus; self.networks = networks; self.disks = disks;
        (point, valid.is_some())
    }
}
