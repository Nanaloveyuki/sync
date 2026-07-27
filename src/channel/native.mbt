///|
priv type RawBox

///|
fn[T] erase_box(value : Ref[T]) -> RawBox = "%identity"

///|
fn[T] restore_box(value : RawBox) -> Ref[T] = "%identity"

///|
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
extern "C" fn native_channel_new(capacity : Int) -> SenderHandle = "sync_channel_new"

///|
#borrow(value)
extern "C" fn native_channel_receiver(value : SenderHandle) -> ReceiverHandle = "sync_channel_receiver"

///|
#borrow(value)
extern "C" fn native_sender_share(value : SenderHandle) -> SenderHandle = "sync_sender_share"

///|
#borrow(value, message)
extern "C" fn native_sender_try_send(
  value : SenderHandle,
  message : RawBox,
) -> Int = "sync_sender_try_send"

///|
#borrow(value, message)
extern "C" fn native_sender_send(value : SenderHandle, message : RawBox) -> Int = "sync_sender_send"

///|
#borrow(value)
extern "C" fn native_sender_close(value : SenderHandle) -> Unit = "sync_sender_close"

///|
#borrow(value, status)
extern "C" fn native_receiver_try_recv(
  value : ReceiverHandle,
  status : Ref[Int],
) -> RawBox = "sync_receiver_try_recv"

///|
#borrow(value, status)
extern "C" fn native_receiver_recv(
  value : ReceiverHandle,
  status : Ref[Int],
) -> RawBox = "sync_receiver_recv"

///|
#borrow(value)
extern "C" fn native_receiver_close(value : ReceiverHandle) -> Unit = "sync_receiver_close"

///|
#borrow(value)
extern "C" fn native_receiver_len(value : ReceiverHandle) -> Int = "sync_receiver_len"

///|
#borrow(value)
extern "C" fn native_receiver_capacity(value : ReceiverHandle) -> Int = "sync_receiver_capacity"
