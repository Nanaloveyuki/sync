///|
test "mutex protects a generic value" {
  let value = Mutex::new(0)
  let worker_value = value.share()
  let thread = @thread.spawn(fn() {
    for i = 0; i < 2000; i = i + 1 {
      worker_value.with_lock(fn(cell) { cell.val += 1 })
    }
  })
  for i = 0; i < 2000; i = i + 1 {
    value.with_lock(fn(cell) { cell.val += 1 })
  }
  thread.join()
  let result = value.with_lock(fn(cell) { cell.val })
  assert_eq(result, 4000)
}

///|
test "condvar releases and reacquires mutex" {
  let ready = Mutex::new(false)
  let worker_ready = ready.share()
  let cond = Condvar::new()
  let worker_cond = cond.share()
  let thread = @thread.spawn(fn() {
    worker_ready.with_lock(fn(cell) {
      cell.val = true
      worker_cond.notify_one()
    })
  })
  ready.with_lock(fn(cell) {
    while !cell.val {
      cond.wait(ready)
    }
  })
  thread.join()
}
