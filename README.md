# sync

`sync` provides native concurrency primitives for MoonBit applications. It is
intended for native programs that explicitly control their OS-thread boundary;
it is not an async runtime or a UI-thread dispatcher.

## Install

```sh
moon add Nanaloveyuki/sync@0.2.0
```

Import the root facade from a consumer package:

```moonbit
import {
  "Nanaloveyuki/sync",
}
```

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
let (sender, receiver) = @sync.owned_bytes_bounded(32)
let worker_sender = sender.share()
let worker = @sync.spawn(fn() {
  ignore(worker_sender.send(b"serialized request"))
})

match receiver.recv() {
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
let (sender, receiver) = @sync.owned_bytes_bounded_with_limits(
  64,
  max_message_bytes=1024 * 1024,
  max_queued_bytes=8 * 1024 * 1024,
)

match sender.send_checked(payload) {
  @sync.OwnedBytesSendResult::Sent => ()
  @sync.OwnedBytesSendResult::MessageTooLarge(actual, maximum) =>
    report_rejected_payload(actual, maximum)
  @sync.OwnedBytesSendResult::Closed => ()
}
```

The generic bounded channel and `ThreadPool` are useful for narrowly controlled
native work, but are not a safe transfer boundary for IPC payloads or arbitrary
closures.

## Lifecycle Semantics

| Primitive | Close and drop behavior |
| --- | --- |
| `Sender` / `OwnedBytesSender` | `close` is idempotent. The final sender drop closes the channel. |
| `Receiver` / `OwnedBytesReceiver` | `close` is idempotent and wakes blocked endpoints. Queued messages drain before `recv` returns `None`. |
| `Thread` | `join` is single-use; dropping an unjoined handle detaches the OS thread. |
| `ThreadPool` | `close` rejects new tasks. `shutdown` drains accepted tasks, is idempotent from external threads, and rejects calls from a pool worker. |

Blocking channel operations, joins, waits, condition-variable waits, and pool
shutdown must not run on a UI event-loop thread.

## Verification

```sh
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
```
