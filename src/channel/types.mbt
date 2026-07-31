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
/// The result of a blocking owned-bytes send.
pub(all) enum OwnedBytesSendResult {
  Sent
  MessageTooLarge(Int, Int)
  Closed
} derive(Eq, Debug)

///|
/// The result of a non-blocking owned-bytes receive.
pub(all) enum OwnedBytesTryRecvResult {
  Received(Bytes)
  Empty
  Closed
} derive(Eq, Debug)
