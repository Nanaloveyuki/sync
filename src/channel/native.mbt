///|
priv type OwnedBytesSenderHandle

///|
priv type OwnedBytesReceiverHandle

///|
priv type RawBytes

///|
fn restore_bytes(value : RawBytes) -> Bytes = "%identity"

///|
extern "C" fn native_owned_bytes_channel_new(
  capacity : Int,
  max_message_bytes : Int,
  max_queued_bytes : Int,
) -> OwnedBytesSenderHandle = "sync_owned_bytes_channel_new"

///|
#borrow(value)
extern "C" fn native_owned_bytes_channel_receiver(
  value : OwnedBytesSenderHandle,
) -> OwnedBytesReceiverHandle = "sync_owned_bytes_channel_receiver"

///|
#borrow(value)
extern "C" fn native_owned_bytes_sender_share(
  value : OwnedBytesSenderHandle,
) -> OwnedBytesSenderHandle = "sync_owned_bytes_sender_share"

///|
#borrow(value, message)
extern "C" fn native_owned_bytes_sender_try_send(
  value : OwnedBytesSenderHandle,
  message : Bytes,
) -> Int = "sync_owned_bytes_sender_try_send"

///|
#borrow(value, message)
extern "C" fn native_owned_bytes_sender_send(
  value : OwnedBytesSenderHandle,
  message : Bytes,
) -> Int = "sync_owned_bytes_sender_send"

///|
#borrow(value)
extern "C" fn native_owned_bytes_sender_close(
  value : OwnedBytesSenderHandle,
) -> Unit = "sync_owned_bytes_sender_close"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_receiver_try_recv(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
) -> RawBytes = "sync_owned_bytes_receiver_try_recv"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_receiver_recv(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
) -> RawBytes = "sync_owned_bytes_receiver_recv"

///|
#borrow(value)
extern "C" fn native_owned_bytes_receiver_close(
  value : OwnedBytesReceiverHandle,
) -> Unit = "sync_owned_bytes_receiver_close"

///|
#borrow(value)
extern "C" fn native_owned_bytes_receiver_len(
  value : OwnedBytesReceiverHandle,
) -> Int = "sync_owned_bytes_receiver_len"

///|
#borrow(value)
extern "C" fn native_owned_bytes_receiver_capacity(
  value : OwnedBytesReceiverHandle,
) -> Int = "sync_owned_bytes_receiver_capacity"
