#include "../internal/native_sync.h"

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
