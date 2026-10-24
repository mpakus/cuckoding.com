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

pub(crate) struct Store {
    home: File,
    parent: File,
    pub(super) owned: File,
    home_path: PathBuf,
    key: String,
    namespace: &'static str,
}

impl Store {
    pub(crate) fn open(home: &Path, key: &str, create: bool) -> Result<Self> {
        Self::namespace(home, key, create, "check-images")
    }
    pub(crate) fn run(home: &Path, key: &str) -> Result<Self> {
        Self::namespace(home, key, true, "check-runs")
    }
    pub(crate) fn retained_run(home: &Path, key: &str) -> Result<Self> {
        Self::namespace(home, key, false, "check-runs")
    }
    fn namespace(home: &Path, key: &str, create: bool, namespace: &'static str) -> Result<Self> {
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
        let parent = directory(&file, namespace, create, false)?;
        let owned = directory(&parent, key, create, true)?;
        Ok(Self {
            home: file,
            parent,
            owned,
            home_path: home.into(),
            key: key.into(),
            namespace,
        })
    }
    pub(crate) fn current(&self) -> Result<()> {
        private_directory(&self.home_path).map_err(|_| "image_changed")?;
        let meta = fs::symlink_metadata(&self.home_path).map_err(|_| "image_changed")?;
        let parent = directory(&self.home, self.namespace, false, false)?;
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
    pub(crate) fn create(&self, name: &str) -> Result<File> {
        open(
            &self.owned,
            name,
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
        )
        .map_err(|_| "image_incomplete")
    }
    pub(crate) fn clone_file(&self, source: &File, name: &str) -> Result<File> {
        let text = CString::new(name).map_err(|_| "invalid_request")?;
        // SAFETY: both descriptors and the fixed NUL-terminated child name remain live.
        if unsafe {
            libc::fclonefileat(source.as_raw_fd(), self.owned.as_raw_fd(), text.as_ptr(), 0)
        } != 0
        {
            if !matches!(
                io::Error::last_os_error().raw_os_error(),
                Some(libc::ENOTSUP | libc::EXDEV)
            ) {
                return Err("image_incomplete");
            }
            let mut output = self.create(name)?;
            let mut input = source.try_clone().map_err(|_| "image_changed")?;
            input.rewind().map_err(|_| "image_changed")?;
            io::copy(&mut input.take(134_217_729), &mut output).map_err(|_| "image_incomplete")?;
            output.sync_all().map_err(|_| "image_incomplete")?;
        }
        open(&self.owned, name, libc::O_WRONLY | libc::O_APPEND)
    }
    pub(crate) fn reader(&self, name: &str) -> Result<File> {
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
    pub(crate) fn write(&self, name: &str, bytes: &[u8]) -> Result<()> {
        let mut file = self.create(name)?;
        file.write_all(bytes)
            .and_then(|_| file.sync_all())
            .map_err(|_| "image_incomplete")?;
        self.owned.sync_all().map_err(|_| "image_incomplete")
    }
    pub(crate) fn read(&self, name: &str, limit: u64) -> Result<Vec<u8>> {
        self.read_mode(name, limit, 0o600)
    }
    pub(crate) fn keeper(&self) -> Result<Vec<u8>> {
        self.read_mode("keeper", 4_194_304, 0o700)
    }
    fn read_mode(&self, name: &str, limit: u64, mode: u32) -> Result<Vec<u8>> {
        let file = open(&self.owned, name, libc::O_RDONLY)?;
        let before = file.metadata().map_err(|_| "image_changed")?;
        if !before.is_file()
            || before.nlink() != 1
            || before.mode() & 0o7777 != mode
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
