# sync

`sync` provides native concurrency primitives for MoonBit applications. It is
intended for native programs that explicitly control their OS-thread boundary;
it is not an async runtime or a UI-thread dispatcher.

## Install

```sh
moon add Nanaloveyuki/sync@0.6.0
```

Import the root facade from a consumer package:

```moonbit
import {
  "Nanaloveyuki/sync",
}
```

The root facade intentionally contains only primitive atomic values,
`WaitGroup`, and the copied `OwnedBytes` message path. Import
`Nanaloveyuki/sync/unsafe` explicitly for OS-thread spawning, generic channels,
generic mutexes, callback-based `Once` / `RwLock`, or thread pools.

## Platform Support

`sync` supports MoonBit's `native` target on Windows, Linux, and macOS. Each
release is checked and tested on all three platforms in GitHub Actions. macOS
coverage currently runs in CI only; no physical-device validation is part of
the release gate.

JavaScript, Wasm, Wasm-GC, Android, and OpenHarmony are not supported targets.

## Concurrency Boundary

MoonBit native reference counting is not atomic and the language does not
enforce `Send` or `Sync`. Do not pass aliased MoonBit objects, including
`String`, `Bytes`, `Array`, `Json`, `Ref`, generic channel payloads, or
captured closures, between OS threads without an explicit ownership boundary.

For serialized work such as IPC, use `owned_bytes_bounded`. It copies input
bytes into native-owned storage before `send` returns and allocates a fresh
`Bytes` value on `recv`; the channel does not retain a MoonBit heap alias from
the sending thread. The default limits are 4 MiB per message and 16 MiB across
all queued payloads.

```moonbit nocheck
import {
  "Nanaloveyuki/sync/unsafe",
}

let (sender, receiver) = try! @sync.owned_bytes_bounded(32)
let worker_sender = try! sender.share()
let worker = try! @unsafe.spawn(fn() raise {
  ignore(worker_sender.send(b"serialized request"))
})

match try! receiver.recv() {
  Some(payload) => handle_ipc(payload)
  None => ()
}
worker.join()
```

Use explicit limits when the IPC protocol has a tighter budget. Oversized
messages are rejected before copying; `send_checked` returns the actual and
allowed sizes so the caller can report the error upstream. `try_send` returns
`QueueByteLimitReached(actual, maximum)` when accepting the message would
exceed the total queued-byte limit.

```moonbit nocheck
let (sender, receiver) = try! @sync.owned_bytes_bounded_with_limits(
  64,
  max_message_bytes=1024 * 1024,
  max_queued_bytes=8 * 1024 * 1024,
)

match try! sender.send_checked(payload) {
  @sync.OwnedBytesSendResult::Sent => ()
  @sync.OwnedBytesSendResult::MessageTooLarge(actual, maximum) =>
    report_rejected_payload(actual, maximum)
  @sync.OwnedBytesSendResult::Closed => ()
}
```

`sync/unsafe` contains callback-based `Once` and `RwLock`, the generic bounded
channel, generic mutex, threads, and thread pools. They remain useful for
narrowly controlled native work, but are not a safe transfer boundary for IPC
payloads or arbitrary closures. `Once::call_once`, `RwLock::with_read`, and
`RwLock::with_write` execute callbacks on a calling thread, but MoonBit cannot
verify that those callbacks capture only thread-safe native handles.

`@unsafe.spawn` is the default thread entry point and only allows a `Unit`
result. It still accepts an arbitrary closure because MoonBit has no static
`Send`/`Sync` check, so its capture set must obey the contract above. A result
thread is available only through the explicitly named
`@unsafe.spawn_unchecked`, which returns `UnsafeThread[T]` and makes the
unchecked result boundary visible at every call site. Both entry points
consume the submitted closure so the library can transfer its reference to the
worker without overlapping creator and worker reference-count updates.

```moonbit nocheck
let worker = try! @unsafe.spawn(fn() raise {
  // Capture only thread-local data or shared native handles.
  do_native_work()
})
worker.join()
```

Every successful thread must be closed with exactly one `join` or `detach`.
Dropping a `Thread` or `UnsafeThread` while it is still joinable is a
programming error and intentionally aborts the process; the library never
silently detaches an untracked worker. `is_finished` is an observation only
and does not replace `join` or `detach`.

`ThreadPool::new` accepts at most 64 workers and 16,384 queued tasks. Larger
values raise `InvalidWorkerCount` or `InvalidCapacity` before native resources
are created. If native pool construction cannot allocate its core or queue, it
raises `ThreadPoolCreationFailed` instead of aborting on allocation failure.
`execute` and `try_execute` consume their task closure on every outcome.

## Unreleased Migration

`Once` and `RwLock` are now explicitly unsafe because their callback capture
sets cannot be constrained by MoonBit's current type system.

| Before | Unreleased |
| --- | --- |
| `@sync.Once` | `@unsafe.Once` |
| `@sync.RwLock` | `@unsafe.RwLock` |
| `Nanaloveyuki/sync/once` | `Nanaloveyuki/sync/unsafe/once` |
| `Nanaloveyuki/sync/rwlock` | `Nanaloveyuki/sync/unsafe/rwlock` |

Atomic primitives, `WaitGroup`, and `OwnedBytes` remain in the root facade.

## 0.6 Migration

`0.6.0` adds an explicit native resource budget to `ThreadPool` construction.

- Values above 64 workers or 16,384 queued tasks are rejected with the existing
  `SyncError::InvalidWorkerCount` or `SyncError::InvalidCapacity` variants.
- Thread-pool core and queue allocation failures now raise
  `SyncError::ThreadPoolCreationFailed`; callers must not assume construction
  can abort the process on memory pressure.
- Existing pools with ordinary sizes keep the same FIFO, close, shutdown, and
  task ownership behavior.

## 0.5 Migration

`0.5.0` makes the native thread lifecycle explicit and tightens native error
handling across the concurrency layer.

- `Thread` is now `Unit`-returning. Replace `Thread[T]` result workers with
  `spawn_unchecked` and `UnsafeThread[T]` only when the unchecked result is
  necessary.
- Replace implicit detach-on-drop with an explicit `detach`. A dropped
  joinable thread handle aborts, which exposes leaked worker ownership during
  testing instead of allowing it to run unnoticed.
- `join`, `detach`, `is_finished`, and native construction failures raise
  `SyncError`. `Once`, `WaitGroup`, `Mutex`, and `ThreadPool` now propagate
  native initialization or operation failures as well.
- The native finalizers fail fast when synchronization destruction or an
  internal wake-up fails. This is deliberate: continuing after a broken native
  synchronization primitive would make later memory and lifecycle failures
  harder to diagnose.

## 0.4 Migration

`0.4.0` makes native channel failures explicit. Constructors and operations
that enter the channel synchronization state now raise `SyncError`; handle
them with normal MoonBit error propagation or `try!` where aborting is the
right policy. This applies to `share`, `try_send`, `send`, `send_checked`,
`try_recv`, `recv`, `close`, and `length` on both the root `OwnedBytes` and
`unsafe` generic channel APIs. Their existing result enums still describe
ordinary queue outcomes, not OS failures.

## 0.3 Migration

`0.3.0` deliberately moves raw APIs behind an explicit import:

| Before | 0.3.0 |
| --- | --- |
| `@sync.spawn`, `@sync.Thread`, `@sync.ThreadPool` | `@unsafe.spawn`, `@unsafe.Thread`, `@unsafe.ThreadPool` |
| `@sync.bounded`, `@sync.Sender`, `@sync.Receiver` | `@unsafe.bounded`, `@unsafe.Sender`, `@unsafe.Receiver` |
| `@sync.Mutex`, `@sync.Condvar` | `@unsafe.Mutex`, `@unsafe.Condvar` |

Within `@unsafe.Mutex.with_lock`, use `MutexGuard.with_value` to access the
protected value and pass that guard to `Condvar.wait`. The old raw wait form is
available only as `@unsafe.condvar_wait_unchecked`.

## Lifecycle Semantics

| Primitive | Close and drop behavior |
| --- | --- |
| `OwnedBytesSender` | `close` is idempotent. The final sender drop closes the channel. |
| `OwnedBytesReceiver` | `close` is idempotent and wakes blocked endpoints. Queued messages drain before `recv` returns `None`. |
| `unsafe.Sender` / `unsafe.Receiver` | Their close and drain semantics are unchanged, but payload ownership remains caller-enforced. |
| `unsafe.Thread` / `unsafe.UnsafeThread[T]` | `join` or `detach` is required exactly once; dropping a joinable handle aborts. |
| `unsafe.ThreadPool` | `close` rejects new tasks. `shutdown` drains accepted tasks, is idempotent from external threads, and rejects calls from a pool worker. |

Blocking channel operations, joins, waits, condition-variable waits, and pool
shutdown must not run on a UI event-loop thread.

## Verification

```sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
```

On a supported native Linux host, run the native sanitizer workflows with:

```sh
python3 scripts/run-asan.py --repo-root .
python3 scripts/run-tsan.py --repo-root .
```

The runners first verify that the selected compiler and sanitizer runtime can
start a trivial executable, then use temporary package configuration and build
directories. ASan/UBSan and ThreadSanitizer run separately because their
compiler runtimes cannot be combined.
