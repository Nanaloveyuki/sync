# Changelog

All notable changes to `sync` are documented in this file.

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
