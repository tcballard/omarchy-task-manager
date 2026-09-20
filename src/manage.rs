//! Linux equivalents of Task Manager's management pages. No shell evaluation.
use crate::{
    desktop,
    process::{self, Identity, Process},
};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use crate::command::run;
pub fn services(user: bool) -> Value {
    let mut args = vec![
        "--no-pager",
        "--plain",
        "--no-ask-password",
        "--output=json",
        "list-units",
        "--type=service",
        "--all",
    ];
    if user {
        args.insert(0, "--user");
    }
    let result = (|| -> Result<Value, String> {
        let loaded: Vec<Value> =
            serde_json::from_str(&run("/usr/bin/systemctl", &args)?).map_err(|e| e.to_string())?;
        let mut rows:BTreeMap<String,Value>=loaded.into_iter().filter_map(|v|Some((v["unit"].as_str()?.into(),json!({"key":v["unit"],"name":v["unit"],"description":v["description"],"state":v["active"],"sub":v["sub"],"scope":if user{"user"}else{"system"}})))).collect();
        let mut args = vec![
            "--no-pager",
            "--no-ask-password",
            "--output=json",
            "list-unit-files",
            "--type=service",
        ];
        if user {
            args.insert(0, "--user");
        }
        let mut error = None;
        match run("/usr/bin/systemctl", &args)
            .and_then(|s| serde_json::from_str::<Vec<Value>>(&s).map_err(|e| e.to_string()))
        {
            Ok(files) => {
                for f in files {
                    if let Some(name) = f["unit_file"].as_str() {
                        let row=rows.entry(name.into()).or_insert_with(||json!({"key":name,"name":name,"state":"inactive","sub":"unloaded","scope":if user{"user"}else{"system"}}));
                        row["enabled"] = f["state"].clone();
                    }
                }
            }
            Err(e) => {
                error = Some(format!(
                    "Loaded services shown; unit-file list unavailable: {e}"
                ))
            }
        }
        Ok(json!({"rows":rows.into_values().collect::<Vec<_>>(),"error":error}))
    })();
    result.unwrap_or_else(|e| json!({"rows":[],"error":e}))
}

fn valid_unit(s: &str) -> bool {
    s.ends_with(".service")
        && s.len() <= 255
        && !s.starts_with('-')
        && s.bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_.@:\\".contains(&c))
}
pub fn service_action(req: &Value) -> Result<String, String> {
    let unit = req["key"].as_str().unwrap_or("");
    let verb = req["verb"].as_str().unwrap_or("");
    if !valid_unit(unit)
        || !["start", "stop", "restart", "enable", "disable", "logs"].contains(&verb)
    {
        return Err("Invalid service action".into());
    }
    let user = req["scope"] == "user";
    if !user && req["scope"] != "system" {
        return Err("Invalid service scope".into());
    }
    if verb == "logs" {
        let mut args = vec![
            "--no-pager",
            "--output=short-iso",
            "--lines=80",
            "--unit",
            unit,
        ];
        if user {
            args.insert(0, "--user");
        }
        return run("/usr/bin/journalctl", &args);
    }
    if [
        "dbus.service",
        "dbus-broker.service",
        "systemd-logind.service",
        "polkit.service",
        "quickshell.service",
        "hyprland.service",
    ]
    .contains(&unit)
        || unit.starts_with("omarchy")
    {
        return Err("Desktop/session service is protected".into());
    }
    let mut args = vec!["--no-pager", "--no-ask-password", verb, unit];
    if user {
        args.insert(0, "--user");
    }
    run("/usr/bin/systemctl", &args)?;
    Ok(format!("{verb}: {unit}"))
}
fn config_dirs() -> Vec<PathBuf> {
    let mut d = vec![desktop::config()];
    d.extend(
        std::env::var("XDG_CONFIG_DIRS")
            .unwrap_or_else(|_| "/etc/xdg".into())
            .split(':')
            .map(PathBuf::from)
            .filter(|p| p.is_absolute()),
    );
    d
}
fn entries() -> BTreeMap<String, PathBuf> {
    let mut found = BTreeMap::new();
    for dir in config_dirs() {
        for file in fs::read_dir(dir.join("autostart"))
            .into_iter()
            .flatten()
            .filter_map(Result::ok)
        {
            let id = file.file_name().to_string_lossy().to_string();
            if id.ends_with(".desktop") {
                found.entry(id).or_insert(file.path());
            }
        }
    }
    found
}
pub fn startup() -> Value {
    let desktops = std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_else(|_| "Hyprland".into());
    let mut rows:Vec<Value>=entries().into_iter().filter_map(|(id,path)|{
        let text=fs::read_to_string(&path).ok()?;let e=crate::desktop_entry::parse(&text);
        let applies=|key:&str|e.get(key).is_some_and(|s|s.split(';').any(|v|!v.is_empty() && desktops.split(':').any(|d|d.eq_ignore_ascii_case(v))));
        let eligible=(!e.contains_key("OnlyShowIn") || applies("OnlyShowIn")) && !applies("NotShowIn");
        Some(json!({"key":id,"name":e.get("Name").unwrap_or(&id),"command":e.get("Exec"),"state":if e.get("Hidden").is_some_and(|v|v=="true"){"Disabled"}else if !eligible{"Other desktop"}else{"Enabled"},"description":e.get("Comment"),"path":path,"kind":"xdg","editable":true,"impact":"Not measured"}))
    }).collect();
    // Hyprland owns these launch commands. Never silently rewrite a user's Lua.
    for relative in ["hypr/autostart.lua", "hypr/autostart.conf"] {
        let path = desktop::config().join(relative);
        if let Ok(text) = fs::read_to_string(&path) {
            for (n, line) in text.lines().enumerate() {
                let s = line.trim();
                if s.is_empty() || s.starts_with('#') || s.starts_with("--") {
                    continue;
                }
                rows.push(json!({"key":format!("hypr:{relative}:{n}"),"name":format!("Hyprland · line {}",n+1),"command":s,"state":"Configured","kind":"hyprland","path":path,"editable":false,"impact":"Not measured"}));
            }
        }
    }
    json!({"rows":rows,"note":"XDG autostart entries follow desktop eligibility. Hyprland startup scripts are shown for inspection; edit their configuration directly. Boot impact has no standard Linux counter."})
}
pub fn startup_action(key: &str, enabled: bool) -> Result<String, String> {
    if key.contains('/') || key.contains('\\') || !key.ends_with(".desktop") || key.starts_with('.')
    {
        return Err("Invalid startup entry".into());
    }
    let found = entries();
    let source = found.get(key).ok_or("Startup entry no longer exists")?;
    let text = fs::read_to_string(source).map_err(|e| e.to_string())?;
    let output = set_hidden(&text, !enabled)?;
    let dest = desktop::config().join("autostart");
    fs::create_dir_all(&dest).map_err(|e| e.to_string())?;
    crate::storage::atomic_write(&dest.join(key), output.as_bytes())?;
    Ok(format!(
        "{} at next login: {key}",
        if enabled { "Enabled" } else { "Disabled" }
    ))
}
fn set_hidden(text: &str, hidden: bool) -> Result<String, String> {
    let mut lines = Vec::new();
    let mut active = false;
    let mut seen = false;
    for line in text.lines() {
        if line.trim().starts_with('[') {
            active = line.trim() == "[Desktop Entry]";
            if active {
                if seen {
                    return Err("Duplicate Desktop Entry section".into());
                }
                seen = true;
                lines.push(line.to_string());
                lines.push(format!("Hidden={hidden}"));
                continue;
            }
        }
        if active
            && line
                .split_once('=')
                .is_some_and(|(k, _)| k.trim() == "Hidden")
        {
            continue;
        }
        lines.push(line.into());
    }
    if !seen {
        return Err("Invalid desktop entry".into());
    }
    Ok(lines.join("\n") + "\n")
}
pub fn users(processes: &[Process]) -> Value {
    let mut users: BTreeMap<u32, Value> = BTreeMap::new();
    for p in processes {
        let u=users.entry(p.uid).or_insert_with(||json!({"key":p.uid.to_string(),"uid":p.uid,"name":p.user,"count":0,"cpu":0.0,"memory":0,"sessions":[]}));
        u["count"] = json!(u["count"].as_u64().unwrap_or(0) + 1);
        u["cpu"] = json!(u["cpu"].as_f64().unwrap_or(0.0) + p.cpu.unwrap_or(0.0));
        u["memory"] = json!(u["memory"].as_u64().unwrap_or(0) + p.memory);
    }
    let sessions = run(
        "/usr/bin/loginctl",
        &["list-sessions", "--json=short", "--no-pager"],
    );
    let mut error = None;
    match sessions {
        Ok(s) => match serde_json::from_str::<Vec<Value>>(&s) {
            Ok(rows) => {
                for r in rows {
                    if let Some(uid) = r["uid"].as_u64() {
                        let u=users.entry(uid as u32).or_insert_with(||json!({"key":uid.to_string(),"uid":uid,"name":r["user"],"count":0,"cpu":0,"memory":0,"sessions":[]}));
                        u["sessions"].as_array_mut().unwrap().push(r);
                    }
                }
            }
            Err(e) => error = Some(e.to_string()),
        },
        Err(e) => error = Some(e),
    }
    json!({"rows":users.into_values().collect::<Vec<_>>(),"error":error})
}
pub fn session_action(req: &Value) -> Result<String, String> {
    let uid = req["uid"].as_u64().ok_or("Invalid user")?;
    // Session actions are deliberately limited to the current user.
    if uid != unsafe { libc::getuid() } as u64 {
        return Err("You can only manage your own sessions".into());
    }
    let session = req["session"].as_str().ok_or("No session selected")?;
    if session.is_empty() || !session.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return Err("Invalid session".into());
    }
    let owner = run(
        "/usr/bin/loginctl",
        &["show-session", session, "--property=User", "--value"],
    )?;
    if owner.trim() != uid.to_string() {
        return Err("Session owner changed".into());
    }
    let verb = match req["verb"].as_str() {
        Some("lock") => "lock-session",
        Some("logout") => "terminate-session",
        _ => return Err("Invalid session action".into()),
    };
    run("/usr/bin/loginctl", &["--no-ask-password", verb, session])?;
    Ok(format!("{verb}: {session}"))
}
pub fn inspect(id: &Identity) -> Result<Value, String> {
    let p = process::read_one(id.pid).map_err(|e| e.to_string())?;
    if p.id != *id {
        return Err("Process exited or changed".into());
    }
    let base = format!("/proc/{}", id.pid);
    let mut files = Vec::new();
    let mut truncated = false;
    for (index, f) in fs::read_dir(format!("{base}/fd"))
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .take(257)
        .enumerate()
    {
        if index == 256 {
            truncated = true;
            break;
        }
        if let Ok(dest) = fs::read_link(f.path()) {
            files.push(format!(
                "{} → {}",
                f.file_name().to_string_lossy(),
                dest.display()
            ));
        }
    }
    let stat = crate::bounded::text(format!("{base}/status"), 64 * 1024).unwrap_or_default();
    let cwd = fs::read_link(format!("{base}/cwd"))
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    let exe = fs::read_link(format!("{base}/exe"))
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    let cgroup = crate::bounded::text(format!("{base}/cgroup"), 64 * 1024).unwrap_or_default();
    let maps = crate::bounded::text(format!("{base}/maps"), 512 * 1024).unwrap_or_default();
    let mut threads: Vec<_> = fs::read_dir(format!("{base}/task"))
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .take(513)
        .map(|e| {
            let p = e.path();
            json!({"tid":e.file_name().to_string_lossy(),
                "name":crate::bounded::text(p.join("comm"), 1024).unwrap_or_default().trim(),
                "wait":crate::bounded::text(p.join("wchan"), 1024).unwrap_or_default().trim()})
        })
        .collect();
    truncated |= threads.len() > 512;
    threads.truncate(512);
    if process::read_one(id.pid).map_err(|_| "Process exited")?.id != *id {
        return Err("Process changed during inspection".into());
    }
    Ok(
        json!({"process":p,"executable":exe,"cwd":cwd,"status":stat,"cgroup":cgroup,"files":files,"maps":maps,"threads":threads,"note":format!("{}Read permissions may hide files or memory maps. No process memory is copied.", if truncated { "Lists truncated to 256 files / 512 threads. " } else { "" })}),
    )
}
pub fn dump(id: &Identity) -> Result<String, String> {
    use std::os::unix::fs::DirBuilderExt;
    let p = process::read_one(id.pid).map_err(|e| e.to_string())?;
    process::validate_target(
        &p,
        id,
        unsafe { libc::getuid() },
        &process::protected_ids(&process::list()),
    )?;
    if !Path::new("/usr/bin/gcore").exists() {
        return Err("Install the optional gdb package to create a core dump".into());
    }
    let state = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    let base = state.join("omarchy-task-manager/dumps");
    fs::create_dir_all(&base).map_err(|e| e.to_string())?;
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = base.join(format!("{}-{stamp}", id.pid));
    fs::DirBuilder::new()
        .mode(0o700)
        .create(&dir)
        .map_err(|e| e.to_string())?;
    let prefix = dir.join("core");
    let pid = id.pid.to_string();
    // gcore is an optional system debugger. Its kernel ptrace checks enforce ownership.
    let result = crate::command::run_for(
        "/usr/bin/gcore",
        &["-o", &prefix.to_string_lossy(), &pid],
        std::time::Duration::from_secs(60),
    );
    let file = dir.join(format!("core.{}", id.pid));
    if let Err(error) = result {
        let _ = fs::remove_file(&file);
        return Err(format!(
            "Core dump failed (ptrace permission, cancellation or timeout): {error}"
        ));
    }
    if !process::read_one(id.pid).is_ok_and(|p| p.id == *id) {
        let _ = fs::remove_file(&file);
        return Err("Process identity could not be verified after capture; dump removed".into());
    }
    Ok(format!("Core dump saved to {}", file.display()))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn large_file_inventory_is_bounded_and_disclosed() {
        let handles: Vec<_> = (0..300)
            .map(|_| fs::File::open("/dev/null").unwrap())
            .collect();
        let id = process::read_one(std::process::id() as i32).unwrap().id;
        let data = inspect(&id).unwrap();
        assert!(data["files"].as_array().unwrap().len() <= 256);
        assert!(data["files"].as_array().unwrap().len() >= 200);
        assert!(data["note"].as_str().unwrap().contains("truncated"));
        assert!(data["threads"]
            .as_array()
            .unwrap()
            .iter()
            .all(|t| t.get("status").is_none()));
        drop(handles);
    }
    #[test]
    fn startup_override_keeps_actions() {
        let s="[Desktop Entry]\nName=A\nHidden=false\nExec=thing\n[Desktop Action X]\nHidden=false\nExec=other\n";
        let out = set_hidden(s, true).unwrap();
        assert!(out.contains("[Desktop Entry]\nHidden=true"));
        assert!(out.contains("[Desktop Action X]\nHidden=false"));
        assert_eq!(out.matches("Hidden=true").count(), 1);
        assert!(set_hidden("Name=A", true).is_err());
    }
    #[test]
    fn unit_validation() {
        assert!(valid_unit("app-org.example@session.service"));
        for s in [
            "--help.service",
            "x;reboot.service",
            "a/b.service",
            "foo.socket",
        ] {
            assert!(!valid_unit(s));
        }
    }
    #[test]
    fn path_traversal_rejected() {
        assert!(startup_action("../evil.desktop", false).is_err());
    }
}
