///|
test "once package links independently" {
  let once = @once.Once::new()
  once.call_once(fn() {  })
  once.call_once(fn() raise { fail("initializer ran twice") })
}
