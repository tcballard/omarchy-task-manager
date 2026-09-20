use std::{
    fs::File,
    io::{self, Read, Write},
    path::Path,
};

pub fn text(path: impl AsRef<Path>, limit: usize) -> io::Result<String> {
    read_text(File::open(path)?, limit)
}
fn read_text(reader: impl Read, limit: usize) -> io::Result<String> {
    let mut bytes = Vec::new();
    reader.take(limit as u64 + 1).read_to_end(&mut bytes)?;
    let truncated = bytes.len() > limit;
    bytes.truncate(limit);
    let mut text = String::from_utf8_lossy(&bytes).into_owned();
    if truncated {
        text.push_str("\n[… truncated …]");
    }
    Ok(text)
}
pub struct Buffer {
    pub bytes: Vec<u8>,
    limit: usize,
}
impl Buffer {
    pub fn new(limit: usize) -> Self {
        Self {
            bytes: Vec::new(),
            limit,
        }
    }
}
impl Write for Buffer {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        if data.len() > self.limit.saturating_sub(self.bytes.len()) {
            return Err(io::Error::other("Response exceeds limit"));
        }
        self.bytes.extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reads_only_limit_plus_one_and_marks_truncation() {
        let mut input = io::Cursor::new(vec![b'x'; 10_000]);
        let text = read_text(&mut input, 128).unwrap();
        assert_eq!(input.position(), 129);
        assert!(text.ends_with("[… truncated …]"));
        assert_eq!(read_text(&b"short"[..], 128).unwrap(), "short");
        assert!(read_text(&[0xff, 0xfe][..], 1).unwrap().contains('�'));
    }
}
