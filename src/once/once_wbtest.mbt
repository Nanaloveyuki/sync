///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

///|
extern "C" fn native_once_test_fail_next_init(status : Int) -> Unit = "sync_once_test_fail_next_init"

///|
extern "C" fn native_once_test_fail_next_begin(status : Int) -> Unit = "sync_once_test_fail_next_begin"

///|
test "once executes one initializer" {
  let once = Once::new()
  let count = @atomic.AtomicInt::new(0)
  let once1 = once.share()
  let once2 = once.share()
  let count1 = count.share()
  let count2 = count.share()
  let first = @thread.spawn(() => {
    once1.call_once(fn() { ignore(count1.fetch_add(1)) })
  })
  let second = @thread.spawn(() => {
    once2.call_once(fn() { ignore(count2.fetch_add(1)) })
  })
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
    SyncError::OncePoisoned => ()
    _ => fail("unexpected poison error")
  }
}

///|
test "once maps injected native failures and remains usable" {
  native_once_test_fail_next_init(123)
  try {
    ignore(Once::new())
    fail("injected initialization failure should raise")
  } catch {
    SyncError::OnceInitializationFailed(status) => assert_eq(status, 123)
    _ => fail("unexpected initialization error")
  }

  let once = Once::new()
  let called = Ref::Ref(false)
  native_once_test_fail_next_begin(234)
  try {
    once.call_once(fn() { called.val = true })
    fail("injected begin failure should raise")
  } catch {
    SyncError::OnceOperationFailed(status) => assert_eq(status, 234)
    _ => fail("unexpected operation error")
  }
  assert_false(called.val)
  once.call_once(fn() { called.val = true })
  assert_true(called.val)
}
