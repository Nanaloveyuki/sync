# Changelog

All notable changes to `sync` are documented in this file.

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
