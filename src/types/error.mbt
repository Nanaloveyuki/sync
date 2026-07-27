///|
pub(all) suberror SyncError {
  InvalidMemoryOrdering(String)
  InvalidCapacity(Int)
  InvalidWorkerCount(Int)
  InvalidWaitGroupCount
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
