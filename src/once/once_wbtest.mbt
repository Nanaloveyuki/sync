///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

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
