//! The shared Desktop Entry section parser used by launchers and autostart.
use std::collections::BTreeMap;

pub fn parse(text: &str) -> BTreeMap<String, String> {
    let mut active = false;
    let mut fields = BTreeMap::new();
    for line in text.lines().map(str::trim) {
        if line.starts_with('[') {
            active = line == "[Desktop Entry]";
        } else if active && !line.starts_with('#') {
            if let Some((key, value)) = line.split_once('=') {
                fields.insert(key.trim().into(), value.trim().into());
            }
        }
    }
    fields
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn comments_and_action_sections_cannot_override_application_fields() {
        let entry = parse("Name=outside\n [Desktop Entry] \nName = Main\n#Hidden=true\nHidden=false\nExec=app --arg=a=b\n[Desktop Action Test]\nName=Other\nHidden=true\n");
        assert_eq!(entry["Name"], "Main");
        assert_eq!(entry["Hidden"], "false");
        assert_eq!(entry["Exec"], "app --arg=a=b");
        assert_eq!(entry.len(), 3);
    }
}
