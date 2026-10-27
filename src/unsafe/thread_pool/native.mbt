///|
type ThreadPool

///|
#borrow(call_closure, status)
extern "C" fn native_thread_pool_new(
  worker_count : Int32,
  capacity : Int32,
  call_closure : FuncRef[(() -> Unit) -> Unit],
  status : Ref[Int32],
) -> ThreadPool = "sync_thread_pool_new"

///|
#borrow(value, status)
extern "C" fn native_thread_pool_share(
  value : ThreadPool,
  status : Ref[Int32],
) -> ThreadPool = "sync_thread_pool_share"

///|
#borrow(value, error)
#owned(task)
extern "C" fn native_thread_pool_try_execute(
  value : ThreadPool,
  task : () -> Unit,
  error : Ref[Int32],
) -> Int32 = "sync_thread_pool_try_execute"

///|
#borrow(value, error)
#owned(task)
extern "C" fn native_thread_pool_execute(
  value : ThreadPool,
  task : () -> Unit,
  error : Ref[Int32],
) -> Int32 = "sync_thread_pool_execute"

///|
#borrow(value, status)
extern "C" fn native_thread_pool_close(
  value : ThreadPool,
  status : Ref[Int32],
) -> Unit = "sync_thread_pool_close"

///|
#borrow(value, status)
extern "C" fn native_thread_pool_shutdown(
  value : ThreadPool,
  status : Ref[Int32],
) -> Int32 = "sync_thread_pool_shutdown"

///|
#borrow(value, status)
extern "C" fn native_thread_pool_is_closed(
  value : ThreadPool,
  status : Ref[Int32],
) -> Bool = "sync_thread_pool_is_closed"

///|
#borrow(value)
extern "C" fn native_thread_pool_worker_count(value : ThreadPool) -> Int32 = "sync_thread_pool_worker_count"

///|
#borrow(value, status)
extern "C" fn native_thread_pool_pending_count(
  value : ThreadPool,
  status : Ref[Int32],
) -> Int32 = "sync_thread_pool_pending_count"
