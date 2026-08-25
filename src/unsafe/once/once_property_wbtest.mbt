///|
priv suberror OncePropertyError {
  CallbackFailed
} derive(Debug)

///|
test "once follows a successful-or-poisoned model" {
  @quickcheck.check(
    (attempts : Array[Bool]) => {
      let once = Once::new()
      let called = Ref::Ref(0)
      let mut state = 0
      for should_fail in attempts {
        let outcome = try {
          once.call_once(fn() raise {
            called.val += 1
            if should_fail {
              raise OncePropertyError::CallbackFailed
            }
          })
          0
        } catch {
          OncePropertyError::CallbackFailed => 1
          SyncError::OncePoisoned => 2
          _ => 3
        }
        let expected = if state == 0 {
          if should_fail {
            1
          } else {
            0
          }
        } else if state == 2 {
          2
        } else {
          0
        }
        guard outcome == expected else { return false }
        if state == 0 {
          state = if should_fail { 2 } else { 1 }
        }
      }
      let expected_called = if attempts.is_empty() { 0 } else { 1 }
      called.val == expected_called
    },
    count=120,
    max_size=48,
    max_shrinks=120,
    seed=20260830,
  )
}
