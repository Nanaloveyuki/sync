///|
test "mutex package links independently" {
  let value = @mutex.Mutex::new(1)
  value.with_lock(fn(cell) { cell.val += 1 })
  assert_eq(value.with_lock(fn(cell) { cell.val }), 2)
}
