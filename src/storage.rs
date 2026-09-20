//! Shared private, same-directory atomic persistence.
use std::{
    fs,
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("Invalid destination")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    // A crashed or concurrent writer must never have its temporary file removed.
    let (temp, mut file) = loop {
        let sequence = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
        let temp = parent.join(format!(
            ".task-manager-{}-{sequence}.tmp",
            std::process::id()
        ));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)
        {
            Ok(file) => break (temp, file),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e.to_string()),
        }
    };
    let result = (|| {
        file.write_all(bytes)
            .and_then(|_| file.sync_all())
            .map_err(|e| e.to_string())?;
        fs::rename(&temp, path).map_err(|e| e.to_string())?;
        fs::File::open(parent)
            .and_then(|f| f.sync_all())
            .map_err(|e| e.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp); // Only this writer's successfully created file.
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn concurrent_writes_are_complete_and_preserve_existing_temporary_files() {
        let dir = std::env::temp_dir().join(format!("task-manager-storage-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let stale = dir.join(format!(".task-manager-{}.tmp", std::process::id()));
        fs::write(&stale, b"unrelated").unwrap();
        let collision = dir.join(format!(".task-manager-{}-0.tmp", std::process::id()));
        fs::write(&collision, b"other writer").unwrap();
        let path = dir.join("state.json");
        std::thread::scope(|scope| {
            for byte in b'a'..=b'h' {
                let path = &path;
                scope.spawn(move || atomic_write(path, &vec![byte; 16384]).unwrap());
            }
        });
        let data = fs::read(&path).unwrap();
        assert_eq!(data.len(), 16384);
        assert!(data.iter().all(|b| *b == data[0]));
        assert_eq!(fs::read(&stale).unwrap(), b"unrelated");
        assert_eq!(fs::read(&collision).unwrap(), b"other writer");
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn failed_rename_preserves_destination_and_cleans_own_temp() {
        let dir =
            std::env::temp_dir().join(format!("task-manager-failed-write-{}", std::process::id()));
        let dest = dir.join("destination");
        fs::create_dir_all(&dest).unwrap();
        fs::write(dest.join("keep"), b"original").unwrap();
        assert!(atomic_write(&dest, b"replacement").is_err());
        assert_eq!(fs::read(dest.join("keep")).unwrap(), b"original");
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }
}
