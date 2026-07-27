///|
/// A producer endpoint for an owned-bytes channel.
///
/// `send` copies the bytes into native-owned storage before it returns. The
/// channel never retains a MoonBit heap object from the sending thread.
pub struct OwnedBytesSender {
  priv handle : OwnedBytesSenderHandle
}

///|
/// A single-consumer endpoint for an owned-bytes channel.
///
/// Received values are newly allocated on the receiving thread. They do not
/// alias the `Bytes` value supplied by the sender.
pub struct OwnedBytesReceiver {
  priv handle : OwnedBytesReceiverHandle
}

///|
/// Creates a bounded channel that transfers copied `Bytes` values between OS
/// threads. Capacity must be greater than zero.
pub fn owned_bytes_bounded(
  capacity : Int,
) -> (OwnedBytesSender, OwnedBytesReceiver) raise SyncError {
  if capacity <= 0 {
    raise SyncError::InvalidCapacity(capacity)
  }
  let sender = native_owned_bytes_channel_new(capacity)
  let receiver = native_owned_bytes_channel_receiver(sender)
  ({ handle: sender }, { handle: receiver })
}

///|
/// Creates an independent producer wrapper for a different OS thread.
pub fn OwnedBytesSender::share(self : OwnedBytesSender) -> OwnedBytesSender {
  { handle: native_owned_bytes_sender_share(self.handle) }
}

///|
/// Attempts to copy and enqueue bytes without blocking.
pub fn OwnedBytesSender::try_send(
  self : OwnedBytesSender,
  message : Bytes,
) -> OwnedBytesTrySendResult {
  match native_owned_bytes_sender_try_send(self.handle, message) {
    0 => Sent
    1 => Full
    _ => Closed
  }
}

///|
/// Blocks until bytes are copied into the queue or the channel closes.
///
/// Returns false when the channel closed before it accepted the message.
pub fn OwnedBytesSender::send(self : OwnedBytesSender, message : Bytes) -> Bool {
  native_owned_bytes_sender_send(self.handle, message) == 0
}

///|
/// Idempotently closes the channel and wakes blocked endpoints.
pub fn OwnedBytesSender::close(self : OwnedBytesSender) -> Unit {
  native_owned_bytes_sender_close(self.handle)
}

///|
/// Attempts to receive without blocking.
pub fn OwnedBytesReceiver::try_recv(
  self : OwnedBytesReceiver,
) -> OwnedBytesTryRecvResult {
  let status = Ref::Ref(0)
  let raw = native_owned_bytes_receiver_try_recv(self.handle, status)
  match status.val {
    0 => Received(restore_bytes(raw))
    1 => Empty
    _ => Closed
  }
}

///|
/// Blocks for a copied message, returning None after closure and queue drain.
pub fn OwnedBytesReceiver::recv(self : OwnedBytesReceiver) -> Bytes? {
  let status = Ref::Ref(0)
  let raw = native_owned_bytes_receiver_recv(self.handle, status)
  if status.val == 0 {
    Some(restore_bytes(raw))
  } else {
    None
  }
}

///|
/// Idempotently closes the channel and wakes blocked endpoints.
pub fn OwnedBytesReceiver::close(self : OwnedBytesReceiver) -> Unit {
  native_owned_bytes_receiver_close(self.handle)
}

///|
/// Returns the number of copied messages waiting to be received.
pub fn OwnedBytesReceiver::length(self : OwnedBytesReceiver) -> Int {
  native_owned_bytes_receiver_len(self.handle)
}

///|
/// Returns the fixed message capacity.
pub fn OwnedBytesReceiver::capacity(self : OwnedBytesReceiver) -> Int {
  native_owned_bytes_receiver_capacity(self.handle)
}
