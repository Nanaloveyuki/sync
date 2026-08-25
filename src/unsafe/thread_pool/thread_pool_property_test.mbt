///|
test "thread pool drains generated task batches" {
  @quickcheck.check(
    (tasks : Array[Unit]) => {
      let pool = @thread_pool.ThreadPool::new(2, 4)
      let completed = @atomic.AtomicInt::new(0)
      for _ in tasks {
        let worker_completed = completed.share()
        pool.execute(fn() { ignore(worker_completed.fetch_add(1)) })
      }
      pool.shutdown()
      completed.load() == tasks.length()
    },
    count=24,
    max_size=16,
    max_shrinks=80,
    seed=20260901,
  )
}
