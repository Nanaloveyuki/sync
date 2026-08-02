#include "../internal/native_sync.h"

typedef struct {
  sync_arc_t refs;
  sync_os_rwlock_t lock;
  int32_t initialized;
} sync_rwlock_core_t;

typedef struct {
  sync_rwlock_core_t *core;
} sync_rwlock_handle_t;

static int32_t sync_rwlock_test_next_init_error = 0;
static int32_t sync_rwlock_test_next_lock_error = 0;
static int32_t sync_rwlock_test_next_unlock_error = 0;

static int32_t sync_rwlock_take_test_error(int32_t *next_error) {
  int32_t status = *next_error;
  *next_error = 0;
  return status;
}

static void sync_rwlock_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_rwlock_finalize(void *self) {
  sync_rwlock_handle_t *handle = (sync_rwlock_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    if (handle->core->initialized) {
      sync_rwlock_abort_if_failed(sync_os_rwlock_destroy(&handle->core->lock));
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
  if (*status != 0) {
    free(core);
    return NULL;
  }
  int32_t injected = sync_rwlock_take_test_error(&sync_rwlock_test_next_init_error);
  if (injected != 0) {
    sync_rwlock_abort_if_failed(sync_os_rwlock_destroy(&core->lock));
    free(core);
    *status = injected;
    return NULL;
  }
  core->initialized = 1;
  return sync_rwlock_wrap(core);
}

MOONBIT_FFI_EXPORT sync_rwlock_handle_t *sync_rwlock_share(sync_rwlock_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_rwlock_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_read_lock(sync_rwlock_handle_t *value) {
  int32_t injected = sync_rwlock_take_test_error(&sync_rwlock_test_next_lock_error);
  if (injected != 0) {
    return injected;
  }
  return sync_os_rwlock_read_lock(&value->core->lock);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_read_unlock(sync_rwlock_handle_t *value) {
  int32_t status = sync_os_rwlock_read_unlock(&value->core->lock);
  if (status != 0) {
    return status;
  }
  return sync_rwlock_take_test_error(&sync_rwlock_test_next_unlock_error);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_write_lock(sync_rwlock_handle_t *value) {
  int32_t injected = sync_rwlock_take_test_error(&sync_rwlock_test_next_lock_error);
  if (injected != 0) {
    return injected;
  }
  return sync_os_rwlock_write_lock(&value->core->lock);
}

MOONBIT_FFI_EXPORT int32_t sync_rwlock_write_unlock(sync_rwlock_handle_t *value) {
  int32_t status = sync_os_rwlock_write_unlock(&value->core->lock);
  if (status != 0) {
    return status;
  }
  return sync_rwlock_take_test_error(&sync_rwlock_test_next_unlock_error);
}

MOONBIT_FFI_EXPORT void sync_rwlock_test_fail_next_init(int32_t status) {
  sync_rwlock_test_next_init_error = status;
}

MOONBIT_FFI_EXPORT void sync_rwlock_test_fail_next_lock(int32_t status) {
  sync_rwlock_test_next_lock_error = status;
}

MOONBIT_FFI_EXPORT void sync_rwlock_test_fail_next_unlock(int32_t status) {
  sync_rwlock_test_next_unlock_error = status;
}
