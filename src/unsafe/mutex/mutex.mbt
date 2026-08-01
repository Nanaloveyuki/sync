///|
/// A non-recursive native mutex protecting one boxed MoonBit value.
pub struct Mutex[T] {
  priv handle : MutexHandle
  priv marker : (T) -> T
}

///|
/// A mutex-lock capability valid only during `Mutex::with_lock`.
pub struct MutexGuard[T] {
  priv handle : MutexHandle
  priv value : RawBox
  priv active : Ref[Bool]
  priv marker : (T) -> T
}

///|
fn[T] MutexGuard::ensure_active(self : MutexGuard[T]) -> Unit {
  ignore(self.handle)
  ignore(self.marker)
  if !self.active.val {
    panic()
  }
}

///|
/// Runs `f` while this guard is active and the mutex remains locked.
pub fn[T, R] MutexGuard::with_value(
  self : MutexGuard[T],
  f : (Ref[T]) -> R raise?,
) -> R raise? {
  self.ensure_active()
  let cell : Ref[T] = restore_box(self.value)
  f(cell)
}

///|
/// Creates a native mutex protecting `value`.
///
/// Raises `MutexInitializationFailed` when the OS mutex cannot be initialized.
pub fn[T] Mutex::new(value : T) -> Mutex[T] raise SyncError {
  let status = Ref::Ref(0)
  let handle = native_mutex_new(box_value(value), status)
  if status.val != 0 {
    raise SyncError::MutexInitializationFailed(status.val)
  }
  { handle, marker: type_marker }
}

///|
/// Creates an independent wrapper for use by another OS thread.
pub fn[T] Mutex::share(self : Mutex[T]) -> Mutex[T] {
  ignore(self.marker)
  { handle: native_mutex_share(self.handle), marker: type_marker }
}

///|
/// Runs `f` while the mutex is locked.
///
/// The supplied guard is valid only for the callback duration and must not be
/// retained. Use `guard.with_value` for the protected value and `Condvar.wait`
/// for an atomic release-and-reacquire wait.
pub fn[T, R] Mutex::with_lock(
  self : Mutex[T],
  f : (MutexGuard[T]) -> R raise?,
) -> R raise {
  ignore(self.marker)
  let lock_status = Ref::Ref(0)
  let raw = native_mutex_lock_get(self.handle, lock_status)
  if lock_status.val != 0 {
    raise SyncError::MutexOperationFailed(lock_status.val)
  }
  let active = Ref::Ref(true)
  let lock_guard = {
    handle: native_mutex_share(self.handle),
    value: raw,
    active,
    marker: type_marker,
  }
  try f(lock_guard) catch {
    err => {
      active.val = false
      let unlock_status = Ref::Ref(0)
      native_mutex_release_unlock(self.handle, raw, unlock_status)
      if unlock_status.val != 0 {
        raise SyncError::MutexOperationFailed(unlock_status.val)
      }
      raise err
    }
  } noraise {
    result => {
      active.val = false
      let unlock_status = Ref::Ref(0)
      native_mutex_release_unlock(self.handle, raw, unlock_status)
      if unlock_status.val != 0 {
        raise SyncError::MutexOperationFailed(unlock_status.val)
      }
      result
    }
  }
}

///|
/// Creates a native condition variable.
///
/// Raises `CondvarInitializationFailed` when the OS condition variable cannot
/// be initialized.
pub fn Condvar::new() -> Condvar raise SyncError {
  let status = Ref::Ref(0)
  let condvar = native_condvar_new(status)
  if status.val != 0 {
    raise SyncError::CondvarInitializationFailed(status.val)
  }
  condvar
}

///|
pub fn Condvar::share(self : Condvar) -> Condvar {
  native_condvar_share(self)
}

///|
/// Atomically releases the guard's mutex, waits, and reacquires it.
///
/// Always recheck the protected predicate in a loop because wakeups may be
/// spurious. The guard must come from the active `Mutex::with_lock` callback.
pub fn[T] Condvar::wait(
  self : Condvar,
  lock_guard : MutexGuard[T],
) -> Unit raise SyncError {
  lock_guard.ensure_active()
  let status = native_condvar_wait(self, lock_guard.handle)
  if status != 0 {
    raise SyncError::CondvarOperationFailed(status)
  }
}

///|
/// Performs a raw condition-variable wait without a guard precondition check.
///
/// This is retained for low-level compatibility only. Calling it without
/// holding `mutex` on the current thread can violate OS API preconditions.
pub fn[T] condvar_wait_unchecked(
  condvar : Condvar,
  mutex : Mutex[T],
) -> Unit raise SyncError {
  let status = native_condvar_wait(condvar, mutex.handle)
  if status != 0 {
    raise SyncError::CondvarOperationFailed(status)
  }
}

///|
/// Wakes one waiter.
///
/// Raises `CondvarOperationFailed` when the OS reports a signal failure.
pub fn Condvar::notify_one(self : Condvar) -> Unit raise SyncError {
  let status = native_condvar_notify_one(self)
  if status != 0 {
    raise SyncError::CondvarOperationFailed(status)
  }
}

///|
/// Wakes all waiters.
///
/// Raises `CondvarOperationFailed` when the OS reports a broadcast failure.
pub fn Condvar::notify_all(self : Condvar) -> Unit raise SyncError {
  let status = native_condvar_notify_all(self)
  if status != 0 {
    raise SyncError::CondvarOperationFailed(status)
  }
}
