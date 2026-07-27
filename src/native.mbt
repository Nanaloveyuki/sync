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
type AtomicBool

///|
type AtomicInt

///|
type AtomicUInt

///|
priv type MutexHandle

///|
type Condvar

///|
type Once

///|
type WaitGroup

///|
priv type ThreadHandle

///|
#external
priv type RawThreadState

///|
priv type SenderHandle

///|
priv type ReceiverHandle

///|
extern "C" fn native_atomic_bool_new(value : Bool) -> AtomicBool = "sync_atomic_bool_new"

///|
#borrow(value)
extern "C" fn native_atomic_bool_share(value : AtomicBool) -> AtomicBool = "sync_atomic_bool_share"

///|
#borrow(value)
extern "C" fn native_atomic_bool_load(value : AtomicBool, order : Int) -> Bool = "sync_atomic_bool_load"

///|
#borrow(value)
extern "C" fn native_atomic_bool_store(
  value : AtomicBool,
  next : Bool,
  order : Int,
) -> Unit = "sync_atomic_bool_store"

///|
#borrow(value)
extern "C" fn native_atomic_bool_swap(
  value : AtomicBool,
  next : Bool,
  order : Int,
) -> Bool = "sync_atomic_bool_swap"

///|
#borrow(value)
extern "C" fn native_atomic_bool_compare_exchange(
  value : AtomicBool,
  current : Bool,
  next : Bool,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_bool_compare_exchange"

///|
extern "C" fn native_atomic_int_new(value : Int) -> AtomicInt = "sync_atomic_int_new"

///|
#borrow(value)
extern "C" fn native_atomic_int_share(value : AtomicInt) -> AtomicInt = "sync_atomic_int_share"

///|
#borrow(value)
extern "C" fn native_atomic_int_load(value : AtomicInt, order : Int) -> Int = "sync_atomic_int_load"

///|
#borrow(value)
extern "C" fn native_atomic_int_store(
  value : AtomicInt,
  next : Int,
  order : Int,
) -> Unit = "sync_atomic_int_store"

///|
#borrow(value)
extern "C" fn native_atomic_int_swap(
  value : AtomicInt,
  next : Int,
  order : Int,
) -> Int = "sync_atomic_int_swap"

///|
#borrow(value)
extern "C" fn native_atomic_int_compare_exchange(
  value : AtomicInt,
  current : Int,
  next : Int,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_int_compare_exchange"

///|
#borrow(value)
extern "C" fn native_atomic_int_fetch_add(
  value : AtomicInt,
  delta : Int,
  order : Int,
) -> Int = "sync_atomic_int_fetch_add"

///|
extern "C" fn native_atomic_uint_new(value : UInt) -> AtomicUInt = "sync_atomic_uint_new"

///|
#borrow(value)
extern "C" fn native_atomic_uint_share(value : AtomicUInt) -> AtomicUInt = "sync_atomic_uint_share"

///|
#borrow(value)
extern "C" fn native_atomic_uint_load(value : AtomicUInt, order : Int) -> UInt = "sync_atomic_uint_load"

///|
#borrow(value)
extern "C" fn native_atomic_uint_store(
  value : AtomicUInt,
  next : UInt,
  order : Int,
) -> Unit = "sync_atomic_uint_store"

///|
#borrow(value)
extern "C" fn native_atomic_uint_swap(
  value : AtomicUInt,
  next : UInt,
  order : Int,
) -> UInt = "sync_atomic_uint_swap"

///|
#borrow(value)
extern "C" fn native_atomic_uint_compare_exchange(
  value : AtomicUInt,
  current : UInt,
  next : UInt,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_uint_compare_exchange"

///|
#borrow(value)
extern "C" fn native_atomic_uint_fetch_add(
  value : AtomicUInt,
  delta : UInt,
  order : Int,
) -> UInt = "sync_atomic_uint_fetch_add"

///|
#owned(value)
extern "C" fn native_mutex_new(value : RawBox) -> MutexHandle = "sync_mutex_new"

///|
#borrow(value)
extern "C" fn native_mutex_share(value : MutexHandle) -> MutexHandle = "sync_mutex_share"

///|
#borrow(value)
extern "C" fn native_mutex_lock_get(value : MutexHandle) -> RawBox = "sync_mutex_lock_get"

///|
#borrow(value)
#owned(box)
extern "C" fn native_mutex_release_unlock(
  value : MutexHandle,
  box : RawBox,
) -> Unit = "sync_mutex_release_unlock"

///|
extern "C" fn native_condvar_new() -> Condvar = "sync_condvar_new"

///|
#borrow(value)
extern "C" fn native_condvar_share(value : Condvar) -> Condvar = "sync_condvar_share"

///|
#borrow(value, mutex)
extern "C" fn native_condvar_wait(value : Condvar, mutex : MutexHandle) -> Unit = "sync_condvar_wait"

///|
#borrow(value)
extern "C" fn native_condvar_notify_one(value : Condvar) -> Unit = "sync_condvar_notify_one"

///|
#borrow(value)
extern "C" fn native_condvar_notify_all(value : Condvar) -> Unit = "sync_condvar_notify_all"

///|
extern "C" fn native_once_new() -> Once = "sync_once_new"

///|
#borrow(value)
extern "C" fn native_once_share(value : Once) -> Once = "sync_once_share"

///|
#borrow(value)
extern "C" fn native_once_begin(value : Once) -> Int = "sync_once_begin"

///|
#borrow(value)
extern "C" fn native_once_complete(value : Once) -> Unit = "sync_once_complete"

///|
#borrow(value)
extern "C" fn native_once_poison(value : Once) -> Unit = "sync_once_poison"

///|
extern "C" fn native_wait_group_new() -> WaitGroup = "sync_wait_group_new"

///|
#borrow(value)
extern "C" fn native_wait_group_share(value : WaitGroup) -> WaitGroup = "sync_wait_group_share"

///|
#borrow(value)
extern "C" fn native_wait_group_add(value : WaitGroup, delta : Int) -> Bool = "sync_wait_group_add"

///|
#borrow(value)
extern "C" fn native_wait_group_wait(value : WaitGroup) -> Unit = "sync_wait_group_wait"

///|
extern "C" fn native_thread_new() -> ThreadHandle = "sync_thread_new"

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
#borrow(value)
extern "C" fn native_thread_id(value : ThreadHandle) -> UInt64 = "sync_thread_id"

///|
extern "C" fn native_thread_yield() -> Unit = "sync_thread_yield"

///|
extern "C" fn native_current_thread_id() -> UInt64 = "sync_current_thread_id"

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
