///|
test "rwlock package links independently" {
  let lock = @rwlock.RwLock::new()
  assert_eq(lock.with_write(fn() { 42 }), 42)
  assert_eq(lock.with_read(fn() { 7 }), 7)
}
