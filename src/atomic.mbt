///|
fn validate_load_order(order : MemoryOrdering) -> Unit raise SyncError {
  match order {
    Release | AcqRel =>
      raise InvalidMemoryOrdering("load does not accept Release or AcqRel")
    _ => ()
  }
}

///|
fn validate_store_order(order : MemoryOrdering) -> Unit raise SyncError {
  match order {
    Acquire | AcqRel =>
      raise InvalidMemoryOrdering("store does not accept Acquire or AcqRel")
    _ => ()
  }
}

///|
fn failure_rank(order : MemoryOrdering) -> Int {
  match order {
    Relaxed => 0
    Acquire => 1
    SeqCst => 2
    Release | AcqRel => -1
  }
}

///|
fn success_failure_rank(order : MemoryOrdering) -> Int {
  match order {
    Relaxed | Release => 0
    Acquire | AcqRel => 1
    SeqCst => 2
  }
}

///|
fn validate_compare_exchange_orders(
  success : MemoryOrdering,
  failure : MemoryOrdering,
) -> Unit raise SyncError {
  let failure_level = failure_rank(failure)
  if failure_level < 0 || failure_level > success_failure_rank(success) {
    raise InvalidMemoryOrdering(
      "compare_exchange failure ordering cannot be Release, AcqRel, or stronger than success",
    )
  }
}

///|
fn packed_exchanged(value : UInt64) -> Bool {
  value >> 32 != 0
}

///|
fn packed_observed_uint(value : UInt64) -> UInt {
  (value & 0xFFFF_FFFFUL).to_uint()
}

///|
/// Creates an atomic boolean. Defaults on operations are SeqCst.
pub fn AtomicBool::new(value : Bool) -> AtomicBool {
  native_atomic_bool_new(value)
}

///|
/// Creates an independent wrapper for use by another OS thread.
pub fn AtomicBool::share(self : AtomicBool) -> AtomicBool {
  native_atomic_bool_share(self)
}

///|
pub fn AtomicBool::load(
  self : AtomicBool,
  order? : MemoryOrdering = SeqCst,
) -> Bool raise SyncError {
  validate_load_order(order)
  native_atomic_bool_load(self, order.code())
}

///|
pub fn AtomicBool::store(
  self : AtomicBool,
  value : Bool,
  order? : MemoryOrdering = SeqCst,
) -> Unit raise SyncError {
  validate_store_order(order)
  native_atomic_bool_store(self, value, order.code())
}

///|
pub fn AtomicBool::swap(
  self : AtomicBool,
  value : Bool,
  order? : MemoryOrdering = SeqCst,
) -> Bool {
  native_atomic_bool_swap(self, value, order.code())
}

///|
pub fn AtomicBool::compare_exchange(
  self : AtomicBool,
  current : Bool,
  next : Bool,
  success? : MemoryOrdering = SeqCst,
  failure? : MemoryOrdering = SeqCst,
) -> CompareExchangeResult[Bool] raise SyncError {
  validate_compare_exchange_orders(success, failure)
  let packed = native_atomic_bool_compare_exchange(
    self,
    current,
    next,
    success.code(),
    failure.code(),
  )
  { observed: (packed & 1UL) != 0, exchanged: packed_exchanged(packed) }
}

///|
/// Creates a 32-bit signed atomic integer.
pub fn AtomicInt::new(value : Int) -> AtomicInt {
  native_atomic_int_new(value)
}

///|
/// Creates an independent wrapper for use by another OS thread.
pub fn AtomicInt::share(self : AtomicInt) -> AtomicInt {
  native_atomic_int_share(self)
}

///|
pub fn AtomicInt::load(
  self : AtomicInt,
  order? : MemoryOrdering = SeqCst,
) -> Int raise SyncError {
  validate_load_order(order)
  native_atomic_int_load(self, order.code())
}

///|
pub fn AtomicInt::store(
  self : AtomicInt,
  value : Int,
  order? : MemoryOrdering = SeqCst,
) -> Unit raise SyncError {
  validate_store_order(order)
  native_atomic_int_store(self, value, order.code())
}

///|
pub fn AtomicInt::swap(
  self : AtomicInt,
  value : Int,
  order? : MemoryOrdering = SeqCst,
) -> Int {
  native_atomic_int_swap(self, value, order.code())
}

///|
pub fn AtomicInt::compare_exchange(
  self : AtomicInt,
  current : Int,
  next : Int,
  success? : MemoryOrdering = SeqCst,
  failure? : MemoryOrdering = SeqCst,
) -> CompareExchangeResult[Int] raise SyncError {
  validate_compare_exchange_orders(success, failure)
  let packed = native_atomic_int_compare_exchange(
    self,
    current,
    next,
    success.code(),
    failure.code(),
  )
  {
    observed: packed_observed_uint(packed).reinterpret_as_int(),
    exchanged: packed_exchanged(packed),
  }
}

///|
pub fn AtomicInt::fetch_add(
  self : AtomicInt,
  delta : Int,
  order? : MemoryOrdering = SeqCst,
) -> Int {
  native_atomic_int_fetch_add(self, delta, order.code())
}

///|
/// Creates a 32-bit unsigned atomic integer.
pub fn AtomicUInt::new(value : UInt) -> AtomicUInt {
  native_atomic_uint_new(value)
}

///|
/// Creates an independent wrapper for use by another OS thread.
pub fn AtomicUInt::share(self : AtomicUInt) -> AtomicUInt {
  native_atomic_uint_share(self)
}

///|
pub fn AtomicUInt::load(
  self : AtomicUInt,
  order? : MemoryOrdering = SeqCst,
) -> UInt raise SyncError {
  validate_load_order(order)
  native_atomic_uint_load(self, order.code())
}

///|
pub fn AtomicUInt::store(
  self : AtomicUInt,
  value : UInt,
  order? : MemoryOrdering = SeqCst,
) -> Unit raise SyncError {
  validate_store_order(order)
  native_atomic_uint_store(self, value, order.code())
}

///|
pub fn AtomicUInt::swap(
  self : AtomicUInt,
  value : UInt,
  order? : MemoryOrdering = SeqCst,
) -> UInt {
  native_atomic_uint_swap(self, value, order.code())
}

///|
pub fn AtomicUInt::compare_exchange(
  self : AtomicUInt,
  current : UInt,
  next : UInt,
  success? : MemoryOrdering = SeqCst,
  failure? : MemoryOrdering = SeqCst,
) -> CompareExchangeResult[UInt] raise SyncError {
  validate_compare_exchange_orders(success, failure)
  let packed = native_atomic_uint_compare_exchange(
    self,
    current,
    next,
    success.code(),
    failure.code(),
  )
  {
    observed: packed_observed_uint(packed),
    exchanged: packed_exchanged(packed),
  }
}

///|
pub fn AtomicUInt::fetch_add(
  self : AtomicUInt,
  delta : UInt,
  order? : MemoryOrdering = SeqCst,
) -> UInt {
  native_atomic_uint_fetch_add(self, delta, order.code())
}
