#include "../internal/native_sync.h"

#include <string.h>

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
  if (sync_arc_dec(&core->refs) == 0) {
    for (int32_t i = 0; i < core->capacity; ++i) {
      if (core->slots[i] != NULL) {
        moonbit_decref(core->slots[i]);
      }
    }
    free(core->slots);
    sync_os_cond_destroy(&core->writable);
    sync_os_cond_destroy(&core->readable);
    sync_os_mutex_destroy(&core->mutex);
    free(core);
  }
}

static void sync_channel_finalize(void *self) {
  sync_channel_handle_t *handle = (sync_channel_handle_t *)self;
  sync_channel_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_os_mutex_lock(&core->mutex);
  if (handle->role == 1) {
    core->senders -= 1;
    if (core->senders == 0) {
      core->closed = 1;
      sync_os_cond_broadcast(&core->readable);
      sync_os_cond_broadcast(&core->writable);
    }
  } else if (handle->role == 2 && core->receiver_alive) {
    core->receiver_alive = 0;
    core->closed = 1;
    sync_os_cond_broadcast(&core->readable);
    sync_os_cond_broadcast(&core->writable);
  }
  sync_os_mutex_unlock(&core->mutex);
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

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_new(int32_t capacity) {
  sync_channel_core_t *core = (sync_channel_core_t *)sync_alloc(sizeof(sync_channel_core_t));
  core->refs = 1;
  core->capacity = capacity;
  core->senders = 1;
  core->slots = (void **)sync_alloc((size_t)capacity * sizeof(void *));
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->readable);
  sync_os_cond_init(&core->writable);
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_channel_receiver(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->receiver_alive = 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_channel_wrap(core, 2);
}

MOONBIT_FFI_EXPORT sync_channel_handle_t *sync_sender_share(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->senders += 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT int32_t sync_sender_try_send(
  sync_channel_handle_t *value,
  void *message
) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  if (core->closed || !core->receiver_alive) {
    sync_os_mutex_unlock(&core->mutex);
    return 2;
  }
  if (core->count == core->capacity) {
    sync_os_mutex_unlock(&core->mutex);
    return 1;
  }
  moonbit_incref(message);
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_os_cond_signal(&core->readable);
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t sync_sender_send(sync_channel_handle_t *value, void *message) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (core->count == core->capacity && !core->closed && core->receiver_alive) {
    sync_os_cond_wait(&core->writable, &core->mutex);
  }
  if (core->closed || !core->receiver_alive) {
    sync_os_mutex_unlock(&core->mutex);
    return 2;
  }
  moonbit_incref(message);
  core->slots[core->tail] = message;
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_os_cond_signal(&core->readable);
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT void sync_sender_close(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

static void *sync_channel_recv(sync_channel_handle_t *value, int32_t *status, int32_t block) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (block && core->count == 0 && !core->closed) {
    sync_os_cond_wait(&core->readable, &core->mutex);
  }
  if (core->count == 0) {
    *status = core->closed ? 2 : 1;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  void *message = core->slots[core->head];
  core->slots[core->head] = NULL;
  core->head = (core->head + 1) % core->capacity;
  core->count -= 1;
  *status = 0;
  sync_os_cond_signal(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
  return message;
}

MOONBIT_FFI_EXPORT void *sync_receiver_try_recv(
  sync_channel_handle_t *value,
  int32_t *status
) {
  return sync_channel_recv(value, status, 0);
}

MOONBIT_FFI_EXPORT void *sync_receiver_recv(
  sync_channel_handle_t *value,
  int32_t *status
) {
  return sync_channel_recv(value, status, 1);
}

MOONBIT_FFI_EXPORT void sync_receiver_close(sync_channel_handle_t *value) {
  sync_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  core->receiver_alive = 0;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_len(sync_channel_handle_t *value) {
  sync_os_mutex_lock(&value->core->mutex);
  int32_t count = value->core->count;
  sync_os_mutex_unlock(&value->core->mutex);
  return count;
}

MOONBIT_FFI_EXPORT int32_t sync_receiver_capacity(sync_channel_handle_t *value) {
  return value->core->capacity;
}

typedef struct {
  uint8_t *data;
  int32_t length;
} sync_owned_bytes_message_t;

typedef struct {
  sync_arc_t refs;
  sync_os_mutex_t mutex;
  sync_os_cond_t readable;
  sync_os_cond_t writable;
  sync_owned_bytes_message_t **slots;
  int32_t capacity;
  int32_t head;
  int32_t tail;
  int32_t count;
  int32_t senders;
  int32_t receiver_alive;
  int32_t closed;
} sync_owned_bytes_channel_core_t;

typedef struct {
  sync_owned_bytes_channel_core_t *core;
  int32_t role;
} sync_owned_bytes_channel_handle_t;

static void sync_owned_bytes_message_release(sync_owned_bytes_message_t *message) {
  if (message == NULL) {
    return;
  }
  free(message->data);
  free(message);
}

static sync_owned_bytes_message_t *sync_owned_bytes_message_copy(
  moonbit_bytes_t bytes
) {
  int32_t length = Moonbit_array_length(bytes);
  sync_owned_bytes_message_t *message = (sync_owned_bytes_message_t *)sync_alloc(
    sizeof(sync_owned_bytes_message_t)
  );
  message->length = length;
  if (length > 0) {
    message->data = (uint8_t *)sync_alloc((size_t)length);
    memcpy(message->data, bytes, (size_t)length);
  }
  return message;
}

static moonbit_bytes_t sync_owned_bytes_message_into_moonbit(
  sync_owned_bytes_message_t *message
) {
  moonbit_bytes_t bytes = moonbit_make_bytes_raw(message->length);
  if (message->length > 0) {
    memcpy(bytes, message->data, (size_t)message->length);
  }
  sync_owned_bytes_message_release(message);
  return bytes;
}

static void sync_owned_bytes_channel_core_release(
  sync_owned_bytes_channel_core_t *core
) {
  if (sync_arc_dec(&core->refs) != 0) {
    return;
  }
  for (int32_t index = 0; index < core->capacity; index += 1) {
    sync_owned_bytes_message_release(core->slots[index]);
  }
  free(core->slots);
  sync_os_cond_destroy(&core->writable);
  sync_os_cond_destroy(&core->readable);
  sync_os_mutex_destroy(&core->mutex);
  free(core);
}

static void sync_owned_bytes_channel_finalize(void *self) {
  sync_owned_bytes_channel_handle_t *handle = (
    sync_owned_bytes_channel_handle_t *
  )self;
  sync_owned_bytes_channel_core_t *core = handle->core;
  if (core == NULL) {
    return;
  }
  sync_os_mutex_lock(&core->mutex);
  if (handle->role == 1) {
    core->senders -= 1;
    if (core->senders == 0) {
      core->closed = 1;
      sync_os_cond_broadcast(&core->readable);
      sync_os_cond_broadcast(&core->writable);
    }
  } else if (handle->role == 2 && core->receiver_alive) {
    core->receiver_alive = 0;
    core->closed = 1;
    sync_os_cond_broadcast(&core->readable);
    sync_os_cond_broadcast(&core->writable);
  }
  sync_os_mutex_unlock(&core->mutex);
  sync_owned_bytes_channel_core_release(core);
}

static sync_owned_bytes_channel_handle_t *sync_owned_bytes_channel_wrap(
  sync_owned_bytes_channel_core_t *core,
  int32_t role
) {
  sync_owned_bytes_channel_handle_t *handle = (
    sync_owned_bytes_channel_handle_t *
  )moonbit_make_external_object(
    sync_owned_bytes_channel_finalize,
    sizeof(sync_owned_bytes_channel_handle_t)
  );
  handle->core = core;
  handle->role = role;
  return handle;
}

MOONBIT_FFI_EXPORT sync_owned_bytes_channel_handle_t *sync_owned_bytes_channel_new(
  int32_t capacity
) {
  sync_owned_bytes_channel_core_t *core = (
    sync_owned_bytes_channel_core_t *
  )sync_alloc(sizeof(sync_owned_bytes_channel_core_t));
  core->refs = 1;
  core->capacity = capacity;
  core->senders = 1;
  core->slots = (sync_owned_bytes_message_t **)sync_alloc(
    (size_t)capacity * sizeof(sync_owned_bytes_message_t *)
  );
  sync_os_mutex_init(&core->mutex);
  sync_os_cond_init(&core->readable);
  sync_os_cond_init(&core->writable);
  return sync_owned_bytes_channel_wrap(core, 1);
}

MOONBIT_FFI_EXPORT sync_owned_bytes_channel_handle_t *sync_owned_bytes_channel_receiver(
  sync_owned_bytes_channel_handle_t *value
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->receiver_alive = 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_owned_bytes_channel_wrap(core, 2);
}

MOONBIT_FFI_EXPORT sync_owned_bytes_channel_handle_t *sync_owned_bytes_sender_share(
  sync_owned_bytes_channel_handle_t *value
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->senders += 1;
  sync_arc_inc(&core->refs);
  sync_os_mutex_unlock(&core->mutex);
  return sync_owned_bytes_channel_wrap(core, 1);
}

static int32_t sync_owned_bytes_channel_submit(
  sync_owned_bytes_channel_handle_t *value,
  moonbit_bytes_t bytes,
  int32_t block
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (block && core->count == core->capacity && !core->closed && core->receiver_alive) {
    sync_os_cond_wait(&core->writable, &core->mutex);
  }
  if (core->closed || !core->receiver_alive) {
    sync_os_mutex_unlock(&core->mutex);
    return 2;
  }
  if (core->count == core->capacity) {
    sync_os_mutex_unlock(&core->mutex);
    return 1;
  }
  core->slots[core->tail] = sync_owned_bytes_message_copy(bytes);
  core->tail = (core->tail + 1) % core->capacity;
  core->count += 1;
  sync_os_cond_signal(&core->readable);
  sync_os_mutex_unlock(&core->mutex);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t sync_owned_bytes_sender_try_send(
  sync_owned_bytes_channel_handle_t *value,
  moonbit_bytes_t bytes
) {
  return sync_owned_bytes_channel_submit(value, bytes, 0);
}

MOONBIT_FFI_EXPORT int32_t sync_owned_bytes_sender_send(
  sync_owned_bytes_channel_handle_t *value,
  moonbit_bytes_t bytes
) {
  return sync_owned_bytes_channel_submit(value, bytes, 1);
}

MOONBIT_FFI_EXPORT void sync_owned_bytes_sender_close(
  sync_owned_bytes_channel_handle_t *value
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

static moonbit_bytes_t sync_owned_bytes_channel_receive(
  sync_owned_bytes_channel_handle_t *value,
  int32_t *status,
  int32_t block
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  while (block && core->count == 0 && !core->closed) {
    sync_os_cond_wait(&core->readable, &core->mutex);
  }
  if (core->count == 0) {
    *status = core->closed ? 2 : 1;
    sync_os_mutex_unlock(&core->mutex);
    return NULL;
  }
  sync_owned_bytes_message_t *message = core->slots[core->head];
  core->slots[core->head] = NULL;
  core->head = (core->head + 1) % core->capacity;
  core->count -= 1;
  *status = 0;
  sync_os_cond_signal(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
  return sync_owned_bytes_message_into_moonbit(message);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t sync_owned_bytes_receiver_try_recv(
  sync_owned_bytes_channel_handle_t *value,
  int32_t *status
) {
  return sync_owned_bytes_channel_receive(value, status, 0);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t sync_owned_bytes_receiver_recv(
  sync_owned_bytes_channel_handle_t *value,
  int32_t *status
) {
  return sync_owned_bytes_channel_receive(value, status, 1);
}

MOONBIT_FFI_EXPORT void sync_owned_bytes_receiver_close(
  sync_owned_bytes_channel_handle_t *value
) {
  sync_owned_bytes_channel_core_t *core = value->core;
  sync_os_mutex_lock(&core->mutex);
  core->closed = 1;
  core->receiver_alive = 0;
  sync_os_cond_broadcast(&core->readable);
  sync_os_cond_broadcast(&core->writable);
  sync_os_mutex_unlock(&core->mutex);
}

MOONBIT_FFI_EXPORT int32_t sync_owned_bytes_receiver_len(
  sync_owned_bytes_channel_handle_t *value
) {
  sync_os_mutex_lock(&value->core->mutex);
  int32_t count = value->core->count;
  sync_os_mutex_unlock(&value->core->mutex);
  return count;
}

MOONBIT_FFI_EXPORT int32_t sync_owned_bytes_receiver_capacity(
  sync_owned_bytes_channel_handle_t *value
) {
  return value->core->capacity;
}
