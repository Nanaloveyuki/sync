#!/usr/bin/env python3
"""Run the native test suite with ASan and UBSan enabled.

The runner patches package configuration only for the duration of the command,
uses a temporary MoonBit target directory, and restores every file and the
MoonBit runtime allocator in a finally block. It is intentionally Linux-only;
the regular CI matrix remains responsible for Windows and macOS validation.
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


SANITIZER_FLAGS = (
    "-g -fsanitize=address,undefined -fno-omit-frame-pointer "
    "-fno-sanitize-recover=all"
)


def _matching_paren(text: str, start: int) -> int:
    depth = 0
    quote = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            continue
        if char == '"':
            quote = True
        elif char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unclosed options(...) block")


def _patch_package(text: str, *, has_stub: bool, is_entry: bool) -> str:
    entries: list[str] = []
    if has_stub:
        entries.append(f'"stub-cc-flags": "{SANITIZER_FLAGS}"')
    if is_entry:
        entries.append(f'"cc-flags": "{SANITIZER_FLAGS}"')
        entries.append(f'"cc-link-flags": "{SANITIZER_FLAGS}"')
    if not entries:
        return text

    indent = "  "
    native_entries = ",\n".join(f"{indent * 3}{entry}" for entry in entries)
    link = (
        f"\n{indent}link: {{\n"
        f'{indent * 2}"native": {{\n'
        f"{native_entries}\n"
        f"{indent * 2}}},\n"
        f"{indent}}},"
    )

    marker = "options("
    start = text.find(marker)
    if start < 0:
        return text.rstrip() + "\n\noptions(" + link + "\n)\n"
    close = _matching_paren(text, start + len("options"))
    body_start = start + len(marker)
    body = text[body_start:close]
    if "link:" in body or '"link"' in body:
        raise ValueError("package already has link configuration; patch it explicitly")
    insertion = body.rstrip()
    if insertion and not insertion.endswith(","):
        insertion += ","
    insertion += link
    return text[:body_start] + insertion + "\n" + text[close:]


def _is_entry(package_dir: Path, text: str) -> bool:
    is_main = re.search(r"\bis-main\b\s*:\s*true\b", text) is not None
    is_executable = re.search(
        r"\bpkgtype\s*\(\s*kind\s*:\s*\"executable\"", text
    ) is not None
    return is_main or is_executable or any(package_dir.glob("*_test.mbt"))


def _find_moonbitrun() -> Path:
    moon = shutil.which("moon")
    candidates: list[Path] = []
    if moon:
        candidates.append(Path(moon).resolve().parent.parent / "lib" / "libmoonbitrun.o")
    moon_home = Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
    candidates.append(moon_home / "lib" / "libmoonbitrun.o")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("could not locate libmoonbitrun.o")


def _disable_mimalloc(cc: str) -> tuple[Path, bytes]:
    runtime = _find_moonbitrun()
    original = runtime.read_bytes()
    try:
        with tempfile.NamedTemporaryFile(suffix=".c") as source:
            source.write(b"/* sanitizer allocator replacement */\n")
            source.flush()
            subprocess.run([cc, "-c", source.name, "-o", str(runtime)], check=True)
    except Exception:
        runtime.write_bytes(original)
        raise
    return runtime, original


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--no-disable-mimalloc",
        action="store_true",
        help="keep MoonBit's bundled allocator (not recommended)",
    )
    args = parser.parse_args()

    if platform.system() != "Linux":
        raise SystemExit("run-asan.py is Linux-only; use the native CI matrix elsewhere")
    root = args.repo_root.resolve()
    package_files = sorted((root / "src").rglob("moon.pkg"))
    if not package_files:
        raise SystemExit(f"no MoonBit packages found below {root / 'src'}")

    cc = shutil.which("clang") or shutil.which("cc")
    if cc is None:
        raise SystemExit("clang or cc is required for sanitizer validation")

    snapshots = {path: path.read_text(encoding="utf-8") for path in package_files}
    allocator_backup: tuple[Path, bytes] | None = None
    try:
        for path in package_files:
            original = snapshots[path]
            has_stub = '"native-stub"' in original or "native-stub" in original
            is_entry = _is_entry(path.parent, original)
            patched = _patch_package(original, has_stub=has_stub, is_entry=is_entry)
            if patched != original:
                path.write_text(patched, encoding="utf-8")

        if not args.no_disable_mimalloc:
            allocator_backup = _disable_mimalloc(cc)

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:fast_unwind_on_malloc=0:abort_on_error=1"
        env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
        with tempfile.TemporaryDirectory(prefix="moonbit-sync-asan-") as target_dir:
            command = [
                "moon",
                "test",
                "--target",
                "native",
                "--deny-warn",
                "--target-dir",
                target_dir,
            ]
            return subprocess.run(command, cwd=root, env=env).returncode
    finally:
        for path, original in snapshots.items():
            path.write_text(original, encoding="utf-8")
        if allocator_backup is not None:
            runtime, original = allocator_backup
            runtime.write_bytes(original)


if __name__ == "__main__":
    raise SystemExit(main())
