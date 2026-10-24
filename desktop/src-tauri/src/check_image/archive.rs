use super::*;
use flate2::{read::MultiGzDecoder, write::GzEncoder, Compression};
use std::{collections::BTreeMap, io::Cursor};

#[derive(Clone, PartialEq)]
struct Entry {
    mode: u32,
    bytes: Vec<u8>,
}
pub(super) struct Image {
    files: BTreeMap<String, Entry>,
    bytes: usize,
}

fn name(value: &str) -> Result<String> {
    let value = value
        .strip_prefix("./")
        .unwrap_or(value)
        .trim_end_matches('/');
    if value.is_empty()
        || value.len() > 1024
        || value.chars().any(char::is_control)
        || value.contains('\\')
        || value.split('/').any(|part| ["", ".", ".."].contains(&part))
    {
        return Err("unsupported_input");
    }
    Ok(value.into())
}
impl Image {
    pub(super) fn new() -> Self {
        Self {
            files: BTreeMap::new(),
            bytes: 0,
        }
    }
    fn add(&mut self, path: &str, mode: u32, bytes: Vec<u8>) -> Result<()> {
        let path = name(path)?;
        if bytes.len() > 67_108_864 {
            return Err("image_limit");
        }
        let next = Entry { mode, bytes };
        if let Some(old) = self.files.get(&path) {
            if *old == next {
                return Ok(());
            }
            if path == "bin/sh"
                && mode == 0o120777
                && [b"busybox".as_slice(), b"/bin/busybox"].contains(&next.bytes.as_slice())
                && [b"busybox".as_slice(), b"/bin/busybox"].contains(&old.bytes.as_slice())
            {
                return Ok(());
            }
            return Err("unsupported_input");
        }
        self.bytes += next.bytes.len();
        if self.bytes > 536_870_912 || self.files.len() >= 12000 {
            return Err("image_limit");
        }
        self.files.insert(path, next);
        Ok(())
    }
    pub(super) fn tar(
        &mut self,
        bytes: &[u8],
        base: bool,
        active: &impl Fn() -> Result<()>,
    ) -> Result<()> {
        let decoded = MultiGzDecoder::new(bytes).take(1_073_741_825);
        let mut archive = tar::Archive::new(decoded);
        archive.set_ignore_zeros(true);
        let mut links = Vec::new();
        let mut count = 0;
        for entry in archive.entries().map_err(|_| "unsupported_input")? {
            active()?;
            count += 1;
            if count > 20000 {
                return Err("image_limit");
            }
            let entry = entry.map_err(|_| "unsupported_input")?;
            let raw = entry
                .path()
                .map_err(|_| "unsupported_input")?
                .to_str()
                .ok_or("unsupported_input")?
                .to_owned();
            if [".", "./"].contains(&raw.as_str()) {
                continue;
            }
            let path = name(&raw)?;
            if path.starts_with('.') {
                continue;
            }
            let kind = entry.header().entry_type();
            if base
                && !["bin/busybox", "lib/ld-musl-aarch64.so.1"].contains(&path.as_str())
                && !kind.is_symlink()
            {
                continue;
            }
            if kind.is_dir() {
                self.add(&path, 0o40755, vec![])?;
            } else if kind.is_file() {
                let size = entry.size();
                if size > 67_108_864 {
                    return Err("image_limit");
                }
                let mode = entry.header().mode().map_err(|_| "unsupported_input")? & 0o777;
                let mut data = Vec::new();
                entry
                    .take(67_108_865)
                    .read_to_end(&mut data)
                    .map_err(|_| "unsupported_input")?;
                if data.len() as u64 != size {
                    return Err("unsupported_input");
                }
                self.add(&path, 0o100000 | mode, data)?;
            } else if kind.is_symlink() || kind.is_hard_link() {
                let target = entry
                    .link_name()
                    .map_err(|_| "unsupported_input")?
                    .and_then(|p| p.to_str().map(str::to_owned))
                    .ok_or("unsupported_input")?;
                if base && !target.contains("busybox") {
                    continue;
                }
                if kind.is_symlink() {
                    if target.len() > 1024 || target.contains('\0') {
                        return Err("unsupported_input");
                    }
                    self.add(&path, 0o120777, target.into_bytes())?;
                } else {
                    links.push((path, name(&target)?));
                }
            } else {
                return Err("unsupported_input");
            }
        }
        if archive.into_inner().limit() == 0 {
            return Err("image_limit");
        }
        for (path, target) in links {
            let source = self
                .files
                .get(&target)
                .filter(|e| e.mode & 0o170000 == 0o100000)
                .cloned()
                .ok_or("unsupported_input")?;
            self.add(&path, source.mode, source.bytes)?;
        }
        Ok(())
    }
    pub(super) fn zip(&mut self, bytes: Vec<u8>, active: &impl Fn() -> Result<()>) -> Result<()> {
        let mut archive =
            zip::ZipArchive::new(Cursor::new(bytes)).map_err(|_| "unsupported_input")?;
        if archive.len() > 2000 {
            return Err("image_limit");
        }
        for index in 0..archive.len() {
            active()?;
            let entry = archive.by_index(index).map_err(|_| "unsupported_input")?;
            let path = format!(
                "opt/elixir/{}",
                name(&entry.name().map_err(|_| "unsupported_input")?)?
            );
            if entry.is_dir() {
                self.add(&path, 0o40755, vec![])?;
            } else {
                if !entry.is_file() || entry.size() > 8_388_608 {
                    return Err("unsupported_input");
                }
                let mut bytes = Vec::new();
                let size = entry.size();
                entry
                    .take(8_388_609)
                    .read_to_end(&mut bytes)
                    .map_err(|_| "unsupported_input")?;
                if bytes.len() as u64 != size {
                    return Err("unsupported_input");
                }
                self.add(
                    &path,
                    if path.starts_with("opt/elixir/bin/") {
                        0o100755
                    } else {
                        0o100644
                    },
                    bytes,
                )?;
            }
        }
        Ok(())
    }
    pub(super) fn finish(
        mut self,
        store: &store::Store,
        spec: &str,
        active: &impl Fn() -> Result<()>,
    ) -> Result<(usize, usize)> {
        for (path, mode, data) in [
            ("init", 0o100555, INIT.as_bytes()),
            ("launch", 0o100555, LAUNCH.as_bytes()),
            ("control.mjs", 0o100444, CONTROL.as_bytes()),
            ("worker.mjs", 0o100444, WORKER.as_bytes()),
            ("protocol.mjs", 0o100444, PROTOCOL.as_bytes()),
            (
                "etc/passwd",
                0o100644,
                b"root:!:0:0::/:/bin/sh\nworker:!:1000:1000::/tmp/home:/bin/sh\n",
            ),
            ("etc/group", 0o100644, b"root:x:0:\nworker:x:1000:\n"),
        ] {
            self.add(path, mode, data.into())?;
        }
        self.add(
            "image.json",
            0o100444,
            json!({"contract":CONTRACT,"spec_sha256":spec,"toolchains":versions()})
                .to_string()
                .into_bytes(),
        )?;
        for path in [
            "bin", "lib", "dev", "proc", "sys", "tmp", "run", "requests", "work",
        ] {
            self.add(path, 0o40755, vec![])?;
        }
        let paths: Vec<_> = self.files.keys().cloned().collect();
        for path in paths {
            for (index, _) in path.match_indices('/') {
                let parent = &path[..index];
                if self.files.get(parent).is_some_and(|e| e.mode != 0o40755) {
                    return Err("unsupported_input");
                }
                self.add(parent, 0o40755, vec![])?;
            }
        }
        let count = self.files.len();
        let expanded = self.bytes;
        let file = store.create("ramdisk.cpio.gz")?;
        let mut output = GzEncoder::new(file, Compression::default());
        let mut offset = 0;
        for (index, (path, entry)) in self
            .files
            .into_iter()
            .chain([(
                "TRAILER!!!".into(),
                Entry {
                    mode: 0,
                    bytes: vec![],
                },
            )])
            .enumerate()
        {
            active()?;
            let mut header = String::from("070701");
            for field in [
                index as u32 + 1,
                entry.mode,
                0,
                0,
                1,
                0,
                entry.bytes.len() as u32,
                0,
                0,
                0,
                0,
                path.len() as u32 + 1,
                0,
            ] {
                header.push_str(&format!("{field:08x}"));
            }
            output
                .write_all(header.as_bytes())
                .and_then(|_| output.write_all(path.as_bytes()))
                .and_then(|_| output.write_all(&[0]))
                .map_err(|_| "image_incomplete")?;
            offset += 110 + path.len() + 1;
            let pad = (4 - offset % 4) % 4;
            output
                .write_all(&[0; 3][..pad])
                .map_err(|_| "image_incomplete")?;
            offset += pad;
            output
                .write_all(&entry.bytes)
                .map_err(|_| "image_incomplete")?;
            offset += entry.bytes.len();
            let pad = (4 - offset % 4) % 4;
            output
                .write_all(&[0; 3][..pad])
                .map_err(|_| "image_incomplete")?;
            offset += pad;
        }
        output
            .finish()
            .and_then(|f| f.sync_all())
            .map_err(|_| "image_incomplete")?;
        store.owned.sync_all().map_err(|_| "image_incomplete")?;
        Ok((count, expanded))
    }
}

pub(super) fn kernel(bytes: &[u8]) -> Result<Vec<u8>> {
    if bytes.len() < 29 || &bytes[4..8] != b"zimg" || &bytes[24..29] != b"gzip\0" {
        return Err("unsupported_input");
    }
    let offset = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    let size = u32::from_le_bytes(bytes[12..16].try_into().unwrap()) as usize;
    let compressed = bytes
        .get(offset..offset.checked_add(size).ok_or("unsupported_input")?)
        .ok_or("unsupported_input")?;
    let mut kernel = Vec::new();
    MultiGzDecoder::new(compressed)
        .take(134_217_729)
        .read_to_end(&mut kernel)
        .map_err(|_| "unsupported_input")?;
    if kernel.len() > 134_217_728 || kernel.get(56..60) != Some(b"ARM\x64") {
        return Err("unsupported_input");
    }
    Ok(kernel)
}
