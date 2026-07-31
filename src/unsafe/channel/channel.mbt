///|
/// The producer side of a bounded MPSC channel.
///
/// This generic channel retains the submitted MoonBit value. Use it only when
/// its payload is not aliased across OS threads. For serialized IPC work, use
/// `owned_bytes_bounded`, which copies payloads through native-owned storage.
pub struct Sender[T] {
  priv handle : SenderHandle
  priv marker : (T) -> T
}

///|
/// The single-consumer side of a bounded MPSC channel.
pub struct Receiver[T] {
  priv handle : ReceiverHandle
  priv marker : (T) -> T
}

///|
/// Creates a bounded MPSC channel. Capacity must be greater than zero.
///
/// Dropping the final sender closes the channel. Closing or dropping either
/// endpoint wakes blocked senders and receivers.
pub fn[T] bounded(capacity : Int) -> (Sender[T], Receiver[T]) raise SyncError {
  if capacity <= 0 {
    raise SyncError::InvalidCapacity(capacity)
  }
  let creation_status = Ref::Ref(0)
  let sender = native_channel_new(capacity, creation_status)
  if creation_status.val != 0 {
    raise SyncError::ChannelInitializationFailed(creation_status.val)
  }
  let receiver_status = Ref::Ref(0)
  let receiver = native_channel_receiver(sender, receiver_status)
  if receiver_status.val != 0 {
    raise SyncError::ChannelOperationFailed(receiver_status.val)
  }
  (
    { handle: sender, marker: type_marker },
    { handle: receiver, marker: type_marker },
  )
}

///|
/// Creates another independent producer wrapper for a different thread.
pub fn[T] Sender::share(self : Sender[T]) -> Sender[T] raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  let handle = native_sender_share(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  { handle, marker: type_marker }
}

///|
/// Attempts to enqueue without blocking and returns ownership on failure.
pub fn[T] Sender::try_send(
  self : Sender[T],
  value : T,
) -> TrySendResult[T] raise SyncError {
  ignore(self.marker)
  let raw = box_value(value)
  let status = Ref::Ref(0)
  let result = native_sender_try_send(self.handle, raw, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  match result {
    0 => Sent
    1 => {
      let cell : Ref[T] = restore_box(raw)
      Full(cell.val)
    }
    _ => {
      let cell : Ref[T] = restore_box(raw)
      Closed(cell.val)
    }
  }
}

///|
/// Blocks until space is available or the channel closes.
pub fn[T] Sender::send(
  self : Sender[T],
  value : T,
) -> Result[Unit, T] raise SyncError {
  ignore(self.marker)
  let raw = box_value(value)
  let status = Ref::Ref(0)
  let result = native_sender_send(self.handle, raw, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  if result == 0 {
    Ok(())
  } else {
    let cell : Ref[T] = restore_box(raw)
    Err(cell.val)
  }
}

///|
pub fn[T] Sender::close(self : Sender[T]) -> Unit raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  native_sender_close(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
}

///|
/// Attempts to receive without blocking.
pub fn[T] Receiver::try_recv(
  self : Receiver[T],
) -> TryRecvResult[T] raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  let error = Ref::Ref(0)
  let raw = native_receiver_try_recv(self.handle, status, error)
  if error.val != 0 {
    raise SyncError::ChannelOperationFailed(error.val)
  }
  match status.val {
    0 => {
      let cell : Ref[T] = restore_box(raw)
      Received(cell.val)
    }
    1 => Empty
    _ => Closed
  }
}

///|
/// Blocks until a message arrives, returning None after closure and drain.
pub fn[T] Receiver::recv(self : Receiver[T]) -> T? raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  let error = Ref::Ref(0)
  let raw = native_receiver_recv(self.handle, status, error)
  if error.val != 0 {
    raise SyncError::ChannelOperationFailed(error.val)
  }
  if status.val == 0 {
    let cell : Ref[T] = restore_box(raw)
    Some(cell.val)
  } else {
    None
  }
}

///|
pub fn[T] Receiver::close(self : Receiver[T]) -> Unit raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  native_receiver_close(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
}

///|
pub fn[T] Receiver::length(self : Receiver[T]) -> Int raise SyncError {
  ignore(self.marker)
  let status = Ref::Ref(0)
  let length = native_receiver_len(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  length
}

///|
pub fn[T] Receiver::capacity(self : Receiver[T]) -> Int {
  ignore(self.marker)
  native_receiver_capacity(self.handle)
}
