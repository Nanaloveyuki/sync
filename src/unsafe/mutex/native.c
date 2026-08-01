#include "../../internal/native_sync.h"

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  void *value;
  uint64_t owner;
  int32_t locked;
} sync_mutex_core_t;

typedef struct {
  sync_mutex_core_t *core;
} sync_mutex_handle_t;

static int32_t sync_mutex_test_next_init_error = 0;
static int32_t sync_condvar_test_next_init_error = 0;
static int32_t sync_condvar_test_next_notify_error = 0;

static void sync_mutex_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_mutex_finalize(void *self) {
  sync_mutex_handle_t *handle = (sync_mutex_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    if (handle->core->value != NULL) {
      moonbit_decref(handle->core->value);
    }
    sync_mutex_abort_if_failed(sync_os_mutex_destroy(&handle->core->mutex));
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

MOONBIT_FFI_EXPORT sync_mutex_handle_t *sync_mutex_new(
  void *value,
  int32_t *status
) {
  sync_mutex_core_t *core = (sync_mutex_core_t *)sync_alloc(sizeof(sync_mutex_core_t));
  core->refs = 1;
  core->value = value;
  if (sync_mutex_test_next_init_error != 0) {
    *status = sync_mutex_test_next_init_error;
    sync_mutex_test_next_init_error = 0;
  } else {
    *status = sync_os_mutex_init(&core->mutex);
  }
  if (*status != 0) {
    moonbit_decref(value);
    free(core);
    return NULL;
  }
  return sync_mutex_wrap(core);
}

MOONBIT_FFI_EXPORT sync_mutex_handle_t *sync_mutex_share(sync_mutex_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_mutex_wrap(value->core);
}

MOONBIT_FFI_EXPORT void *sync_mutex_lock_get(
  sync_mutex_handle_t *value,
  int32_t *status
) {
  *status = sync_os_mutex_lock(&value->core->mutex);
  if (*status != 0) {
    return NULL;
  }
  value->core->owner = sync_os_current_thread_id();
  value->core->locked = 1;
  moonbit_incref(value->core->value);
  return value->core->value;
}

MOONBIT_FFI_EXPORT void sync_mutex_release_unlock(
  sync_mutex_handle_t *value,
  void *box,
  int32_t *status
) {
  moonbit_decref(box);
  value->core->locked = 0;
  value->core->owner = 0;
  *status = sync_os_mutex_unlock(&value->core->mutex);
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
    sync_mutex_abort_if_failed(sync_os_cond_destroy(&handle->core->cond));
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

MOONBIT_FFI_EXPORT sync_cond_handle_t *sync_condvar_new(int32_t *status) {
  sync_cond_core_t *core = (sync_cond_core_t *)sync_alloc(sizeof(sync_cond_core_t));
  core->refs = 1;
  if (sync_condvar_test_next_init_error != 0) {
    *status = sync_condvar_test_next_init_error;
    sync_condvar_test_next_init_error = 0;
  } else {
    *status = sync_os_cond_init(&core->cond);
  }
  if (*status != 0) {
    free(core);
    return NULL;
  }
  return sync_cond_wrap(core);
}

MOONBIT_FFI_EXPORT sync_cond_handle_t *sync_condvar_share(sync_cond_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_cond_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_condvar_wait(
  sync_cond_handle_t *value,
  sync_mutex_handle_t *mutex
) {
  sync_mutex_core_t *mutex_core = mutex->core;
  if (!mutex_core->locked || mutex_core->owner != sync_os_current_thread_id()) {
    return -1;
  }
  int32_t status = sync_os_cond_wait(&value->core->cond, &mutex_core->mutex);
  if (status == 0) {
    mutex_core->owner = sync_os_current_thread_id();
    mutex_core->locked = 1;
  }
  return status;
}

MOONBIT_FFI_EXPORT int32_t sync_condvar_notify_one(sync_cond_handle_t *value) {
  if (sync_condvar_test_next_notify_error != 0) {
    int32_t status = sync_condvar_test_next_notify_error;
    sync_condvar_test_next_notify_error = 0;
    return status;
  }
  return sync_os_cond_signal(&value->core->cond);
}

MOONBIT_FFI_EXPORT int32_t sync_condvar_notify_all(sync_cond_handle_t *value) {
  if (sync_condvar_test_next_notify_error != 0) {
    int32_t status = sync_condvar_test_next_notify_error;
    sync_condvar_test_next_notify_error = 0;
    return status;
  }
  return sync_os_cond_broadcast(&value->core->cond);
}

MOONBIT_FFI_EXPORT void sync_mutex_test_fail_next_init(int32_t status) {
  sync_mutex_test_next_init_error = status;
}

MOONBIT_FFI_EXPORT void sync_condvar_test_fail_next_init(int32_t status) {
  sync_condvar_test_next_init_error = status;
}

MOONBIT_FFI_EXPORT void sync_condvar_test_fail_next_notify(int32_t status) {
  sync_condvar_test_next_notify_error = status;
}
