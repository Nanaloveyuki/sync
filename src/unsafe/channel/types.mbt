///|
pub(all) enum TrySendResult[T] {
  Sent
  Full(T)
  Closed(T)
} derive(Eq, Debug)

///|
#doc(hidden)
pub extend TrySendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend TrySendResult with @debug.Debug::{to_repr}

///|
pub(all) enum TryRecvResult[T] {
  Received(T)
  Empty
  Closed
} derive(Eq, Debug)

///|
#doc(hidden)
pub extend TryRecvResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend TryRecvResult with @debug.Debug::{to_repr}

///|
