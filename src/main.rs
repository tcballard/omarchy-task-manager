mod bounded;
mod command;
mod desktop;
mod desktop_entry;
mod gpu;
mod history;
mod manage;
mod metrics;
mod monitor;
mod process;
mod slow;
mod storage;
use serde_json::{json, Value};
use std::io::{self, BufRead, Read, Write};
fn main() {
    if let Err(e) = command::install_cancellation() {
        eprintln!("Cannot install worker shutdown handler: {e}");
        std::process::exit(1);
    }
    if std::env::args().any(|a| a == "--monitor") {
        if let Err(error) = monitor::run() {
            eprintln!("Background monitoring: {error}");
            std::process::exit(1);
        }
        return;
    }
    let mut sampler = metrics::Sampler::new();
    let desktop = desktop::Desktop::new();
    let mut history = history::History::new();
    let mut cache = (String::new(), std::time::Instant::now(), json!({}));
    if std::env::args().any(|a| a == "--once") {
        let value = snapshot(&mut sampler, &desktop, &mut history, &mut cache, "apps");
        let _ = write_response(&mut io::stdout(), &value);
        return;
    }
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout());
    let mut input = stdin.lock();
    while !command::cancelled() {
        let Ok(Some(line)) = request_line(&mut input) else {
            break;
        };
        let response = match serde_json::from_str::<Value>(&line) {
            Ok(req) => match req["op"].as_str().unwrap_or("") {
                "sample" => {
                    if req["reset"].as_bool().unwrap_or(false) {
                        sampler.invalidate();
                    }
                    let mut value = snapshot(
                        &mut sampler,
                        &desktop,
                        &mut history,
                        &mut cache,
                        req["page"].as_str().unwrap_or("apps"),
                    );
                    if req["background_history"].as_bool().unwrap_or(false) {
                        value["background"] = monitor::history().unwrap_or(Value::Null);
                    }
                    value
                }
                "manage" => {
                    cache.0.clear();
                    action(&req, &mut history, &desktop)
                }
                "inspect" => match serde_json::from_value::<process::Identity>(req["id"].clone()) {
                    Ok(id) => match manage::inspect(&id) {
                        Ok(data) => json!({"kind":"inspection","data":data}),
                        Err(e) => json!({"kind":"error","message":e}),
                    },
                    Err(_) => json!({"kind":"error","message":"Invalid process identity"}),
                },
                "signal" => {
                    let targets =
                        serde_json::from_value::<Vec<process::Identity>>(req["targets"].clone());
                    match targets {
                        Ok(ids) if !ids.is_empty() && ids.len() <= 4096 => {
                            let force = req["force"].as_bool().unwrap_or(false);
                            let results: Vec<_> = ids
                                .iter()
                                .zip(process::signal_batch(&ids, force))
                                .map(|(id, result)| match result {
                                    Ok(message) => {
                                        json!({"pid":id.pid,"ok":true,"message":message})
                                    }
                                    Err(message) => {
                                        json!({"pid":id.pid,"ok":false,"message":message})
                                    }
                                })
                                .collect();
                            json!({"kind":"action","results":results})
                        }
                        _ => json!({"kind":"error","message":"Invalid target list"}),
                    }
                }
                "window" => match serde_json::from_value::<process::Identity>(req["id"].clone()) {
                    Ok(id) => match desktop::window_action(
                        req["address"].as_str().unwrap_or(""),
                        &id,
                        req["close"].as_bool().unwrap_or(false),
                    ) {
                        Ok(message) => {
                            json!({"kind":"action","results":[{"ok":true,"message":message}]})
                        }
                        Err(message) => json!({"kind":"error","message":message}),
                    },
                    Err(_) => json!({"kind":"error","message":"Invalid process identity"}),
                },
                "float" => match desktop::float_panel(
                    req["width"].as_i64().unwrap_or(1080),
                    req["height"].as_i64().unwrap_or(760),
                ) {
                    Ok(message) => {
                        json!({"kind":"action","results":[{"ok":true,"message":message}]})
                    }
                    Err(message) => json!({"kind":"error","message":message}),
                },
                "quit" => break,
                _ => json!({"kind":"error","message":"Unknown request"}),
            },
            Err(_) => json!({"kind":"error","message":"Malformed request"}),
        };
        if write_response(&mut stdout, &response).is_err() {
            break;
        }
    }
}
fn snapshot(
    sampler: &mut metrics::Sampler,
    desktop: &desktop::Desktop,
    history: &mut history::History,
    cache: &mut (String, std::time::Instant, Value),
    page: &str,
) -> Value {
    let (system, processes) = sampler.sample();
    history.sample(&processes, system["continuous"].as_bool().unwrap_or(false));
    let windows = desktop::windows();
    let apps = desktop.apps(&processes, windows.as_deref().unwrap_or(&[]));
    if cache.0 != page || cache.1.elapsed().as_secs() >= 5 {
        cache.2 = match page {
            "services" => manage::services(true),
            "system-services" => manage::services(false),
            "startup" => manage::startup(),
            "users" => manage::users(&processes),
            _ => json!({}),
        };
        cache.0 = page.into();
        cache.1 = std::time::Instant::now();
    }
    if page == "users" {
        // Resource totals follow each sample; session enumeration is cached.
        if let Some(rows) = cache.2["rows"].as_array_mut() {
            for u in rows {
                let uid = u["uid"].as_u64().unwrap_or(u64::MAX);
                let ps: Vec<_> = processes.iter().filter(|p| p.uid as u64 == uid).collect();
                u["cpu"] = json!(ps.iter().filter_map(|p| p.cpu).sum::<f64>());
                u["memory"] = json!(ps.iter().map(|p| p.memory).sum::<u64>());
                u["count"] = json!(ps.len());
            }
        }
    }
    json!({"kind":"snapshot","system":system,"processes":processes,"apps":apps,"desktop_error":windows.err(),"theme":desktop::theme(),"uid":unsafe{libc::getuid()},"management_page":page,"management":cache.2,"usage":history.view()})
}
fn action(req: &Value, history: &mut history::History, desktop: &desktop::Desktop) -> Value {
    let result: Result<String, String> = match req["category"].as_str().unwrap_or("") {
        "restart" => serde_json::from_value::<Vec<process::Identity>>(req["targets"].clone())
            .map_err(|_| "Invalid process list".to_string())
            .and_then(|ids| desktop.restart(&ids, req["desktop_file"].as_str().unwrap_or(""))),
        "service" => manage::service_action(req),
        "startup" => manage::startup_action(
            req["key"].as_str().unwrap_or(""),
            req["enabled"].as_bool().unwrap_or(false),
        ),
        "session" => manage::session_action(req),
        "history" if req["verb"] == "reset" => history.reset(),
        "process" => (|| {
            let id: process::Identity = serde_json::from_value(req["id"].clone())
                .map_err(|_| "Invalid process identity")?;
            match req["verb"].as_str().unwrap_or("") {
                "dump" => manage::dump(&id),
                "suspend" => process::send_signal(&id, libc::SIGSTOP),
                "resume" => process::send_signal(&id, libc::SIGCONT),
                "nice" => process::tune(
                    &id,
                    Some(
                        req["nice"]
                            .as_i64()
                            .and_then(|n| i32::try_from(n).ok())
                            .ok_or("Invalid priority")?,
                    ),
                    None,
                ),
                "affinity" => process::tune(
                    &id,
                    None,
                    Some(
                        serde_json::from_value(req["cpus"].clone())
                            .map_err(|_| "Invalid CPU list")?,
                    ),
                ),
                _ => Err("Unknown process action".into()),
            }
        })(),
        _ => Err("Unknown management action".into()),
    };
    if req["category"] == "service" && req["verb"] == "logs" {
        return match result {
            Ok(logs) => json!({"kind":"inspection","data":{"logs":logs}}),
            Err(message) => json!({"kind":"error","message":message}),
        };
    }
    match result {
        Ok(message) => json!({"kind":"action","results":[{"ok":true,"message":message}]}),
        Err(message) => json!({"kind":"error","message":message}),
    }
}

// Leave headroom below the GUI's 32 MiB framing cap. Serialize into a
// bounded buffer before writing so a rejected payload never corrupts framing.
const RESPONSE_LIMIT: usize = 16 * 1024 * 1024;
fn write_response(output: &mut impl Write, response: &Value) -> io::Result<()> {
    let mut buffer = bounded::Buffer::new(RESPONSE_LIMIT);
    if serde_json::to_writer(&mut buffer, response).is_err() {
        buffer = bounded::Buffer::new(RESPONSE_LIMIT);
        serde_json::to_writer(
            &mut buffer,
            &json!({"kind":"error", "message":"Monitoring response exceeds 16 MiB. Last complete sample retained; reduce the workload or inspection size."}),
        )?;
    }
    output.write_all(&buffer.bytes)?;
    output.write_all(b"\n")?;
    output.flush()
}
const REQUEST_LIMIT: u64 = 1024 * 1024;
fn request_line(input: &mut impl BufRead) -> io::Result<Option<String>> {
    let mut line = String::new();
    let read = input.take(REQUEST_LIMIT + 1).read_line(&mut line)?;
    if read as u64 > REQUEST_LIMIT {
        return Err(io::Error::other("Request exceeds limit"));
    }
    Ok((read > 0).then_some(line))
}
#[cfg(test)]
mod protocol_tests {
    use super::*;
    #[test]
    fn oversized_response_is_framed_error_and_next_response_survives() {
        let mut output = Vec::new();
        write_response(&mut output, &json!({"data":"x".repeat(RESPONSE_LIMIT)})).unwrap();
        write_response(&mut output, &json!({"kind":"snapshot"})).unwrap();
        let rows: Vec<Value> = String::from_utf8(output)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["kind"], "error");
        assert_eq!(rows[1]["kind"], "snapshot");
    }
    #[test]
    fn line_limit_applies_before_allocating_entire_request() {
        let mut input = io::Cursor::new(vec![b'x'; REQUEST_LIMIT as usize * 3]);
        assert!(request_line(&mut input).is_err());
        assert_eq!(input.position(), REQUEST_LIMIT + 1);
        let mut valid = io::Cursor::new(b"{}\n{}\n");
        assert_eq!(request_line(&mut valid).unwrap().as_deref(), Some("{}\n"));
        assert_eq!(request_line(&mut valid).unwrap().as_deref(), Some("{}\n"));
        assert_eq!(request_line(&mut valid).unwrap(), None);
    }
}
