///|
/// Creates a wait group with count zero.
pub fn WaitGroup::new() -> WaitGroup {
  native_wait_group_new()
}

///|
pub fn WaitGroup::share(self : WaitGroup) -> WaitGroup {
  native_wait_group_share(self)
}

///|
pub fn WaitGroup::add(self : WaitGroup, delta : Int) -> Unit raise SyncError {
  if !native_wait_group_add(self, delta) {
    raise SyncError::InvalidWaitGroupCount
  }
}

///|
pub fn WaitGroup::done(self : WaitGroup) -> Unit raise SyncError {
  self.add(-1)
}

///|
pub fn WaitGroup::wait(self : WaitGroup) -> Unit {
  native_wait_group_wait(self)
}
