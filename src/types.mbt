///|
/// Memory ordering for atomic operations.
///
/// Windows uses Interlocked operations and may strengthen every ordering to
/// SeqCst. Linux implements the requested ordering with compiler atomics.
pub(all) enum MemoryOrdering {
  /// No inter-thread synchronization beyond atomicity.
  Relaxed
  /// Prevents later operations from moving before this operation.
  Acquire
  /// Prevents earlier operations from moving after this operation.
  Release
  /// Applies both Acquire and Release constraints.
  AcqRel
  /// Participates in one global sequentially consistent order.
  SeqCst
} derive(Eq, Debug)

///|
fn MemoryOrdering::code(self : MemoryOrdering) -> Int {
  match self {
    Relaxed => 0
    Acquire => 1
    Release => 2
    AcqRel => 3
    SeqCst => 4
  }
}

///|
pub(all) suberror SyncError {
  InvalidMemoryOrdering(String)
  InvalidCapacity(Int)
  InvalidWaitGroupCount
  ThreadCreationFailed(Int)
  ThreadJoinFailed(Int)
  ThreadAlreadyJoined
  ThreadPanicked(String)
  OncePoisoned
} derive(Debug)

///|
pub struct CompareExchangeResult[T] {
  observed : T
  exchanged : Bool
} derive(Eq, Debug)

///|
pub(all) enum TrySendResult[T] {
  Sent
  Full(T)
  Closed(T)
} derive(Eq, Debug)

///|
pub(all) enum TryRecvResult[T] {
  Received(T)
  Empty
  Closed
} derive(Eq, Debug)

///|
priv enum ThreadOutcome[T] {
  Returned(T)
  Failed(String)
}

///|
fn[T] type_marker(value : T) -> T {
  value
}
