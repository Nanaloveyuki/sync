///|
test "channel package links independently" {
  let (sender, receiver) : (@channel.Sender[Int32], @channel.Receiver[Int32]) = @channel.bounded(
    1,
  )
  assert_eq(sender.try_send(42), @channel.TrySendResult::Sent)
  assert_eq(receiver.try_recv(), @channel.TryRecvResult::Received(42))
}
