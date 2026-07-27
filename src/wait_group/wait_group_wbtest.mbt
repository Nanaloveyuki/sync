///|
test "wait group waits for workers" {
  let group = WaitGroup::new()
  group.add(2)
  let group1 = group.share()
  let group2 = group.share()
  let count = @atomic.AtomicInt::new(0)
  let count1 = count.share()
  let count2 = count.share()
  let first = @thread.spawn(() => {
    ignore(count1.fetch_add(1))
    group1.done()
  })
  let second = @thread.spawn(() => {
    ignore(count2.fetch_add(1))
    group2.done()
  })
  group.wait()
  assert_eq(count.load(), 2)
  first.join()
  second.join()
}
