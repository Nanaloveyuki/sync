///|
pub using @types {type SyncError}

///|
pub using @atomic {
  type AtomicBool,
  type AtomicInt,
  type AtomicUInt,
  type CompareExchangeResult,
  type MemoryOrdering,
}

///|
pub using @once {type Once}

///|
pub using @wait_group {type WaitGroup}

///|
pub using @rwlock {type RwLock}

///|
pub using @channel {
  type OwnedBytesSender,
  type OwnedBytesReceiver,
  type OwnedBytesTrySendResult,
  type OwnedBytesSendResult,
  type OwnedBytesTryRecvResult,
  owned_bytes_bounded,
  owned_bytes_bounded_with_limits,
}
