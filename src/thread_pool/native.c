#include "../internal/native_sync.h"

typedef void (*sync_call_closure_t)(void *);

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

static void sync_thread_pool_core_release(sync_thread_pool_core_t *core) {
  if (sync_arc_dec(&core->refs) != 0) {
    return;
  }
  for (int32_t index = 0; index < core->length; index += 1) {
    int32_t slot = (core->head + index) % core->capacity;
    moonbit_decref(core->tasks[slot]);
  }
  free(core->tasks);
  sync_os_cond_destroy(&core->stopped);
  sync_os_cond_destroy(&core->not_full);
  sync_os_cond_destroy(&core->not_empty);
  sync_os_mutex_destroy(&core->mutex);
  free(core);
}

static void sync_thread_pool_close_core(sync_thread_pool_core_t *core) {
  sync_os_mutex_lock(&core->mutex);
  core->accepting = 0;
  sync_os_cond_broadcast(&core->not_empty);
  sync_os_cond_broadcast(&core->not_full);
  sync_os_mutex_unlock(&core->mutex);
}

static void sync_thread_pool_finalize(void *self) {
  sync_thread_pool_handle_t *handle = (sync_thread_pool_handle_t *)self;
  if (handle->core != NULL) {
    sync_os_mutex_lock(&handle->core->mutex);
    handle->core->handles -= 1;
    if (handle->core->handles == 0) {
      handle->core->accepting = 0;
      sync_os_cond_broadcast(&handle->core->not_empty);
      sync_os_cond_broadcast(&handle->core->not_full);
    }
    sync_os_mutex_unlock(&handle->core->mutex);
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
    sync_os_mutex_lock(&core->mutex);
    while (core->length == 0 && core->accepting) {
      sync_os_cond_wait(&core->not_empty, &core->mutex);
    }
    if (core->length == 0) {
      core->live_workers -= 1;
      sync_os_cond_broadcast(&core->stopped);
      sync_os_mutex_unlock(&core->mutex);
      break;
    }
    void *task = core->tasks[core->head];
    core->tasks[core->head] = NULL;
    core->head = (core->head + 1) % core->capacity;
    core->length -= 1;
    sync_os_cond_signal(&core->not_full);
    sync_os_mutex_unlock(&core->mutex);

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
  sync_thread_pool_core_t *core = (sync_thread_pool_core_t *)sync_alloc(
    sizeof(sync_thread_pool_core_t)
  );
  core->refs = 1;
  core->call = call;
  core->tasks = (void **)sync_alloc(sizeof(void *) * (size_t)capacity);
  core->capacity = capacity;
  core->worker_count = worker_count;
  core->handles = 1;
  core->accepting = 1;
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->not_empty);
  sync_os_cond_init(&core->not_full);
  sync_os_cond_init(&core->stopped);
  *status = 0;

  for (int32_t index = 0; index < worker_count; index += 1) {
    sync_arc_inc(&core->refs);
    sync_os_mutex_lock(&core->mutex);
    core->live_workers += 1;
    sync_os_mutex_unlock(&core->mutex);
#if defined(_WIN32)
    HANDLE thread = CreateThread(NULL, 0, sync_thread_pool_worker, core, 0, NULL);
    if (thread == NULL) {
      int32_t create_status = (int32_t)GetLastError();
      sync_os_mutex_lock(&core->mutex);
      core->live_workers -= 1;
      sync_os_cond_broadcast(&core->stopped);
      sync_os_mutex_unlock(&core->mutex);
      sync_thread_pool_core_release(core);
      *status = create_status;
      break;
    }
    (void)CloseHandle(thread);
#else
    pthread_t thread;
    int create_status = pthread_create(&thread, NULL, sync_thread_pool_worker, core);
    if (create_status != 0) {
      sync_os_mutex_lock(&core->mutex);
      core->live_workers -= 1;
      sync_os_cond_broadcast(&core->stopped);
      sync_os_mutex_unlock(&core->mutex);
      sync_thread_pool_core_release(core);
      *status = create_status;
      break;
    }
    (void)pthread_detach(thread);
#endif
  }

  if (*status != 0) {
    sync_thread_pool_close_core(core);
  }
  return sync_thread_pool_wrap(core);
}

MOONBIT_FFI_EXPORT sync_thread_pool_handle_t *sync_thread_pool_share(
  sync_thread_pool_handle_t *value
) {
  sync_arc_inc(&value->core->refs);
  sync_os_mutex_lock(&value->core->mutex);
  value->core->handles += 1;
  sync_os_mutex_unlock(&value->core->mutex);
  return sync_thread_pool_wrap(value->core);
}

static int32_t sync_thread_pool_submit_task(
  sync_thread_pool_handle_t *value,
  void *task,
  int32_t block
) {
  sync_thread_pool_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  if (
    block && core->accepting && sync_current_thread_pool == core
    && core->length == core->capacity
  ) {
    sync_os_mutex_unlock(&core->mutex);
    moonbit_decref(task);
    return 3;
  }
  while (block && core->accepting && core->length == core->capacity) {
    sync_os_cond_wait(&core->not_full, &core->mutex);
  }
  int32_t status = 0;
  if (!core->accepting) {
    status = 2;
  } else if (core->length == core->capacity) {
    status = 1;
  } else {
    core->tasks[core->tail] = task;
    core->tail = (core->tail + 1) % core->capacity;
    core->length += 1;
    sync_os_cond_signal(&core->not_empty);
  }
  sync_os_mutex_unlock(&core->mutex);
  if (status != 0) {
    moonbit_decref(task);
  }
  return status;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_try_execute(
  sync_thread_pool_handle_t *value,
  void *task
) {
  return sync_thread_pool_submit_task(value, task, 0);
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_execute(
  sync_thread_pool_handle_t *value,
  void *task
) {
  return sync_thread_pool_submit_task(value, task, 1);
}

MOONBIT_FFI_EXPORT void sync_thread_pool_close(sync_thread_pool_handle_t *value) {
  sync_thread_pool_close_core(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_shutdown(sync_thread_pool_handle_t *value) {
  sync_thread_pool_core_t *core = value->core;
  if (sync_current_thread_pool == core) {
    return -1;
  }
  sync_thread_pool_close_core(core);
  sync_os_mutex_lock(&core->mutex);
  while (core->live_workers != 0) {
    sync_os_cond_wait(&core->stopped, &core->mutex);
  }
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_is_closed(sync_thread_pool_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  int32_t result = !value->core->accepting;
  sync_os_mutex_unlock(&value->core->mutex);
  return result;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_worker_count(sync_thread_pool_handle_t *value) {
  return value->core->worker_count;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_pool_pending_count(sync_thread_pool_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  int32_t result = value->core->length;
  sync_os_mutex_unlock(&value->core->mutex);
  return result;
}
