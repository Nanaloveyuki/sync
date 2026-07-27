#include "../internal/native_sync.h"

typedef struct {
  sync_arc_t refs;
  sync_os_rwlock_t lock;
  int32_t initialized;
} sync_rwlock_core_t;

typedef struct {
  sync_rwlock_core_t *core;
} sync_rwlock_handle_t;

static void sync_rwlock_finalize(void *self) {
  sync_rwlock_handle_t *handle = (sync_rwlock_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    if (handle->core->initialized) {
      sync_os_rwlock_destroy(&handle->core->lock);
    }
    free(handle->core);
  }
}

static sync_rwlock_handle_t *sync_rwlock_wrap(sync_rwlock_core_t *core) {
  sync_rwlock_handle_t *handle = (sync_rwlock_handle_t *)moonbit_make_external_object(
    sync_rwlock_finalize,
    sizeof(sync_rwlock_handle_t)
  );
  handle->core = core;
  return handle;
}

MOONBIT_FFI_EXPORT sync_rwlock_handle_t *sync_rwlock_new(int32_t *status) {
  sync_rwlock_core_t *core = (sync_rwlock_core_t *)sync_alloc(sizeof(sync_rwlock_core_t));
  core->refs = 1;
  *status = sync_os_rwlock_init(&core->lock);
  core->initialized = *status == 0;
  return sync_rwlock_wrap(core);
}

MOONBIT_FFI_EXPORT sync_rwlock_handle_t *sync_rwlock_share(sync_rwlock_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_rwlock_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_read_lock(sync_rwlock_handle_t *value) {
  return sync_os_rwlock_read_lock(&value->core->lock);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_read_unlock(sync_rwlock_handle_t *value) {
  return sync_os_rwlock_read_unlock(&value->core->lock);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_write_lock(sync_rwlock_handle_t *value) {
  return sync_os_rwlock_write_lock(&value->core->lock);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_write_unlock(sync_rwlock_handle_t *value) {
  return sync_os_rwlock_write_unlock(&value->core->lock);
}
