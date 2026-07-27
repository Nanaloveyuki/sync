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
/// The result of a non-blocking owned-bytes send.
pub(all) enum OwnedBytesTrySendResult {
  Sent
  Full
  Closed
} derive(Eq, Debug)

///|
/// The result of a non-blocking owned-bytes receive.
pub(all) enum OwnedBytesTryRecvResult {
  Received(Bytes)
  Empty
  Closed
} derive(Eq, Debug)
