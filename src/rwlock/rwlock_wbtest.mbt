///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

///|
fn rwlock_test_reader(
  lock : RwLock,
  active : @atomic.AtomicInt,
  overlap : @atomic.AtomicInt,
  started : @atomic.AtomicInt,
  release : @atomic.AtomicInt,
) -> Unit raise {
  lock.with_read(fn() {
    if active.fetch_add(1) > 0 {
      ignore(overlap.fetch_add(1))
    }
    ignore(started.fetch_add(1))
    while release.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) == 0 {
      @thread.yield_now()
    }
    ignore(active.fetch_add(-1))
  })
}

///|
test "rwlock permits concurrent readers" {
  let lock = RwLock::new()
  let active = @atomic.AtomicInt::new(0)
  let overlap = @atomic.AtomicInt::new(0)
  let started = @atomic.AtomicInt::new(0)
  let release = @atomic.AtomicInt::new(0)
  let first_lock = lock.share()
  let first_active = active.share()
  let first_overlap = overlap.share()
  let first_started = started.share()
  let first_release = release.share()
  let first = @thread.spawn(fn() raise {
    rwlock_test_reader(
      first_lock, first_active, first_overlap, first_started, first_release,
    )
  })
  let second_lock = lock.share()
  let second_active = active.share()
  let second_overlap = overlap.share()
  let second_started = started.share()
  let second_release = release.share()
  let second = @thread.spawn(fn() raise {
    rwlock_test_reader(
      second_lock, second_active, second_overlap, second_started, second_release,
    )
  })
  for spin = 0
      spin < 100000 &&
     started.fetch_add(0, order=@atomic.MemoryOrdering::Acquire) < 2
      spin = spin + 1 {
    @thread.yield_now()
  }
  ignore(release.swap(1, order=@atomic.MemoryOrdering::Release))
  first.join()
  second.join()
  assert_true(overlap.fetch_add(0) > 0)
  assert_eq(active.load(), 0)
}

///|
fn rwlock_test_writer(
  lock : RwLock,
  active : @atomic.AtomicInt,
  violation : @atomic.AtomicInt,
) -> Unit raise {
  for iteration = 0; iteration < 500; iteration = iteration + 1 {
    lock.with_write(fn() {
      if active.fetch_add(1) != 0 {
        ignore(violation.fetch_add(1))
      }
      @thread.yield_now()
      ignore(active.fetch_add(-1))
    })
  }
}

///|
test "rwlock writers are exclusive" {
  let lock = RwLock::new()
  let active = @atomic.AtomicInt::new(0)
  let violation = @atomic.AtomicInt::new(0)
  let first_lock = lock.share()
  let first_active = active.share()
  let first_violation = violation.share()
  let first = @thread.spawn(fn() raise {
    rwlock_test_writer(first_lock, first_active, first_violation)
  })
  let second_lock = lock.share()
  let second_active = active.share()
  let second_violation = violation.share()
  let second = @thread.spawn(fn() raise {
    rwlock_test_writer(second_lock, second_active, second_violation)
  })
  let third_lock = lock.share()
  let third_active = active.share()
  let third_violation = violation.share()
  let third = @thread.spawn(fn() raise {
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
  let writer_started = @atomic.AtomicInt::new(0)
  let release_writer = @atomic.AtomicInt::new(0)
  let reader_attempting = @atomic.AtomicInt::new(0)
  let reader_entered = @atomic.AtomicInt::new(0)
  let writer_lock = lock.share()
  let worker_started = writer_started.share()
  let worker_release = release_writer.share()
  let writer = @thread.spawn(fn() raise {
    writer_lock.with_write(fn() {
      ignore(worker_started.fetch_add(1))
      while worker_release.fetch_add(0) == 0 {
        @thread.yield_now()
      }
    })
  })
  while writer_started.fetch_add(0) == 0 {
    @thread.yield_now()
  }
  let reader_lock = lock.share()
  let worker_attempting = reader_attempting.share()
  let worker_entered = reader_entered.share()
  let reader = @thread.spawn(fn() raise {
    ignore(worker_attempting.fetch_add(1))
    reader_lock.with_read(fn() { ignore(worker_entered.fetch_add(1)) })
  })
  while reader_attempting.fetch_add(0) == 0 {
    @thread.yield_now()
  }
  for spin = 0; spin < 10000; spin = spin + 1 {
    @thread.yield_now()
  }
  assert_eq(reader_entered.fetch_add(0), 0)
  ignore(release_writer.fetch_add(1))
  writer.join()
  reader.join()
  assert_eq(reader_entered.fetch_add(0), 1)
}
