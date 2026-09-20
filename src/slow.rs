//! One background collector: a blocked syscall cannot hold up procfs sampling
//! or cause an accumulating population of replacement threads.
use serde_json::{json, Value};
use std::{
    sync::mpsc::{self, Receiver, SyncSender, TryRecvError},
    time::{Duration, Instant},
};
pub struct Collector {
    request: SyncSender<()>,
    response: Receiver<Vec<Value>>,
    pending: bool,
    updated: Option<Instant>,
    rows: Vec<Value>,
    failed: bool,
}
impl Collector {
    pub fn new(mut read: impl FnMut() -> Vec<Value> + Send + 'static) -> Self {
        let (request, requests) = mpsc::sync_channel(1);
        let (responses, response) = mpsc::sync_channel(1);
        let failed = std::thread::Builder::new()
            .name("filesystem-capacity".into())
            .spawn(move || {
                while requests.recv().is_ok() {
                    if responses.send(read()).is_err() {
                        break;
                    }
                }
            })
            .is_err();
        Self {
            request,
            response,
            pending: false,
            updated: None,
            rows: Vec::new(),
            failed,
        }
    }
    pub fn poll(&mut self) -> Value {
        match self.response.try_recv() {
            Ok(rows) => {
                self.rows = rows;
                self.updated = Some(Instant::now());
                self.pending = false;
            }
            Err(TryRecvError::Disconnected) => self.failed = true,
            Err(TryRecvError::Empty) => {}
        }
        let age = self.updated.map(|t| t.elapsed());
        if !self.failed && !self.pending && age.is_none_or(|a| a >= Duration::from_secs(5)) {
            self.pending = self.request.try_send(()).is_ok();
            if !self.pending {
                self.failed = true;
            }
        }
        let stale = self.failed || age.is_none_or(|a| a >= Duration::from_secs(15));
        json!({"rows":if stale { &[][..] } else { &self.rows }, "stale":stale,
            "age_seconds":age.map(|a| a.as_secs()),
            "message":if self.failed {"Filesystem capacity unavailable: collector stopped."}
                else if stale {"Filesystem capacity pending or unavailable; other metrics remain live."}
                else {"Filesystem capacity refreshes every 5 seconds."}})
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stalled_reader_never_blocks_sampling_or_starts_replacements() {
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let mut c = Collector::new(move || {
            entered_tx.send(()).unwrap();
            release_rx.recv().unwrap();
            vec![json!({"name":"fixture"})]
        });
        assert_eq!(c.poll()["stale"], true);
        entered_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        for _ in 0..1000 {
            assert_eq!(c.poll()["stale"], true);
        }
        assert!(entered_rx.try_recv().is_err());
        release_tx.send(()).unwrap();
        let rows = c.response.recv_timeout(Duration::from_secs(2)).unwrap();
        c.rows = rows;
        c.pending = false;
        c.updated = Some(Instant::now());
        assert_eq!(c.poll()["rows"][0]["name"], "fixture");
        c.updated = Some(Instant::now() - Duration::from_secs(20));
        c.pending = true; // A later refresh is stuck: old values are not live.
        assert_eq!(c.poll()["rows"], json!([]));
        assert_eq!(c.poll()["stale"], true);
    }
}
