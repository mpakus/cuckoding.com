use super::*;
use std::{
    ffi::CString,
    os::fd::{AsRawFd, FromRawFd},
    os::unix::fs::MetadataExt,
};

fn open(parent: &File, name: &str, flags: i32) -> Result<File> {
    let name = CString::new(name).map_err(|_| "invalid_request")?;
    // SAFETY: the parent descriptor and NUL-terminated name remain live through openat.
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
            0o600,
        )
    };
    if fd < 0 {
        return Err("image_changed");
    }
    // SAFETY: successful openat returned a new owned descriptor.
    Ok(unsafe { File::from_raw_fd(fd) })
}

fn directory(parent: &File, name: &str, create: bool, exclusive: bool) -> Result<File> {
    if create {
        let text = CString::new(name).map_err(|_| "invalid_request")?;
        // SAFETY: parent owns its live descriptor and text remains NUL terminated.
        if unsafe { libc::mkdirat(parent.as_raw_fd(), text.as_ptr(), 0o700) } == 0 {
            parent.sync_all().map_err(|_| "image_incomplete")?;
        } else if exclusive {
            return Err("image_exists");
        } else if io::Error::last_os_error().kind() != io::ErrorKind::AlreadyExists {
            return Err("image_incomplete");
        }
    }
    let file = open(parent, name, libc::O_RDONLY | libc::O_DIRECTORY)?;
    let meta = file.metadata().map_err(|_| "image_changed")?;
    if meta.mode() & 0o077 != 0
        || meta.uid() != parent.metadata().map_err(|_| "image_changed")?.uid()
    {
        return Err("image_changed");
    }
    Ok(file)
}

pub(super) struct Store {
    home: File,
    parent: File,
    pub(super) owned: File,
    home_path: PathBuf,
    key: String,
}

impl Store {
    pub(super) fn open(home: &Path, key: &str, create: bool) -> Result<Self> {
        private_directory(home).map_err(|_| "unsafe_image")?;
        if home.file_name().and_then(|n| n.to_str()) != Some("runtime-home") {
            return Err("unsafe_image");
        }
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW | libc::O_DIRECTORY)
            .open(home)
            .map_err(|_| "unsafe_image")?;
        // SAFETY: geteuid has no pointer arguments or memory preconditions.
        if file.metadata().map_err(|_| "unsafe_image")?.uid() != unsafe { libc::geteuid() } {
            return Err("unsafe_image");
        }
        let parent = directory(&file, "check-images", create, false)?;
        let owned = directory(&parent, key, create, true)?;
        Ok(Self {
            home: file,
            parent,
            owned,
            home_path: home.into(),
            key: key.into(),
        })
    }
    pub(super) fn current(&self) -> Result<()> {
        private_directory(&self.home_path).map_err(|_| "image_changed")?;
        let meta = fs::symlink_metadata(&self.home_path).map_err(|_| "image_changed")?;
        let parent = directory(&self.home, "check-images", false, false)?;
        let owned = directory(&parent, &self.key, false, false)?;
        for (current, pinned) in [
            (&meta, &self.home.metadata().map_err(|_| "image_changed")?),
            (
                &parent.metadata().map_err(|_| "image_changed")?,
                &self.parent.metadata().map_err(|_| "image_changed")?,
            ),
            (
                &owned.metadata().map_err(|_| "image_changed")?,
                &self.owned.metadata().map_err(|_| "image_changed")?,
            ),
        ] {
            if current.dev() != pinned.dev() || current.ino() != pinned.ino() {
                return Err("image_changed");
            }
        }
        Ok(())
    }
    pub(super) fn create(&self, name: &str) -> Result<File> {
        open(
            &self.owned,
            name,
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
        )
        .map_err(|_| "image_incomplete")
    }
    pub(super) fn reader(&self, name: &str) -> Result<File> {
        let file = open(&self.owned, name, libc::O_RDONLY)?;
        let meta = file.metadata().map_err(|_| "image_changed")?;
        if !meta.is_file()
            || meta.nlink() != 1
            || meta.mode() & 0o7777 != 0o600
            || meta.len() > 134_217_728
            || meta.uid() != self.owned.metadata().map_err(|_| "image_changed")?.uid()
        {
            return Err("image_changed");
        }
        Ok(file)
    }
    pub(super) fn write(&self, name: &str, bytes: &[u8]) -> Result<()> {
        let mut file = self.create(name)?;
        file.write_all(bytes)
            .and_then(|_| file.sync_all())
            .map_err(|_| "image_incomplete")?;
        self.owned.sync_all().map_err(|_| "image_incomplete")
    }
    pub(super) fn read(&self, name: &str, limit: u64) -> Result<Vec<u8>> {
        let file = open(&self.owned, name, libc::O_RDONLY)?;
        let before = file.metadata().map_err(|_| "image_changed")?;
        if !before.is_file()
            || before.nlink() != 1
            || before.mode() & 0o7777 != 0o600
            || before.len() > limit
            || before.uid() != self.owned.metadata().map_err(|_| "image_changed")?.uid()
        {
            return Err("image_changed");
        }
        let mut bytes = Vec::new();
        (&file)
            .take(limit + 1)
            .read_to_end(&mut bytes)
            .map_err(|_| "image_changed")?;
        let after = file.metadata().map_err(|_| "image_changed")?;
        if bytes.len() as u64 != before.len()
            || before.len() != after.len()
            || before.mode() != after.mode()
            || before.mtime() != after.mtime()
            || before.mtime_nsec() != after.mtime_nsec()
            || before.ctime() != after.ctime()
            || before.ctime_nsec() != after.ctime_nsec()
        {
            return Err("image_changed");
        }
        Ok(bytes)
    }
}
