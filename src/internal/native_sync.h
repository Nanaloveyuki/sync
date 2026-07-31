#ifndef SYNC_NATIVE_SYNC_H
#define SYNC_NATIVE_SYNC_H

#include "native_internal.h"

#include <string.h>

#if defined(_WIN32)
typedef SRWLOCK sync_os_mutex_t;
typedef SRWLOCK sync_os_rwlock_t;
typedef CONDITION_VARIABLE sync_os_cond_t;

static inline void sync_os_mutex_init(sync_os_mutex_t *mutex) {
  InitializeSRWLock(mutex);
}

static inline void sync_os_mutex_destroy(sync_os_mutex_t *mutex) {
  (void)mutex;
}

static inline void sync_os_mutex_lock(sync_os_mutex_t *mutex) {
  AcquireSRWLockExclusive(mutex);
}

static inline void sync_os_mutex_unlock(sync_os_mutex_t *mutex) {
  ReleaseSRWLockExclusive(mutex);
}

static inline uint64_t sync_os_current_thread_id(void) {
  return (uint64_t)GetCurrentThreadId();
}

static inline int32_t sync_os_rwlock_init(sync_os_rwlock_t *lock) {
  InitializeSRWLock(lock);
  return 0;
}

static inline void sync_os_rwlock_destroy(sync_os_rwlock_t *lock) {
  (void)lock;
}

static inline int32_t sync_os_rwlock_read_lock(sync_os_rwlock_t *lock) {
  AcquireSRWLockShared(lock);
  return 0;
}

static inline int32_t sync_os_rwlock_read_unlock(sync_os_rwlock_t *lock) {
  ReleaseSRWLockShared(lock);
  return 0;
}

static inline int32_t sync_os_rwlock_write_lock(sync_os_rwlock_t *lock) {
  AcquireSRWLockExclusive(lock);
  return 0;
}

static inline int32_t sync_os_rwlock_write_unlock(sync_os_rwlock_t *lock) {
  ReleaseSRWLockExclusive(lock);
  return 0;
}

static inline void sync_os_cond_init(sync_os_cond_t *cond) {
  InitializeConditionVariable(cond);
}

static inline void sync_os_cond_destroy(sync_os_cond_t *cond) {
  (void)cond;
}

static inline int32_t sync_os_cond_wait(sync_os_cond_t *cond, sync_os_mutex_t *mutex) {
  if (SleepConditionVariableSRW(cond, mutex, INFINITE, 0)) {
    return 0;
  }
  return (int32_t)GetLastError();
}

static inline void sync_os_cond_signal(sync_os_cond_t *cond) {
  WakeConditionVariable(cond);
}

static inline void sync_os_cond_broadcast(sync_os_cond_t *cond) {
  WakeAllConditionVariable(cond);
}
#else
#include <pthread.h>

typedef pthread_mutex_t sync_os_mutex_t;
typedef pthread_rwlock_t sync_os_rwlock_t;
typedef pthread_cond_t sync_os_cond_t;

static inline void sync_os_mutex_init(sync_os_mutex_t *mutex) {
  (void)pthread_mutex_init(mutex, NULL);
}

static inline void sync_os_mutex_destroy(sync_os_mutex_t *mutex) {
  (void)pthread_mutex_destroy(mutex);
}

static inline void sync_os_mutex_lock(sync_os_mutex_t *mutex) {
  (void)pthread_mutex_lock(mutex);
}

static inline void sync_os_mutex_unlock(sync_os_mutex_t *mutex) {
  (void)pthread_mutex_unlock(mutex);
}

static inline uint64_t sync_os_current_thread_id(void) {
  pthread_t thread = pthread_self();
  uint64_t id = 0;
  memcpy(&id, &thread, sizeof(thread) < sizeof(id) ? sizeof(thread) : sizeof(id));
  return id;
}

static inline int32_t sync_os_rwlock_init(sync_os_rwlock_t *lock) {
  return (int32_t)pthread_rwlock_init(lock, NULL);
}

static inline void sync_os_rwlock_destroy(sync_os_rwlock_t *lock) {
  (void)pthread_rwlock_destroy(lock);
}

static inline int32_t sync_os_rwlock_read_lock(sync_os_rwlock_t *lock) {
  return (int32_t)pthread_rwlock_rdlock(lock);
}

static inline int32_t sync_os_rwlock_read_unlock(sync_os_rwlock_t *lock) {
  return (int32_t)pthread_rwlock_unlock(lock);
}

static inline int32_t sync_os_rwlock_write_lock(sync_os_rwlock_t *lock) {
  return (int32_t)pthread_rwlock_wrlock(lock);
}

static inline int32_t sync_os_rwlock_write_unlock(sync_os_rwlock_t *lock) {
  return (int32_t)pthread_rwlock_unlock(lock);
}

static inline void sync_os_cond_init(sync_os_cond_t *cond) {
  (void)pthread_cond_init(cond, NULL);
}

static inline void sync_os_cond_destroy(sync_os_cond_t *cond) {
  (void)pthread_cond_destroy(cond);
}

static inline int32_t sync_os_cond_wait(sync_os_cond_t *cond, sync_os_mutex_t *mutex) {
  return (int32_t)pthread_cond_wait(cond, mutex);
}

static inline void sync_os_cond_signal(sync_os_cond_t *cond) {
  (void)pthread_cond_signal(cond);
}

static inline void sync_os_cond_broadcast(sync_os_cond_t *cond) {
  (void)pthread_cond_broadcast(cond);
}
#endif

#endif
