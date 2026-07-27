#include <moonbit.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef SRWLOCK sync_os_mutex_t;
typedef CONDITION_VARIABLE sync_os_cond_t;
typedef HANDLE sync_os_thread_t;

static void sync_os_mutex_init(sync_os_mutex_t *mutex) { InitializeSRWLock(mutex); }
static void sync_os_mutex_destroy(sync_os_mutex_t *mutex) { (void)mutex; }
static void sync_os_mutex_lock(sync_os_mutex_t *mutex) { AcquireSRWLockExclusive(mutex); }
static void sync_os_mutex_unlock(sync_os_mutex_t *mutex) { ReleaseSRWLockExclusive(mutex); }
static void sync_os_cond_init(sync_os_cond_t *cond) { InitializeConditionVariable(cond); }
static void sync_os_cond_destroy(sync_os_cond_t *cond) { (void)cond; }
static void sync_os_cond_wait(sync_os_cond_t *cond, sync_os_mutex_t *mutex) {
  SleepConditionVariableSRW(cond, mutex, INFINITE, 0);
}
static void sync_os_cond_signal(sync_os_cond_t *cond) { WakeConditionVariable(cond); }
static void sync_os_cond_broadcast(sync_os_cond_t *cond) { WakeAllConditionVariable(cond); }

typedef volatile LONG sync_arc_t;
static int32_t sync_arc_inc(sync_arc_t *value) { return (int32_t)InterlockedIncrement(value); }
static int32_t sync_arc_dec(sync_arc_t *value) { return (int32_t)InterlockedDecrement(value); }

#else

#include <pthread.h>
#include <sched.h>

typedef pthread_mutex_t sync_os_mutex_t;
typedef pthread_cond_t sync_os_cond_t;
typedef pthread_t sync_os_thread_t;

static void sync_os_mutex_init(sync_os_mutex_t *mutex) { (void)pthread_mutex_init(mutex, NULL); }
static void sync_os_mutex_destroy(sync_os_mutex_t *mutex) { (void)pthread_mutex_destroy(mutex); }
static void sync_os_mutex_lock(sync_os_mutex_t *mutex) { (void)pthread_mutex_lock(mutex); }
static void sync_os_mutex_unlock(sync_os_mutex_t *mutex) { (void)pthread_mutex_unlock(mutex); }
static void sync_os_cond_init(sync_os_cond_t *cond) { (void)pthread_cond_init(cond, NULL); }
static void sync_os_cond_destroy(sync_os_cond_t *cond) { (void)pthread_cond_destroy(cond); }
static void sync_os_cond_wait(sync_os_cond_t *cond, sync_os_mutex_t *mutex) {
  (void)pthread_cond_wait(cond, mutex);
}
static void sync_os_cond_signal(sync_os_cond_t *cond) { (void)pthread_cond_signal(cond); }
static void sync_os_cond_broadcast(sync_os_cond_t *cond) { (void)pthread_cond_broadcast(cond); }

typedef int32_t sync_arc_t;
static int32_t sync_arc_inc(sync_arc_t *value) {
  return __atomic_add_fetch(value, 1, __ATOMIC_SEQ_CST);
}
static int32_t sync_arc_dec(sync_arc_t *value) {
  return __atomic_sub_fetch(value, 1, __ATOMIC_SEQ_CST);
}

#endif

static void *sync_alloc(size_t size) {
  void *value = calloc(1, size);
  if (value == NULL) {
    abort();
  }
  return value;
}

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
  observed = (int32_t)InterlockedCompareExchange(&handle->core->value, (LONG)next, (LONG)current);
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

static int32_t sync_atomic_fetch_add_value(sync_atomic_handle_t *handle, int32_t delta, int32_t order) {
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
MOONBIT_FFI_EXPORT void sync_atomic_bool_store(sync_atomic_handle_t *value, int32_t next, int32_t order) {
  sync_atomic_store_value(value, next != 0, order);
}
MOONBIT_FFI_EXPORT int32_t sync_atomic_bool_swap(sync_atomic_handle_t *value, int32_t next, int32_t order) {
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
MOONBIT_FFI_EXPORT void sync_atomic_int_store(sync_atomic_handle_t *value, int32_t next, int32_t order) {
  sync_atomic_store_value(value, next, order);
}
MOONBIT_FFI_EXPORT int32_t sync_atomic_int_swap(sync_atomic_handle_t *value, int32_t next, int32_t order) {
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
MOONBIT_FFI_EXPORT void sync_atomic_uint_store(sync_atomic_handle_t *value, uint32_t next, int32_t order) {
  sync_atomic_store_value(value, (int32_t)next, order);
}
MOONBIT_FFI_EXPORT uint32_t sync_atomic_uint_swap(sync_atomic_handle_t *value, uint32_t next, int32_t order) {
  return (uint32_t)sync_atomic_swap_value(value, (int32_t)next, order);
}
MOONBIT_FFI_EXPORT uint64_t sync_atomic_uint_compare_exchange(
  sync_atomic_handle_t *value,
  uint32_t current,
  uint32_t next,
  int32_t success,
  int32_t failure
) {
  return sync_atomic_compare_exchange_value(value, (int32_t)current, (int32_t)next, success, failure);
}
MOONBIT_FFI_EXPORT uint32_t sync_atomic_uint_fetch_add(
  sync_atomic_handle_t *value,
  uint32_t delta,
  int32_t order
) {
  return (uint32_t)sync_atomic_fetch_add_value(value, (int32_t)delta, order);
}

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  void *value;
} sync_mutex_core_t;

typedef struct {
  sync_mutex_core_t *core;
} sync_mutex_handle_t;

static void sync_mutex_finalize(void *self) {
  sync_mutex_handle_t *handle = (sync_mutex_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    if (handle->core->value != NULL) {
      moonbit_decref(handle->core->value);
    }
    sync_os_mutex_destroy(&handle->core->mutex);
    free(handle->core);
  }
}

static sync_mutex_handle_t *sync_mutex_wrap(sync_mutex_core_t *core) {
  sync_mutex_handle_t *handle = (sync_mutex_handle_t *)moonbit_make_external_object(
    sync_mutex_finalize,
    sizeof(sync_mutex_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_mutex_handle_t *sync_mutex_new(void *value) {
  sync_mutex_core_t *core = (sync_mutex_core_t *)sync_alloc(sizeof(sync_mutex_core_t));
  core->refs = 1;
  core->value = value;
  sync_os_mutex_init(&core->mutex);
  return sync_mutex_wrap(core);
}

MOONBIT_FFI_EXPORT sync_mutex_handle_t *sync_mutex_share(sync_mutex_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_mutex_wrap(value->core);
}

MOONBIT_FFI_EXPORT void *sync_mutex_lock_get(sync_mutex_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  moonbit_incref(value->core->value);
  return value->core->value;
}

MOONBIT_FFI_EXPORT void sync_mutex_release_unlock(sync_mutex_handle_t *value, void *box) {
  moonbit_decref(box);
  sync_os_mutex_unlock(&value->core->mutex);
}

typedef struct {
  sync_arc_t refs;
  sync_os_cond_t cond;
} sync_cond_core_t;

typedef struct {
  sync_cond_core_t *core;
} sync_cond_handle_t;

static void sync_cond_finalize(void *self) {
  sync_cond_handle_t *handle = (sync_cond_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    sync_os_cond_destroy(&handle->core->cond);
    free(handle->core);
  }
}

static sync_cond_handle_t *sync_cond_wrap(sync_cond_core_t *core) {
  sync_cond_handle_t *handle = (sync_cond_handle_t *)moonbit_make_external_object(
    sync_cond_finalize,
    sizeof(sync_cond_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_cond_handle_t *sync_condvar_new(void) {
  sync_cond_core_t *core = (sync_cond_core_t *)sync_alloc(sizeof(sync_cond_core_t));
  core->refs = 1;
  sync_os_cond_init(&core->cond);
  return sync_cond_wrap(core);
}

MOONBIT_FFI_EXPORT sync_cond_handle_t *sync_condvar_share(sync_cond_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_cond_wrap(value->core);
}

MOONBIT_FFI_EXPORT void sync_condvar_wait(
  sync_cond_handle_t *value,
  sync_mutex_handle_t *mutex
) {
  sync_os_cond_wait(&value->core->cond, &mutex->core->mutex);
}

MOONBIT_FFI_EXPORT void sync_condvar_notify_one(sync_cond_handle_t *value) {
  sync_os_cond_signal(&value->core->cond);
}

MOONBIT_FFI_EXPORT void sync_condvar_notify_all(sync_cond_handle_t *value) {
  sync_os_cond_broadcast(&value->core->cond);
}

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t cond;
  int32_t state;
} sync_once_core_t;

typedef struct {
  sync_once_core_t *core;
} sync_once_handle_t;

static void sync_once_finalize(void *self) {
  sync_once_handle_t *handle = (sync_once_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    sync_os_cond_destroy(&handle->core->cond);
    sync_os_mutex_destroy(&handle->core->mutex);
    free(handle->core);
  }
}

static sync_once_handle_t *sync_once_wrap(sync_once_core_t *core) {
  sync_once_handle_t *handle = (sync_once_handle_t *)moonbit_make_external_object(
    sync_once_finalize,
    sizeof(sync_once_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_once_handle_t *sync_once_new(void) {
  sync_once_core_t *core = (sync_once_core_t *)sync_alloc(sizeof(sync_once_core_t));
  core->refs = 1;
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->cond);
  return sync_once_wrap(core);
}

MOONBIT_FFI_EXPORT sync_once_handle_t *sync_once_share(sync_once_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_once_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_once_begin(sync_once_handle_t *value) {
  sync_once_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (core->state == 1) {
    sync_os_cond_wait(&core->cond, &core->mutex);
  }
  if (core->state == 0) {
    core->state = 1;
    sync_os_mutex_unlock(&core->mutex);
    return 1;
  }
  int32_t result = core->state == 2 ? 0 : -1;
  sync_os_mutex_unlock(&core->mutex);
  return result;
}

MOONBIT_FFI_EXPORT void sync_once_complete(sync_once_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  value->core->state = 2;
  sync_os_cond_broadcast(&value->core->cond);
  sync_os_mutex_unlock(&value->core->mutex);
}

MOONBIT_FFI_EXPORT void sync_once_poison(sync_once_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  value->core->state = 3;
  sync_os_cond_broadcast(&value->core->cond);
  sync_os_mutex_unlock(&value->core->mutex);
}

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t cond;
  int32_t count;
} sync_wait_group_core_t;

typedef struct {
  sync_wait_group_core_t *core;
} sync_wait_group_handle_t;

static void sync_wait_group_finalize(void *self) {
  sync_wait_group_handle_t *handle = (sync_wait_group_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    sync_os_cond_destroy(&handle->core->cond);
    sync_os_mutex_destroy(&handle->core->mutex);
    free(handle->core);
  }
}

static sync_wait_group_handle_t *sync_wait_group_wrap(sync_wait_group_core_t *core) {
  sync_wait_group_handle_t *handle = (sync_wait_group_handle_t *)moonbit_make_external_object(
    sync_wait_group_finalize,
    sizeof(sync_wait_group_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_wait_group_handle_t *sync_wait_group_new(void) {
  sync_wait_group_core_t *core = (sync_wait_group_core_t *)sync_alloc(
    sizeof(sync_wait_group_core_t)
  );
  core->refs = 1;
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->cond);
  return sync_wait_group_wrap(core);
}

MOONBIT_FFI_EXPORT sync_wait_group_handle_t *sync_wait_group_share(
  sync_wait_group_handle_t *value
) {
  sync_arc_inc(&value->core->refs);
  return sync_wait_group_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_wait_group_add(sync_wait_group_handle_t *value, int32_t delta) {
  sync_wait_group_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  if (delta < 0 && core->count < -delta) {
    sync_os_mutex_unlock(&core->mutex);
    return 0;
  }
  core->count += delta;
  if (core->count == 0) {
    sync_os_cond_broadcast(&core->cond);
  }
  sync_os_mutex_unlock(&core->mutex);
  return 1;
}

MOONBIT_FFI_EXPORT void sync_wait_group_wait(sync_wait_group_handle_t *value) {
  sync_wait_group_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (core->count != 0) {
    sync_os_cond_wait(&core->cond, &core->mutex);
  }
  sync_os_mutex_unlock(&core->mutex);
}

typedef void (*sync_call_closure_t)(void *);

typedef struct sync_thread_core_s {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_thread_t thread;
  sync_call_closure_t call;
  void *task;
  void *result;
  uint64_t id;
  int32_t started;
  int32_t joined;
} sync_thread_core_t;

typedef struct {
  sync_thread_core_t *core;
} sync_thread_handle_t;

static void sync_thread_core_release(sync_thread_core_t *core) {
  if (sync_arc_dec(&core->refs) == 0) {
    if (core->task != NULL) {
      moonbit_decref(core->task);
    }
    if (core->result != NULL) {
      moonbit_decref(core->result);
    }
    sync_os_mutex_destroy(&core->mutex);
    free(core);
  }
}

static void sync_thread_finalize(void *self) {
  sync_thread_handle_t *handle = (sync_thread_handle_t *)self;
  sync_thread_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_os_mutex_lock(&core->mutex);
  int32_t detach = core->started && !core->joined;
  core->joined = core->joined || detach;
  sync_os_mutex_unlock(&core->mutex);
  if (detach) {
#if defined(_WIN32)
    CloseHandle(core->thread);
#else
    (void)pthread_detach(core->thread);
#endif
  }
  sync_thread_core_release(core);
}

MOONBIT_FFI_EXPORT sync_thread_handle_t *sync_thread_new(void) {
  sync_thread_core_t *core = (sync_thread_core_t *)sync_alloc(sizeof(sync_thread_core_t));
  core->refs = 1;
  sync_os_mutex_init(&core->mutex);
  sync_thread_handle_t *handle = (sync_thread_handle_t *)moonbit_make_external_object(
    sync_thread_finalize,
    sizeof(sync_thread_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_thread_core_t *sync_thread_state(sync_thread_handle_t *value) {
  return value->core;
}

#if defined(_WIN32)
static DWORD WINAPI sync_thread_main(LPVOID arg) {
#else
static void *sync_thread_main(void *arg) {
#endif
  sync_thread_core_t *core = (sync_thread_core_t *)arg;
  core->call(core->task);
  moonbit_decref(core->task);
  sync_os_mutex_lock(&core->mutex);
  core->task = NULL;
  sync_os_mutex_unlock(&core->mutex);
  sync_thread_core_release(core);
#if defined(_WIN32)
  return 0;
#else
  return NULL;
#endif
}

MOONBIT_FFI_EXPORT int32_t sync_thread_start(
  sync_thread_handle_t *value,
  sync_call_closure_t call,
  void *task
) {
  sync_thread_core_t *core = value->core;
  core->call = call;
  core->task = task;
  sync_arc_inc(&core->refs);
#if defined(_WIN32)
  DWORD id = 0;
  core->thread = CreateThread(NULL, 0, sync_thread_main, core, 0, &id);
  if (core->thread == NULL) {
    core->task = NULL;
    moonbit_decref(task);
    sync_thread_core_release(core);
    return (int32_t)GetLastError();
  }
  core->id = (uint64_t)id;
#else
  int status = pthread_create(&core->thread, NULL, sync_thread_main, core);
  if (status != 0) {
    core->task = NULL;
    moonbit_decref(task);
    sync_thread_core_release(core);
    return status;
  }
  memset(&core->id, 0, sizeof(core->id));
  memcpy(&core->id, &core->thread, sizeof(core->thread) < sizeof(core->id)
    ? sizeof(core->thread)
    : sizeof(core->id));
#endif
  core->started = 1;
  return 0;
}

MOONBIT_FFI_EXPORT void sync_thread_complete(sync_thread_core_t *state, void *result) {
  sync_os_mutex_lock(&state->mutex);
  if (state->result == NULL) {
    state->result = result;
  } else {
    moonbit_decref(result);
  }
  sync_os_mutex_unlock(&state->mutex);
}

MOONBIT_FFI_EXPORT void *sync_thread_join(sync_thread_handle_t *value, int32_t *status) {
  sync_thread_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  if (!core->started || core->joined) {
    *status = 1;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  core->joined = 1;
  sync_os_mutex_unlock(&core->mutex);
#if defined(_WIN32)
  DWORD wait_status = WaitForSingleObject(core->thread, INFINITE);
  if (wait_status != WAIT_OBJECT_0) {
    *status = (int32_t)GetLastError();
    return NULL;
  }
  CloseHandle(core->thread);
#else
  int join_status = pthread_join(core->thread, NULL);
  if (join_status != 0) {
    *status = join_status;
    return NULL;
  }
#endif
  sync_os_mutex_lock(&core->mutex);
  void *result = core->result;
  core->result = NULL;
  sync_os_mutex_unlock(&core->mutex);
  *status = 0;
  return result;
}

MOONBIT_FFI_EXPORT uint64_t sync_thread_id(sync_thread_handle_t *value) {
  return value->core->id;
}

MOONBIT_FFI_EXPORT void sync_thread_yield(void) {
#if defined(_WIN32)
  (void)SwitchToThread();
#else
  (void)sched_yield();
#endif
}

MOONBIT_FFI_EXPORT uint64_t sync_current_thread_id(void) {
#if defined(_WIN32)
  return (uint64_t)GetCurrentThreadId();
#else
  pthread_t thread = pthread_self();
  uint64_t id = 0;
  memcpy(&id, &thread, sizeof(thread) < sizeof(id) ? sizeof(thread) : sizeof(id));
  return id;
#endif
}

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t readable;
  sync_os_cond_t writable;
  void **slots;
  int32_t capacity;
  int32_t head;
  int32_t tail;
  int32_t count;
  int32_t senders;
  int32_t receiver_alive;
  int32_t closed;
} sync_channel_core_t;

typedef struct {
  sync_channel_core_t *core;
  int32_t role;
} sync_channel_handle_t;

static void sync_channel_core_release(sync_channel_core_t *core) {
  if (sync_arc_dec(&core->refs) == 0) {
    for (int32_t i = 0; i < core->capacity; ++i) {
      if (core->slots[i] != NULL) {
        moonbit_decref(core->slots[i]);
      }
    }
    free(core->slots);
    sync_os_cond_destroy(&core->writable);
    sync_os_cond_destroy(&core->readable);
    sync_os_mutex_destroy(&core->mutex);
    free(core);
  }
}

static void sync_channel_finalize(void *self) {
  sync_channel_handle_t *handle = (sync_channel_handle_t *)self;
  sync_channel_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_os_mutex_lock(&core->mutex);
  if (handle->role == 1) {
    core->senders -= 1;
    if (core->senders == 0) {
      core->closed = 1;
      sync_os_cond_broadcast(&core->readable);
      sync_os_cond_broadcast(&core->writable);
    }
  } else if (handle->role == 2 && core->receiver_alive) {
    core->receiver_alive = 0;
    core->closed = 1;
    sync_os_cond_broadcast(&core->readable);
    sync_os_cond_broadcast(&core->writable);
  }
  sync_os_mutex_unlock(&core->mutex);
  sync_channel_core_release(core);
}

static sync_channel_handle_t *sync_channel_wrap(sync_channel_core_t *core, int32_t role) {
  sync_channel_handle_t *handle = (sync_channel_handle_t *)moonbit_make_external_object(
    sync_channel_finalize,
    sizeof(sync_channel_handle_t)
  );
  handle->core = core;
  handle->role = role;
  return handle;
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_new(int32_t capacity) {
  sync_channel_core_t *core = (sync_channel_core_t *)sync_alloc(sizeof(sync_channel_core_t));
  core->refs = 1;
  core->capacity = capacity;
  core->senders = 1;
  core->slots = (void **)sync_alloc((size_t)capacity * sizeof(void *));
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->readable);
  sync_os_cond_init(&core->writable);
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_receiver(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->receiver_alive = 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_channel_wrap(core, 2);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_sender_share(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->senders += 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT int32_t sync_sender_try_send(
  sync_channel_handle_t *value,
  void *message
) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  if (core->closed || !core->receiver_alive) {
    sync_os_mutex_unlock(&core->mutex);
    return 2;
  }
  if (core->count == core->capacity) {
    sync_os_mutex_unlock(&core->mutex);
    return 1;
  }
  moonbit_incref(message);
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_os_cond_signal(&core->readable);
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t sync_sender_send(sync_channel_handle_t *value, void *message) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (core->count == core->capacity && !core->closed && core->receiver_alive) {
    sync_os_cond_wait(&core->writable, &core->mutex);
  }
  if (core->closed || !core->receiver_alive) {
    sync_os_mutex_unlock(&core->mutex);
    return 2;
  }
  moonbit_incref(message);
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_os_cond_signal(&core->readable);
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT void sync_sender_close(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

static void *sync_channel_recv(sync_channel_handle_t *value, int32_t *status, int32_t block) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (block && core->count == 0 && !core->closed) {
    sync_os_cond_wait(&core->readable, &core->mutex);
  }
  if (core->count == 0) {
    *status = core->closed ? 2 : 1;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  void *message = core->slots[core->head];
  core->slots[core->head] = NULL;
  core->head = (core->head + 1) % core->capacity;
  core->count -= 1;
  *status = 0;
  sync_os_cond_signal(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
  return message;
}

MOONBIT_FFI_EXPORT void *sync_receiver_try_recv(
  sync_channel_handle_t *value,
  int32_t *status
) {
  return sync_channel_recv(value, status, 0);
}

MOONBIT_FFI_EXPORT void *sync_receiver_recv(sync_channel_handle_t *value, int32_t *status) {
  return sync_channel_recv(value, status, 1);
}

MOONBIT_FFI_EXPORT void sync_receiver_close(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  core->receiver_alive = 0;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_len(sync_channel_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  int32_t count = value->core->count;
  sync_os_mutex_unlock(&value->core->mutex);
  return count;
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_capacity(sync_channel_handle_t *value) {
  return value->core->capacity;
}
