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
priv enum ThreadOutcome[T] {
  Returned(T)
  Failed(String)
}

///|
priv type ThreadHandle

///|
#external
priv type RawThreadState

///|
#borrow(status)
extern "C" fn native_thread_new(status : Ref[Int]) -> ThreadHandle = "sync_thread_new"

///|
#borrow(value)
extern "C" fn native_thread_state(value : ThreadHandle) -> RawThreadState = "sync_thread_state"

///|
#borrow(value, call_closure)
#owned(task)
extern "C" fn native_thread_start(
  value : ThreadHandle,
  call_closure : FuncRef[(() -> Unit) -> Unit],
  task : () -> Unit,
) -> Int = "sync_thread_start"

///|
#owned(result)
extern "C" fn native_thread_complete(
  state : RawThreadState,
  result : RawBox,
) -> Unit = "sync_thread_complete"

///|
#borrow(value, status)
extern "C" fn native_thread_join(
  value : ThreadHandle,
  status : Ref[Int],
) -> RawBox = "sync_thread_join"

///|
#borrow(value, status)
extern "C" fn native_thread_detach(
  value : ThreadHandle,
  status : Ref[Int],
) -> Unit = "sync_thread_detach"

///|
#borrow(value, status)
extern "C" fn native_thread_is_finished(
  value : ThreadHandle,
  status : Ref[Int],
) -> Bool = "sync_thread_is_finished"

///|
#borrow(value)
extern "C" fn native_thread_id(value : ThreadHandle) -> UInt64 = "sync_thread_id"

///|
extern "C" fn native_thread_yield() -> Unit = "sync_thread_yield"

///|
extern "C" fn native_current_thread_id() -> UInt64 = "sync_current_thread_id"
