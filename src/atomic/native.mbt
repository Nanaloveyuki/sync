///|
type AtomicBool

///|
type AtomicInt

///|
type AtomicUInt

///|
extern "C" fn native_atomic_bool_new(value : Bool) -> AtomicBool = "sync_atomic_bool_new"

///|
#borrow(value)
extern "C" fn native_atomic_bool_share(value : AtomicBool) -> AtomicBool = "sync_atomic_bool_share"

///|
#borrow(value)
extern "C" fn native_atomic_bool_load(value : AtomicBool, order : Int) -> Bool = "sync_atomic_bool_load"

///|
#borrow(value)
extern "C" fn native_atomic_bool_store(
  value : AtomicBool,
  next : Bool,
  order : Int,
) -> Unit = "sync_atomic_bool_store"

///|
#borrow(value)
extern "C" fn native_atomic_bool_swap(
  value : AtomicBool,
  next : Bool,
  order : Int,
) -> Bool = "sync_atomic_bool_swap"

///|
#borrow(value)
extern "C" fn native_atomic_bool_compare_exchange(
  value : AtomicBool,
  current : Bool,
  next : Bool,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_bool_compare_exchange"

///|
extern "C" fn native_atomic_int_new(value : Int) -> AtomicInt = "sync_atomic_int_new"

///|
#borrow(value)
extern "C" fn native_atomic_int_share(value : AtomicInt) -> AtomicInt = "sync_atomic_int_share"

///|
#borrow(value)
extern "C" fn native_atomic_int_load(value : AtomicInt, order : Int) -> Int = "sync_atomic_int_load"

///|
#borrow(value)
extern "C" fn native_atomic_int_store(
  value : AtomicInt,
  next : Int,
  order : Int,
) -> Unit = "sync_atomic_int_store"

///|
#borrow(value)
extern "C" fn native_atomic_int_swap(
  value : AtomicInt,
  next : Int,
  order : Int,
) -> Int = "sync_atomic_int_swap"

///|
#borrow(value)
extern "C" fn native_atomic_int_compare_exchange(
  value : AtomicInt,
  current : Int,
  next : Int,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_int_compare_exchange"

///|
#borrow(value)
extern "C" fn native_atomic_int_fetch_add(
  value : AtomicInt,
  delta : Int,
  order : Int,
) -> Int = "sync_atomic_int_fetch_add"

///|
extern "C" fn native_atomic_uint_new(value : UInt) -> AtomicUInt = "sync_atomic_uint_new"

///|
#borrow(value)
extern "C" fn native_atomic_uint_share(value : AtomicUInt) -> AtomicUInt = "sync_atomic_uint_share"

///|
#borrow(value)
extern "C" fn native_atomic_uint_load(value : AtomicUInt, order : Int) -> UInt = "sync_atomic_uint_load"

///|
#borrow(value)
extern "C" fn native_atomic_uint_store(
  value : AtomicUInt,
  next : UInt,
  order : Int,
) -> Unit = "sync_atomic_uint_store"

///|
#borrow(value)
extern "C" fn native_atomic_uint_swap(
  value : AtomicUInt,
  next : UInt,
  order : Int,
) -> UInt = "sync_atomic_uint_swap"

///|
#borrow(value)
extern "C" fn native_atomic_uint_compare_exchange(
  value : AtomicUInt,
  current : UInt,
  next : UInt,
  success : Int,
  failure : Int,
) -> UInt64 = "sync_atomic_uint_compare_exchange"

///|
#borrow(value)
extern "C" fn native_atomic_uint_fetch_add(
  value : AtomicUInt,
  delta : UInt,
  order : Int,
) -> UInt = "sync_atomic_uint_fetch_add"
