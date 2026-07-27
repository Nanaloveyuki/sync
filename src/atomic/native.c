#include "../internal/native_internal.h"

#if !defined(_WIN32)
static int sync_memory_order(int32_t order) {
  switch (order) {
  case 0: return __ATOMIC_RELAXED;
  case 1: return __ATOMIC_ACQUIRE;
  case 2: return __ATOMIC_RELEASE;
  case 3: return __ATOMIC_ACQ_REL;
  default: return __ATOMIC_SEQ_CST;
  }
}
#endif

typedef struct {
  sync_arc_t refs;
#if defined(_WIN32)
  volatile LONG value;
#else
  int32_t value;
#endif
} sync_atomic_core_t;

typedef struct {
  sync_atomic_core_t *core;
} sync_atomic_handle_t;

static void sync_atomic_finalize(void *self) {
  sync_atomic_handle_t *handle = (sync_atomic_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    free(handle->core);
  }
}

static sync_atomic_handle_t *sync_atomic_wrap(sync_atomic_core_t *core) {
  sync_atomic_handle_t *handle = (sync_atomic_handle_t *)moonbit_make_external_object(
    sync_atomic_finalize,
    sizeof(sync_atomic_handle_t)
  );
  handle->core = core;
  return handle;
}

static sync_atomic_handle_t *sync_atomic_new(int32_t value) {
  sync_atomic_core_t *core = (sync_atomic_core_t *)sync_alloc(sizeof(sync_atomic_core_t));
  core->refs = 1;
  core->value = value;
  return sync_atomic_wrap(core);
}

static sync_atomic_handle_t *sync_atomic_share(sync_atomic_handle_t *handle) {
  sync_arc_inc(&handle->core->refs);
  return sync_atomic_wrap(handle->core);
}

static int32_t sync_atomic_load_value(sync_atomic_handle_t *handle, int32_t order) {
#if defined(_WIN32)
  (void)order;
  return (int32_t)InterlockedCompareExchange(&handle->core->value, 0, 0);
#else
  return __atomic_load_n(&handle->core->value, sync_memory_order(order));
#endif
}

static void sync_atomic_store_value(sync_atomic_handle_t *handle, int32_t value, int32_t order) {
#if defined(_WIN32)
  (void)order;
  (void)InterlockedExchange(&handle->core->value, (LONG)value);
#else
  __atomic_store_n(&handle->core->value, value, sync_memory_order(order));
#endif
}

static int32_t sync_atomic_swap_value(sync_atomic_handle_t *handle, int32_t value, int32_t order) {
#if defined(_WIN32)
  (void)order;
  return (int32_t)InterlockedExchange(&handle->core->value, (LONG)value);
#else
  return __atomic_exchange_n(&handle->core->value, value, sync_memory_order(order));
#endif
}

static uint64_t sync_atomic_compare_exchange_value(
  sync_atomic_handle_t *handle,
  int32_t current,
  int32_t next,
  int32_t success,
  int32_t failure
) {
  int32_t observed = current;
  int exchanged;
#if defined(_WIN32)
  (void)success;
  (void)failure;
  observed = (int32_t)InterlockedCompareExchange(
    &handle->core->value,
    (LONG)next,
    (LONG)current
  );
  exchanged = observed == current;
#else
  exchanged = __atomic_compare_exchange_n(
    &handle->core->value,
    &observed,
    next,
    0,
    sync_memory_order(success),
    sync_memory_order(failure)
  );
#endif
  return ((uint64_t)(exchanged != 0) << 32) | (uint32_t)observed;
}

static int32_t sync_atomic_fetch_add_value(
  sync_atomic_handle_t *handle,
  int32_t delta,
  int32_t order
) {
#if defined(_WIN32)
  (void)order;
  return (int32_t)InterlockedExchangeAdd(&handle->core->value, (LONG)delta);
#else
  return __atomic_fetch_add(&handle->core->value, delta, sync_memory_order(order));
#endif
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_bool_new(int32_t value) {
  return sync_atomic_new(value != 0);
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_bool_share(sync_atomic_handle_t *value) {
  return sync_atomic_share(value);
}

MOONBIT_FFI_EXPORT int32_t sync_atomic_bool_load(sync_atomic_handle_t *value, int32_t order) {
  return sync_atomic_load_value(value, order) != 0;
}

MOONBIT_FFI_EXPORT void sync_atomic_bool_store(
  sync_atomic_handle_t *value,
  int32_t next,
  int32_t order
) {
  sync_atomic_store_value(value, next != 0, order);
}

MOONBIT_FFI_EXPORT int32_t sync_atomic_bool_swap(
  sync_atomic_handle_t *value,
  int32_t next,
  int32_t order
) {
  return sync_atomic_swap_value(value, next != 0, order) != 0;
}

MOONBIT_FFI_EXPORT uint64_t sync_atomic_bool_compare_exchange(
  sync_atomic_handle_t *value,
  int32_t current,
  int32_t next,
  int32_t success,
  int32_t failure
) {
  return sync_atomic_compare_exchange_value(value, current != 0, next != 0, success, failure);
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_int_new(int32_t value) {
  return sync_atomic_new(value);
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_int_share(sync_atomic_handle_t *value) {
  return sync_atomic_share(value);
}

MOONBIT_FFI_EXPORT int32_t sync_atomic_int_load(sync_atomic_handle_t *value, int32_t order) {
  return sync_atomic_load_value(value, order);
}

MOONBIT_FFI_EXPORT void sync_atomic_int_store(
  sync_atomic_handle_t *value,
  int32_t next,
  int32_t order
) {
  sync_atomic_store_value(value, next, order);
}

MOONBIT_FFI_EXPORT int32_t sync_atomic_int_swap(
  sync_atomic_handle_t *value,
  int32_t next,
  int32_t order
) {
  return sync_atomic_swap_value(value, next, order);
}

MOONBIT_FFI_EXPORT uint64_t sync_atomic_int_compare_exchange(
  sync_atomic_handle_t *value,
  int32_t current,
  int32_t next,
  int32_t success,
  int32_t failure
) {
  return sync_atomic_compare_exchange_value(value, current, next, success, failure);
}

MOONBIT_FFI_EXPORT int32_t sync_atomic_int_fetch_add(
  sync_atomic_handle_t *value,
  int32_t delta,
  int32_t order
) {
  return sync_atomic_fetch_add_value(value, delta, order);
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_uint_new(uint32_t value) {
  return sync_atomic_new((int32_t)value);
}

MOONBIT_FFI_EXPORT sync_atomic_handle_t *sync_atomic_uint_share(sync_atomic_handle_t *value) {
  return sync_atomic_share(value);
}

MOONBIT_FFI_EXPORT uint32_t sync_atomic_uint_load(sync_atomic_handle_t *value, int32_t order) {
  return (uint32_t)sync_atomic_load_value(value, order);
}

MOONBIT_FFI_EXPORT void sync_atomic_uint_store(
  sync_atomic_handle_t *value,
  uint32_t next,
  int32_t order
) {
  sync_atomic_store_value(value, (int32_t)next, order);
}

MOONBIT_FFI_EXPORT uint32_t sync_atomic_uint_swap(
  sync_atomic_handle_t *value,
  uint32_t next,
  int32_t order
) {
  return (uint32_t)sync_atomic_swap_value(value, (int32_t)next, order);
}

MOONBIT_FFI_EXPORT uint64_t sync_atomic_uint_compare_exchange(
  sync_atomic_handle_t *value,
  uint32_t current,
  uint32_t next,
  int32_t success,
  int32_t failure
) {
  return sync_atomic_compare_exchange_value(
    value,
    (int32_t)current,
    (int32_t)next,
    success,
    failure
  );
}

MOONBIT_FFI_EXPORT uint32_t sync_atomic_uint_fetch_add(
  sync_atomic_handle_t *value,
  uint32_t delta,
  int32_t order
) {
  return (uint32_t)sync_atomic_fetch_add_value(value, (int32_t)delta, order);
}
