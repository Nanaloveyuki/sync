///|
priv suberror RwLockPropertyError {
  CallbackFailed
} derive(Debug)

///|
test "rwlock releases both callback modes after failures" {
  @quickcheck.check(
    (failures : Array[Bool]) => {
      let lock = RwLock::new()
      for should_fail in failures {
        let write_ok = if should_fail {
          try {
            let _result : Unit = lock.with_write(fn() raise {
              raise RwLockPropertyError::CallbackFailed
            })
            false
          } catch {
            RwLockPropertyError::CallbackFailed => true
            _ => false
          }
        } else {
          lock.with_write(fn() { 1 }) == 1
        }
        guard write_ok else { return false }

        let read_ok = if should_fail {
          try {
            let _result : Unit = lock.with_read(fn() raise {
              raise RwLockPropertyError::CallbackFailed
            })
            false
          } catch {
            RwLockPropertyError::CallbackFailed => true
            _ => false
          }
        } else {
          lock.with_read(fn() { 2 }) == 2
        }
        guard read_ok else { return false }
        guard lock.with_read(fn() { 3 }) == 3 else { return false }
      }
      true
    },
    count=120,
    max_size=48,
    max_shrinks=120,
    seed=20260831,
  )
}
