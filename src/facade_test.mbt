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
  assert_eq(value.fetch_add(1, order=@sync.MemoryOrdering::Relaxed), 3)
  assert_eq(value.load(), 4)

  let unsigned = @sync.AtomicUInt::new(1U)
  unsigned.store(2U)
  assert_eq(unsigned.swap(3U), 2U)
  assert_true(unsigned.compare_exchange(3U, 4U).exchanged)
  assert_eq(unsigned.fetch_add(1U), 4U)

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

  let (owned_sender, owned_receiver) = @sync.owned_bytes_bounded(1)
  let _shared_owned_sender = owned_sender.share()
  assert_eq(owned_sender.try_send(b"safe"), @sync.OwnedBytesTrySendResult::Sent)
  assert_eq(
    owned_receiver.try_recv(),
    @sync.OwnedBytesTryRecvResult::Received(b"safe"),
  )
  assert_true(owned_sender.send(b"again"))
  assert_eq(owned_receiver.recv(), Some(b"again"))
  owned_sender.close()
  owned_receiver.close()

  let (limited_sender, _limited_receiver) = @sync.owned_bytes_bounded_with_limits(
    1,
    max_message_bytes=4,
    max_queued_bytes=4,
  )
  assert_eq(
    limited_sender.send_checked(b"large"),
    @sync.OwnedBytesSendResult::MessageTooLarge(5, 4),
  )
}
