///|
/// The result of a non-blocking owned-bytes send.
#derive(Eq, Debug)
pub(all) enum OwnedBytesTrySendResult {
  Sent
  Full
  QueueByteLimitReached(Int32, Int32)
  MessageTooLarge(Int32, Int32)
  Closed
}

///|
#doc(hidden)
pub extend OwnedBytesTrySendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesTrySendResult with @debug.Debug::{to_repr}

///|
/// The result of a blocking owned-bytes send.
#derive(Eq, Debug)
pub(all) enum OwnedBytesSendResult {
  Sent
  MessageTooLarge(Int32, Int32)
  Closed
}

///|
#doc(hidden)
pub extend OwnedBytesSendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesSendResult with @debug.Debug::{to_repr}

///|
/// The result of a non-blocking owned-bytes receive.
#derive(Eq, Debug)
pub(all) enum OwnedBytesTryRecvResult {
  Received(Bytes)
  Empty
  Closed
}

///|
#doc(hidden)
pub extend OwnedBytesTryRecvResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesTryRecvResult with @debug.Debug::{to_repr}
