use crate::process::{Identity, Process};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    time::Duration,
};
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Window {
    pub address: String,
    pub pid: i32,
    #[serde(default)]
    pub class: String,
    #[serde(default)]
    pub title: String,
}
pub fn config() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
        })
}
pub fn hypr(command: &str) -> Result<String, String> {
    let runtime = std::env::var("XDG_RUNTIME_DIR").map_err(|_| "Hyprland session unavailable")?;
    let instance =
        std::env::var("HYPRLAND_INSTANCE_SIGNATURE").map_err(|_| "Hyprland session unavailable")?;
    if instance.contains('/') || instance.contains("..") {
        return Err("Invalid session identity".into());
    }
    let mut s = UnixStream::connect(format!("{runtime}/hypr/{instance}/.socket.sock"))
        .map_err(|e| e.to_string())?;
    s.set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|e| e.to_string())?;
    s.set_write_timeout(Some(Duration::from_millis(500)))
        .map_err(|e| e.to_string())?;
    s.write_all(command.as_bytes()).map_err(|e| e.to_string())?;
    let mut output = String::new();
    s.take(8 * 1024 * 1024)
        .read_to_string(&mut output)
        .map_err(|e| e.to_string())?;
    Ok(output)
}
pub fn windows() -> Result<Vec<Window>, String> {
    serde_json::from_str(&hypr("j/clients")?).map_err(|e| e.to_string())
}
#[derive(Clone)]
struct DesktopEntry {
    path: PathBuf,
    name: String,
    icon: String,
    class: String,
    id: String,
}
pub struct Desktop {
    entries: Vec<DesktopEntry>,
}
impl Desktop {
    pub fn new() -> Self {
        let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
        let data = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| home.join(".local/share"));
        let mut dirs = vec![data.join("applications")];
        for d in std::env::var("XDG_DATA_DIRS")
            .unwrap_or_else(|_| "/usr/local/share:/usr/share".into())
            .split(':')
            .filter(|d| d.starts_with('/'))
        {
            dirs.push(PathBuf::from(d).join("applications"));
        }
        let mut entries = vec![];
        let mut seen = HashSet::new();
        for dir in dirs {
            for e in fs::read_dir(dir)
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
            {
                let id = e
                    .file_name()
                    .to_string_lossy()
                    .trim_end_matches(".desktop")
                    .to_string();
                if e.path().extension().and_then(|s| s.to_str()) != Some("desktop")
                    || !seen.insert(id.clone())
                {
                    continue;
                }
                if let Ok(s) = fs::read_to_string(e.path()) {
                    let fields = crate::desktop_entry::parse(&s);
                    if fields.get("Hidden").is_some_and(|v| v == "true") {
                        continue;
                    }
                    entries.push(DesktopEntry {
                        path: e.path(),
                        name: fields.get("Name").cloned().unwrap_or_else(|| id.clone()),
                        icon: fields.get("Icon").cloned().unwrap_or_default(),
                        class: fields.get("StartupWMClass").cloned().unwrap_or_default(),
                        id,
                    });
                }
            }
        }
        Self { entries }
    }
    pub fn restart(&self, ids: &[Identity], path: &str) -> Result<String, String> {
        if ids.is_empty()
            || ids.len() > 4096
            || !self
                .entries
                .iter()
                .any(|e| e.path == std::path::Path::new(path))
        {
            return Err("Application launcher unavailable".into());
        }
        let all = crate::process::list();
        let protected = crate::process::protected_ids(&all);
        for id in ids {
            let p = crate::process::read_one(id.pid).map_err(|_| "Process exited")?;
            crate::process::validate_target(&p, id, unsafe { libc::getuid() }, &protected)?;
        }
        for (id, result) in ids.iter().zip(crate::process::signal_batch(ids, false)) {
            // A parent may have already reaped a child while the fixed group was closing.
            if let Err(error) = result {
                if crate::process::read_one(id.pid).is_ok_and(|p| p.id == *id && p.state != "Z") {
                    return Err(format!("Application partially closed: {error}"));
                }
            }
        }
        let start = std::time::Instant::now();
        while ids
            .iter()
            .any(|id| crate::process::read_one(id.pid).is_ok_and(|p| p.id == *id && p.state != "Z"))
        {
            if start.elapsed().as_secs() >= 3 {
                return Err(
                    "Application is still closing. Resolve any save prompts, then launch it again."
                        .into(),
                );
            }
            std::thread::sleep(Duration::from_millis(30));
        }
        let status = std::process::Command::new("/usr/bin/timeout")
            .args(["--signal=KILL", "4s", "/usr/bin/gio", "launch", path])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map_err(|e| e.to_string())?;
        if status.success() {
            Ok("Application restart requested".into())
        } else {
            Err("Application closed, but its desktop launcher failed".into())
        }
    }
    pub fn apps(&self, processes: &[Process], windows: &[Window]) -> Vec<Value> {
        let groups = group(processes, windows);
        let by_pid: HashMap<_, _> = processes.iter().map(|p| (p.id.pid, p)).collect();
        let mut roots: Vec<_> = groups.keys().copied().collect();
        roots.sort();
        roots.into_iter().filter_map(|root| {
            let p=by_pid.get(&root)?;let ws:Vec<_>=windows.iter().filter(|w|w.pid==root).collect();
            let class=ws.first().map(|w|w.class.as_str()).unwrap_or(&p.name);
            let e=self.entries.iter().find(|e|e.id.eq_ignore_ascii_case(class)||(!e.class.is_empty()&&e.class.eq_ignore_ascii_case(class)));
            let members:Vec<_>=groups[&root].iter().filter_map(|pid|by_pid.get(pid).copied()).collect();
            let cpu=if members.iter().all(|p|p.cpu.is_some()){Some(members.iter().filter_map(|p|p.cpu).sum::<f64>())}else{None};
            let ids:Vec<_>=members.iter().map(|p|p.id.clone()).collect();
            Some(json!({"key":format!("{}:{}",root,p.id.start),"name":e.map(|e|e.name.as_str()).unwrap_or(class),"desktop_file":e.map(|e|e.path.to_string_lossy().to_string()),"icon":application_icon(class, e.map(|e|e.icon.as_str())),"cpu":cpu,"memory":members.iter().map(|p|p.memory).sum::<u64>(),"count":ids.len(),"targets":ids,"windows":ws,"protected":members.iter().any(|p|p.protected),"uid":p.uid,"note":"Memory is summed RSS; shared pages may be counted more than once. Grouping follows window processes and their descendants."}))
        }).collect()
    }
}
fn application_icon<'a>(class: &str, desktop_icon: Option<&'a str>) -> &'a str {
    if class.starts_with("org.omarchy.") {
        "omarchy-default"
    } else {
        desktop_icon
            .filter(|icon| !icon.is_empty())
            .unwrap_or("application-x-executable")
    }
}
pub fn group(processes: &[Process], windows: &[Window]) -> HashMap<i32, Vec<i32>> {
    let roots: HashSet<_> = windows.iter().map(|w| w.pid).filter(|p| *p > 0).collect();
    let by_pid: HashMap<_, _> = processes.iter().map(|p| (p.id.pid, p)).collect();
    let mut result: HashMap<i32, Vec<i32>> = HashMap::new();
    for p in processes {
        let mut id = p.id.pid;
        let mut seen = HashSet::new();
        while seen.insert(id) {
            let Some(parent) = by_pid.get(&id) else { break };
            if parent.uid != p.uid {
                break;
            }
            if roots.contains(&id) {
                result.entry(id).or_default().push(p.id.pid);
                break;
            }
            // Never attribute terminal jobs or session-launched children to their parent window.
            if id != p.id.pid
                && ["bash", "zsh", "fish", "sh", "nu", "systemd"].contains(&parent.name.as_str())
            {
                break;
            }
            id = parent.ppid;
        }
    }
    result
}
pub fn window_action(address: &str, id: &Identity, close: bool) -> Result<String, String> {
    if !address.starts_with("0x") || !address[2..].chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Invalid window identity".into());
    }
    let all = crate::process::list();
    let p = crate::process::read_one(id.pid).map_err(|_| "Process exited")?;
    crate::process::validate_target(
        &p,
        id,
        unsafe { libc::getuid() },
        &crate::process::protected_ids(&all),
    )?;
    if !windows()?
        .iter()
        .any(|w| w.address == address && w.pid == id.pid)
    {
        return Err("Window changed or closed".into());
    }
    let verb = if close { "closewindow" } else { "focuswindow" };
    let result = hypr(&format!("/dispatch {verb} address:{address}"))?;
    if result.trim() == "ok" {
        Ok(if close {
            "Close requested"
        } else {
            "Window focused"
        }
        .into())
    } else {
        Err(result)
    }
}
pub fn theme() -> Value {
    let state = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    let current = state.join("omarchy/current/theme");
    // Prefer current state over a stale pre-migration config palette.
    // Resolve each sample: Omarchy replaces the entire theme directory.
    let directory = if current.exists() {
        current
    } else {
        config().join("omarchy/current/theme")
    };
    let text = fs::read_to_string(directory.join("colors.toml")).unwrap_or_default();
    let mut map = serde_json::Map::new();
    for l in text.lines() {
        if let Some((key, value)) = l.split_once('=') {
            let color = value.trim().trim_matches('"');
            if ["background", "foreground", "accent"].contains(&key.trim())
                && color.len() == 7
                && color.starts_with('#')
                && color[1..].chars().all(|c| c.is_ascii_hexdigit())
            {
                map.insert(key.trim().into(), json!(color));
            }
        }
    }
    if map.len() == 3 {
        let text = fs::read_to_string(directory.join("shell.toml")).unwrap_or_default();
        let mut section = String::new();
        let mut tokens = serde_json::Map::new();
        for line in text.lines() {
            let l = line.trim();
            if l.starts_with('#') {
                continue;
            }
            if let Some(s) = l.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                section = s.into();
                continue;
            }
            if let Some((k, v)) = l.split_once('=') {
                let v = v.trim();
                let val = if v.starts_with('"') {
                    v.trim_start_matches('"').split('"').next().unwrap_or("")
                } else {
                    v.split('#').next().unwrap_or("").trim()
                };
                tokens.insert(format!("{section}.{}", k.trim()), json!(val));
            }
        }
        for (from, to) in [
            ("popups.background", "background"),
            ("popups.text", "foreground"),
        ] {
            if let Some(c) = tokens.get(from).and_then(Value::as_str) {
                if c.len() == 7
                    && c.starts_with('#')
                    && c[1..].bytes().all(|b| b.is_ascii_hexdigit())
                {
                    map.insert(to.into(), json!(c));
                }
            }
        }
        map.insert("shell".into(), Value::Object(tokens));
        Value::Object(map)
    } else {
        json!({})
    }
}
fn panel_extent(request: i64, logical: f64, margin: f64, minimum: i64, maximum: i64) -> i64 {
    (request.clamp(minimum, maximum) as f64).min((logical - margin).max(1.0)) as i64
}
/// Position only this worker's parent window; never changes global compositor config.
pub fn float_panel(width: i64, height: i64) -> Result<String, String> {
    let pid = unsafe { libc::getppid() };
    let ws = windows()?;
    let window = ws
        .iter()
        .find(|w| w.pid == pid && w.class == "io.github.tcballard.TaskManager")
        .ok_or("Task Manager window is not mapped yet")?;
    if !window.address.starts_with("0x")
        || !window.address[2..].chars().all(|c| c.is_ascii_hexdigit())
    {
        return Err("Invalid window address".into());
    }
    let selector = format!("address:{}", window.address);
    let result = hypr(&format!(
        "/dispatch hl.dsp.window.float({{ window = \"{selector}\", action = \"set\" }})"
    ))?;
    let lua_dispatch = result.trim() == "ok";
    if !lua_dispatch {
        let result = hypr(&format!("/dispatch setfloating {selector}"))?;
        if result.trim() != "ok" {
            return Err(result);
        }
    }
    let monitors: Vec<Value> =
        serde_json::from_str(&hypr("j/monitors")?).map_err(|e| e.to_string())?;
    if let Some(m) = monitors.iter().find(|m| m["focused"] == true) {
        let scale = m["scale"].as_f64().unwrap_or(1.0).max(0.1);
        let mut mw = m["width"].as_f64().unwrap_or(1920.0) / scale;
        let mut mh = m["height"].as_f64().unwrap_or(1080.0) / scale;
        if m["transform"].as_i64().unwrap_or(0) % 2 == 1 {
            std::mem::swap(&mut mw, &mut mh);
        }
        let w = panel_extent(width, mw, 40.0, 640, 2400);
        let h = panel_extent(height, mh, 60.0, 420, 1600);
        let x = m["x"].as_i64().unwrap_or(0) + (mw as i64 - w) / 2;
        let y = m["y"].as_i64().unwrap_or(0) + (mh as i64 - h) / 2;
        let commands = if lua_dispatch {
            [
                format!("/dispatch hl.dsp.window.resize({{ window = \"{selector}\", x = {w}, y = {h} }})"),
                format!("/dispatch hl.dsp.window.move({{ window = \"{selector}\", x = {x}, y = {y} }})"),
            ]
        } else {
            [
                format!("/dispatch resizewindowpixel exact {w} {h},{selector}"),
                format!("/dispatch movewindowpixel exact {x} {y},{selector}"),
            ]
        };
        for cmd in commands {
            let result = hypr(&cmd)?;
            if result.trim() != "ok" {
                return Err(result);
            }
        }
    }
    Ok("Floating panel ready".into())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn omarchy_windows_use_brand_icon_only_for_their_namespace() {
        for class in [
            "org.omarchy.agent",
            "org.omarchy.terminal",
            "org.omarchy.btop",
        ] {
            assert_eq!(application_icon(class, None), "omarchy-default");
            assert_eq!(
                application_icon(class, Some("utilities-terminal")),
                "omarchy-default"
            );
        }
        assert_eq!(application_icon("chromium", Some("chromium")), "chromium");
        assert_eq!(
            application_icon("org.omarchyish.app", None),
            "application-x-executable"
        );
        assert_eq!(
            application_icon("other", Some("")),
            "application-x-executable"
        );
    }
    #[test]
    fn floating_extent_fits_small_logical_monitors() {
        assert_eq!(panel_extent(1120, 800.0, 40.0, 850, 2400), 760);
        assert_eq!(panel_extent(760, 540.0, 60.0, 560, 1600), 480);
        assert_eq!(panel_extent(9999, 3840.0, 40.0, 850, 2400), 2400);
    }
    fn p(pid: i32, parent: i32, name: &str) -> Process {
        Process {
            id: Identity { pid, start: 1 },
            ppid: parent,
            name: name.into(),
            command: String::new(),
            uid: 1000,
            user: String::new(),
            state: "S".into(),
            ticks: 0,
            memory: 0,
            cpu: None,
            read: None,
            write: None,
            read_rate: None,
            write_rate: None,
            protected: false,
            exe: None,
            gpu: None,
            gpu_memory: None,
            nice: 0,
            threads: 1,
            virtual_memory: 0,
            cpu_seconds: 0.0,
        }
    }
    fn w(pid: i32) -> Window {
        Window {
            pid,
            address: "0x1".into(),
            class: "app".into(),
            title: String::new(),
        }
    }
    #[test]
    fn nearest_window_owns_process() {
        let g = group(
            &[p(10, 1, "browser"), p(11, 10, "child"), p(12, 10, "other")],
            &[w(10), w(12)],
        );
        assert_eq!(g[&10], vec![10, 11]);
        assert_eq!(g[&12], vec![12]);
    }
    #[test]
    fn shell_jobs_not_terminal_members() {
        let g = group(
            &[p(10, 1, "terminal"), p(11, 10, "bash"), p(12, 11, "job")],
            &[w(10)],
        );
        assert!(!g[&10].contains(&12));
    }
    #[test]
    fn cycles_and_orphans_terminate() {
        assert!(group(&[p(10, 11, "x"), p(11, 10, "y"), p(12, 99, "z")], &[]).is_empty());
    }
}
