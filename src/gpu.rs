//! Unprivileged GPU adapters. Absence of driver counters is not reported as zero.
use crate::process::Process;
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs,
    io::{self, BufRead, BufReader, Read},
    os::unix::process::CommandExt,
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex, PoisonError},
    time::{Duration, Instant},
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
    nvidia: Option<NvidiaStream>,
    nvidia_started: Option<Instant>,
}
impl Gpu {
    pub fn sample(&mut self, processes: &mut [Process], seconds: Option<f64>) -> Vec<Value> {
        let mut seen = HashSet::new();
        let mut next = HashMap::new();
        let mut engine_totals: BTreeMap<String, BTreeMap<String, f64>> = BTreeMap::new();
        for p in processes {
            let mut engines: BTreeMap<String, f64> = BTreeMap::new();
            let mut memory = None;
            for f in fs::read_dir(format!("/proc/{}/fd", p.id.pid))
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .take(4096)
                .filter(|f| drm_device(&f.path()))
            {
                let fdinfo = format!("/proc/{}/fdinfo/{}", p.id.pid, f.file_name().display());
                let Some(c) = fs::read_to_string(fdinfo).ok().and_then(|s| parse(&s)) else {
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
                    next.insert(key, n);
                    if let Some(usage) = engine_usage(
                        n,
                        prev.copied(),
                        seconds,
                        c.capacity.get(&engine).copied().unwrap_or(1),
                    ) {
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
            merge_nvidia(&mut devices, &self.nvidia_rows());
        }
        devices
    }
    fn nvidia_rows(&mut self) -> String {
        let exited = self.nvidia.as_mut().is_none_or(NvidiaStream::exited);
        if exited
            && self
                .nvidia_started
                .is_none_or(|t| t.elapsed() >= NVIDIA_RESTART)
        {
            self.nvidia = None;
            self.nvidia_started = Some(Instant::now());
            self.nvidia = NvidiaStream::spawn(
                "/usr/bin/nvidia-smi",
                &[
                    "--query-gpu=pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                    "--format=csv,noheader,nounits",
                    "-lms",
                    "1000",
                ],
            )
            .ok();
        }
        self.nvidia
            .as_ref()
            .map(NvidiaStream::fresh)
            .unwrap_or_default()
    }
}
const NVIDIA_STALE: Duration = Duration::from_secs(3);
const NVIDIA_RESTART: Duration = Duration::from_secs(10);
/// NVML initialisation dominates each nvidia-smi query (~35 ms CPU), so one
/// long-running query streams readings instead of spawning one per sample.
/// Lines are bounded, rows older than NVIDIA_STALE are withheld rather than
/// shown as live, and an exited stream restarts at most every NVIDIA_RESTART.
struct NvidiaStream {
    child: Child,
    rows: Arc<Mutex<BTreeMap<String, (Instant, String)>>>,
}
impl NvidiaStream {
    fn spawn(program: &str, args: &[&str]) -> io::Result<Self> {
        let parent = std::process::id() as libc::pid_t;
        let mut command = Command::new(program);
        command
            .args(args)
            .env("LC_ALL", "C")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0);
        // Bound to the sampling (main) thread: the stream cannot outlive a killed worker.
        unsafe {
            command.pre_exec(move || {
                if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) != 0 {
                    return Err(io::Error::last_os_error());
                }
                if libc::getppid() != parent {
                    return Err(io::Error::other("worker exited"));
                }
                Ok(())
            });
        }
        let child = command.spawn()?;
        let mut stream = Self {
            rows: Arc::default(),
            child,
        };
        let stdout = stream
            .child
            .stdout
            .take()
            .ok_or(io::ErrorKind::BrokenPipe)?;
        let rows = Arc::clone(&stream.rows);
        std::thread::Builder::new()
            .name("nvidia-smi".into())
            .spawn(move || read_nvidia(BufReader::new(stdout), &rows))?;
        // The first reading takes ~40 ms; keep the first snapshot complete.
        let start = Instant::now();
        while stream.fresh().is_empty()
            && !stream.exited()
            && start.elapsed() < Duration::from_secs(1)
        {
            std::thread::sleep(Duration::from_millis(10));
        }
        Ok(stream)
    }
    fn exited(&mut self) -> bool {
        !matches!(self.child.try_wait(), Ok(None))
    }
    fn fresh(&self) -> String {
        let rows = self.rows.lock().unwrap_or_else(PoisonError::into_inner);
        rows.values()
            .filter(|(time, _)| time.elapsed() < NVIDIA_STALE)
            .map(|(_, line)| line.as_str())
            .collect::<Vec<_>>()
            .join("\n")
    }
}
impl Drop for NvidiaStream {
    fn drop(&mut self) {
        // Signal only a child that has not been reaped; its group ID cannot be reused yet.
        if !self.exited() {
            unsafe {
                libc::kill(-(self.child.id() as i32), libc::SIGKILL);
            }
            let _ = self.child.wait();
        }
    }
}
/// Keeps the latest line per PCI bus ID. An overlong line or read error ends
/// the reader; the closed pipe then stops nvidia-smi on its next write.
fn read_nvidia(mut input: impl BufRead, rows: &Mutex<BTreeMap<String, (Instant, String)>>) {
    let mut line = String::new();
    loop {
        line.clear();
        match (&mut input).take(4096).read_line(&mut line) {
            Ok(n) if n > 0 && line.ends_with('\n') => {}
            _ => return,
        }
        let Some((bus, _)) = line.split_once(',') else {
            continue;
        };
        let mut rows = rows.lock().unwrap_or_else(PoisonError::into_inner);
        if rows.len() < 64 || rows.contains_key(bus) {
            rows.insert(bus.into(), (Instant::now(), line.trim_end().into()));
        }
    }
}
/// Only DRM (226) and compute-accelerator (261) character devices publish
/// drm-* fdinfo. One stat per descriptor replaces opening and parsing the
/// fdinfo of every socket, pipe and file on the system each sample.
fn drm_device(fd: &std::path::Path) -> bool {
    use std::os::unix::fs::{FileTypeExt, MetadataExt};
    fs::metadata(fd)
        .is_ok_and(|m| m.file_type().is_char_device() && matches!(libc::major(m.rdev()), 226 | 261))
}
fn engine_usage(now: u64, old: Option<u64>, seconds: Option<f64>, capacity: u64) -> Option<f64> {
    crate::metrics::delta(now, old?, seconds?)
        .map(|rate| 100.0 * rate / (1e9 * capacity.max(1) as f64))
}
fn merge_nvidia(devices: &mut Vec<Value>, output: &str) {
    let rows: Vec<_> = output.lines().filter_map(|line| {
        let cols: Vec<_> = line.split(',').map(str::trim).collect();
        if cols.len() != 7 || cols[0].is_empty() { return None; }
        let n = |i: usize| cols[i].parse::<f64>().ok().filter(|v| v.is_finite() && *v >= 0.0);
        Some(json!({"name":cols[1],"driver":"nvidia","device":cols[0],"usage":n(2),"memory_used":n(3).map(|v|v*1048576.0),"memory_total":n(4).map(|v|v*1048576.0),"temperature":n(5),"power_watts":n(6),"source":"NVIDIA device counters"}))
    }).collect();
    if !rows.is_empty() {
        devices.retain(|v| v["driver"] != "nvidia");
        devices.extend(rows);
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
    fn nvidia_keeps_multiple_devices_and_non_nvidia_adapters() {
        let mut devices = vec![
            json!({"driver":"amdgpu"}),
            json!({"driver":"nvidia","device":"fallback"}),
        ];
        merge_nvidia(&mut devices, "00000000:01:00.0, GPU A, 10, 100, 200, 40, 30\n00000000:02:00.0, GPU B, N/A, 300, 400, 50, 60\n");
        assert_eq!(devices.len(), 3);
        assert_eq!(devices[0]["driver"], "amdgpu");
        assert_eq!(devices[1]["name"], "GPU A");
        assert_eq!(devices[2]["name"], "GPU B");
        assert!(devices[2]["usage"].is_null());
        let before = devices.clone();
        merge_nvidia(&mut devices, "malformed output");
        assert_eq!(devices, before);
    }
    const ROW_A: &str = "00000000:01:00.0, GPU A, 10, 100, 200, 40, 30";
    const ROW_B: &str = "00000000:02:00.0, GPU B, 20, 300, 400, 50, 60";
    #[test]
    fn nvidia_stream_keeps_latest_row_per_device_and_withholds_stale_rows() {
        let rows = Mutex::default();
        let older = ROW_A.replace(", 10,", ", 99,");
        read_nvidia(
            io::Cursor::new(format!("{older}\n{ROW_B}\n{ROW_A}\nmalformed\n")),
            &rows,
        );
        let stream = NvidiaStream {
            child: {
                let mut done = Command::new("/usr/bin/true").spawn().unwrap();
                done.wait().unwrap();
                done
            },
            rows: Arc::new(rows),
        };
        assert_eq!(stream.fresh(), format!("{ROW_A}\n{ROW_B}"));
        let mut devices = vec![];
        merge_nvidia(&mut devices, &stream.fresh());
        assert_eq!(devices.len(), 2);
        assert_eq!(devices[0]["usage"], 10.0);
        stream
            .rows
            .lock()
            .unwrap()
            .get_mut("00000000:02:00.0")
            .unwrap()
            .0 -= NVIDIA_STALE;
        assert_eq!(stream.fresh(), ROW_A);
    }
    #[test]
    fn nvidia_stream_rejects_overlong_lines() {
        let rows = Mutex::default();
        read_nvidia(
            io::Cursor::new(format!("{}\n{ROW_A}\n", "x".repeat(8192))),
            &rows,
        );
        assert!(rows.lock().unwrap().is_empty());
    }
    #[test]
    fn nvidia_stream_is_live_and_stopped_with_its_owner() {
        let script = format!("while :; do echo '{ROW_A}'; sleep 0.05; done");
        let mut stream = NvidiaStream::spawn("/bin/sh", &["-c", &script]).unwrap();
        assert_eq!(stream.fresh(), ROW_A);
        assert!(!stream.exited());
        let pid = stream.child.id() as i32;
        drop(stream);
        assert_ne!(
            unsafe { libc::kill(pid, 0) },
            0,
            "stream child was not reaped"
        );
        // A failed stream reports no rows and is detected as exited.
        let mut failed = NvidiaStream::spawn("/usr/bin/false", &[]).unwrap();
        assert!(failed.fresh().is_empty());
        let start = Instant::now();
        while !failed.exited() && start.elapsed() < Duration::from_secs(2) {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(failed.exited());
    }
    #[test]
    fn engine_reset_is_unknown_and_recovers_on_next_sample() {
        assert_eq!(engine_usage(100, Some(1000), Some(1.0), 1), None);
        assert_eq!(
            engine_usage(500_000_100, Some(100), Some(1.0), 2),
            Some(25.0)
        );
        assert_eq!(engine_usage(1000, Some(100), None, 1), None);
    }
    #[test]
    fn only_drm_descriptors_are_inspected() {
        let null = fs::File::open("/dev/null").unwrap();
        let file = fs::File::open("/proc/self/stat").unwrap();
        for f in [&null, &file] {
            use std::os::fd::AsRawFd;
            assert!(!drm_device(std::path::Path::new(&format!(
                "/proc/self/fd/{}",
                f.as_raw_fd()
            ))));
        }
        assert!(!drm_device(std::path::Path::new("/proc/self/fd/-1")));
        // Portable CI has no GPU; exercise a real render node where one exists.
        if let Some(node) = fs::read_dir("/dev/dri")
            .into_iter()
            .flatten()
            .flatten()
            .find(|e| e.file_name().to_string_lossy().starts_with("renderD"))
        {
            if let Ok(render) = fs::File::open(node.path()) {
                use std::os::fd::AsRawFd;
                assert!(drm_device(std::path::Path::new(&format!(
                    "/proc/self/fd/{}",
                    render.as_raw_fd()
                ))));
            }
        }
    }
    #[test]
    fn drm_units_and_capacity() {
        let c=parse("drm-driver: xe\ndrm-client-id: 8\ndrm-pdev: 0000:00:02.0\ndrm-engine-render: 500 ns\ndrm-engine-capacity-render: 2\ndrm-resident-system: 128 KiB\n").unwrap();
        assert_eq!(c.engines["render"], 500);
        assert_eq!(c.capacity["render"], 2);
        assert_eq!(c.memory, Some(131072));
        assert!(parse("pos: 0").is_none());
    }
}
