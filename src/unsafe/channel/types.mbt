///|
#derive(Eq, Debug)
pub(all) enum TrySendResult[T] {
  Sent
  Full(T)
  Closed(T)
}

///|
#doc(hidden)
pub extend TrySendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend TrySendResult with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum TryRecvResult[T] {
  Received(T)
  Empty
  Closed
}

///|
#doc(hidden)
pub extend TryRecvResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend TryRecvResult with @debug.Debug::{to_repr}

///|
