///|
type ThreadPool

///|
#borrow(call_closure, status)
extern "C" fn native_thread_pool_new(
  worker_count : Int,
  capacity : Int,
  call_closure : FuncRef[(() -> Unit) -> Unit],
  status : Ref[Int],
) -> ThreadPool = "sync_thread_pool_new"

///|
#borrow(value)
extern "C" fn native_thread_pool_share(value : ThreadPool) -> ThreadPool = "sync_thread_pool_share"

///|
#borrow(value)
#owned(task)
extern "C" fn native_thread_pool_try_execute(
  value : ThreadPool,
  task : () -> Unit,
) -> Int = "sync_thread_pool_try_execute"

///|
#borrow(value)
#owned(task)
extern "C" fn native_thread_pool_execute(
  value : ThreadPool,
  task : () -> Unit,
) -> Int = "sync_thread_pool_execute"

///|
#borrow(value)
extern "C" fn native_thread_pool_close(value : ThreadPool) -> Unit = "sync_thread_pool_close"

///|
#borrow(value)
extern "C" fn native_thread_pool_shutdown(value : ThreadPool) -> Int = "sync_thread_pool_shutdown"

///|
#borrow(value)
extern "C" fn native_thread_pool_is_closed(value : ThreadPool) -> Bool = "sync_thread_pool_is_closed"

///|
#borrow(value)
extern "C" fn native_thread_pool_worker_count(value : ThreadPool) -> Int = "sync_thread_pool_worker_count"

///|
#borrow(value)
extern "C" fn native_thread_pool_pending_count(value : ThreadPool) -> Int = "sync_thread_pool_pending_count"
