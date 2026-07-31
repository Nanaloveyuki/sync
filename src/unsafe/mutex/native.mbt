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
priv type MutexHandle

///|
type Condvar

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
extern "C" fn native_condvar_wait(value : Condvar, mutex : MutexHandle) -> Int = "sync_condvar_wait"

///|
#borrow(value)
extern "C" fn native_condvar_notify_one(value : Condvar) -> Unit = "sync_condvar_notify_one"

///|
#borrow(value)
extern "C" fn native_condvar_notify_all(value : Condvar) -> Unit = "sync_condvar_notify_all"
