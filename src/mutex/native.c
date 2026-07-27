#include "../internal/native_sync.h"

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
