///|
priv type OwnedBytesSenderHandle

///|
priv type OwnedBytesReceiverHandle

///|
priv type RawBytes

///|
fn restore_bytes(value : RawBytes) -> Bytes = "%identity"

///|
#borrow(status)
extern "C" fn native_owned_bytes_channel_new(
  capacity : Int,
  max_message_bytes : Int,
  max_queued_bytes : Int,
  status : Ref[Int],
) -> OwnedBytesSenderHandle = "sync_owned_bytes_channel_new"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_channel_receiver(
  value : OwnedBytesSenderHandle,
  status : Ref[Int],
) -> OwnedBytesReceiverHandle = "sync_owned_bytes_channel_receiver"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_sender_share(
  value : OwnedBytesSenderHandle,
  status : Ref[Int],
) -> OwnedBytesSenderHandle = "sync_owned_bytes_sender_share"

///|
#borrow(value, message, status)
extern "C" fn native_owned_bytes_sender_try_send(
  value : OwnedBytesSenderHandle,
  message : Bytes,
  status : Ref[Int],
) -> Int = "sync_owned_bytes_sender_try_send"

///|
#borrow(value, message, status)
extern "C" fn native_owned_bytes_sender_send(
  value : OwnedBytesSenderHandle,
  message : Bytes,
  status : Ref[Int],
) -> Int = "sync_owned_bytes_sender_send"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_sender_close(
  value : OwnedBytesSenderHandle,
  status : Ref[Int],
) -> Unit = "sync_owned_bytes_sender_close"

///|
#borrow(value, status, error)
extern "C" fn native_owned_bytes_receiver_try_recv(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
  error : Ref[Int],
) -> RawBytes = "sync_owned_bytes_receiver_try_recv"

///|
#borrow(value, status, error)
extern "C" fn native_owned_bytes_receiver_recv(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
  error : Ref[Int],
) -> RawBytes = "sync_owned_bytes_receiver_recv"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_receiver_close(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
) -> Unit = "sync_owned_bytes_receiver_close"

///|
#borrow(value, status)
extern "C" fn native_owned_bytes_receiver_len(
  value : OwnedBytesReceiverHandle,
  status : Ref[Int],
) -> Int = "sync_owned_bytes_receiver_len"

///|
#borrow(value)
extern "C" fn native_owned_bytes_receiver_capacity(
  value : OwnedBytesReceiverHandle,
) -> Int = "sync_owned_bytes_receiver_capacity"
