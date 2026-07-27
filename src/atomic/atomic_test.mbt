///|
test "atomic package links independently" {
  let value = @atomic.AtomicInt::new(1)
  assert_eq(value.fetch_add(2, order=@atomic.MemoryOrdering::Relaxed), 1)
  assert_eq(value.load(), 3)
}
