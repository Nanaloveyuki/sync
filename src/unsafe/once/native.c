#include "../../internal/native_sync.h"

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t cond;
  int32_t state;
} sync_once_core_t;

typedef struct {
  sync_once_core_t *core;
} sync_once_handle_t;

static sync_test_atomic_t sync_once_test_next_init_error = 0;
static sync_test_atomic_t sync_once_test_next_begin_error = 0;

static int32_t sync_once_take_test_error(sync_test_atomic_t *next_error) {
  return sync_test_atomic_take(next_error);
}

static void sync_once_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static void sync_once_record_error(int32_t *status, int32_t candidate) {
  if (*status == 0 && candidate != 0) {
    *status = candidate;
  }
}

static void sync_once_finalize(void *self) {
  sync_once_handle_t *handle = (sync_once_handle_t *)self;
  if (handle->core != NULL && sync_arc_dec(&handle->core->refs) == 0) {
    sync_once_abort_if_failed(sync_os_cond_destroy(&handle->core->cond));
    sync_once_abort_if_failed(sync_os_mutex_destroy(&handle->core->mutex));
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

MOONBIT_FFI_EXPORT sync_once_handle_t *sync_once_new(int32_t *status) {
  sync_once_core_t *core = (sync_once_core_t *)sync_alloc(sizeof(sync_once_core_t));
  core->refs = 1;
  *status = sync_os_mutex_init(&core->mutex);
  if (*status != 0) {
    free(core);
    return NULL;
  }
  int32_t injected = sync_once_take_test_error(&sync_once_test_next_init_error);
  if (injected != 0) {
    sync_once_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core);
    *status = injected;
    return NULL;
  }
  *status = sync_os_cond_init(&core->cond);
  if (*status != 0) {
    sync_once_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core);
    return NULL;
  }
  return sync_once_wrap(core);
}

MOONBIT_FFI_EXPORT sync_once_handle_t *sync_once_share(sync_once_handle_t *value) {
  sync_arc_inc(&value->core->refs);
  return sync_once_wrap(value->core);
}

MOONBIT_FFI_EXPORT int32_t sync_once_begin(
  sync_once_handle_t *value,
  int32_t *status
) {
  sync_once_core_t *core = value->core;
  int32_t injected = sync_once_take_test_error(&sync_once_test_next_begin_error);
  if (injected != 0) {
    *status = injected;
    return 0;
  }
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return 0;
  }
  while (core->state == 1) {
    int32_t wait_status = sync_os_cond_wait(&core->cond, &core->mutex);
    if (wait_status != 0) {
      *status = wait_status;
      sync_once_record_error(status, sync_os_mutex_unlock(&core->mutex));
      return 0;
    }
  }
  int32_t result;
  if (core->state == 0) {
    core->state = 1;
    result = 1;
  } else {
    result = core->state == 2 ? 0 : -1;
  }
  sync_once_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return result;
}

MOONBIT_FFI_EXPORT void sync_once_complete(
  sync_once_handle_t *value,
  int32_t *status
) {
  sync_once_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return;
  }
  core->state = 2;
  sync_once_record_error(status, sync_os_cond_broadcast(&core->cond));
  sync_once_record_error(status, sync_os_mutex_unlock(&core->mutex));
}

MOONBIT_FFI_EXPORT void sync_once_test_fail_next_init(int32_t status) {
  sync_test_atomic_store(&sync_once_test_next_init_error, status);
}

MOONBIT_FFI_EXPORT void sync_once_test_fail_next_begin(int32_t status) {
  sync_test_atomic_store(&sync_once_test_next_begin_error, status);
}

MOONBIT_FFI_EXPORT void sync_once_poison(
  sync_once_handle_t *value,
  int32_t *status
) {
  sync_once_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return;
  }
  core->state = 3;
  sync_once_record_error(status, sync_os_cond_broadcast(&core->cond));
  sync_once_record_error(status, sync_os_mutex_unlock(&core->mutex));
}
