#include "../internal/native_sync.h"

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

MOONBIT_FFI_EXPORT int32_t sync_wait_group_add(
  sync_wait_group_handle_t *value,
  int32_t delta
) {
  sync_wait_group_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  int64_t next = (int64_t)core->count + (int64_t)delta;
  if (next < 0 || next > INT32_MAX) {
    sync_os_mutex_unlock(&core->mutex);
    return 0;
  }
  core->count = (int32_t)next;
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
