//! Public local-preview identity; no credentials, user paths or execution grants.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{fs::OpenOptions, io::Read, os::unix::fs::OpenOptionsExt, path::Path};

const EMBEDDED: &str = env!("CCODING_BUILD_INFO");
const RELATIVE: &str = "lib/cuckoding-0.1.0/priv/build-info.json";
const FIELDS: [&str; 13] = [
    "format",
    "build_id",
    "application",
    "channel",
    "source_revision",
    "source_dirty",
    "source_sha256",
    "built_at",
    "target",
    "schema",
    "elixir",
    "otp",
    "rust",
];

pub struct Identity {
    pub id: String,
    pub sha256: String,
}

fn parse(bytes: &str) -> Result<Value, &'static str> {
    if bytes.len() > 4096 {
        return Err("invalid build identity");
    }
    let value: Value = serde_json::from_str(bytes).map_err(|_| "invalid build identity")?;
    let id = value["build_id"].as_str().unwrap_or("");
    if bytes.len() > 4096
        || value["format"] != 1
        || value["application"] != "0.1.0"
        || value["channel"] != "local-preview"
        || !value.as_object().is_some_and(|o| {
            o.len() == FIELDS.len() && FIELDS.iter().all(|field| o.contains_key(*field))
        })
        || !hex(&value["source_revision"], 40)
        || !hex(&value["source_sha256"], 64)
        || !value["source_dirty"].is_boolean()
        || value["target"] != "aarch64-apple-darwin"
        || !value["schema"]
            .as_u64()
            .is_some_and(|n| (1..=1000).contains(&n))
        || !["elixir", "otp", "rust"]
            .iter()
            .all(|key| version(&value[*key]))
        || !utc(&value["built_at"])
        || id.len() != 36
        || !id.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
            }
        })
    {
        return Err("invalid build identity");
    }
    Ok(value)
}

fn hex(value: &Value, length: usize) -> bool {
    value.as_str().is_some_and(|s| {
        s.len() == length
            && s.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    })
}

fn version(value: &Value) -> bool {
    value.as_str().is_some_and(|s| {
        let (base, suffix) = s.split_once('-').unwrap_or((s, "stable"));
        let parts: Vec<_> = base.split('.').collect();
        s.len() <= 32
            && (2..=4).contains(&parts.len())
            && parts
                .iter()
                .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
            && !suffix.is_empty()
            && suffix
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'.')
    })
}

fn utc(value: &Value) -> bool {
    value.as_str().is_some_and(|s| {
        let b = s.as_bytes();
        if b.len() != 20
            || !b.iter().enumerate().all(|(i, c)| match i {
                4 | 7 => *c == b'-',
                10 => *c == b'T',
                13 | 16 => *c == b':',
                19 => *c == b'Z',
                _ => c.is_ascii_digit(),
            })
        {
            return false;
        }
        let year = s[..4].parse::<u16>().unwrap();
        let month = s[5..7].parse::<usize>().unwrap();
        let day = s[8..10].parse::<u8>().unwrap();
        let leap =
            year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
        let days = [
            31,
            if leap { 29 } else { 28 },
            31,
            30,
            31,
            30,
            31,
            31,
            30,
            31,
            30,
            31,
        ];
        (1..=12).contains(&month)
            && day > 0
            && day <= days[month - 1]
            && s[11..13] <= *"23"
            && s[14..16] <= *"59"
            && s[17..19] <= *"59"
    })
}

pub fn public() -> Value {
    parse(EMBEDDED).unwrap_or_else(|_| json!({"status":"unavailable","reason":"not_packaged"}))
}

pub fn release(release: &Path) -> Result<Identity, &'static str> {
    verify(EMBEDDED, release)
}

fn verify(embedded: &str, release: &Path) -> Result<Identity, &'static str> {
    let info = parse(embedded)?;
    let path = release.join(RELATIVE);
    for parent in path.ancestors() {
        if std::fs::symlink_metadata(parent)
            .map_err(|_| "build identity unavailable")?
            .file_type()
            .is_symlink()
        {
            return Err("linked build identity");
        }
    }
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(&path)
        .map_err(|_| "build identity unavailable")?;
    let metadata = file.metadata().map_err(|_| "build identity unavailable")?;
    if !metadata.is_file() || metadata.len() > 4096 {
        return Err("invalid build identity file");
    }
    let mut bytes = String::new();
    file.take(4097)
        .read_to_string(&mut bytes)
        .map_err(|_| "build identity unavailable")?;
    if bytes != embedded {
        return Err("native/release build mismatch");
    }
    Ok(Identity {
        id: info["build_id"].as_str().unwrap().to_owned(),
        sha256: format!("{:x}", Sha256::digest(embedded.as_bytes())),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, os::unix::fs::symlink};

    #[test]
    fn exact_release_binding_refuses_missing_changed_oversized_and_linked_metadata() {
        let root = std::env::temp_dir().canonicalize().unwrap().join(format!(
            "cuckoding-build-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = root.join(RELATIVE);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let value = json!({"format":1,"application":"0.1.0","channel":"local-preview",
            "build_id":"00000000-0000-4000-8000-000000000001","source_revision":"a".repeat(40),
            "source_dirty":true,"source_sha256":"b".repeat(64),"built_at":"2026-10-23T00:00:00Z",
            "target":"aarch64-apple-darwin","schema":17,"elixir":"1.20.3","otp":"28.5","rust":"1.97.1"}).to_string();
        assert!(verify(&value, &root).is_err());
        fs::write(&path, &value).unwrap();
        let proof = verify(&value, &root).unwrap();
        assert_eq!(
            proof.sha256,
            format!("{:x}", Sha256::digest(value.as_bytes()))
        );
        fs::write(&path, value.replace("000000000001", "000000000002")).unwrap();
        assert!(verify(&value, &root).is_err());
        fs::write(&path, "x".repeat(4097)).unwrap();
        assert!(verify(&value, &root).is_err());
        fs::remove_file(&path).unwrap();
        symlink(root.join("absent"), &path).unwrap();
        assert!(verify(&value, &root).is_err());
        assert!(parse("{}").is_err());
        assert!(!utc(&json!("2026-02-31T00:00:00Z")));
        assert!(utc(&json!("2024-02-29T23:59:59Z")));
        let mut foreign: Value = serde_json::from_str(&value).unwrap();
        foreign.as_object_mut().unwrap().remove("source_dirty");
        foreign["credential"] = json!("CANARY_NOT_PUBLIC");
        assert!(parse(&foreign.to_string()).is_err());
        for (key, bad) in [
            ("rust", json!("CANARY_NOT_PUBLIC")),
            ("source_sha256", json!("not-a-hash")),
            ("built_at", json!("2026-99-99T00:00:00Z")),
        ] {
            let mut changed: Value = serde_json::from_str(&value).unwrap();
            changed[key] = bad;
            assert!(parse(&changed.to_string()).is_err());
        }
        fs::remove_dir_all(root).unwrap();
    }
}
