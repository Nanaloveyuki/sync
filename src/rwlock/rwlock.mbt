///|
/// A native reader-writer lock without an associated MoonBit value.
///
/// Multiple read callbacks may run concurrently, while a write callback is
/// exclusive. Ordinary MoonBit objects must not be aliased across OS threads;
/// callbacks should coordinate native handles or explicitly shared primitives.
/// The lock is non-recursive, cannot be upgraded or downgraded, and does not
/// guarantee fairness or freedom from reader/writer starvation.
pub fn RwLock::new() -> RwLock raise SyncError {
  let status = Ref::Ref(0)
  let lock = native_rwlock_new(status)
  if status.val != 0 {
    raise SyncError::RwLockInitializationFailed(status.val)
  }
  lock
}

///|
/// Creates an independent wrapper for use by another OS thread.
pub fn RwLock::share(self : RwLock) -> RwLock {
  native_rwlock_share(self)
}

///|
/// Runs `f` while holding a shared read lock.
///
/// MoonBit cannot statically prevent mutation through captured aliases. The
/// callback must treat any concurrently shared state as read-only itself.
pub fn[R] RwLock::with_read(self : RwLock, f : () -> R raise?) -> R raise {
  let lock_status = native_rwlock_read_lock(self)
  if lock_status != 0 {
    raise SyncError::RwLockOperationFailed(lock_status)
  }
  try f() catch {
    err => {
      let unlock_status = native_rwlock_read_unlock(self)
      if unlock_status != 0 {
        raise SyncError::RwLockOperationFailed(unlock_status)
      }
      raise err
    }
  } noraise {
    result => {
      let unlock_status = native_rwlock_read_unlock(self)
      if unlock_status != 0 {
        raise SyncError::RwLockOperationFailed(unlock_status)
      }
      result
    }
  }
}

///|
/// Runs `f` while holding an exclusive write lock.
pub fn[R] RwLock::with_write(self : RwLock, f : () -> R raise?) -> R raise {
  let lock_status = native_rwlock_write_lock(self)
  if lock_status != 0 {
    raise SyncError::RwLockOperationFailed(lock_status)
  }
  try f() catch {
    err => {
      let unlock_status = native_rwlock_write_unlock(self)
      if unlock_status != 0 {
        raise SyncError::RwLockOperationFailed(unlock_status)
      }
      raise err
    }
  } noraise {
    result => {
      let unlock_status = native_rwlock_write_unlock(self)
      if unlock_status != 0 {
        raise SyncError::RwLockOperationFailed(unlock_status)
      }
      result
    }
  }
}
