#include "../internal/native_sync.h"

#include <string.h>

#if defined(_WIN32)
typedef HANDLE sync_os_thread_t;
#else
#include <sched.h>
typedef pthread_t sync_os_thread_t;
#endif

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
    (void)CloseHandle(core->thread);
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
  memcpy(
    &core->id,
    &core->thread,
    sizeof(core->thread) < sizeof(core->id) ? sizeof(core->thread) : sizeof(core->id)
  );
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
    *status = -1;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
#if defined(_WIN32)
  int32_t joining_self =
    (uint64_t)GetCurrentThreadId() == core->id
    && WaitForSingleObject(core->thread, 0) == WAIT_TIMEOUT;
#else
  int32_t joining_self = pthread_equal(pthread_self(), core->thread);
#endif
  if (joining_self) {
    *status = -2;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  core->joined = 1;
  sync_os_mutex_unlock(&core->mutex);
#if defined(_WIN32)
  DWORD wait_status = WaitForSingleObject(core->thread, INFINITE);
  if (wait_status != WAIT_OBJECT_0) {
    *status = (int32_t)GetLastError();
    sync_os_mutex_lock(&core->mutex);
    core->joined = 0;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  (void)CloseHandle(core->thread);
#else
  int join_status = pthread_join(core->thread, NULL);
  if (join_status != 0) {
    *status = join_status;
    sync_os_mutex_lock(&core->mutex);
    core->joined = 0;
    sync_os_mutex_unlock(&core->mutex);
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
