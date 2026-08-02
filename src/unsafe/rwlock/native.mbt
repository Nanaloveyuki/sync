///|
type RwLock

///|
#borrow(status)
extern "C" fn native_rwlock_new(status : Ref[Int]) -> RwLock = "sync_rwlock_new"

///|
#borrow(value)
extern "C" fn native_rwlock_share(value : RwLock) -> RwLock = "sync_rwlock_share"

///|
#borrow(value)
extern "C" fn native_rwlock_read_lock(value : RwLock) -> Int = "sync_rwlock_read_lock"

///|
#borrow(value)
extern "C" fn native_rwlock_read_unlock(value : RwLock) -> Int = "sync_rwlock_read_unlock"

///|
#borrow(value)
extern "C" fn native_rwlock_write_lock(value : RwLock) -> Int = "sync_rwlock_write_lock"

///|
#borrow(value)
extern "C" fn native_rwlock_write_unlock(value : RwLock) -> Int = "sync_rwlock_write_unlock"
