///|
type Once

///|
extern "C" fn native_once_new() -> Once = "sync_once_new"

///|
#borrow(value)
extern "C" fn native_once_share(value : Once) -> Once = "sync_once_share"

///|
#borrow(value)
extern "C" fn native_once_begin(value : Once) -> Int = "sync_once_begin"

///|
#borrow(value)
extern "C" fn native_once_complete(value : Once) -> Unit = "sync_once_complete"

///|
#borrow(value)
extern "C" fn native_once_poison(value : Once) -> Unit = "sync_once_poison"
