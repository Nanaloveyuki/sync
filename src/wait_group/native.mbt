///|
type WaitGroup

///|
#borrow(status)
extern "C" fn native_wait_group_new(status : Ref[Int]) -> WaitGroup = "sync_wait_group_new"

///|
#borrow(value)
extern "C" fn native_wait_group_share(value : WaitGroup) -> WaitGroup = "sync_wait_group_share"

///|
#borrow(value, status)
extern "C" fn native_wait_group_add(
  value : WaitGroup,
  delta : Int,
  status : Ref[Int],
) -> Bool = "sync_wait_group_add"

///|
#borrow(value, status)
extern "C" fn native_wait_group_wait(
  value : WaitGroup,
  status : Ref[Int],
) -> Unit = "sync_wait_group_wait"
