///|
pub(all) suberror SyncError {
  InvalidMemoryOrdering(String)
  InvalidCapacity(Int)
  InvalidMessageSizeLimit(Int)
  InvalidQueuedByteLimit(Int)
  InvalidOwnedBytesLimits
  InvalidWorkerCount(Int)
  InvalidWaitGroupCount
  MutexInitializationFailed(Int)
  CondvarInitializationFailed(Int)
  CondvarOperationFailed(Int)
  RwLockInitializationFailed(Int)
  RwLockOperationFailed(Int)
  ThreadCreationFailed(Int)
  ThreadJoinFailed(Int)
  ThreadAlreadyJoined
  ThreadJoinSelf
  ThreadPanicked(String)
  ThreadPoolCreationFailed(Int)
  ThreadPoolClosed
  ThreadPoolWouldDeadlock
  ThreadPoolShutdownFromWorker
  OncePoisoned
} derive(Debug)
