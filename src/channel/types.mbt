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
