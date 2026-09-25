///|
/// The result of a non-blocking owned-bytes send.
pub(all) enum OwnedBytesTrySendResult {
  Sent
  Full
  QueueByteLimitReached(Int, Int)
  MessageTooLarge(Int, Int)
  Closed
} derive(Eq, Debug)

///|
#doc(hidden)
pub extend OwnedBytesTrySendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesTrySendResult with @debug.Debug::{to_repr}

///|
/// The result of a blocking owned-bytes send.
pub(all) enum OwnedBytesSendResult {
  Sent
  MessageTooLarge(Int, Int)
  Closed
} derive(Eq, Debug)

///|
#doc(hidden)
pub extend OwnedBytesSendResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesSendResult with @debug.Debug::{to_repr}

///|
/// The result of a non-blocking owned-bytes receive.
pub(all) enum OwnedBytesTryRecvResult {
  Received(Bytes)
  Empty
  Closed
} derive(Eq, Debug)

///|
#doc(hidden)
pub extend OwnedBytesTryRecvResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend OwnedBytesTryRecvResult with @debug.Debug::{to_repr}
