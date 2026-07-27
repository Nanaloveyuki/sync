///|
type WaitGroup

///|
extern "C" fn native_wait_group_new() -> WaitGroup = "sync_wait_group_new"

///|
#borrow(value)
extern "C" fn native_wait_group_share(value : WaitGroup) -> WaitGroup = "sync_wait_group_share"

///|
#borrow(value)
extern "C" fn native_wait_group_add(value : WaitGroup, delta : Int) -> Bool = "sync_wait_group_add"

///|
#borrow(value)
extern "C" fn native_wait_group_wait(value : WaitGroup) -> Unit = "sync_wait_group_wait"
