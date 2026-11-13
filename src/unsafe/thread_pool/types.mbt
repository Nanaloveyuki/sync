///|
/// Result of a non-blocking thread-pool submission.
///
/// The submitted closure is consumed for every result variant.
#derive(Eq, Debug)
pub(all) enum TryExecuteResult {
  Submitted
  QueueFull
  PoolClosed
}

///|
#doc(hidden)
pub extend TryExecuteResult with Eq::{equal, not_equal}

///|
#doc(hidden)
pub extend TryExecuteResult with @debug.Debug::{to_repr}
