///|
/// A joinable native OS thread returning `T`.
pub struct Thread[T] {
  priv handle : ThreadHandle
  priv marker : (T) -> T
}

///|
/// Spawns a native OS thread.
///
/// Captured native handles must be created with their `share()` method. Plain
/// MoonBit objects with aliases in another thread are not safe to capture
/// because the current native runtime uses non-atomic reference counting.
pub fn[T] spawn(task : () -> T raise) -> Thread[T] raise SyncError {
  let handle = native_thread_new()
  let state = native_thread_state(handle)
  let runner = fn() {
    let outcome : ThreadOutcome[T] = Returned(task()) catch {
      err => Failed(err.to_string())
    }
    native_thread_complete(state, box_value(outcome))
  }
  let status = native_thread_start(handle, fn(callback) { callback() }, runner)
  if status != 0 {
    raise ThreadCreationFailed(status)
  }
  { handle, marker: type_marker }
}

///|
pub fn[T] Thread::spawn(task : () -> T raise) -> Thread[T] raise SyncError {
  spawn(task)
}

///|
/// Waits for completion and returns the task result.
pub fn[T] Thread::join(self : Thread[T]) -> T raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  let raw = native_thread_join(self.handle, status)
  match status.val {
    0 => {
      let cell : Ref[ThreadOutcome[T]] = restore_box(raw)
      match cell.val {
        Returned(value) => value
        Failed(message) => raise ThreadPanicked(message)
      }
    }
    -1 => raise ThreadAlreadyJoined
    -2 => raise ThreadJoinSelf
    code => raise ThreadJoinFailed(code)
  }
}

///|
/// Returns an opaque process-local identifier for this thread.
pub fn[T] Thread::id(self : Thread[T]) -> UInt64 {
  ignore(self.marker)
  native_thread_id(self.handle)
}

///|
/// Yields the current OS thread's remaining time slice.
pub fn yield_now() -> Unit {
  native_thread_yield()
}

///|
/// Returns an opaque process-local identifier for the current thread.
pub fn current_thread_id() -> UInt64 {
  native_current_thread_id()
}
