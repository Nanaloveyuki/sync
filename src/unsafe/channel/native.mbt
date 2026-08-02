///|
priv type RawBox

///|
fn[T] erase_box(value : Ref[T]) -> RawBox = "%identity"

///|
fn[T] restore_box(value : RawBox) -> Ref[T] = "%identity"

///|
#owned(value)
fn[T] box_value(value : T) -> RawBox {
  erase_box(Ref::Ref(value))
}

///|
fn[T] type_marker(value : T) -> T {
  value
}

///|
priv type SenderHandle

///|
priv type ReceiverHandle

///|
#borrow(status)
extern "C" fn native_channel_new(
  capacity : Int,
  status : Ref[Int],
) -> SenderHandle = "sync_channel_new"

///|
#borrow(value, status)
extern "C" fn native_channel_receiver(
  value : SenderHandle,
  status : Ref[Int],
) -> ReceiverHandle = "sync_channel_receiver"

///|
#borrow(value, status)
extern "C" fn native_sender_share(
  value : SenderHandle,
  status : Ref[Int],
) -> SenderHandle = "sync_sender_share"

///|
#borrow(value, result, status)
#owned(message)
extern "C" fn native_sender_try_send(
  value : SenderHandle,
  message : RawBox,
  result : Ref[Int],
  status : Ref[Int],
) -> RawBox = "sync_sender_try_send"

///|
#borrow(value, result, status)
#owned(message)
extern "C" fn native_sender_send(
  value : SenderHandle,
  message : RawBox,
  result : Ref[Int],
  status : Ref[Int],
) -> RawBox = "sync_sender_send"

///|
#borrow(value, status)
extern "C" fn native_sender_close(
  value : SenderHandle,
  status : Ref[Int],
) -> Unit = "sync_sender_close"

///|
#borrow(value, status, error)
extern "C" fn native_receiver_try_recv(
  value : ReceiverHandle,
  status : Ref[Int],
  error : Ref[Int],
) -> RawBox = "sync_receiver_try_recv"

///|
#borrow(value, status, error)
extern "C" fn native_receiver_recv(
  value : ReceiverHandle,
  status : Ref[Int],
  error : Ref[Int],
) -> RawBox = "sync_receiver_recv"

///|
#borrow(value, status)
extern "C" fn native_receiver_close(
  value : ReceiverHandle,
  status : Ref[Int],
) -> Unit = "sync_receiver_close"

///|
#borrow(value, status)
extern "C" fn native_receiver_len(
  value : ReceiverHandle,
  status : Ref[Int],
) -> Int = "sync_receiver_len"

///|
#borrow(value)
extern "C" fn native_receiver_capacity(value : ReceiverHandle) -> Int = "sync_receiver_capacity"
