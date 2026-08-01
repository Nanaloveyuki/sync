///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

///|
extern "C" fn native_thread_test_fail_next_start(status : Int) -> Unit = "sync_thread_test_fail_next_start"

///|
extern "C" fn native_thread_test_fail_next_join(status : Int) -> Unit = "sync_thread_test_fail_next_join"

///|
extern "C" fn native_thread_test_fail_next_detach(status : Int) -> Unit = "sync_thread_test_fail_next_detach"

///|
test "thread returns a value and has an id" {
  let parent_id = current_thread_id()
  let thread = spawn_unchecked(fn() { (current_thread_id(), 42) })
  assert_true(thread.id() != 0UL)
  let (worker_id, value) = thread.join()
  assert_true(worker_id != parent_id)
  assert_eq(value, 42)
}

///|
test "thread transports raised errors" {
  let thread : UnsafeThread[Unit] = spawn_unchecked(fn() raise {
    raise WorkerFailed
  })
  try {
    thread.join()
    fail("join should raise ThreadPanicked")
  } catch {
    SyncError::ThreadPanicked(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread rejects double join" {
  let thread = spawn_unchecked(fn() { 7 })
  assert_eq(thread.join(), 7)
  try {
    ignore(thread.join())
    fail("second join should raise")
  } catch {
    SyncError::ThreadAlreadyJoined => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread maps injected creation failure" {
  native_thread_test_fail_next_start(123)
  try {
    ignore(spawn(fn() {  }))
    fail("injected creation failure should raise")
  } catch {
    SyncError::ThreadCreationFailed(123) => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread maps injected join failure and remains joinable" {
  let thread = spawn_unchecked(fn() { 11 })
  native_thread_test_fail_next_join(456)
  try {
    ignore(thread.join())
    fail("injected join failure should raise")
  } catch {
    SyncError::ThreadJoinFailed(456) => ()
    _ => fail("unexpected error")
  }
  assert_eq(thread.join(), 11)
}

///|
fn spawn_and_detach(
  group : @wait_group.WaitGroup,
  completed : @atomic.AtomicInt,
) -> Unit raise SyncError {
  let worker_group = group.share()
  let worker_completed = completed.share()
  let thread = spawn(fn() raise {
    ignore(worker_completed.fetch_add(1))
    worker_group.done()
  })
  thread.detach()
}

///|
test "detached thread continues after its handle drops" {
  let group = @wait_group.WaitGroup::new()
  let completed = @atomic.AtomicInt::new(0)
  try! group.add(1)
  try! spawn_and_detach(group, completed)
  group.wait()
  assert_eq(completed.load(), 1)
}

///|
test "threads complete repeated concurrent spawn and join" {
  let completed = @atomic.AtomicInt::new(0)
  let mut total = 0
  for _ in 0..<16 {
    let workers : Array[UnsafeThread[Int]] = []
    for index in 0..<32 {
      let worker_completed = completed.share()
      workers.push(
        try! spawn_unchecked(fn() {
          ignore(worker_completed.fetch_add(1))
          index
        }),
      )
    }
    for worker in workers {
      total += try! worker.join()
    }
  }
  assert_eq(total, 7_936)
  assert_eq(completed.load(), 512)
}

///|
test "detach rejects join and can be called after completion" {
  let thread = spawn(fn() {  })
  thread.detach()
  try {
    thread.join()
    fail("detached thread should not be joinable")
  } catch {
    SyncError::ThreadAlreadyDetached => ()
    _ => fail("unexpected error")
  }
}

///|
test "thread exposes completion state" {
  let started = @atomic.AtomicInt::new(0)
  let release = @atomic.AtomicInt::new(0)
  let worker_started = started.share()
  let worker_release = release.share()
  let thread = spawn(fn() raise {
    ignore(worker_started.swap(1, order=@atomic.MemoryOrdering::Release))
    while worker_release.load(order=@atomic.MemoryOrdering::Acquire) == 0 {
      yield_now()
    }
  })
  while started.load(order=@atomic.MemoryOrdering::Acquire) == 0 {
    yield_now()
  }
  assert_false(thread.is_finished())
  ignore(release.swap(1, order=@atomic.MemoryOrdering::Release))
  thread.join()
  assert_true(thread.is_finished())
}

///|
test "thread maps injected detach failure and remains joinable" {
  let thread = spawn(fn() {  })
  native_thread_test_fail_next_detach(789)
  try {
    thread.detach()
    fail("injected detach failure should raise")
  } catch {
    SyncError::ThreadDetachFailed(789) => ()
    _ => fail("unexpected error")
  }
  thread.join()
}
