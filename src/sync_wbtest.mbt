///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

///|
test "atomic bool operations" {
  let value = AtomicBool::new(false)
  assert_false(value.load(order=Relaxed))
  value.store(true, order=Release)
  assert_true(value.load(order=Acquire))
  assert_true(value.swap(false))
  let exchanged = value.compare_exchange(false, true)
  assert_true(exchanged.exchanged)
  assert_false(exchanged.observed)
}

///|
test "atomic int and uint operations" {
  let signed = AtomicInt::new(-2)
  assert_eq(signed.fetch_add(5, order=AcqRel), -2)
  assert_eq(signed.load(), 3)
  let signed_cas = signed.compare_exchange(3, 9)
  assert_true(signed_cas.exchanged)
  assert_eq(signed_cas.observed, 3)
  let unsigned = AtomicUInt::new(1U)
  assert_eq(unsigned.fetch_add(2U), 1U)
  assert_eq(unsigned.swap(10U), 3U)
  assert_eq(unsigned.load(), 10U)
}

///|
test "invalid memory ordering is rejected" {
  let value = AtomicInt::new(0)
  try {
    ignore(value.load(order=Release))
    fail("Release load should fail")
  } catch {
    InvalidMemoryOrdering(_) => ()
    _ => fail("unexpected error")
  }
  try {
    value.store(1, order=Acquire)
    fail("Acquire store should fail")
  } catch {
    InvalidMemoryOrdering(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread returns a value and has an id" {
  let parent_id = current_thread_id()
  let thread = spawn(fn() { (current_thread_id(), 42) })
  assert_true(thread.id() != 0UL)
  let (worker_id, value) = thread.join()
  assert_true(worker_id != parent_id)
  assert_eq(value, 42)
}

///|
test "thread transports raised errors" {
  let thread : Thread[Unit] = spawn(fn() raise { raise WorkerFailed })
  try {
    thread.join()
    fail("join should raise ThreadPanicked")
  } catch {
    ThreadPanicked(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "atomic handle is shared across threads" {
  let counter = AtomicInt::new(0)
  let worker_counter = counter.share()
  let thread = spawn(fn() {
    for i = 0; i < 10000; i = i + 1 {
      ignore(worker_counter.fetch_add(1, order=Relaxed))
    }
  })
  thread.join()
  assert_eq(counter.load(), 10000)
}

///|
test "mutex protects a generic value" {
  let value = Mutex::new(0)
  let worker_value = value.share()
  let thread = spawn(fn() {
    for i = 0; i < 2000; i = i + 1 {
      worker_value.with_lock(fn(cell) { cell.val += 1 })
    }
  })
  for i = 0; i < 2000; i = i + 1 {
    value.with_lock(fn(cell) { cell.val += 1 })
  }
  thread.join()
  let result = value.with_lock(fn(cell) { cell.val })
  assert_eq(result, 4000)
}

///|
test "condvar releases and reacquires mutex" {
  let ready = Mutex::new(false)
  let worker_ready = ready.share()
  let cond = Condvar::new()
  let worker_cond = cond.share()
  let thread = spawn(fn() {
    worker_ready.with_lock(fn(cell) {
      cell.val = true
      worker_cond.notify_one()
    })
  })
  ready.with_lock(fn(cell) {
    while !cell.val {
      cond.wait(ready)
    }
  })
  thread.join()
}

///|
test "once executes one initializer" {
  let once = Once::new()
  let count = AtomicInt::new(0)
  let once1 = once.share()
  let once2 = once.share()
  let count1 = count.share()
  let count2 = count.share()
  let first = spawn(() => once1.call_once(fn() { ignore(count1.fetch_add(1)) }))
  let second = spawn(() => once2.call_once(fn() { ignore(count2.fetch_add(1)) }))
  once.call_once(fn() { ignore(count.fetch_add(1)) })
  first.join()
  second.join()
  assert_eq(count.load(), 1)
}

///|
test "once is poisoned after initializer failure" {
  let once = Once::new()
  once.call_once(fn() raise { raise WorkerFailed }) catch {
    WorkerFailed => ()
    _ => fail("unexpected initializer error")
  }
  try {
    once.call_once(fn() {  })
    fail("poisoned once should fail")
  } catch {
    OncePoisoned => ()
    _ => fail("unexpected poison error")
  }
}

///|
test "wait group waits for workers" {
  let group = WaitGroup::new()
  group.add(2)
  let group1 = group.share()
  let group2 = group.share()
  let count = AtomicInt::new(0)
  let count1 = count.share()
  let count2 = count.share()
  let first = spawn(() => {
    ignore(count1.fetch_add(1))
    group1.done()
  })
  let second = spawn(() => {
    ignore(count2.fetch_add(1))
    group2.done()
  })
  group.wait()
  assert_eq(count.load(), 2)
  first.join()
  second.join()
}

///|
test "bounded channel reports full empty and closed" {
  let (sender, receiver) : (Sender[Int], Receiver[Int]) = bounded(1)
  assert_eq(sender.try_send(7), Sent)
  assert_eq(sender.try_send(8), Full(8))
  assert_eq(receiver.try_recv(), Received(7))
  assert_eq(receiver.try_recv(), Empty)
  sender.close()
  assert_eq(receiver.try_recv(), Closed)
  assert_eq(sender.try_send(9), Closed(9))
}

///|
test "bounded channel carries reference values" {
  let (sender, receiver) : (Sender[String], Receiver[String]) = bounded(2)
  assert_eq(sender.send("hello"), Ok(()))
  assert_eq(receiver.recv(), Some("hello"))
}

///|
test "bounded channel supports multiple producers" {
  let (sender, receiver) : (Sender[Int], Receiver[Int]) = bounded(8)
  let sender1 = sender.share()
  let sender2 = sender.share()
  let first = spawn(() => {
    for i = 0; i < 100; i = i + 1 {
      assert_eq(sender1.send(i), Ok(()))
    }
  })
  let second = spawn(() => {
    for i = 100; i < 200; i = i + 1 {
      assert_eq(sender2.send(i), Ok(()))
    }
  })
  let mut sum = 0
  for i = 0; i < 200; i = i + 1 {
    match receiver.recv() {
      Some(value) => sum += value
      None => fail("channel closed before all messages arrived")
    }
  }
  first.join()
  second.join()
  assert_eq(sum, 19900)
}

///|
fn rwlock_test_reader(
  lock : RwLock,
  active : AtomicInt,
  overlap : AtomicInt,
  started : AtomicInt,
  release : AtomicInt,
) -> Unit raise {
  lock.with_read(fn() {
    if active.fetch_add(1) > 0 {
      ignore(overlap.fetch_add(1))
    }
    ignore(started.fetch_add(1))
    while release.fetch_add(0, order=Acquire) == 0 {
      yield_now()
    }
    ignore(active.fetch_add(-1))
  })
}

///|
test "rwlock permits concurrent readers" {
  let lock = RwLock::new()
  let active = AtomicInt::new(0)
  let overlap = AtomicInt::new(0)
  let started = AtomicInt::new(0)
  let release = AtomicInt::new(0)
  let first_lock = lock.share()
  let first_active = active.share()
  let first_overlap = overlap.share()
  let first_started = started.share()
  let first_release = release.share()
  let first = spawn(fn() raise {
    rwlock_test_reader(
      first_lock, first_active, first_overlap, first_started, first_release,
    )
  })
  let second_lock = lock.share()
  let second_active = active.share()
  let second_overlap = overlap.share()
  let second_started = started.share()
  let second_release = release.share()
  let second = spawn(fn() raise {
    rwlock_test_reader(
      second_lock, second_active, second_overlap, second_started, second_release,
    )
  })
  for spin = 0
      spin < 100000 && started.fetch_add(0, order=Acquire) < 2
      spin = spin + 1 {
    yield_now()
  }
  ignore(release.swap(1, order=Release))
  first.join()
  second.join()
  assert_true(overlap.fetch_add(0) > 0)
  assert_eq(active.load(), 0)
}

///|
fn rwlock_test_writer(
  lock : RwLock,
  active : AtomicInt,
  violation : AtomicInt,
) -> Unit raise {
  for iteration = 0; iteration < 500; iteration = iteration + 1 {
    lock.with_write(fn() {
      if active.fetch_add(1) != 0 {
        ignore(violation.fetch_add(1))
      }
      yield_now()
      ignore(active.fetch_add(-1))
    })
  }
}

///|
test "rwlock writers are exclusive" {
  let lock = RwLock::new()
  let active = AtomicInt::new(0)
  let violation = AtomicInt::new(0)
  let first_lock = lock.share()
  let first_active = active.share()
  let first_violation = violation.share()
  let first = spawn(fn() raise {
    rwlock_test_writer(first_lock, first_active, first_violation)
  })
  let second_lock = lock.share()
  let second_active = active.share()
  let second_violation = violation.share()
  let second = spawn(fn() raise {
    rwlock_test_writer(second_lock, second_active, second_violation)
  })
  let third_lock = lock.share()
  let third_active = active.share()
  let third_violation = violation.share()
  let third = spawn(fn() raise {
    rwlock_test_writer(third_lock, third_active, third_violation)
  })
  first.join()
  second.join()
  third.join()
  assert_eq(violation.fetch_add(0), 0)
  assert_eq(active.load(), 0)
}

///|
test "rwlock unlocks when a callback raises" {
  let lock = RwLock::new()
  try {
    let _result : Unit = lock.with_write(fn() raise { raise WorkerFailed })
    fail("write callback should raise")
  } catch {
    WorkerFailed => ()
    _ => fail("unexpected error")
  }
  try {
    let _result : Unit = lock.with_read(fn() raise { raise WorkerFailed })
    fail("read callback should raise")
  } catch {
    WorkerFailed => ()
    _ => fail("unexpected error")
  }
  assert_eq(lock.with_read(fn() { 42 }), 42)
}

///|
test "rwlock writer excludes readers" {
  let lock = RwLock::new()
  let writer_started = AtomicInt::new(0)
  let release_writer = AtomicInt::new(0)
  let reader_attempting = AtomicInt::new(0)
  let reader_entered = AtomicInt::new(0)
  let writer_lock = lock.share()
  let worker_started = writer_started.share()
  let worker_release = release_writer.share()
  let writer = spawn(fn() raise {
    writer_lock.with_write(fn() {
      ignore(worker_started.fetch_add(1))
      while worker_release.fetch_add(0) == 0 {
        yield_now()
      }
    })
  })
  while writer_started.fetch_add(0) == 0 {
    yield_now()
  }
  let reader_lock = lock.share()
  let worker_attempting = reader_attempting.share()
  let worker_entered = reader_entered.share()
  let reader = spawn(fn() raise {
    ignore(worker_attempting.fetch_add(1))
    reader_lock.with_read(fn() { ignore(worker_entered.fetch_add(1)) })
  })
  while reader_attempting.fetch_add(0) == 0 {
    yield_now()
  }
  for spin = 0; spin < 10000; spin = spin + 1 {
    yield_now()
  }
  assert_eq(reader_entered.fetch_add(0), 0)
  ignore(release_writer.fetch_add(1))
  writer.join()
  reader.join()
  assert_eq(reader_entered.fetch_add(0), 1)
}

///|
fn pool_test_blocking_task(
  started : AtomicInt,
  release : AtomicInt,
  completed : AtomicInt,
) -> Unit {
  ignore(started.fetch_add(1))
  while release.fetch_add(0, order=Acquire) == 0 {
    yield_now()
  }
  ignore(completed.fetch_add(1))
}

///|
test "thread pool runs a fixed set of workers and drains on shutdown" {
  let pool = ThreadPool::new(4, 8)
  let started = AtomicInt::new(0)
  let release = AtomicInt::new(0)
  let completed = AtomicInt::new(0)
  for task_index = 0; task_index < 4; task_index = task_index + 1 {
    let task_started = started.share()
    let task_release = release.share()
    let task_completed = completed.share()
    pool.execute(fn() {
      pool_test_blocking_task(task_started, task_release, task_completed)
    })
  }
  for spin = 0
      spin < 100000 && started.fetch_add(0, order=Acquire) < 4
      spin = spin + 1 {
    yield_now()
  }
  assert_eq(started.fetch_add(0), 4)
  assert_eq(pool.worker_count(), 4)
  ignore(release.swap(1, order=Release))
  pool.shutdown()
  assert_eq(completed.load(), 4)
  assert_eq(pool.pending_count(), 0)
  assert_true(pool.is_closed())
  pool.shutdown()
}

///|
test "thread pool reports full and closed queues" {
  let pool = ThreadPool::new(1, 1)
  let started = AtomicInt::new(0)
  let release = AtomicInt::new(0)
  let worker_started = started.share()
  let worker_release = release.share()
  pool.execute(fn() {
    ignore(worker_started.swap(1, order=Release))
    while worker_release.fetch_add(0, order=Acquire) == 0 {
      yield_now()
    }
  })
  for spin = 0
      spin < 100000 && started.fetch_add(0, order=Acquire) == 0
      spin = spin + 1 {
    yield_now()
  }
  assert_eq(started.fetch_add(0), 1)
  assert_eq(pool.try_execute(fn() {  }), Submitted)
  assert_eq(pool.try_execute(fn() {  }), QueueFull)
  ignore(release.swap(1, order=Release))
  pool.close()
  pool.shutdown()
  assert_eq(pool.try_execute(fn() {  }), PoolClosed)
  try {
    pool.execute(fn() {  })
    fail("closed pool should reject tasks")
  } catch {
    ThreadPoolClosed => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread pool accepts concurrent producers" {
  let pool = ThreadPool::new(3, 16)
  let completed = AtomicInt::new(0)
  let first_pool = pool.share()
  let first_completed = completed.share()
  let first = spawn(fn() raise {
    for task_index = 0; task_index < 100; task_index = task_index + 1 {
      let counter = first_completed.share()
      first_pool.execute(fn() { ignore(counter.fetch_add(1)) })
    }
  })
  let second_pool = pool.share()
  let second_completed = completed.share()
  let second = spawn(fn() raise {
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
  let rejected = AtomicInt::new(0)
  let worker_rejected = rejected.share()
  pool.execute(fn() {
    worker_pool.shutdown() catch {
      ThreadPoolShutdownFromWorker => ignore(worker_rejected.fetch_add(1))
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
  let started = AtomicInt::new(0)
  let attempt = AtomicInt::new(0)
  let outcome = AtomicInt::new(0)
  let worker_started = started.share()
  let worker_attempt = attempt.share()
  let worker_outcome = outcome.share()
  pool.execute(fn() {
    ignore(worker_started.fetch_add(1))
    while worker_attempt.fetch_add(0) == 0 {
      yield_now()
    }
    try worker_pool.execute(fn() {  }) catch {
      ThreadPoolWouldDeadlock => ignore(worker_outcome.swap(1))
      _ => ignore(worker_outcome.swap(2))
    } noraise {
      _ => ignore(worker_outcome.swap(3))
    }
  })
  while started.fetch_add(0) == 0 {
    yield_now()
  }
  pool.execute(fn() {  })
  ignore(attempt.fetch_add(1))
  while outcome.fetch_add(0) == 0 {
    yield_now()
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
    InvalidWorkerCount(0) => ()
    _ => fail("unexpected error")
  }
  try {
    ignore(ThreadPool::new(1, 0))
    fail("zero queue capacity should fail")
  } catch {
    InvalidCapacity(0) => ()
    _ => fail("unexpected error")
  }
}

///|
fn launch_pool_without_shutdown(completed : AtomicInt) -> Unit raise SyncError {
  let pool = ThreadPool::new(2, 4)
  for task_index = 0; task_index < 4; task_index = task_index + 1 {
    let task_completed = completed.share()
    pool.execute(fn() { ignore(task_completed.fetch_add(1)) })
  }
}

///|
test "dropping the last pool handle closes and drains tasks" {
  let completed = AtomicInt::new(0)
  launch_pool_without_shutdown(completed.share())
  for spin = 0; spin < 100000 && completed.fetch_add(0) < 4; spin = spin + 1 {
    yield_now()
  }
  assert_eq(completed.fetch_add(0), 4)
}

///|
test "concurrent thread pool shutdown is idempotent" {
  let pool = ThreadPool::new(2, 2)
  let first_pool = pool.share()
  let second_pool = pool.share()
  let first = spawn(fn() raise { first_pool.shutdown() })
  let second = spawn(fn() raise { second_pool.shutdown() })
  first.join()
  second.join()
  assert_true(pool.is_closed())
  pool.shutdown()
}
