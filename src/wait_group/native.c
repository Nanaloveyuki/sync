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

static sync_test_atomic_t sync_wait_group_test_next_init_error = 0;
static sync_test_atomic_t sync_wait_group_test_next_add_error = 0;
static sync_test_atomic_t sync_wait_group_test_next_wait_error = 0;

static int32_t sync_wait_group_take_test_error(sync_test_atomic_t *next_error) {
  return sync_test_atomic_take(next_error);
}

static void sync_wait_group_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_wait_group_record_error(int32_t *status, int32_t candidate) {
  if (*status == 0 && candidate != 0) {
    *status = candidate;
  }
}

static void sync_wait_group_finalize(void *self) {
  sync_wait_group_handle_t *handle = (sync_wait_group_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    sync_wait_group_abort_if_failed(sync_os_cond_destroy(&handle->core->cond));
    sync_wait_group_abort_if_failed(sync_os_mutex_destroy(&handle->core->mutex));
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

MOONBIT_FFI_EXPORT sync_wait_group_handle_t *sync_wait_group_new(int32_t *status) {
  sync_wait_group_core_t *core = (sync_wait_group_core_t *)sync_alloc(
    sizeof(sync_wait_group_core_t)
  );
  core->refs = 1;
  *status = sync_os_mutex_init(&core->mutex);
  if (*status != 0) {
    free(core);
    return NULL;
  }
  int32_t injected = sync_wait_group_take_test_error(
    &sync_wait_group_test_next_init_error
  );
  if (injected != 0) {
    sync_wait_group_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core);
    *status = injected;
    return NULL;
  }
  *status = sync_os_cond_init(&core->cond);
  if (*status != 0) {
    sync_wait_group_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core);
    return NULL;
  }
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
  int32_t delta,
  int32_t *status
) {
  sync_wait_group_core_t *core = value->core;
  int32_t injected = sync_wait_group_take_test_error(
    &sync_wait_group_test_next_add_error
  );
  if (injected != 0) {
    *status = injected;
    return 0;
  }
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  int64_t next = (int64_t)core->count + (int64_t)delta;
  if (next < 0 || next > INT32_MAX) {
    sync_wait_group_record_error(status, sync_os_mutex_unlock(&core->mutex));
    return 0;
  }
  core->count = (int32_t)next;
  if (core->count == 0) {
    sync_wait_group_record_error(status, sync_os_cond_broadcast(&core->cond));
  }
  sync_wait_group_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return *status == 0;
}

MOONBIT_FFI_EXPORT void sync_wait_group_wait(
  sync_wait_group_handle_t *value,
  int32_t *status
) {
  sync_wait_group_core_t *core = value->core;
  int32_t injected = sync_wait_group_take_test_error(
    &sync_wait_group_test_next_wait_error
  );
  if (injected != 0) {
    *status = injected;
    return;
  }
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return;
  }
  while (core->count != 0) {
    int32_t wait_status = sync_os_cond_wait(&core->cond, &core->mutex);
    if (wait_status != 0) {
      sync_wait_group_record_error(status, wait_status);
      break;
    }
  }
  sync_wait_group_record_error(status, sync_os_mutex_unlock(&core->mutex));
}

MOONBIT_FFI_EXPORT void sync_wait_group_test_fail_next_init(int32_t status) {
  sync_test_atomic_store(&sync_wait_group_test_next_init_error, status);
}

MOONBIT_FFI_EXPORT void sync_wait_group_test_fail_next_add(int32_t status) {
  sync_test_atomic_store(&sync_wait_group_test_next_add_error, status);
}

MOONBIT_FFI_EXPORT void sync_wait_group_test_fail_next_wait(int32_t status) {
  sync_test_atomic_store(&sync_wait_group_test_next_wait_error, status);
}
