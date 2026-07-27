///|
priv suberror WorkerTestError {
  WorkerFailed
} derive(Debug)

///|
test "thread returns a value and has an id" {
  let parent_id = current_thread_id()
  let thread = spawn(fn() { (current_thread_id(), 42) })
  assert_true(thread.id() != 0UL)
  let (worker_id, value) = thread.join()
  assert_true(worker_id != parent_id)
  assert_eq(value, 42)
}

///|
test "thread transports raised errors" {
  let thread : Thread[Unit] = spawn(fn() raise { raise WorkerFailed })
  try {
    thread.join()
    fail("join should raise ThreadPanicked")
  } catch {
    SyncError::ThreadPanicked(_) => ()
    _ => fail("unexpected error")
  }
}
