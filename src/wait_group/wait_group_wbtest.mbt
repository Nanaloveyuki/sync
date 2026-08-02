///|
extern "C" fn native_wait_group_test_fail_next_init(status : Int) -> Unit = "sync_wait_group_test_fail_next_init"

///|
extern "C" fn native_wait_group_test_fail_next_add(status : Int) -> Unit = "sync_wait_group_test_fail_next_add"

///|
extern "C" fn native_wait_group_test_fail_next_wait(status : Int) -> Unit = "sync_wait_group_test_fail_next_wait"

///|
test "wait group waits for workers" {
  let group = WaitGroup::new()
  group.add(2)
  let group1 = group.share()
  let group2 = group.share()
  let count = @atomic.AtomicInt::new(0)
  let count1 = count.share()
  let count2 = count.share()
  let first = @thread.spawn(() => {
    ignore(count1.fetch_add(1))
    group1.done()
  })
  let second = @thread.spawn(() => {
    ignore(count2.fetch_add(1))
    group2.done()
  })
  group.wait()
  assert_eq(count.load(), 2)
  first.join()
  second.join()
}

///|
test "wait group rejects count overflow" {
  let group = WaitGroup::new()
  try! group.add(2_147_483_647)
  try {
    group.add(1)
    fail("overflow should raise")
  } catch {
    SyncError::InvalidWaitGroupCount => ()
    _ => fail("unexpected error")
  }
}

///|
test "wait group maps injected native failures and remains usable" {
  native_wait_group_test_fail_next_init(345)
  try {
    ignore(WaitGroup::new())
    fail("injected initialization failure should raise")
  } catch {
    SyncError::WaitGroupInitializationFailed(status) => assert_eq(status, 345)
    _ => fail("unexpected initialization error")
  }

  let group = WaitGroup::new()
  native_wait_group_test_fail_next_add(456)
  try {
    group.add(1)
    fail("injected add failure should raise")
  } catch {
    SyncError::WaitGroupOperationFailed(status) => assert_eq(status, 456)
    _ => fail("unexpected add error")
  }
  group.add(1)
  native_wait_group_test_fail_next_wait(567)
  try {
    group.wait()
    fail("injected wait failure should raise")
  } catch {
    SyncError::WaitGroupOperationFailed(status) => assert_eq(status, 567)
    _ => fail("unexpected wait error")
  }
  group.done()
  group.wait()
}
