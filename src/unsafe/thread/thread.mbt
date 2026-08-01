///|
/// A native OS thread whose task returns `Unit`.
///
/// The task must only capture thread-local values or independently shared
/// native handles. This type does not make captured MoonBit heap objects safe.
pub struct Thread {
  priv handle : ThreadHandle
}

///|
/// An explicitly unchecked native OS thread returning `T`.
///
/// The result and task closure cross an OS-thread boundary without a
/// compiler-enforced ownership or Send/Sync check.
pub struct UnsafeThread[T] {
  priv handle : ThreadHandle
  priv marker : (T) -> T
}

///|
fn[T] spawn_raw(task : () -> T raise) -> ThreadHandle raise SyncError {
  let creation_status = Ref::Ref(0)
  let handle = native_thread_new(creation_status)
  if creation_status.val != 0 {
    raise SyncError::ThreadInitializationFailed(creation_status.val)
  }
  let state = native_thread_state(handle)
  let runner = fn() {
    let outcome : ThreadOutcome[T] = Returned(task()) catch {
      err => Failed(err.to_string())
    }
    native_thread_complete(state, box_value(outcome))
  }
  let status = native_thread_start(handle, fn(callback) { callback() }, runner)
  if status != 0 {
    raise SyncError::ThreadCreationFailed(status)
  }
  handle
}

///|
fn[T] join_raw(handle : ThreadHandle) -> T raise SyncError {
  let status = Ref::Ref(0)
  let raw = native_thread_join(handle, status)
  match status.val {
    0 => {
      let cell : Ref[ThreadOutcome[T]] = restore_box(raw)
      match cell.val {
        Returned(value) => value
        Failed(message) => raise SyncError::ThreadPanicked(message)
      }
    }
    -1 => raise SyncError::ThreadAlreadyJoined
    -2 => raise SyncError::ThreadJoinSelf
    -3 => raise SyncError::ThreadAlreadyDetached
    -4 => raise SyncError::ThreadOperationInProgress
    code => raise SyncError::ThreadJoinFailed(code)
  }
}

///|
fn detach_raw(handle : ThreadHandle) -> Unit raise SyncError {
  let status = Ref::Ref(0)
  native_thread_detach(handle, status)
  match status.val {
    0 => ()
    -1 => raise SyncError::ThreadAlreadyJoined
    -2 => raise SyncError::ThreadAlreadyDetached
    -3 => raise SyncError::ThreadOperationInProgress
    code => raise SyncError::ThreadDetachFailed(code)
  }
}

///|
fn is_finished_raw(handle : ThreadHandle) -> Bool raise SyncError {
  let status = Ref::Ref(0)
  let result = native_thread_is_finished(handle, status)
  if status.val != 0 {
    raise SyncError::ThreadOperationFailed(status.val)
  }
  result
}

///|
/// Spawns a native OS thread with a `Unit` result.
pub fn spawn(task : () -> Unit raise) -> Thread raise SyncError {
  { handle: spawn_raw(task) }
}

///|
/// Spawns a native OS thread with a `Unit` result.
pub fn Thread::spawn(task : () -> Unit raise) -> Thread raise SyncError {
  spawn(task)
}

///|
/// Spawns an explicitly unchecked thread returning `T`.
pub fn[T] spawn_unchecked(
  task : () -> T raise,
) -> UnsafeThread[T] raise SyncError {
  { handle: spawn_raw(task), marker: type_marker }
}

///|
/// Spawns an explicitly unchecked thread returning `T`.
pub fn[T] UnsafeThread::spawn(
  task : () -> T raise,
) -> UnsafeThread[T] raise SyncError {
  spawn_unchecked(task)
}

///|
/// Waits for completion. A thread must be joined or detached before its
/// handle becomes unreachable.
pub fn Thread::join(self : Thread) -> Unit raise SyncError {
  let result : Unit = join_raw(self.handle)
  ignore(result)
}

///|
/// Waits for completion and returns the unchecked task result.
pub fn[T] UnsafeThread::join(self : UnsafeThread[T]) -> T raise SyncError {
  ignore(self.marker)
  join_raw(self.handle)
}

///|
/// Detaches the OS thread explicitly. Detached threads cannot be joined.
pub fn Thread::detach(self : Thread) -> Unit raise SyncError {
  detach_raw(self.handle)
}

///|
/// Detaches the OS thread explicitly. Detached threads cannot be joined.
pub fn[T] UnsafeThread::detach(self : UnsafeThread[T]) -> Unit raise SyncError {
  ignore(self.marker)
  detach_raw(self.handle)
}

///|
/// Reports whether the task has completed. This does not join or detach it.
pub fn Thread::is_finished(self : Thread) -> Bool raise SyncError {
  is_finished_raw(self.handle)
}

///|
/// Reports whether the unchecked task has completed. This does not join or
/// detach it.
pub fn[T] UnsafeThread::is_finished(
  self : UnsafeThread[T],
) -> Bool raise SyncError {
  ignore(self.marker)
  is_finished_raw(self.handle)
}

///|
/// Returns an opaque process-local identifier for this thread.
pub fn Thread::id(self : Thread) -> UInt64 {
  native_thread_id(self.handle)
}

///|
/// Returns an opaque process-local identifier for this unchecked thread.
pub fn[T] UnsafeThread::id(self : UnsafeThread[T]) -> UInt64 {
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
