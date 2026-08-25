///|
priv enum ChannelOperation {
  Send(Int)
  TryRecv
  CloseSender
  CloseReceiver
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ChannelOperation with fn arbitrary(size, rs) {
  match rs.next_uint() % 6U {
    0 | 1 | 2 => Send(@quickcheck.int_range(-32, 33).run(size, rs))
    3 => TryRecv
    4 => CloseSender
    _ => CloseReceiver
  }
}

///|
impl @shrink.Shrink for ChannelOperation with fn shrink(operation) {
  match operation {
    Send(value) => @shrink.Shrink::shrink(value).map(value => Send(value))
    TryRecv | CloseSender | CloseReceiver => [||]
  }
}

///|
test "bounded channel follows a queue model" {
  @quickcheck.check(
    (operations : Array[ChannelOperation]) => {
      let capacity = 1
      let (sender, receiver) : (@channel.Sender[Int], @channel.Receiver[Int]) = @channel.bounded(
        capacity,
      )
      let model : Array[Int] = []
      let mut head = 0
      let mut closed = false
      guard receiver.capacity() == capacity else { return false }
      for operation in operations {
        match operation {
          Send(value) => {
            let expected = if closed {
              @channel.TrySendResult::Closed(value)
            } else if model.length() - head >= capacity {
              @channel.TrySendResult::Full(value)
            } else {
              model.push(value)
              @channel.TrySendResult::Sent
            }
            guard sender.try_send(value) == expected else { return false }
          }
          TryRecv => {
            let expected = if head < model.length() {
              let value = model[head]
              head += 1
              @channel.TryRecvResult::Received(value)
            } else if closed {
              @channel.TryRecvResult::Closed
            } else {
              @channel.TryRecvResult::Empty
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
        guard receiver.try_recv() == @channel.TryRecvResult::Received(expected) else {
          return false
        }
      }
      receiver.try_recv() == @channel.TryRecvResult::Closed
    },
    count=160,
    max_size=56,
    max_shrinks=200,
    seed=20260827,
  )
}
