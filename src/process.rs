use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    fs, io,
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    path::Path,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Identity {
    pub pid: i32,
    pub start: u64,
}
#[derive(Debug, Clone, Serialize)]
pub struct Process {
    pub id: Identity,
    pub ppid: i32,
    pub name: String,
    pub command: String,
    pub uid: u32,
    pub user: String,
    pub state: String,
    pub ticks: u64,
    pub memory: u64,
    pub cpu: Option<f64>,
    pub read: Option<u64>,
    pub write: Option<u64>,
    pub read_rate: Option<f64>,
    pub write_rate: Option<f64>,
    pub protected: bool,
    pub nice: i32,
    pub threads: u64,
    pub virtual_memory: u64,
    pub cpu_seconds: f64,
    pub gpu: Option<f64>,
    pub gpu_memory: Option<u64>,
}
fn number<T: std::str::FromStr>(s: &str) -> io::Result<T> {
    s.parse()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "invalid process field"))
}
pub fn parse_stat(s: &str) -> io::Result<(String, Vec<&str>)> {
    let a = s
        .find('(')
        .ok_or_else(|| io::Error::other("missing name"))?;
    let b = s
        .rfind(')')
        .filter(|b| *b > a)
        .ok_or_else(|| io::Error::other("missing name end"))?;
    let fields: Vec<_> = s[b + 1..].split_whitespace().collect();
    if fields.len() < 22 {
        return Err(io::Error::other("short process stat"));
    }
    Ok((s[a + 1..b].to_string(), fields))
}
pub fn read_one(pid: i32) -> io::Result<Process> {
    let base = format!("/proc/{pid}");
    let stat = fs::read_to_string(format!("{base}/stat"))?;
    let (comm, f) = parse_stat(&stat)?;
    let name = fs::read_link(format!("{base}/exe"))
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .unwrap_or(comm);
    let status = fs::read_to_string(format!("{base}/status"))?;
    let uid = status
        .lines()
        .find_map(|l| l.strip_prefix("Uid:"))
        .and_then(|s| s.split_whitespace().next())
        .ok_or_else(|| io::Error::other("missing owner"))?;
    let command = fs::read(format!("{base}/cmdline"))
        .map(|v| {
            String::from_utf8_lossy(&v)
                .replace('\0', " ")
                .trim()
                .to_string()
        })
        .unwrap_or_default();
    let io = fs::read_to_string(format!("{base}/io")).unwrap_or_default();
    let counter = |key: &str| {
        io.lines()
            .find_map(|l| l.strip_prefix(key))
            .and_then(|v| v.trim().parse().ok())
    };
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(1) as u64;
    let rss: i64 = number(f[21])?;
    Ok(Process {
        id: Identity {
            pid,
            start: number(f[19])?,
        },
        ppid: number(f[1])?,
        name,
        command,
        uid: number(uid)?,
        user: uid.to_string(),
        state: f[0].to_string(),
        ticks: number::<u64>(f[11])?.saturating_add(number(f[12])?),
        memory: rss.max(0) as u64 * page,
        cpu: None,
        read: counter("read_bytes:"),
        write: counter("write_bytes:"),
        read_rate: None,
        write_rate: None,
        protected: false,
        gpu: None,
        gpu_memory: None,
        nice: number(f[16])?,
        threads: number(f[17])?,
        virtual_memory: number(f[20])?,
        cpu_seconds: (number::<u64>(f[11])?.saturating_add(number(f[12])?)) as f64
            / unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64,
    })
}
pub fn list() -> Vec<Process> {
    let users: HashMap<u32, String> = fs::read_to_string("/etc/passwd")
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            let p: Vec<_> = l.split(':').collect();
            Some((p.get(2)?.parse().ok()?, p.first()?.to_string()))
        })
        .collect();
    let mut v: Vec<_> = fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|p| p.file_name().to_str()?.parse().ok())
        .filter_map(|pid| read_one(pid).ok())
        .collect();
    let protected = protected_ids(&v);
    for p in &mut v {
        p.user = users
            .get(&p.uid)
            .cloned()
            .unwrap_or_else(|| p.uid.to_string());
        p.protected = protected.contains(&p.id.pid);
    }
    v
}
fn critical(p: &Process) -> bool {
    let exe = fs::read_link(format!("/proc/{}/exe", p.id.pid)).ok();
    let name = exe
        .as_deref()
        .and_then(Path::file_name)
        .and_then(|s| s.to_str())
        .unwrap_or(&p.name)
        .to_ascii_lowercase();
    p.id.pid <= 1
        || [
            "hyprland",
            "quickshell",
            "qs",
            "systemd",
            "dbus-daemon",
            "dbus-broker",
            "dbus-broker-launch",
            "omarchy-task-manager",
            "omarchy-task-manager-core",
        ]
        .contains(&name.as_str())
}
pub fn protected_ids(v: &[Process]) -> HashSet<i32> {
    let parents: HashMap<_, _> = v.iter().map(|p| (p.id.pid, p.ppid)).collect();
    let mut ids: HashSet<_> = v.iter().filter(|p| critical(p)).map(|p| p.id.pid).collect();
    ids.insert(std::process::id() as i32);
    for seed in ids.clone() {
        let mut pid = seed;
        let mut visited = HashSet::new();
        while visited.insert(pid) {
            ids.insert(pid);
            match parents.get(&pid) {
                Some(p) if *p > 0 => pid = *p,
                _ => break,
            }
        }
    }
    ids
}
pub fn validate_target(
    p: &Process,
    id: &Identity,
    uid: u32,
    protected: &HashSet<i32>,
) -> Result<(), String> {
    if &p.id != id {
        return Err("Process changed or exited; refresh and try again".into());
    }
    if p.uid != uid {
        return Err("Only your own processes can be controlled".into());
    }
    if protected.contains(&id.pid) {
        return Err("This process is required by the desktop or monitor".into());
    }
    Ok(())
}
pub fn signal(id: &Identity, force: bool) -> Result<String, String> {
    send_signal(id, if force { libc::SIGKILL } else { libc::SIGTERM })
}
pub fn send_signal(id: &Identity, sig: i32) -> Result<String, String> {
    if ![libc::SIGTERM, libc::SIGKILL, libc::SIGSTOP, libc::SIGCONT].contains(&sig) {
        return Err("Invalid signal".into());
    }
    // Pin the kernel process before checking /proc, then send through that descriptor.
    let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, id.pid, 0) } as i32;
    if fd < 0 {
        return Err(format!(
            "Cannot open process: {}",
            io::Error::last_os_error()
        ));
    }
    let fd = unsafe { OwnedFd::from_raw_fd(fd) };
    let all = list();
    let p = read_one(id.pid).map_err(|_| "Process has exited".to_string())?;
    validate_target(&p, id, unsafe { libc::getuid() }, &protected_ids(&all))?;
    let result = unsafe {
        libc::syscall(
            libc::SYS_pidfd_send_signal,
            fd.as_raw_fd(),
            sig,
            std::ptr::null::<libc::siginfo_t>(),
            0,
        )
    };
    if result < 0 {
        Err(io::Error::last_os_error().to_string())
    } else {
        Ok(format!("{}: signal sent", id.pid))
    }
}
/// Linux nice and affinity APIs use a numeric task ID. Revalidate each thread
/// immediately before mutation, and report any concurrent exit/permission error.
pub fn tune(id: &Identity, nice: Option<i32>, cpus: Option<Vec<usize>>) -> Result<String, String> {
    let leader = read_one(id.pid).map_err(|e| e.to_string())?;
    validate_target(
        &leader,
        id,
        unsafe { libc::getuid() },
        &protected_ids(&list()),
    )?;
    if nice.is_some_and(|v| !(-20..=19).contains(&v)) {
        return Err("Nice must be between -20 and 19".into());
    }
    let mut set: libc::cpu_set_t = unsafe { std::mem::zeroed() };
    if let Some(ref cpus) = cpus {
        if cpus.is_empty() || cpus.iter().any(|c| *c >= libc::CPU_SETSIZE as usize) {
            return Err("Choose at least one valid CPU".into());
        }
        unsafe {
            libc::CPU_ZERO(&mut set);
            for c in cpus {
                libc::CPU_SET(*c, &mut set);
            }
        }
    }
    let tasks: Vec<_> = fs::read_dir(format!("/proc/{}/task", id.pid))
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .filter_map(|e| e.file_name().to_str()?.parse::<i32>().ok())
        .filter_map(|tid| read_one(tid).ok())
        .collect();
    let mut success = 0;
    let mut failures = Vec::new();
    for t in tasks {
        let current = read_one(t.id.pid).map_err(|e| e.to_string())?;
        validate_target(&current, &t.id, leader.uid, &HashSet::new())?;
        if read_one(id.pid).map_err(|_| "Process exited")?.id != *id {
            return Err("Process changed".into());
        }
        let r = unsafe {
            if let Some(n) = nice {
                libc::setpriority(libc::PRIO_PROCESS, t.id.pid as u32, n)
            } else if cpus.is_some() {
                libc::sched_setaffinity(t.id.pid, std::mem::size_of::<libc::cpu_set_t>(), &set)
            } else {
                return Err("No setting supplied".into());
            }
        };
        if r == 0 {
            success += 1;
        } else {
            failures.push(format!("{}: {}", t.id.pid, io::Error::last_os_error()));
        }
    }
    if !failures.is_empty() {
        Err(format!(
            "Updated {success} threads; failures: {}",
            failures.join("; ")
        ))
    } else {
        Ok(format!(
            "Updated {success} threads. New threads inherit their creator's settings."
        ))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names_can_contain_parentheses() {
        let s = format!("12 (a ) b) S {}", vec!["0"; 21].join(" "));
        assert_eq!(parse_stat(&s).unwrap().0, "a ) b");
    }
    #[test]
    fn short_stat_rejected() {
        assert!(parse_stat("1 (x) S 0").is_err());
    }
    #[test]
    fn current_identity_and_owner_enforced() {
        let p = read_one(std::process::id() as i32).unwrap();
        let mut id = p.id.clone();
        id.start += 1;
        assert!(validate_target(&p, &id, p.uid, &HashSet::new()).is_err());
        assert!(validate_target(&p, &p.id, p.uid + 1, &HashSet::new()).is_err());
        assert!(validate_target(&p, &p.id, p.uid, &HashSet::from([p.id.pid])).is_err());
    }
    #[test]
    fn self_is_protected() {
        let p = read_one(std::process::id() as i32).unwrap();
        assert!(signal(&p.id, false).is_err());
    }
    #[test]
    fn disposable_child_termination() {
        let mut c = std::process::Command::new("sleep")
            .arg("30")
            .spawn()
            .unwrap();
        let id = read_one(c.id() as i32).unwrap().id;
        signal(&id, false).unwrap();
        assert!(!c.wait().unwrap().success());
        assert!(signal(&id, true).is_err());
    }
}
