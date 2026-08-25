///|
priv suberror MutexPropertyError {
  CallbackFailed
} derive(Debug)

///|
priv enum MutexOperation {
  Add(Int)
  Fail
  Read
} derive(Debug)

///|
impl @quickcheck.Arbitrary for MutexOperation with fn arbitrary(size, rs) {
  match rs.next_uint() % 5U {
    0 | 1 | 2 => Add(@quickcheck.int_range(-8, 9).run(size, rs))
    3 => Fail
    _ => Read
  }
}

///|
impl @shrink.Shrink for MutexOperation with fn shrink(operation) {
  match operation {
    Add(value) => @shrink.Shrink::shrink(value).map(value => Add(value))
    Fail | Read => [||]
  }
}

///|
test "mutex remains usable after generated callback failures" {
  @quickcheck.check(
    (operations : Array[MutexOperation]) => {
      let mutex = Mutex::new(0)
      let mut expected = 0
      for operation in operations {
        match operation {
          Add(delta) => {
            mutex.with_lock(fn(lock_guard) {
              ignore(lock_guard.with_value(fn(value) { value.val += delta }))
            })
            expected += delta
          }
          Fail => {
            let caught = try {
              let _result : Unit = mutex.with_lock(fn(_lock_guard) raise {
                raise MutexPropertyError::CallbackFailed
              })
              false
            } catch {
              MutexPropertyError::CallbackFailed => true
              _ => false
            }
            guard caught else { return false }
          }
          Read => ()
        }
        let current : Int = mutex.with_lock(fn(lock_guard) {
          lock_guard.with_value(fn(value) { value.val })
        })
        guard current == expected else { return false }
      }
      true
    },
    count=120,
    max_size=48,
    max_shrinks=160,
    seed=20260829,
  )
}
