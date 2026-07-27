///|
/// A non-recursive native mutex protecting one boxed MoonBit value.
pub struct Mutex[T] {
  priv handle : MutexHandle
  priv marker : (T) -> T
}

///|
pub fn[T] Mutex::new(value : T) -> Mutex[T] {
  { handle: native_mutex_new(box_value(value)), marker: type_marker }
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
/// The supplied Ref is valid only for the callback duration and must not be
/// retained. Use `share()` before moving a Mutex wrapper to another thread.
pub fn[T, R] Mutex::with_lock(
  self : Mutex[T],
  f : (Ref[T]) -> R raise?,
) -> R raise? {
  ignore(self.marker)
  let raw = native_mutex_lock_get(self.handle)
  let cell : Ref[T] = restore_box(raw)
  try f(cell) catch {
    err => {
      native_mutex_release_unlock(self.handle, erase_box(cell))
      raise err
    }
  } noraise {
    result => {
      native_mutex_release_unlock(self.handle, erase_box(cell))
      result
    }
  }
}

///|
/// Creates a native condition variable.
pub fn Condvar::new() -> Condvar {
  native_condvar_new()
}

///|
pub fn Condvar::share(self : Condvar) -> Condvar {
  native_condvar_share(self)
}

///|
/// Atomically releases `mutex`, waits, and reacquires it before returning.
/// Call only while the current thread holds `mutex`, and always recheck the
/// protected predicate in a loop because wakeups may be spurious.
pub fn[T] Condvar::wait(self : Condvar, mutex : Mutex[T]) -> Unit {
  native_condvar_wait(self, mutex.handle)
}

///|
pub fn Condvar::notify_one(self : Condvar) -> Unit {
  native_condvar_notify_one(self)
}

///|
pub fn Condvar::notify_all(self : Condvar) -> Unit {
  native_condvar_notify_all(self)
}

///|
pub fn Once::new() -> Once {
  native_once_new()
}

///|
pub fn Once::share(self : Once) -> Once {
  native_once_share(self)
}

///|
/// Runs an initializer once. A raised error poisons this Once instance.
pub fn Once::call_once(self : Once, f : () -> Unit raise?) -> Unit raise {
  match native_once_begin(self) {
    0 => ()
    1 =>
      try f() catch {
        err => {
          native_once_poison(self)
          raise err
        }
      } noraise {
        _ => native_once_complete(self)
      }
    _ => raise OncePoisoned
  }
}

///|
/// Creates a wait group with count zero.
pub fn WaitGroup::new() -> WaitGroup {
  native_wait_group_new()
}

///|
pub fn WaitGroup::share(self : WaitGroup) -> WaitGroup {
  native_wait_group_share(self)
}

///|
pub fn WaitGroup::add(self : WaitGroup, delta : Int) -> Unit raise SyncError {
  if !native_wait_group_add(self, delta) {
    raise InvalidWaitGroupCount
  }
}

///|
pub fn WaitGroup::done(self : WaitGroup) -> Unit raise SyncError {
  self.add(-1)
}

///|
pub fn WaitGroup::wait(self : WaitGroup) -> Unit {
  native_wait_group_wait(self)
}
