#ifndef SYNC_NATIVE_INTERNAL_H
#define SYNC_NATIVE_INTERNAL_H

#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include <moonbit.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

typedef volatile LONG sync_arc_t;

static inline int32_t sync_arc_inc(sync_arc_t *value) {
  return (int32_t)InterlockedIncrement(value);
}

static inline int32_t sync_arc_dec(sync_arc_t *value) {
  return (int32_t)InterlockedDecrement(value);
}
#else
typedef int32_t sync_arc_t;

static inline int32_t sync_arc_inc(sync_arc_t *value) {
  return __atomic_add_fetch(value, 1, __ATOMIC_SEQ_CST);
}

static inline int32_t sync_arc_dec(sync_arc_t *value) {
  return __atomic_sub_fetch(value, 1, __ATOMIC_SEQ_CST);
}
#endif

static inline void *sync_alloc(size_t size) {
  void *value = calloc(1, size);
  if (value == NULL) {
    abort();
  }
  return value;
}

static inline size_t sync_array_size_or_abort(int32_t length, size_t element_size) {
  if (length <= 0 || (size_t)length > SIZE_MAX / element_size) {
    abort();
  }
  return (size_t)length * element_size;
}

#endif
