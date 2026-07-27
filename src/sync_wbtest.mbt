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
