///|
test "thread package links independently" {
  let thread = @thread.spawn_unchecked(fn() { 42 })
  assert_eq(thread.join(), 42)
}
