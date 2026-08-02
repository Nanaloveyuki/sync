///|
/// An unchecked once-initialization primitive for OS threads.
///
/// The initializer may capture arbitrary MoonBit heap values, so callers must
/// enforce the cross-thread ownership and aliasing boundary themselves.
pub fn Once::new() -> Once raise SyncError {
  let status = Ref::Ref(0)
  let once = native_once_new(status)
  if status.val != 0 {
    raise SyncError::OnceInitializationFailed(status.val)
  }
  once
}

///|
pub fn Once::share(self : Once) -> Once {
  native_once_share(self)
}

///|
/// Runs an initializer once. A raised error poisons this Once instance.
///
/// The callback runs on one of the calling threads and is not statically
/// checked for thread-safe captures.
pub fn Once::call_once(self : Once, f : () -> Unit raise?) -> Unit raise {
  let begin_status = Ref::Ref(0)
  match native_once_begin(self, begin_status) {
    _ if begin_status.val != 0 =>
      raise SyncError::OnceOperationFailed(begin_status.val)
    0 => ()
    1 =>
      try f() catch {
        err => {
          let poison_status = Ref::Ref(0)
          native_once_poison(self, poison_status)
          if poison_status.val != 0 {
            raise SyncError::OnceOperationFailed(poison_status.val)
          }
          raise err
        }
      } noraise {
        _ => {
          let complete_status = Ref::Ref(0)
          native_once_complete(self, complete_status)
          if complete_status.val != 0 {
            raise SyncError::OnceOperationFailed(complete_status.val)
          }
        }
      }
    _ => raise SyncError::OncePoisoned
  }
}
