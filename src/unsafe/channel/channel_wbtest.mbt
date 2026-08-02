///|
extern "C" fn native_channel_test_fail_next_init(status : Int) -> Unit = "sync_channel_test_fail_next_init"

///|
extern "C" fn native_channel_test_fail_next_operation(status : Int) -> Unit = "sync_channel_test_fail_next_operation"

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
  let worker = @thread.spawn(() => assert_eq(sender.send("hello"), Ok(())))
  assert_eq(receiver.recv(), Some("hello"))
  worker.join()
}

///|
test "bounded channel supports multiple producers" {
  let (sender, receiver) : (Sender[Int], Receiver[Int]) = bounded(8)
  let sender1 = sender.share()
  let sender2 = sender.share()
  let first = @thread.spawn(() => {
    for i = 0; i < 100; i = i + 1 {
      assert_eq(sender1.send(i), Ok(()))
    }
  })
  let second = @thread.spawn(() => {
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

///|
test "bounded channel maps injected native failures" {
  native_channel_test_fail_next_init(345)
  try {
    let _ : (Sender[Int], Receiver[Int]) = bounded(1)
    fail("injected initialization failure should raise")
  } catch {
    SyncError::ChannelInitializationFailed(345) => ()
    _ => fail("unexpected error")
  }

  let (sender, _receiver) : (Sender[Int], Receiver[Int]) = try! bounded(1)
  native_channel_test_fail_next_operation(456)
  try {
    ignore(sender.try_send(1))
    fail("injected operation failure should raise")
  } catch {
    SyncError::ChannelOperationFailed(456) => ()
    _ => fail("unexpected error")
  }
}
