///|
test "root facade preserves the public entry points" {
  let error = @sync.SyncError::InvalidCapacity(0)
  match error {
    @sync.SyncError::InvalidCapacity(capacity) => assert_eq(capacity, 0)
    _ => assert_true(false)
  }

  let flag = @sync.AtomicBool::new(false)
  assert_false(flag.load())
  flag.store(true)
  assert_true(flag.swap(false))
  assert_true(flag.compare_exchange(false, true).exchanged)

  let value = @sync.AtomicInt::new(1)
  value.store(1)
  assert_eq(value.swap(2), 1)
  assert_true(value.compare_exchange(2, 3).exchanged)
  let worker_value = value.share()
  let worker = @sync.spawn(fn() {
    ignore(worker_value.fetch_add(1, order=@sync.MemoryOrdering::Relaxed))
  })
  ignore(worker.id())
  worker.join()
  assert_eq(value.load(), 4)

  let unsigned = @sync.AtomicUInt::new(1U)
  unsigned.store(2U)
  assert_eq(unsigned.swap(3U), 2U)
  assert_true(unsigned.compare_exchange(3U, 4U).exchanged)
  assert_eq(unsigned.fetch_add(1U), 4U)

  let mutex = @sync.Mutex::new(1)
  let _shared_mutex = mutex.share()
  mutex.with_lock(fn(cell) { cell.val += 1 })
  assert_eq(mutex.with_lock(fn(cell) { cell.val }), 2)
  let cond = @sync.Condvar::new()
  let _shared_cond = cond.share()
  cond.notify_one()
  cond.notify_all()

  let once = @sync.Once::new()
  let _shared_once = once.share()
  once.call_once(fn() {  })

  let group = @sync.WaitGroup::new()
  let _shared_group = group.share()
  group.add(1)
  group.done()
  group.wait()

  let rwlock = @sync.RwLock::new()
  let _shared_rwlock = rwlock.share()
  assert_eq(rwlock.with_write(fn() { 1 }), 1)
  assert_eq(rwlock.with_read(fn() { 2 }), 2)

  let (sender, receiver) : (@sync.Sender[Int], @sync.Receiver[Int]) = @sync.bounded(
    2,
  )
  let _shared_sender = sender.share()
  assert_eq(sender.try_send(42), @sync.TrySendResult::Sent)
  assert_eq(receiver.try_recv(), @sync.TryRecvResult::Received(42))
  assert_eq(sender.send(7), Ok(()))
  assert_eq(receiver.recv(), Some(7))
  assert_eq(receiver.length(), 0)
  assert_eq(receiver.capacity(), 2)
  sender.close()
  receiver.close()

  let pool = @sync.ThreadPool::new(1, 1)
  let _shared_pool = pool.share()
  assert_eq(pool.worker_count(), 1)
  assert_false(pool.is_closed())
  pool.execute(fn() {  })
  ignore(pool.try_execute(fn() {  }))
  ignore(pool.pending_count())
  pool.close()
  pool.shutdown()

  @sync.yield_now()
  assert_true(@sync.current_thread_id() != 0UL)
}
