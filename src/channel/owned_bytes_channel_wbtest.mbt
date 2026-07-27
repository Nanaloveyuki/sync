///|
test "owned bytes channel copies and drains messages" {
  let (sender, receiver) = owned_bytes_bounded(2)
  assert_eq(sender.try_send(b"first"), Sent)
  assert_true(sender.send(b"second"))
  sender.close()
  assert_eq(receiver.try_recv(), Received(b"first"))
  assert_eq(receiver.recv(), Some(b"second"))
  assert_eq(receiver.try_recv(), Closed)
}

///|
test "owned bytes channel transfers copied bytes from a worker" {
  let (sender, receiver) = owned_bytes_bounded(1)
  let worker_sender = sender.share()
  let worker = @thread.spawn(fn() { worker_sender.send(b"worker payload") })
  assert_eq(receiver.recv(), Some(b"worker payload"))
  assert_true(worker.join())
}

///|
test "owned bytes channel close wakes a blocked sender" {
  let (sender, receiver) = owned_bytes_bounded(1)
  assert_true(sender.send(b"queued"))
  let worker_sender = sender.share()
  let worker = @thread.spawn(fn() { worker_sender.send(b"blocked") })
  receiver.close()
  assert_false(worker.join())
}

///|
test "owned bytes channel validates capacity" {
  try {
    ignore(owned_bytes_bounded(0))
    fail("zero capacity should raise")
  } catch {
    SyncError::InvalidCapacity(0) => ()
    _ => fail("unexpected error")
  }
}
