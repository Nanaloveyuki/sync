///|
priv enum OwnedBytesOperation {
  Send(Bytes)
  TryRecv
  CloseSender
  CloseReceiver
} derive(Debug)

///|
impl @quickcheck.Arbitrary for OwnedBytesOperation with fn arbitrary(size, rs) {
  match rs.next_uint() % 6U {
    0 | 1 | 2 => {
      let length = @quickcheck.int_range(0, 9).run(size, rs)
      Send(
        Bytes::makei(length, _ => @quickcheck.Arbitrary::arbitrary(size, rs)),
      )
    }
    3 => TryRecv
    4 => CloseSender
    _ => CloseReceiver
  }
}

///|
impl @shrink.Shrink for OwnedBytesOperation with fn shrink(operation) {
  match operation {
    Send(value) => @shrink.Shrink::shrink(value).map(value => Send(value))
    TryRecv | CloseSender | CloseReceiver => [||]
  }
}

///|
test "owned bytes channel follows count and byte budget models" {
  @quickcheck.check(
    (operations : Array[OwnedBytesOperation]) => {
      let capacity = 2
      let max_message_bytes = 4
      let max_queued_bytes = 7
      let (sender, receiver) = @channel.owned_bytes_bounded_with_limits(
        capacity,
        max_message_bytes~,
        max_queued_bytes~,
      )
      let model : Array[Bytes] = []
      let mut head = 0
      let mut queued_bytes = 0
      let mut closed = false
      guard receiver.capacity() == capacity else { return false }
      for operation in operations {
        match operation {
          Send(value) => {
            let length = value.length()
            let expected = if length > max_message_bytes {
              @channel.OwnedBytesTrySendResult::MessageTooLarge(
                length, max_message_bytes,
              )
            } else if closed {
              @channel.OwnedBytesTrySendResult::Closed
            } else if model.length() - head >= capacity {
              @channel.OwnedBytesTrySendResult::Full
            } else if queued_bytes + length > max_queued_bytes {
              @channel.OwnedBytesTrySendResult::QueueByteLimitReached(
                length, max_queued_bytes,
              )
            } else {
              model.push(value)
              queued_bytes += length
              @channel.OwnedBytesTrySendResult::Sent
            }
            guard sender.try_send(value) == expected else { return false }
            match expected {
              @channel.OwnedBytesTrySendResult::MessageTooLarge(actual, maximum) => {
                guard sender.send_checked(value) ==
                  @channel.OwnedBytesSendResult::MessageTooLarge(
                    actual, maximum,
                  ) else {
                  return false
                }
              }
              _ => ()
            }
          }
          TryRecv => {
            let expected = if head < model.length() {
              let value = model[head]
              head += 1
              queued_bytes -= value.length()
              @channel.OwnedBytesTryRecvResult::Received(value)
            } else if closed {
              @channel.OwnedBytesTryRecvResult::Closed
            } else {
              @channel.OwnedBytesTryRecvResult::Empty
            }
            guard receiver.try_recv() == expected else { return false }
          }
          CloseSender => {
            sender.close()
            closed = true
          }
          CloseReceiver => {
            receiver.close()
            closed = true
          }
        }
        guard receiver.length() == model.length() - head else { return false }
      }
      sender.close()
      receiver.close()
      while head < model.length() {
        let expected = model[head]
        head += 1
        queued_bytes -= expected.length()
        guard receiver.try_recv() ==
          @channel.OwnedBytesTryRecvResult::Received(expected) else {
          return false
        }
      }
      queued_bytes == 0 &&
      receiver.try_recv() == @channel.OwnedBytesTryRecvResult::Closed
    },
    count=160,
    max_size=56,
    max_shrinks=200,
    seed=20260828,
  )
}
