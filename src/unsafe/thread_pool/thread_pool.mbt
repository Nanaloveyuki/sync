///|
/// Creates a fixed-size native thread pool with a bounded FIFO task queue.
///
/// Tasks must not raise; catch fallible work inside the task before submission.
/// Captured native handles must be created with their `share()` method;
/// ordinary aliased MoonBit objects are not safe to capture.
pub fn ThreadPool::new(
  worker_count : Int,
  queue_capacity : Int,
) -> ThreadPool raise SyncError {
  if worker_count <= 0 {
    raise SyncError::InvalidWorkerCount(worker_count)
  }
  if queue_capacity <= 0 {
    raise SyncError::InvalidCapacity(queue_capacity)
  }
  let status = Ref::Ref(0)
  let pool = native_thread_pool_new(
    worker_count,
    queue_capacity,
    fn(callback) { callback() },
    status,
  )
  if status.val != 0 {
    raise SyncError::ThreadPoolCreationFailed(status.val)
  }
  pool
}

///|
/// Creates an independent producer wrapper for another OS thread.
pub fn ThreadPool::share(self : ThreadPool) -> ThreadPool {
  native_thread_pool_share(self)
}

///|
/// Attempts to enqueue a task without blocking.
///
/// The closure is consumed whether submission succeeds or fails.
pub fn ThreadPool::try_execute(
  self : ThreadPool,
  task : () -> Unit,
) -> TryExecuteResult {
  match native_thread_pool_try_execute(self, task) {
    0 => Submitted
    1 => QueueFull
    _ => PoolClosed
  }
}

///|
/// Blocks until the task is queued or the pool closes.
///
/// The closure is consumed in both cases.
/// Calling this from one of the same pool's workers is rejected when the queue
/// is full, because waiting there could deadlock every worker.
pub fn ThreadPool::execute(
  self : ThreadPool,
  task : () -> Unit,
) -> Unit raise SyncError {
  match native_thread_pool_execute(self, task) {
    0 => ()
    3 => raise SyncError::ThreadPoolWouldDeadlock
    _ => raise SyncError::ThreadPoolClosed
  }
}

///|
/// Stops accepting tasks. Already queued tasks are still executed.
pub fn ThreadPool::close(self : ThreadPool) -> Unit {
  native_thread_pool_close(self)
}

///|
/// Closes the pool and waits until queued and running tasks finish.
///
/// Calling this method from one of this pool's workers raises instead of
/// deadlocking. It is safe to call repeatedly from external threads.
pub fn ThreadPool::shutdown(self : ThreadPool) -> Unit raise SyncError {
  if native_thread_pool_shutdown(self) != 0 {
    raise SyncError::ThreadPoolShutdownFromWorker
  }
}

///|
pub fn ThreadPool::is_closed(self : ThreadPool) -> Bool {
  native_thread_pool_is_closed(self)
}

///|
pub fn ThreadPool::worker_count(self : ThreadPool) -> Int {
  native_thread_pool_worker_count(self)
}

///|
pub fn ThreadPool::pending_count(self : ThreadPool) -> Int {
  native_thread_pool_pending_count(self)
}
