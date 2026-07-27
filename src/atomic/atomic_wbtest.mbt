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
    SyncError::InvalidMemoryOrdering(_) => ()
    _ => fail("unexpected error")
  }
  try {
    value.store(1, order=Acquire)
    fail("Acquire store should fail")
  } catch {
    SyncError::InvalidMemoryOrdering(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "atomic handle is shared across threads" {
  let counter = AtomicInt::new(0)
  let worker_counter = counter.share()
  let thread = @thread.spawn(fn() {
    for i = 0; i < 10000; i = i + 1 {
      ignore(worker_counter.fetch_add(1, order=Relaxed))
    }
  })
  thread.join()
  assert_eq(counter.load(), 10000)
}
