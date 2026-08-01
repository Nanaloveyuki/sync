#include "../../internal/native_sync.h"

#include <string.h>

#if defined(_WIN32)
typedef HANDLE sync_os_thread_t;
#else
#include <sched.h>
typedef pthread_t sync_os_thread_t;
#endif

typedef void (*sync_call_closure_t)(void *);

#define SYNC_THREAD_CREATED 0
#define SYNC_THREAD_JOINABLE 1
#define SYNC_THREAD_JOINING 2
#define SYNC_THREAD_DETACHING 3
#define SYNC_THREAD_JOINED 4
#define SYNC_THREAD_DETACHED 5
#define SYNC_THREAD_FAILED 6

typedef struct sync_thread_core_s {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  int32_t mutex_initialized;
  sync_os_thread_t thread;
  sync_call_closure_t call;
  void *task;
  void *result;
  uint64_t id;
  int32_t started;
  int32_t finished;
  int32_t state;
} sync_thread_core_t;

typedef struct {
  sync_thread_core_t *core;
} sync_thread_handle_t;

static int32_t sync_thread_test_next_start_error = 0;
static int32_t sync_thread_test_next_join_error = 0;
static int32_t sync_thread_test_next_detach_error = 0;

static void sync_thread_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_thread_lock_or_abort(sync_thread_core_t *core) {
  sync_thread_abort_if_failed(sync_os_mutex_lock(&core->mutex));
}

static void sync_thread_unlock_or_abort(sync_thread_core_t *core) {
  sync_thread_abort_if_failed(sync_os_mutex_unlock(&core->mutex));
}

static void sync_thread_core_release(sync_thread_core_t *core) {
  if (sync_arc_dec(&core->refs) != 0) {
    return;
  }
  if (core->task != NULL) {
    moonbit_decref(core->task);
  }
  if (core->result != NULL) {
    moonbit_decref(core->result);
  }
  if (core->mutex_initialized) {
    sync_thread_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
  }
  free(core);
}

static void sync_thread_finalize(void *self) {
  sync_thread_handle_t *handle = (sync_thread_handle_t *)self;
  sync_thread_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_thread_lock_or_abort(core);
  int32_t terminal =
    core->state == SYNC_THREAD_JOINED ||
    core->state == SYNC_THREAD_DETACHED ||
    core->state == SYNC_THREAD_FAILED;
  sync_thread_unlock_or_abort(core);
  if (!terminal) {
    abort();
  }
  sync_thread_core_release(core);
}

static sync_thread_handle_t *sync_thread_wrap(sync_thread_core_t *core) {
  sync_thread_handle_t *handle = (sync_thread_handle_t *)moonbit_make_external_object(
    sync_thread_finalize,
    sizeof(sync_thread_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_thread_handle_t *sync_thread_new(int32_t *status) {
  sync_thread_core_t *core = (sync_thread_core_t *)sync_alloc(sizeof(sync_thread_core_t));
  core->refs = 1;
  core->state = SYNC_THREAD_CREATED;
  *status = sync_os_mutex_init(&core->mutex);
  if (*status != 0) {
    free(core);
    return NULL;
  }
  core->mutex_initialized = 1;
  return sync_thread_wrap(core);
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
  sync_thread_lock_or_abort(core);
  core->task = NULL;
  sync_thread_unlock_or_abort(core);
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
  if (sync_thread_test_next_start_error != 0) {
    int32_t status = sync_thread_test_next_start_error;
    sync_thread_test_next_start_error = 0;
    core->task = NULL;
    moonbit_decref(task);
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_FAILED;
    sync_thread_unlock_or_abort(core);
    sync_thread_core_release(core);
    return status;
  }
#if defined(_WIN32)
  DWORD id = 0;
  core->thread = CreateThread(NULL, 0, sync_thread_main, core, 0, &id);
  if (core->thread == NULL) {
    int32_t status = (int32_t)GetLastError();
    core->task = NULL;
    moonbit_decref(task);
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_FAILED;
    sync_thread_unlock_or_abort(core);
    sync_thread_core_release(core);
    return status;
  }
  core->id = (uint64_t)id;
#else
  int status = pthread_create(&core->thread, NULL, sync_thread_main, core);
  if (status != 0) {
    core->task = NULL;
    moonbit_decref(task);
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_FAILED;
    sync_thread_unlock_or_abort(core);
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
  sync_thread_lock_or_abort(core);
  core->started = 1;
  core->state = SYNC_THREAD_JOINABLE;
  sync_thread_unlock_or_abort(core);
  return 0;
}

MOONBIT_FFI_EXPORT void sync_thread_complete(sync_thread_core_t *state, void *result) {
  sync_thread_lock_or_abort(state);
  if (state->result == NULL) {
    state->result = result;
  } else {
    moonbit_decref(result);
  }
  state->finished = 1;
  sync_thread_unlock_or_abort(state);
}

MOONBIT_FFI_EXPORT void *sync_thread_join(sync_thread_handle_t *value, int32_t *status) {
  sync_thread_core_t *core = value->core;
  sync_thread_lock_or_abort(core);
  if (!core->started || core->state == SYNC_THREAD_FAILED ||
      core->state == SYNC_THREAD_JOINED) {
    *status = -1;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
  if (core->state == SYNC_THREAD_DETACHED) {
    *status = -3;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
  if (core->state == SYNC_THREAD_JOINING || core->state == SYNC_THREAD_DETACHING) {
    *status = -4;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
#if defined(_WIN32)
  int32_t joining_self =
    (uint64_t)GetCurrentThreadId() == core->id &&
    WaitForSingleObject(core->thread, 0) == WAIT_TIMEOUT;
#else
  int32_t joining_self = pthread_equal(pthread_self(), core->thread);
#endif
  if (joining_self) {
    *status = -2;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
  if (sync_thread_test_next_join_error != 0) {
    *status = sync_thread_test_next_join_error;
    sync_thread_test_next_join_error = 0;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
  core->state = SYNC_THREAD_JOINING;
  sync_thread_unlock_or_abort(core);
#if defined(_WIN32)
  DWORD wait_status = WaitForSingleObject(core->thread, INFINITE);
  if (wait_status != WAIT_OBJECT_0) {
    *status = (int32_t)GetLastError();
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
  if (!CloseHandle(core->thread)) {
    *status = (int32_t)GetLastError();
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
#else
  int join_status = pthread_join(core->thread, NULL);
  if (join_status != 0) {
    *status = join_status;
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return NULL;
  }
#endif
  sync_thread_lock_or_abort(core);
  void *result = core->result;
  core->result = NULL;
  core->state = SYNC_THREAD_JOINED;
  sync_thread_unlock_or_abort(core);
  *status = 0;
  return result;
}

MOONBIT_FFI_EXPORT void sync_thread_detach(sync_thread_handle_t *value, int32_t *status) {
  sync_thread_core_t *core = value->core;
  sync_thread_lock_or_abort(core);
  if (!core->started || core->state == SYNC_THREAD_FAILED ||
      core->state == SYNC_THREAD_JOINED) {
    *status = -1;
    sync_thread_unlock_or_abort(core);
    return;
  }
  if (core->state == SYNC_THREAD_DETACHED) {
    *status = -2;
    sync_thread_unlock_or_abort(core);
    return;
  }
  if (core->state == SYNC_THREAD_JOINING || core->state == SYNC_THREAD_DETACHING) {
    *status = -3;
    sync_thread_unlock_or_abort(core);
    return;
  }
  core->state = SYNC_THREAD_DETACHING;
  int32_t injected = sync_thread_test_next_detach_error;
  sync_thread_test_next_detach_error = 0;
  sync_thread_unlock_or_abort(core);
  if (injected != 0) {
    *status = injected;
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return;
  }
#if defined(_WIN32)
  if (!CloseHandle(core->thread)) {
    *status = (int32_t)GetLastError();
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return;
  }
#else
  int detach_status = pthread_detach(core->thread);
  if (detach_status != 0) {
    *status = detach_status;
    sync_thread_lock_or_abort(core);
    core->state = SYNC_THREAD_JOINABLE;
    sync_thread_unlock_or_abort(core);
    return;
  }
#endif
  sync_thread_lock_or_abort(core);
  core->state = SYNC_THREAD_DETACHED;
  sync_thread_unlock_or_abort(core);
  *status = 0;
}

MOONBIT_FFI_EXPORT int32_t sync_thread_is_finished(
  sync_thread_handle_t *value,
  int32_t *status
) {
  sync_thread_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  int32_t result = core->finished;
  int32_t unlock_status = sync_os_mutex_unlock(&core->mutex);
  if (*status == 0) {
    *status = unlock_status;
  }
  return result;
}

MOONBIT_FFI_EXPORT void sync_thread_test_fail_next_start(int32_t status) {
  sync_thread_test_next_start_error = status;
}

MOONBIT_FFI_EXPORT void sync_thread_test_fail_next_join(int32_t status) {
  sync_thread_test_next_join_error = status;
}

MOONBIT_FFI_EXPORT void sync_thread_test_fail_next_detach(int32_t status) {
  sync_thread_test_next_detach_error = status;
}

MOONBIT_FFI_EXPORT void sync_thread_test_abort_if_unjoined(void) {
  int32_t status = 0;
  sync_thread_handle_t *handle = sync_thread_new(&status);
  if (status != 0 || handle == NULL) {
    abort();
  }
  sync_thread_finalize(handle);
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
