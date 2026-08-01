///|
/// Creates a wait group with count zero.
pub fn WaitGroup::new() -> WaitGroup raise SyncError {
  let status = Ref::Ref(0)
  let group = native_wait_group_new(status)
  if status.val != 0 {
    raise SyncError::WaitGroupInitializationFailed(status.val)
  }
  group
}

///|
pub fn WaitGroup::share(self : WaitGroup) -> WaitGroup {
  native_wait_group_share(self)
}

///|
pub fn WaitGroup::add(self : WaitGroup, delta : Int) -> Unit raise SyncError {
  let status = Ref::Ref(0)
  if !native_wait_group_add(self, delta, status) {
    if status.val != 0 {
      raise SyncError::WaitGroupOperationFailed(status.val)
    }
    raise SyncError::InvalidWaitGroupCount
  }
}

///|
pub fn WaitGroup::done(self : WaitGroup) -> Unit raise SyncError {
  self.add(-1)
}

///|
pub fn WaitGroup::wait(self : WaitGroup) -> Unit raise SyncError {
  let status = Ref::Ref(0)
  native_wait_group_wait(self, status)
  if status.val != 0 {
    raise SyncError::WaitGroupOperationFailed(status.val)
  }
}
