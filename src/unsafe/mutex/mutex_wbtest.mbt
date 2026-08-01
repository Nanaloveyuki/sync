///|
extern "C" fn native_mutex_test_fail_next_init(status : Int) -> Unit = "sync_mutex_test_fail_next_init"

///|
extern "C" fn native_condvar_test_fail_next_init(status : Int) -> Unit = "sync_condvar_test_fail_next_init"

///|
extern "C" fn native_condvar_test_fail_next_notify(status : Int) -> Unit = "sync_condvar_test_fail_next_notify"

///|
test "mutex protects a generic value" {
  let value = try! Mutex::new(0)
  let worker_value = value.share()
  let thread = @thread.spawn(fn() raise {
    for i = 0; i < 2000; i = i + 1 {
      worker_value.with_lock(fn(lock_guard) {
        lock_guard.with_value(fn(cell) { cell.val += 1 })
      })
    }
  })
  for i = 0; i < 2000; i = i + 1 {
    value.with_lock(fn(lock_guard) {
      lock_guard.with_value(fn(cell) { cell.val += 1 })
    })
  }
  thread.join()
  let result = value.with_lock(fn(lock_guard) {
    lock_guard.with_value(fn(cell) { cell.val })
  })
  assert_eq(result, 4000)
}

///|
test "mutex maps injected initialization failure" {
  native_mutex_test_fail_next_init(123)
  try {
    ignore(Mutex::new(()))
    fail("injected initialization failure should raise")
  } catch {
    SyncError::MutexInitializationFailed(123) => ()
    _ => fail("unexpected error")
  }
}

///|
test "condvar maps injected initialization and notify failures" {
  native_condvar_test_fail_next_init(234)
  try {
    ignore(Condvar::new())
    fail("injected initialization failure should raise")
  } catch {
    SyncError::CondvarInitializationFailed(234) => ()
    _ => fail("unexpected error")
  }

  let condvar = try! Condvar::new()
  native_condvar_test_fail_next_notify(345)
  try {
    condvar.notify_one()
    fail("injected notify failure should raise")
  } catch {
    SyncError::CondvarOperationFailed(345) => ()
    _ => fail("unexpected error")
  }
}

///|
test "condvar releases and reacquires mutex" {
  let ready = try! Mutex::new(false)
  let worker_ready = ready.share()
  let cond = try! Condvar::new()
  let worker_cond = cond.share()
  let thread = @thread.spawn(fn() raise {
    worker_ready.with_lock(fn(lock_guard) raise {
      lock_guard.with_value(fn(cell) { cell.val = true })
      worker_cond.notify_one()
    })
  })
  try! ready.with_lock(fn(lock_guard) raise {
    while !lock_guard.with_value(fn(cell) { cell.val }) {
      cond.wait(lock_guard)
    }
  })
  thread.join()
}

///|
test "unchecked condvar wait rejects an unlocked mutex" {
  let mutex = try! Mutex::new(())
  let condvar = try! Condvar::new()
  try {
    condvar_wait_unchecked(condvar, mutex)
    fail("unlocked wait should raise")
  } catch {
    SyncError::CondvarOperationFailed(-1) => ()
    _ => fail("unexpected error")
  }
}
