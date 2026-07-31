///|
test "unsafe facade exposes raw APIs explicitly" {
  let (sender, receiver) : (@unsafe.Sender[Int], @unsafe.Receiver[Int]) = @unsafe.bounded(
    1,
  )
  assert_eq(sender.try_send(1), @unsafe.TrySendResult::Sent)
  assert_eq(receiver.recv(), Some(1))

  let mutex = @unsafe.Mutex::new(1)
  mutex.with_lock(fn(lock_guard) {
    lock_guard.with_value(fn(value) { value.val += 1 })
  })
  assert_eq(
    mutex.with_lock(fn(lock_guard) {
      lock_guard.with_value(fn(value) { value.val })
    }),
    2,
  )

  let worker = try! @unsafe.spawn(fn() {  })
  try! worker.join()
}
