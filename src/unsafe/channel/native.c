#include "../../internal/native_sync.h"

static void sync_record_error(int32_t *error, int32_t status) {
  if (*error == 0 && status != 0) {
    *error = status;
  }
}

static void sync_channel_abort_if_failed(int32_t status) {
  if (status != 0) {
    abort();
  }
}

static sync_test_atomic_t sync_channel_test_next_init_error = 0;
static sync_test_atomic_t sync_channel_test_next_operation_error = 0;

static int32_t sync_channel_test_take_next_operation_error(void) {
  return sync_test_atomic_take(&sync_channel_test_next_operation_error);
}

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t readable;
  sync_os_cond_t writable;
  void **slots;
  int32_t capacity;
  int32_t head;
  int32_t tail;
  int32_t count;
  int32_t senders;
  int32_t receiver_alive;
  int32_t closed;
} sync_channel_core_t;

typedef struct {
  sync_channel_core_t *core;
  int32_t role;
} sync_channel_handle_t;

static void sync_channel_core_release(sync_channel_core_t *core) {
  if (sync_arc_dec(&core->refs) != 0) {
    return;
  }
  for (int32_t index = 0; index < core->capacity; index += 1) {
    if (core->slots[index] != NULL) {
      moonbit_decref(core->slots[index]);
    }
  }
  free(core->slots);
  sync_channel_abort_if_failed(sync_os_cond_destroy(&core->writable));
  sync_channel_abort_if_failed(sync_os_cond_destroy(&core->readable));
  sync_channel_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
  free(core);
}

static void sync_channel_finalize(void *self) {
  sync_channel_handle_t *handle = (sync_channel_handle_t *)self;
  sync_channel_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_channel_abort_if_failed(sync_os_mutex_lock(&core->mutex));
  if (handle->role == 1) {
    core->senders -= 1;
    if (core->senders == 0) {
      core->closed = 1;
      sync_channel_abort_if_failed(sync_os_cond_broadcast(&core->readable));
      sync_channel_abort_if_failed(sync_os_cond_broadcast(&core->writable));
    }
  } else if (handle->role == 2 && core->receiver_alive) {
    core->receiver_alive = 0;
    core->closed = 1;
    sync_channel_abort_if_failed(sync_os_cond_broadcast(&core->readable));
    sync_channel_abort_if_failed(sync_os_cond_broadcast(&core->writable));
  }
  sync_channel_abort_if_failed(sync_os_mutex_unlock(&core->mutex));
  sync_channel_core_release(core);
}

static sync_channel_handle_t *sync_channel_wrap(sync_channel_core_t *core, int32_t role) {
  sync_channel_handle_t *handle = (sync_channel_handle_t *)moonbit_make_external_object(
    sync_channel_finalize,
    sizeof(sync_channel_handle_t)
  );
  handle->core = core;
  handle->role = role;
  return handle;
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_new(
  int32_t capacity,
  int32_t *status
) {
  sync_channel_core_t *core = (sync_channel_core_t *)sync_alloc(sizeof(sync_channel_core_t));
  core->refs = 1;
  core->capacity = capacity;
  core->senders = 1;
  core->slots = (void **)sync_alloc(sync_array_size_or_abort(capacity, sizeof(void *)));
  *status = sync_test_atomic_take(&sync_channel_test_next_init_error);
  if (*status == 0) {
    *status = sync_os_mutex_init(&core->mutex);
  }
  if (*status != 0) {
    free(core->slots);
    free(core);
    return NULL;
  }
  *status = sync_os_cond_init(&core->readable);
  if (*status != 0) {
    sync_channel_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core->slots);
    free(core);
    return NULL;
  }
  *status = sync_os_cond_init(&core->writable);
  if (*status != 0) {
    sync_channel_abort_if_failed(sync_os_cond_destroy(&core->readable));
    sync_channel_abort_if_failed(sync_os_mutex_destroy(&core->mutex));
    free(core->slots);
    free(core);
    return NULL;
  }
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_receiver(
  sync_channel_handle_t *value,
  int32_t *status
) {
  sync_channel_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return NULL;
  }
  core->receiver_alive = 1;
  sync_arc_inc(&core->refs);
  sync_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return sync_channel_wrap(core, 2);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_sender_share(
  sync_channel_handle_t *value,
  int32_t *status
) {
  sync_channel_core_t *core = value->core;
  *status = sync_os_mutex_lock(&core->mutex);
  if (*status != 0) {
    return NULL;
  }
  core->senders += 1;
  sync_arc_inc(&core->refs);
  sync_record_error(status, sync_os_mutex_unlock(&core->mutex));
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT void *sync_sender_try_send(
  sync_channel_handle_t *value,
  void *message,
  int32_t *result,
  int32_t *error
) {
  sync_channel_core_t *core = value->core;
  *error = sync_channel_test_take_next_operation_error();
  if (*error != 0) {
    *result = 2;
    return message;
  }
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    *result = 2;
    return message;
  }
  if (core->closed || !core->receiver_alive) {
    sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
    *result = 2;
    return message;
  }
  if (core->count == core->capacity) {
    sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
    *result = 1;
    return message;
  }
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_record_error(error, sync_os_cond_signal(&core->readable));
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
  *result = 0;
  return NULL;
}

MOONBIT_FFI_EXPORT void *sync_sender_send(
  sync_channel_handle_t *value,
  void *message,
  int32_t *result,
  int32_t *error
) {
  sync_channel_core_t *core = value->core;
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    *result = 2;
    return message;
  }
  while (core->count == core->capacity && !core->closed && core->receiver_alive) {
    int32_t wait_status = sync_os_cond_wait(&core->writable, &core->mutex);
    if (wait_status != 0) {
      sync_record_error(error, wait_status);
      sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
      *result = 2;
      return message;
    }
  }
  if (core->closed || !core->receiver_alive) {
    sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
    *result = 2;
    return message;
  }
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_record_error(error, sync_os_cond_signal(&core->readable));
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
  *result = 0;
  return NULL;
}

MOONBIT_FFI_EXPORT void sync_sender_close(sync_channel_handle_t *value, int32_t *error) {
  sync_channel_core_t *core = value->core;
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    return;
  }
  core->closed = 1;
  sync_record_error(error, sync_os_cond_broadcast(&core->readable));
  sync_record_error(error, sync_os_cond_broadcast(&core->writable));
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
}

static void *sync_channel_receive(
  sync_channel_handle_t *value,
  int32_t *status,
  int32_t *error,
  int32_t block
) {
  sync_channel_core_t *core = value->core;
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    *status = 2;
    return NULL;
  }
  while (block && core->count == 0 && !core->closed) {
    int32_t wait_status = sync_os_cond_wait(&core->readable, &core->mutex);
    if (wait_status != 0) {
      *status = 2;
      sync_record_error(error, wait_status);
      sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
      return NULL;
    }
  }
  if (core->count == 0) {
    *status = core->closed ? 2 : 1;
    sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
    return NULL;
  }
  void *message = core->slots[core->head];
  core->slots[core->head] = NULL;
  core->head = (core->head + 1) % core->capacity;
  core->count -= 1;
  *status = 0;
  sync_record_error(error, sync_os_cond_signal(&core->writable));
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
  return message;
}

MOONBIT_FFI_EXPORT void *sync_receiver_try_recv(
  sync_channel_handle_t *value,
  int32_t *status,
  int32_t *error
) {
  return sync_channel_receive(value, status, error, 0);
}

MOONBIT_FFI_EXPORT void *sync_receiver_recv(
  sync_channel_handle_t *value,
  int32_t *status,
  int32_t *error
) {
  return sync_channel_receive(value, status, error, 1);
}

MOONBIT_FFI_EXPORT void sync_receiver_close(sync_channel_handle_t *value, int32_t *error) {
  sync_channel_core_t *core = value->core;
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    return;
  }
  core->closed = 1;
  core->receiver_alive = 0;
  sync_record_error(error, sync_os_cond_broadcast(&core->readable));
  sync_record_error(error, sync_os_cond_broadcast(&core->writable));
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_len(sync_channel_handle_t *value, int32_t *error) {
  sync_channel_core_t *core = value->core;
  *error = sync_os_mutex_lock(&core->mutex);
  if (*error != 0) {
    return 0;
  }
  int32_t count = core->count;
  sync_record_error(error, sync_os_mutex_unlock(&core->mutex));
  return count;
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_capacity(sync_channel_handle_t *value) {
  return value->core->capacity;
}

MOONBIT_FFI_EXPORT void sync_channel_test_fail_next_init(int32_t status) {
  sync_test_atomic_store(&sync_channel_test_next_init_error, status);
}

MOONBIT_FFI_EXPORT void sync_channel_test_fail_next_operation(int32_t status) {
  sync_test_atomic_store(&sync_channel_test_next_operation_error, status);
}
