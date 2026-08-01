///|
/// Explicit low-level native concurrency APIs.
///
/// MoonBit does not enforce a Send/Sync boundary. Do not transfer aliased
/// MoonBit heap objects or closures between OS threads through these APIs.
pub using @types {type SyncError}

///|
pub using @thread {
  type Thread,
  type UnsafeThread,
  spawn,
  spawn_unchecked,
  yield_now,
  current_thread_id,
}

///|
pub using @thread_pool {type ThreadPool, type TryExecuteResult}

///|
pub using @channel {
  type Sender,
  type Receiver,
  type TrySendResult,
  type TryRecvResult,
  bounded,
}

///|
pub using @mutex {
  type Mutex,
  type MutexGuard,
  type Condvar,
  condvar_wait_unchecked,
}
