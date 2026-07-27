///|
pub fn Once::new() -> Once {
  native_once_new()
}

///|
pub fn Once::share(self : Once) -> Once {
  native_once_share(self)
}

///|
/// Runs an initializer once. A raised error poisons this Once instance.
pub fn Once::call_once(self : Once, f : () -> Unit raise?) -> Unit raise {
  match native_once_begin(self) {
    0 => ()
    1 =>
      try f() catch {
        err => {
          native_once_poison(self)
          raise err
        }
      } noraise {
        _ => native_once_complete(self)
      }
    _ => raise SyncError::OncePoisoned
  }
}
