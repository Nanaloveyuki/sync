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

///|
test "owned bytes channel rejects an oversized message before copying" {
  let (sender, receiver) = owned_bytes_bounded_with_limits(
    2,
    max_message_bytes=4,
    max_queued_bytes=8,
  )
  assert_eq(sender.try_send(b"oversized"), MessageTooLarge(9, 4))
  assert_eq(sender.send_checked(b"oversized"), MessageTooLarge(9, 4))
  assert_eq(sender.try_send(b"safe"), Sent)
  assert_eq(receiver.try_recv(), Received(b"safe"))
}

///|
test "owned bytes channel enforces its queued byte limit" {
  let (sender, receiver) = owned_bytes_bounded_with_limits(
    4,
    max_message_bytes=8,
    max_queued_bytes=10,
  )
  assert_eq(sender.try_send(b"123456"), Sent)
  assert_eq(sender.try_send(b"78901"), QueueByteLimitReached(5, 10))
  assert_eq(receiver.recv(), Some(b"123456"))
  assert_eq(sender.try_send(b"78901"), Sent)
  assert_eq(receiver.try_recv(), Received(b"78901"))
}

///|
test "owned bytes channel blocking send waits for byte capacity" {
  let (sender, receiver) = owned_bytes_bounded_with_limits(
    2,
    max_message_bytes=8,
    max_queued_bytes=10,
  )
  assert_true(sender.send(b"123456"))
  let worker_sender = sender.share()
  let worker = @thread.spawn(fn() { worker_sender.send_checked(b"78901") })
  assert_eq(receiver.recv(), Some(b"123456"))
  assert_eq(worker.join(), OwnedBytesSendResult::Sent)
  assert_eq(receiver.try_recv(), Received(b"78901"))
}

///|
test "owned bytes channel validates byte limits" {
  try {
    ignore(
      owned_bytes_bounded_with_limits(
        1,
        max_message_bytes=0,
        max_queued_bytes=1,
      ),
    )
    fail("zero message limit should raise")
  } catch {
    SyncError::InvalidMessageSizeLimit(0) => ()
    _ => fail("unexpected error")
  }
  try {
    ignore(
      owned_bytes_bounded_with_limits(
        1,
        max_message_bytes=1,
        max_queued_bytes=0,
      ),
    )
    fail("zero queue limit should raise")
  } catch {
    SyncError::InvalidQueuedByteLimit(0) => ()
    _ => fail("unexpected error")
  }
  try {
    ignore(
      owned_bytes_bounded_with_limits(
        1,
        max_message_bytes=2,
        max_queued_bytes=1,
      ),
    )
    fail("message limit above queue limit should raise")
  } catch {
    SyncError::InvalidOwnedBytesLimits => ()
    _ => fail("unexpected error")
  }
}
