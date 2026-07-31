///|
test "mutex package links independently" {
  let value = try! @mutex.Mutex::new(1)
  value.with_lock(fn(lock_guard) {
    lock_guard.with_value(fn(cell) { cell.val += 1 })
  })
  assert_eq(
    value.with_lock(fn(lock_guard) {
      lock_guard.with_value(fn(cell) { cell.val })
    }),
    2,
  )
}
