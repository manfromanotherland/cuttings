// SPDX-License-Identifier: MIT

//! Cross-process serialization for one reading's files.
//!
//! The lock file lives outside the reading folder so deletion cannot unlink the
//! lock inode while another process is waiting on it. Sidecars are persistent:
//! removing them after use would create a race between the old inode and a newly
//! created one.

use std::{
    fs::{self, File, OpenOptions},
    path::PathBuf,
};

use anyhow::{bail, Result};

use crate::LibraryRoot;

pub(crate) struct ReadingLock {
    file: File,
    path: PathBuf,
}

/// Acquire the exclusive advisory lock for `id`, blocking until every other
/// Cuttings process has finished its read-modify-write or delete operation.
pub(crate) fn lock_reading(library: &LibraryRoot, id: &str) -> Result<ReadingLock> {
    let path = lock_path(library, id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&path)?;
    fs2::FileExt::lock_exclusive(&file)?;
    Ok(ReadingLock { file, path })
}

impl ReadingLock {
    /// Guard against accidentally using a lock for one reading while writing
    /// another through an unlocked internal helper.
    pub(crate) fn ensure_protects(&self, library: &LibraryRoot, id: &str) -> Result<()> {
        let expected = lock_path(library, id);
        if self.path != expected {
            bail!(
                "reading lock {} does not protect {}",
                self.path.display(),
                library.article_path(id).display()
            );
        }
        Ok(())
    }
}

impl Drop for ReadingLock {
    fn drop(&mut self) {
        let _ = fs2::FileExt::unlock(&self.file);
    }
}

/// Hash even already-hashed ids so arbitrary external ids cannot introduce a
/// path component into the operational lock directory.
fn lock_path(library: &LibraryRoot, id: &str) -> PathBuf {
    let key = crate::sha256_hex(id.as_bytes());
    library
        .path()
        .join(".cuttings-locks")
        .join(&key[..2])
        .join(format!("{key}.lock"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sidecar_is_persistent_and_outside_reading_folder() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "reading-id";
        let path = lock_path(&library, id);

        {
            let guard = lock_reading(&library, id).unwrap();
            guard.ensure_protects(&library, id).unwrap();
            assert!(path.is_file());
            assert!(!path.starts_with(library.reading_dir(id)));
        }

        assert!(path.is_file(), "sidecar must retain one stable lock inode");
    }

    #[test]
    fn ids_cannot_escape_the_lock_directory() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let path = lock_path(&library, "../../outside");
        assert!(path.starts_with(library.path().join(".cuttings-locks")));
    }

    #[test]
    fn a_second_process_handle_cannot_enter_the_same_reading() {
        let dir = tempfile::TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let id = "same-reading";
        let first = lock_reading(&library, id).unwrap();
        let second = OpenOptions::new()
            .read(true)
            .write(true)
            .open(lock_path(&library, id))
            .unwrap();

        assert!(
            fs2::FileExt::try_lock_exclusive(&second).is_err(),
            "a distinct file handle must not enter while the first holds the lock"
        );

        drop(first);
        fs2::FileExt::lock_exclusive(&second).unwrap();
        fs2::FileExt::unlock(&second).unwrap();
    }
}
