///|
fn pool_test_blocking_task(
  started : @atomic.AtomicInt,
  release : @atomic.AtomicInt,
  completed : @atomic.AtomicInt,
) -> Unit {
  ignore(started.fetch_add(1))
  while release.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) == 0 {
    @thread.yield_now()
  }
  ignore(completed.fetch_add(1))
}

///|
extern "C" fn native_thread_pool_test_fail_alloc_after(
  successful_allocations : Int,
) -> Unit = "sync_thread_pool_test_fail_alloc_after"

///|
test "thread pool runs a fixed set of workers and drains on shutdown" {
  let pool = ThreadPool::new(4, 8)
  let started = @atomic.AtomicInt::new(0)
  let release = @atomic.AtomicInt::new(0)
  let completed = @atomic.AtomicInt::new(0)
  for task_index = 0; task_index < 4; task_index = task_index + 1 {
    let task_started = started.share()
    let task_release = release.share()
    let task_completed = completed.share()
    pool.execute(fn() {
      pool_test_blocking_task(task_started, task_release, task_completed)
    })
  }
  for spin = 0
      spin < 100000 &&
     started.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) < 4
      spin = spin + 1 {
    @thread.yield_now()
  }
  assert_eq(started.fetch_add(0), 4)
  assert_eq(pool.worker_count(), 4)
  ignore(release.swap(1, order=@atomic.MemoryOrdering::Release))
  pool.shutdown()
  assert_eq(completed.load(), 4)
  assert_eq(pool.pending_count(), 0)
  assert_true(pool.is_closed())
  pool.shutdown()
}

///|
test "thread pool reports full and closed queues" {
  let pool = ThreadPool::new(1, 1)
  let started = @atomic.AtomicInt::new(0)
  let release = @atomic.AtomicInt::new(0)
  let worker_started = started.share()
  let worker_release = release.share()
  pool.execute(fn() {
    ignore(worker_started.swap(1, order=@atomic.MemoryOrdering::Release))
    while worker_release.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) ==
          0 {
      @thread.yield_now()
    }
  })
  for spin = 0
      spin < 100000 &&
     started.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) == 0
      spin = spin + 1 {
    @thread.yield_now()
  }
  assert_eq(started.fetch_add(0), 1)
  assert_eq(pool.try_execute(fn() {  }), Submitted)
  assert_eq(pool.try_execute(fn() {  }), QueueFull)
  ignore(release.swap(1, order=@atomic.MemoryOrdering::Release))
  pool.close()
  pool.shutdown()
  assert_eq(pool.try_execute(fn() {  }), PoolClosed)
  try {
    pool.execute(fn() {  })
    fail("closed pool should reject tasks")
  } catch {
    SyncError::ThreadPoolClosed => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread pool accepts concurrent producers" {
  let pool = ThreadPool::new(3, 16)
  let completed = @atomic.AtomicInt::new(0)
  let first_pool = pool.share()
  let first_completed = completed.share()
  let first = @thread.spawn(fn() raise {
    for task_index = 0; task_index < 100; task_index = task_index + 1 {
      let counter = first_completed.share()
      first_pool.execute(fn() { ignore(counter.fetch_add(1)) })
    }
  })
  let second_pool = pool.share()
  let second_completed = completed.share()
  let second = @thread.spawn(fn() raise {
    for task_index = 0; task_index < 100; task_index = task_index + 1 {
      let counter = second_completed.share()
      second_pool.execute(fn() { ignore(counter.fetch_add(1)) })
    }
  })
  first.join()
  second.join()
  pool.shutdown()
  assert_eq(completed.load(), 200)
}

///|
test "thread pool rejects self shutdown without losing the worker" {
  let pool = ThreadPool::new(1, 1)
  let worker_pool = pool.share()
  let rejected = @atomic.AtomicInt::new(0)
  let worker_rejected = rejected.share()
  pool.execute(fn() {
    worker_pool.shutdown() catch {
      SyncError::ThreadPoolShutdownFromWorker =>
        ignore(worker_rejected.fetch_add(1))
      _ => ()
    }
  })
  pool.shutdown()
  assert_eq(rejected.fetch_add(0), 1)
}

///|
test "thread pool rejects a blocking self submit when full" {
  let pool = ThreadPool::new(1, 1)
  let worker_pool = pool.share()
  let started = @atomic.AtomicInt::new(0)
  let attempt = @atomic.AtomicInt::new(0)
  let outcome = @atomic.AtomicInt::new(0)
  let worker_started = started.share()
  let worker_attempt = attempt.share()
  let worker_outcome = outcome.share()
  pool.execute(fn() {
    ignore(worker_started.fetch_add(1))
    while worker_attempt.fetch_add(0) == 0 {
      @thread.yield_now()
    }
    try worker_pool.execute(fn() {  }) catch {
      SyncError::ThreadPoolWouldDeadlock => ignore(worker_outcome.swap(1))
      _ => ignore(worker_outcome.swap(2))
    } noraise {
      _ => ignore(worker_outcome.swap(3))
    }
  })
  while started.fetch_add(0) == 0 {
    @thread.yield_now()
  }
  pool.execute(fn() {  })
  ignore(attempt.fetch_add(1))
  while outcome.fetch_add(0) == 0 {
    @thread.yield_now()
  }
  pool.shutdown()
  assert_eq(outcome.fetch_add(0), 1)
}

///|
test "thread pool validates its configuration" {
  try {
    ignore(ThreadPool::new(0, 1))
    fail("zero workers should fail")
  } catch {
    SyncError::InvalidWorkerCount(0) => ()
    _ => fail("unexpected error")
  }
  try {
    ignore(ThreadPool::new(1, 0))
    fail("zero queue capacity should fail")
  } catch {
    SyncError::InvalidCapacity(0) => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread pool rejects sizes above its native resource limits" {
  try {
    ignore(ThreadPool::new(max_worker_count + 1, 1))
    fail("worker limit should fail")
  } catch {
    SyncError::InvalidWorkerCount(count) =>
      assert_eq(count, max_worker_count + 1)
    _ => fail("unexpected worker limit error")
  }
  try {
    ignore(ThreadPool::new(1, max_queue_capacity + 1))
    fail("queue limit should fail")
  } catch {
    SyncError::InvalidCapacity(capacity) =>
      assert_eq(capacity, max_queue_capacity + 1)
    _ => fail("unexpected queue limit error")
  }
}

///|
test "thread pool reports allocation failures" {
  native_thread_pool_test_fail_alloc_after(0)
  try {
    ignore(ThreadPool::new(1, 1))
    fail("core allocation failure should be reported")
  } catch {
    SyncError::ThreadPoolCreationFailed(status) => assert_eq(status, -2)
    _ => fail("unexpected core allocation error")
  }

  native_thread_pool_test_fail_alloc_after(1)
  try {
    ignore(ThreadPool::new(1, 1))
    fail("queue allocation failure should be reported")
  } catch {
    SyncError::ThreadPoolCreationFailed(status) => assert_eq(status, -2)
    _ => fail("unexpected queue allocation error")
  }
}

///|
fn launch_pool_without_shutdown(
  completed : @atomic.AtomicInt,
) -> Unit raise SyncError {
  let pool = ThreadPool::new(2, 4)
  for task_index = 0; task_index < 4; task_index = task_index + 1 {
    let task_completed = completed.share()
    pool.execute(fn() { ignore(task_completed.fetch_add(1)) })
  }
}

///|
test "dropping the last pool handle closes and drains tasks" {
  let completed = @atomic.AtomicInt::new(0)
  launch_pool_without_shutdown(completed.share())
  for spin = 0; spin < 100000 && completed.fetch_add(0) < 4; spin = spin + 1 {
    @thread.yield_now()
  }
  assert_eq(completed.fetch_add(0), 4)
}

///|
test "concurrent thread pool shutdown is idempotent" {
  let pool = ThreadPool::new(2, 2)
  let first_pool = pool.share()
  let second_pool = pool.share()
  let first = @thread.spawn(fn() raise { first_pool.shutdown() })
  let second = @thread.spawn(fn() raise { second_pool.shutdown() })
  first.join()
  second.join()
  assert_true(pool.is_closed())
  pool.shutdown()
}
