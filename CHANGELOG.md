# Changelog

All notable changes to `sync` are documented in this file.

## Unreleased

### Fixed

- Transfer thread and thread-pool task closures with consuming ownership so
  creator and worker threads do not concurrently mutate MoonBit's non-atomic
  reference count during task handoff.
- Release joined and detached thread tasks only after their callback has fully
  returned, removing the intermittent leaks reported by LeakSanitizer.
- Propagate native `ThreadPool::shutdown` status failures instead of silently
  treating them as success.
- Transfer generic channel payload boxes directly from sender to receiver,
  removing cross-thread reference-count races during successful sends while
  preserving payload return on full or closed channels.

### Testing

- Add private native failure injection for `Once`, `WaitGroup`, `RwLock`, and
  `ThreadPool` initialization and operation error mappings.
- Add a shared native sanitizer runner and an independent Linux
  ThreadSanitizer CI job with compiler/runtime preflight validation.
- Make private native fault-injection controls atomic so concurrent production
  operations do not race while whitebox injection is idle.

## 0.6.0

### Safety

- Bound `ThreadPool` construction to 64 workers and 16,384 queued tasks in both
  the MoonBit wrapper and native FFI boundary.
- Return `ThreadPoolCreationFailed` when thread-pool core or queue allocation
  fails instead of aborting through the shared fail-fast allocator.
- Add regression coverage for values above both resource limits.

## 0.5.0

### Breaking

- Make `unsafe.Thread` a `Unit`-returning handle. Generic result transport is
  now explicit through `unsafe.spawn_unchecked` and `UnsafeThread[T]`.
- Require every successful thread to be explicitly `join`ed or `detach`ed.
  Dropping a still-joinable thread handle fails fast instead of implicitly
  detaching the native thread.
- Add `detach`, `is_finished`, `ThreadAlreadyDetached`,
  `ThreadOperationInProgress`, and native thread lifecycle errors.
- Propagate native initialization and operation failures from `Once`,
  `WaitGroup`, `Mutex`, `ThreadPool`, and the remaining native synchronization
  finalizers through `SyncError` or fail-fast termination where no safe return
  path exists.

### Safety

- Keep arbitrary closure capture and generic result transport explicitly
  unsafe-by-contract. The API does not establish a `Send`/`Sync` boundary for
  MoonBit heap objects.
- Serialize thread-pool lifecycle transitions and validate native cleanup
  failures instead of silently continuing with an invalid synchronization
  object.

## 0.4.0

### Breaking

- Make construction and every stateful operation of both channel APIs raise
  `SyncError` when the native mutex or condition-variable operation fails.
  `ChannelInitializationFailed` identifies channel setup failures and
  `ChannelOperationFailed` identifies failures while sharing, sending,
  receiving, closing, or reading the queued length. The existing channel
  result enums still represent only normal full, empty, closed, and byte-limit
  outcomes.

## 0.3.0

### Breaking

- Restrict the root facade to native handles and the copied `OwnedBytes`
  channel. Move threads, thread pools, generic channels, generic mutexes, and
  condition variables to the explicit `Nanaloveyuki/sync/unsafe` facade.
- Replace `Condvar.wait(condvar, mutex)` with guard-based waiting inside
  `Mutex.with_lock`; retain the raw operation as
  `unsafe.condvar_wait_unchecked`.

### Safety

- Reject WaitGroup count overflow and validate queue allocation multiplication
  before allocation.
- Track the owning mutex thread across condition waits and reject obvious
  unlocked or foreign-thread waits before reaching the OS primitive.

## 0.2.1

- Bound owned-bytes channels by both per-message and aggregate queued-byte
  limits. The default limits are 4 MiB and 16 MiB respectively.
- Add explicit configuration and rejection results for callers that need to
  report oversized IPC payloads upstream.
- Move owned-byte copies outside the channel mutex so large payloads do not
  serialize queue operations while being copied.

## 0.2.0

- Split the concurrency features into independently consumable MoonBit
  subpackages while retaining the root facade entry points.
- Add `owned_bytes_bounded`, an explicit native-copying `Bytes` channel for
  safe serialized message transfer across OS threads.
- Add repository and README metadata for Mooncakes publication.
- Add macOS to the native CI matrix. Windows, Linux, and macOS are supported
  native release platforms.

### Compatibility

The root `Nanaloveyuki/sync` facade remains the supported consumer entry point.
Feature subpackages are public for focused imports. The generic channel,
thread, and thread-pool APIs do not establish a `Send`/`Sync` boundary; use
`owned_bytes_bounded` for background IPC payloads.
