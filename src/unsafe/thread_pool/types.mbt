///|
/// Result of a non-blocking thread-pool submission.
///
/// The submitted closure is consumed for every result variant.
pub(all) enum TryExecuteResult {
  Submitted
  QueueFull
  PoolClosed
} derive(Eq, Debug)
