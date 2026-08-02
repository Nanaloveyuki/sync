#include "../../internal/native_sync.h"

typedef void (*sync_call_closure_t)(void *);

#define SYNC_THREAD_POOL_MAX_WORKER_COUNT 64
#define SYNC_THREAD_POOL_MAX_CAPACITY 16384
#define SYNC_THREAD_POOL_ALLOCATION_FAILED (-2)

static int32_t sync_thread_pool_test_alloc_fail_after = -1;
static int32_t sync_thread_pool_test_next_submit_error = 0;
static int32_t sync_thread_pool_test_next_shutdown_error = 0;

static int32_t sync_thread_pool_take_test_error(int32_t *next_error) {
  int32_t status = *next_error;
  *next_error = 0;
  return status;
}

typedef struct sync_thread_pool_core_s {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t not_empty;
  sync_os_cond_t not_full;
  sync_os_cond_t stopped;
  sync_call_closure_t call;
  void **tasks;
  int32_t capacity;
  int32_t head;
  int32_t tail;
  int32_t length;
  int32_t worker_count;
  int32_t live_workers;
  int32_t handles;
  int32_t accepting;
} sync_thread_pool_core_t;

typedef struct {
  sync_thread_pool_core_t *core;
} sync_thread_pool_handle_t;

#if defined(_WIN32)
static __declspec(thread) sync_thread_pool_core_t *sync_current_thread_pool;
#else
static _Thread_local sync_thread_pool_core_t *sync_current_thread_pool;
#endif

static void sync_thread_pool_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_thread_pool_record_error(int32_t *status, int32_t candidate) {
  if (*status == 0 && candidate != 0) {
    *status = candidate;
  }
}

static void sync_thread_pool_lock_or_abort(sync_thread_pool_core_t *core) {
  sync_thread_pool_abort_if_failed(sync_os_mutex_lock(&core->mutex));
}

static void sync_thread_pool_unlock_or_abort(sync_thread_pool_core_t *core) {
  sync_thread_pool_abort_if_failed(sync_os_mutex_unlock(&core->mutex));
}

static void *sync_thread_pool_try_alloc(size_t size) {
  if (sync_thread_pool_test_alloc_fail_after == 0) {
    sync_thread_pool_test_alloc_fail_after = -1;
    return NULL;
  }
  if (sync_thread_pool_test_alloc_fail_after > 0) {
    sync_thread_pool_test_alloc_fail_after -= 1;
  }
  return sync_try_alloc(size);
}

static void sync_thread_pool_core_release(sync_thread_pool_core_t *core) {
  if (sync_arc_dec(&core->refs) != 0) {
    return;
  }
  for (int32_t index = 0; index < core->length; index += 1) {
    int32_t slot = (core->head + index) % core->capacity;
    moonbit_decref(core->tasks[slot]);
  }
  free(core->tasks);
  sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->stopped));
  sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->not_full));
  sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->not_empty));
  sync_thread_pool_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
  free(core);
}

static int32_t sync_thread_pool_close_core(sync_thread_pool_core_t *core) {
  int32_t status = sync_os_mutex_lock(&core->mutex);
  if (status != 0) {
    return status;
  }
  core->accepting = 0;
  sync_thread_pool_record_error(&status, sync_os_cond_broadcast(&core->not_empty));
  sync_thread_pool_record_error(&status, sync_os_cond_broadcast(&core->not_full));
  sync_thread_pool_record_error(&status, sync_os_mutex_unlock(&core->mutex));
  return status;
}

static void sync_thread_pool_close_core_or_abort(sync_thread_pool_core_t *core) {
  sync_thread_pool_abort_if_failed(sync_thread_pool_close_core(core));
}

static void sync_thread_pool_wait_workers_or_abort(sync_thread_pool_core_t *core) {
  sync_thread_pool_lock_or_abort(core);
  while (core->live_workers != 0) {
    sync_thread_pool_abort_if_failed(sync_os_cond_wait(&core->stopped, &core->mutex));
  }
  sync_thread_pool_unlock_or_abort(core);
}

static void sync_thread_pool_finalize(void *self) {
  sync_thread_pool_handle_t *handle = (sync_thread_pool_handle_t *)self;
  if (handle->core != NULL) {
    sync_thread_pool_lock_or_abort(handle->core);
    if (handle->core->handles <= 0) {
      sync_thread_pool_unlock_or_abort(handle->core);
      abort();
    }
    handle->core->handles -= 1;
    if (handle->core->handles == 0) {
      handle->core->accepting = 0;
      sync_thread_pool_abort_if_failed(sync_os_cond_broadcast(&handle->core->not_empty));
      sync_thread_pool_abort_if_failed(sync_os_cond_broadcast(&handle->core->not_full));
    }
    sync_thread_pool_unlock_or_abort(handle->core);
    sync_thread_pool_core_release(handle->core);
  }
}

static sync_thread_pool_handle_t *sync_thread_pool_wrap(sync_thread_pool_core_t *core) {
  sync_thread_pool_handle_t *handle = (sync_thread_pool_handle_t *)moonbit_make_external_object(
    sync_thread_pool_finalize,
    sizeof(sync_thread_pool_handle_t)
  );
  handle->core = core;
  return handle;
}

#if defined(_WIN32)
static DWORD WINAPI sync_thread_pool_worker(LPVOID arg) {
#else
static void *sync_thread_pool_worker(void *arg) {
#endif
  sync_thread_pool_core_t *core = (sync_thread_pool_core_t *)arg;
  sync_current_thread_pool = core;
  for (;;) {
    sync_thread_pool_lock_or_abort(core);
    while (core->length == 0 && core->accepting) {
      sync_thread_pool_abort_if_failed(sync_os_cond_wait(&core->not_empty, &core->mutex));
    }
    if (core->length == 0) {
      core->live_workers -= 1;
      sync_thread_pool_abort_if_failed(sync_os_cond_broadcast(&core->stopped));
      sync_thread_pool_unlock_or_abort(core);
      break;
    }
    void *task = core->tasks[core->head];
    core->tasks[core->head] = NULL;
    core->head = (core->head + 1) % core->capacity;
    core->length -= 1;
    sync_thread_pool_abort_if_failed(sync_os_cond_signal(&core->not_full));
    sync_thread_pool_unlock_or_abort(core);

    core->call(task);
    moonbit_decref(task);
  }
  sync_current_thread_pool = NULL;
  sync_thread_pool_core_release(core);
#if defined(_WIN32)
  return 0;
#else
  return NULL;
#endif
}

MOONBIT_FFI_EXPORT sync_thread_pool_handle_t *sync_thread_pool_new(
  int32_t worker_count,
  int32_t capacity,
  sync_call_closure_t call,
  int32_t *status
) {
  if (worker_count <= 0 || worker_count > SYNC_THREAD_POOL_MAX_WORKER_COUNT ||
      capacity <= 0 || capacity > SYNC_THREAD_POOL_MAX_CAPACITY ||
      (size_t)capacity > SIZE_MAX / sizeof(void *)) {
    *status = -1;
    return NULL;
  }
  sync_thread_pool_core_t *core = (sync_thread_pool_core_t *)sync_thread_pool_try_alloc(
    sizeof(sync_thread_pool_core_t)
  );
  if (core == NULL) {
    *status = SYNC_THREAD_POOL_ALLOCATION_FAILED;
    return NULL;
  }
  core->refs = 1;
  core->call = call;
  core->tasks = (void **)sync_thread_pool_try_alloc((size_t)capacity * sizeof(void *));
  if (core->tasks == NULL) {
    free(core);
    *status = SYNC_THREAD_POOL_ALLOCATION_FAILED;
    return NULL;
  }
  core->capacity = capacity;
  core->worker_count = worker_count;
  core->handles = 1;
  core->accepting = 1;
  *status = sync_os_mutex_init(&core->mutex);
  if (*status != 0) {
    free(core->tasks);
    free(core);
    return NULL;
  }
  *status = sync_os_cond_init(&core->not_empty);
  if (*status != 0) {
    sync_thread_pool_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core->tasks);
    free(core);
    return NULL;
  }
  *status = sync_os_cond_init(&core->not_full);
  if (*status != 0) {
    sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->not_empty));
    sync_thread_pool_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core->tasks);
    free(core);
    return NULL;
  }
  *status = sync_os_cond_init(&core->stopped);
  if (*status != 0) {
    sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->not_full));
    sync_thread_pool_abort_if_failed(sync_os_cond_destroy(&core->not_empty));
    sync_thread_pool_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core->tasks);
    free(core);
    return NULL;
  }

  for (int32_t index = 0; index < worker_count; index += 1) {
    sync_arc_inc(&core->refs);
    sync_thread_pool_lock_or_abort(core);
    core->live_workers += 1;
    sync_thread_pool_unlock_or_abort(core);
#if defined(_WIN32)
    HANDLE thread = CreateThread(NULL, 0, sync_thread_pool_worker, core, 0, NULL);
    if (thread == NULL) {
      int32_t create_status = (int32_t)GetLastError();
      sync_thread_pool_lock_or_abort(core);
      core->live_workers -= 1;
      sync_thread_pool_unlock_or_abort(core);
      sync_thread_pool_core_release(core);
      sync_thread_pool_close_core_or_abort(core);
      sync_thread_pool_wait_workers_or_abort(core);
      sync_thread_pool_core_release(core);
      *status = create_status;
      return NULL;
    }
    sync_thread_pool_abort_if_failed(CloseHandle(thread) ? 0 : (int32_t)GetLastError());
#else
    pthread_t thread;
    int create_status = pthread_create(&thread, NULL, sync_thread_pool_worker, core);
    if (create_status != 0) {
      sync_thread_pool_lock_or_abort(core);
      core->live_workers -= 1;
      sync_thread_pool_unlock_or_abort(core);
      sync_thread_pool_core_release(core);
      sync_thread_pool_close_core_or_abort(core);
      sync_thread_pool_wait_workers_or_abort(core);
      sync_thread_pool_core_release(core);
      *status = create_status;
      return NULL;
    }
    sync_thread_pool_abort_if_failed(pthread_detach(thread));
#endif
  }
  *status = 0;
  return sync_thread_pool_wrap(core);
}

MOONBIT_FFI_EXPORT sync_thread_pool_handle_t *sync_thread_pool_share(
  sync_thread_pool_handle_t *value,
  int32_t *status
) {
  sync_thread_pool_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return NULL;
  }
  if (core->handles == INT32_MAX) {
    sync_thread_pool_record_error(status, sync_os_mutex_unlock(&core->mutex));
    if (*status == 0) {
      *status = -1;
    }
    return NULL;
  }
  core->handles += 1;
  sync_arc_inc(&core->refs);
  sync_thread_pool_abort_if_failed(sync_os_mutex_unlock(&core->mutex));
  return sync_thread_pool_wrap(core);
}

static int32_t sync_thread_pool_submit_task(
  sync_thread_pool_handle_t *value,
  void *task,
  int32_t block,
  int32_t *error
) {
  sync_thread_pool_core_t *core = value->core;
  *error = sync_thread_pool_take_test_error(
    &sync_thread_pool_test_next_submit_error
  );
  if (*error != 0) {
    moonbit_decref(task);
    return 2;
  }
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    moonbit_decref(task);
    return 2;
  }
  if (
    block && core->accepting && sync_current_thread_pool == core
    && core->length == core->capacity
  ) {
    sync_thread_pool_record_error(error, sync_os_mutex_unlock(&core->mutex));
    moonbit_decref(task);
    return 3;
  }
  while (block && core->accepting && core->length == core->capacity) {
    int32_t wait_status = sync_os_cond_wait(&core->not_full, &core->mutex);
    if (wait_status != 0) {
      sync_thread_pool_record_error(error, wait_status);
      sync_thread_pool_record_error(error, sync_os_mutex_unlock(&core->mutex));
      moonbit_decref(task);
      return 2;
    }
  }
  int32_t result = 0;
  if (!core->accepting) {
    result = 2;
  } else if (core->length == core->capacity) {
    result = 1;
  } else {
    core->tasks[core->tail] = task;
    core->tail = (core->tail + 1) % core->capacity;
    core->length += 1;
    sync_thread_pool_record_error(error, sync_os_cond_signal(&core->not_empty));
  }
  sync_thread_pool_record_error(error, sync_os_mutex_unlock(&core->mutex));
  if (result != 0) {
    moonbit_decref(task);
  }
  return result;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_try_execute(
  sync_thread_pool_handle_t *value,
  void *task,
  int32_t *error
) {
  return sync_thread_pool_submit_task(value, task, 0, error);
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_execute(
  sync_thread_pool_handle_t *value,
  void *task,
  int32_t *error
) {
  return sync_thread_pool_submit_task(value, task, 1, error);
}

MOONBIT_FFI_EXPORT void sync_thread_pool_close(
  sync_thread_pool_handle_t *value,
  int32_t *status
) {
  *status = sync_thread_pool_close_core(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_shutdown(
  sync_thread_pool_handle_t *value,
  int32_t *status
) {
  sync_thread_pool_core_t *core = value->core;
  *status = sync_thread_pool_take_test_error(
    &sync_thread_pool_test_next_shutdown_error
  );
  if (*status != 0) {
    return 0;
  }
  if (sync_current_thread_pool == core) {
    return -1;
  }
  *status = sync_thread_pool_close_core(core);
  if (*status != 0) {
    return 0;
  }
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  while (core->live_workers != 0) {
    int32_t wait_status = sync_os_cond_wait(&core->stopped, &core->mutex);
    if (wait_status != 0) {
      sync_thread_pool_record_error(status, wait_status);
      break;
    }
  }
  sync_thread_pool_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return 0;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_is_closed(
  sync_thread_pool_handle_t *value,
  int32_t *status
) {
  sync_thread_pool_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  int32_t result = !core->accepting;
  sync_thread_pool_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return result;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_worker_count(sync_thread_pool_handle_t *value) {
  return value->core->worker_count;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_pending_count(
  sync_thread_pool_handle_t *value,
  int32_t *status
) {
  sync_thread_pool_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  int32_t count = core->length;
  sync_thread_pool_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return count;
}

MOONBIT_FFI_EXPORT void sync_thread_pool_test_fail_alloc_after(
  int32_t successful_allocations
) {
  sync_thread_pool_test_alloc_fail_after = successful_allocations;
}

MOONBIT_FFI_EXPORT void sync_thread_pool_test_fail_next_submit(int32_t status) {
  sync_thread_pool_test_next_submit_error = status;
}

MOONBIT_FFI_EXPORT void sync_thread_pool_test_fail_next_shutdown(int32_t status) {
  sync_thread_pool_test_next_shutdown_error = status;
}
