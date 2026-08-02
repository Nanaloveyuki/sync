///|
type Once

///|
#borrow(status)
extern "C" fn native_once_new(status : Ref[Int]) -> Once = "sync_once_new"

///|
#borrow(value)
extern "C" fn native_once_share(value : Once) -> Once = "sync_once_share"

///|
#borrow(value, status)
extern "C" fn native_once_begin(value : Once, status : Ref[Int]) -> Int = "sync_once_begin"

///|
#borrow(value, status)
extern "C" fn native_once_complete(value : Once, status : Ref[Int]) -> Unit = "sync_once_complete"

///|
#borrow(value, status)
extern "C" fn native_once_poison(value : Once, status : Ref[Int]) -> Unit = "sync_once_poison"
