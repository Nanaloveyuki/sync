///|
test "wait group package links independently" {
  let group = @wait_group.WaitGroup::new()
  group.add(1)
  group.done()
  group.wait()
}
