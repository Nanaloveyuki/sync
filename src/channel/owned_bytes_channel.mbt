///|
/// A producer endpoint for an owned-bytes channel.
///
/// `send` copies the bytes into native-owned storage before it returns. The
/// channel never retains a MoonBit heap object from the sending thread.
pub struct OwnedBytesSender {
  priv handle : OwnedBytesSenderHandle
  priv max_message_bytes : Int
  priv max_queued_bytes : Int
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
/// Creates a bounded channel with a 4 MiB per-message and 16 MiB total queue
/// byte limit. Capacity must be greater than zero.
pub fn owned_bytes_bounded(
  capacity : Int,
) -> (OwnedBytesSender, OwnedBytesReceiver) raise SyncError {
  owned_bytes_bounded_with_limits(
    capacity,
    max_message_bytes=4 * 1024 * 1024,
    max_queued_bytes=16 * 1024 * 1024,
  )
}

///|
/// Creates a bounded channel with explicit byte limits.
///
/// `max_message_bytes` rejects oversized messages before copying. The channel
/// accepts at most `max_queued_bytes` of copied payloads at once, in addition
/// to its message-count capacity.
pub fn owned_bytes_bounded_with_limits(
  capacity : Int,
  max_message_bytes~ : Int,
  max_queued_bytes~ : Int,
) -> (OwnedBytesSender, OwnedBytesReceiver) raise SyncError {
  if capacity <= 0 {
    raise SyncError::InvalidCapacity(capacity)
  }
  if max_message_bytes <= 0 {
    raise SyncError::InvalidMessageSizeLimit(max_message_bytes)
  }
  if max_queued_bytes <= 0 {
    raise SyncError::InvalidQueuedByteLimit(max_queued_bytes)
  }
  if max_message_bytes > max_queued_bytes {
    raise SyncError::InvalidOwnedBytesLimits
  }
  let creation_status = Ref::Ref(0)
  let sender = native_owned_bytes_channel_new(
    capacity, max_message_bytes, max_queued_bytes, creation_status,
  )
  if creation_status.val != 0 {
    raise SyncError::ChannelInitializationFailed(creation_status.val)
  }
  let receiver_status = Ref::Ref(0)
  let receiver = native_owned_bytes_channel_receiver(sender, receiver_status)
  if receiver_status.val != 0 {
    raise SyncError::ChannelOperationFailed(receiver_status.val)
  }
  (
    { handle: sender, max_message_bytes, max_queued_bytes },
    { handle: receiver },
  )
}

///|
/// Creates an independent producer wrapper for a different OS thread.
pub fn OwnedBytesSender::share(
  self : OwnedBytesSender,
) -> OwnedBytesSender raise SyncError {
  let status = Ref::Ref(0)
  let handle = native_owned_bytes_sender_share(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  {
    handle,
    max_message_bytes: self.max_message_bytes,
    max_queued_bytes: self.max_queued_bytes,
  }
}

///|
/// Attempts to copy and enqueue bytes without blocking.
pub fn OwnedBytesSender::try_send(
  self : OwnedBytesSender,
  message : Bytes,
) -> OwnedBytesTrySendResult raise SyncError {
  let status = Ref::Ref(0)
  let result = native_owned_bytes_sender_try_send(self.handle, message, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  match result {
    0 => Sent
    1 => Full
    2 => Closed
    3 => MessageTooLarge(message.length(), self.max_message_bytes)
    _ => QueueByteLimitReached(message.length(), self.max_queued_bytes)
  }
}

///|
/// Blocks until bytes are copied into the queue or the channel closes.
///
/// Returns false when the channel closes or rejects an oversized message.
/// Use `send_checked` when the caller must distinguish these outcomes.
pub fn OwnedBytesSender::send(
  self : OwnedBytesSender,
  message : Bytes,
) -> Bool raise SyncError {
  match self.send_checked(message) {
    Sent => true
    _ => false
  }
}

///|
/// Blocks until bytes are copied into the queue, the channel closes, or the
/// message exceeds its configured byte limit.
pub fn OwnedBytesSender::send_checked(
  self : OwnedBytesSender,
  message : Bytes,
) -> OwnedBytesSendResult raise SyncError {
  let status = Ref::Ref(0)
  let result = native_owned_bytes_sender_send(self.handle, message, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  match result {
    0 => Sent
    3 => MessageTooLarge(message.length(), self.max_message_bytes)
    _ => Closed
  }
}

///|
/// Idempotently closes the channel and wakes blocked endpoints.
pub fn OwnedBytesSender::close(self : OwnedBytesSender) -> Unit raise SyncError {
  let status = Ref::Ref(0)
  native_owned_bytes_sender_close(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
}

///|
/// Attempts to receive without blocking.
pub fn OwnedBytesReceiver::try_recv(
  self : OwnedBytesReceiver,
) -> OwnedBytesTryRecvResult raise SyncError {
  let status = Ref::Ref(0)
  let error = Ref::Ref(0)
  let raw = native_owned_bytes_receiver_try_recv(self.handle, status, error)
  if error.val != 0 {
    raise SyncError::ChannelOperationFailed(error.val)
  }
  match status.val {
    0 => Received(restore_bytes(raw))
    1 => Empty
    _ => Closed
  }
}

///|
/// Blocks for a copied message, returning None after closure and queue drain.
pub fn OwnedBytesReceiver::recv(
  self : OwnedBytesReceiver,
) -> Bytes? raise SyncError {
  let status = Ref::Ref(0)
  let error = Ref::Ref(0)
  let raw = native_owned_bytes_receiver_recv(self.handle, status, error)
  if error.val != 0 {
    raise SyncError::ChannelOperationFailed(error.val)
  }
  if status.val == 0 {
    Some(restore_bytes(raw))
  } else {
    None
  }
}

///|
/// Idempotently closes the channel and wakes blocked endpoints.
pub fn OwnedBytesReceiver::close(
  self : OwnedBytesReceiver,
) -> Unit raise SyncError {
  let status = Ref::Ref(0)
  native_owned_bytes_receiver_close(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
}

///|
/// Returns the number of copied messages waiting to be received.
pub fn OwnedBytesReceiver::length(
  self : OwnedBytesReceiver,
) -> Int raise SyncError {
  let status = Ref::Ref(0)
  let length = native_owned_bytes_receiver_len(self.handle, status)
  if status.val != 0 {
    raise SyncError::ChannelOperationFailed(status.val)
  }
  length
}

///|
/// Returns the fixed message capacity.
pub fn OwnedBytesReceiver::capacity(self : OwnedBytesReceiver) -> Int {
  native_owned_bytes_receiver_capacity(self.handle)
}
