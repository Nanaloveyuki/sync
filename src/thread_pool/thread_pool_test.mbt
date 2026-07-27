///|
test "thread pool package links independently" {
  let pool = @thread_pool.ThreadPool::new(1, 1)
  let completed = @atomic.AtomicInt::new(0)
  let worker_completed = completed.share()
  pool.execute(fn() { ignore(worker_completed.fetch_add(1)) })
  pool.shutdown()
  assert_eq(completed.load(), 1)
}
