#!/usr/bin/env python3
"""Run the native test suite with ThreadSanitizer enabled."""

from __future__ import annotations

from native_sanitizer_runner import main


if __name__ == "__main__":
    raise SystemExit(main("thread"))
