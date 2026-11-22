#!/usr/bin/env python3
"""
Validate Anarva and package it with its per-OS installer as
    dist/anarva-<version>-windows-x64.zip
    dist/anarva-<version>-linux-x64.tar.gz
each with one top-level folder anarva-<version>-<os>-x64/ holding Anarva/stable/, the installer, README.md and
LICENSE, and a .sha256 beside every archive.

The native library (SkirmishAI.dll / libSkirmishAI.so) is NOT shipped: the installer copies BARb's from the
user's newest engine, so it always matches the engine the game runs.

Usage (from anywhere, Python 3.12, stdlib only):
    python build.py                      self-test, then package both archives
    python build.py --selftest           self-test only
    python build.py --checksum FILE...   rewrite the .sha256 of existing archives only
"""
import glob
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tarfile
import time
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
AI_DIR = os.path.join(ROOT, "Anarva", "stable")
DIST_DIR = os.path.join(ROOT, "dist")
APP_NAME = "anarva"
SHORT_NAME = "Anarva"
EXTRA_FILES = ("README.md", "LICENSE")
# Files that must never be packaged: the native library comes from the user's engine at install time.
EXCLUDED_SUFFIXES = (".dll", ".so", ".dylib", ".pyc")
EXCLUDED_DIRS = ("__pycache__",)

# (os tag, archive extension, installer files relative to ROOT, files that must be executable)
TARGETS = (
    ("windows", ".zip", ("installer/windows/install.cmd", "installer/windows/install.ps1"), ()),
    ("linux", ".tar.gz", ("installer/linux/install.sh",), ("install.sh",)),
)


def read_version() -> str:
    path = os.path.join(ROOT, "VERSION")
    if not os.path.isfile(path):
        raise SystemExit(f"VERSION file missing: {path}")
    with open(path, encoding="utf-8") as fh:
        version = fh.read().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit(f"VERSION must be MAJOR.MINOR.PATCH, got {version!r}")
    return version


# ---------------------------------------------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------------------------------------------

def strip_json_comments(text: str) -> str:
    """Remove // and /* */ comments outside of string literals, keeping newlines so line numbers stay right"""
    out = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = n if end < 0 else end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("unterminated /* comment")
            out.append("\n" * text.count("\n", i, end))
            i = end + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def strip_trailing_commas(text: str) -> str:
    """Drop a comma that is followed only by whitespace and then } or ] (outside strings).
    CircuitAI reads its configs with JsonCpp, which accepts these, and BARb's own configs contain them."""
    out = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            out.append(c)
        elif c == ",":
            j = i + 1
            while j < n and text[j].isspace():
                j += 1
            if j >= n or text[j] not in "}]":
                out.append(c)
        else:
            out.append(c)
        i += 1
    return "".join(out)


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def check_configs(errors: list) -> int:
    files = sorted(glob.glob(os.path.join(AI_DIR, "config", "**", "*.json"), recursive=True))
    if not files:
        errors.append(f"no config JSON found under {rel(os.path.join(AI_DIR, 'config'))}")
    for path in files:
        try:
            with open(path, encoding="utf-8") as fh:
                json.loads(strip_trailing_commas(strip_json_comments(fh.read())))
        except (ValueError, UnicodeDecodeError) as exc:
            errors.append(f"{rel(path)}: invalid JSON (comments and trailing commas allowed): {exc}")
    return len(files)


INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"', re.MULTILINE)


def check_includes(errors: list) -> int:
    files = sorted(glob.glob(os.path.join(AI_DIR, "script", "**", "*.as"), recursive=True))
    if not files:
        errors.append(f"no AngelScript found under {rel(os.path.join(AI_DIR, 'script'))}")
    count = 0
    for path in files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for match in INCLUDE_RE.finditer(text):
            count += 1
            target = os.path.normpath(os.path.join(os.path.dirname(path), match.group(1)))
            if not os.path.isfile(target):
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{rel(path)}:{line}: #include \"{match.group(1)}\" does not resolve ({rel(target)})")
    return count


def lua_value(text: str, key: str):
    """value of { key = '<key>', value = '...' } in an AIInfo-style table"""
    m = re.search(r"key\s*=\s*'" + re.escape(key) + r"'\s*,\s*value\s*=\s*'([^']*)'", text)
    return m.group(1) if m else None


def check_lua(errors: list) -> list:
    info_path = os.path.join(AI_DIR, "AIInfo.lua")
    opts_path = os.path.join(AI_DIR, "AIOptions.lua")
    missing = [p for p in (info_path, opts_path) if not os.path.isfile(p)]
    if missing:
        errors.extend(f"missing {rel(p)}" for p in missing)
        return []
    with open(info_path, encoding="utf-8") as fh:
        short = lua_value(fh.read(), "shortName")
    if short != SHORT_NAME:
        errors.append(f"{rel(info_path)}: shortName is {short!r}, expected {SHORT_NAME!r}")

    with open(opts_path, encoding="utf-8") as fh:
        opts = fh.read()
    m = re.search(r"key\s*=\s*'profile'.*?items\s*=\s*\{(.*?)\n\t\t\},", opts, re.DOTALL)
    if not m:
        errors.append(f"{rel(opts_path)}: no 'profile' list with items found")
        return []
    profiles = re.findall(r"key\s*=\s*'([^']+)'", m.group(1))
    if not profiles:
        errors.append(f"{rel(opts_path)}: 'profile' list has no item keys")
    for key in profiles:
        for kind in ("config", "script"):
            folder = os.path.join(AI_DIR, kind, key)
            if not os.path.isdir(folder):
                errors.append(f"{rel(opts_path)}: profile '{key}' has no {rel(folder)}/ directory")
    return profiles


def check_release_files(errors: list):
    needed = list(EXTRA_FILES) + [f for t in TARGETS for f in t[2]]
    for name in needed:
        if not os.path.isfile(os.path.join(ROOT, name)):
            errors.append(f"missing {name}")
    for name in needed:
        path = os.path.join(ROOT, name)
        if name.endswith(".sh") and os.path.isfile(path):
            with open(path, "rb") as fh:
                if b"\r\n" in fh.read():
                    errors.append(f"{name}: has CRLF line endings, bash on Linux will fail")


def selftest() -> None:
    errors: list = []
    read_version()
    n_json = check_configs(errors)
    n_inc = check_includes(errors)
    profiles = check_lua(errors)
    check_release_files(errors)
    if errors:
        print("SELF-TEST FAILED:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Self-test passed: {n_json} config JSON parsed, {n_inc} #include lines resolved, "
          f"shortName '{SHORT_NAME}', profiles {', '.join(profiles)} have config/ and script/ dirs.")


# ---------------------------------------------------------------------------------------------------------------
# packaging
# ---------------------------------------------------------------------------------------------------------------

def ai_files():
    """(absolute path, path inside Anarva/stable) of every file to ship, sorted"""
    result = []
    for folder, dirs, files in os.walk(AI_DIR):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
        for fn in sorted(files):
            if fn.lower().endswith(EXCLUDED_SUFFIXES):
                continue
            full = os.path.join(folder, fn)
            result.append((full, os.path.relpath(full, AI_DIR).replace(os.sep, "/")))
    if not result:
        raise SystemExit(f"nothing to package in {AI_DIR}")
    return result


def archive_entries(installers):
    """(source path, archive-relative path) for one target"""
    entries = [(src, f"Anarva/stable/{inner}") for src, inner in ai_files()]
    for name in installers:
        src = os.path.join(ROOT, name)
        if not os.path.isfile(src):
            raise SystemExit(f"missing installer file: {name}")
        entries.append((src, os.path.basename(name)))
    for name in EXTRA_FILES:
        src = os.path.join(ROOT, name)
        if not os.path.isfile(src):
            raise SystemExit(f"missing {name}")
        entries.append((src, name))
    return entries


def write_zip(archive: str, top: str, entries) -> None:
    stamp = time.localtime()[:6]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
        for src, arc in entries:
            info = zipfile.ZipInfo(f"{top}/{arc}", date_time=stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(src, "rb") as fh:
                zf.writestr(info, fh.read())


def write_tar(archive: str, top: str, entries, executables) -> None:
    now = int(time.time())
    with tarfile.open(archive, "w:gz") as tf:
        dirs = set()
        for _src, arc in entries:
            parts = arc.split("/")[:-1]
            for i in range(len(parts)):
                dirs.add("/".join(parts[:i + 1]))
        for d in [""] + sorted(dirs):
            info = tarfile.TarInfo(f"{top}/{d}".rstrip("/"))
            info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, now
            tf.addfile(info)
        for src, arc in entries:
            with open(src, "rb") as fh:
                data = fh.read()
            info = tarfile.TarInfo(f"{top}/{arc}")
            info.size, info.mtime = len(data), now
            info.mode = 0o755 if arc in executables else 0o644
            tf.addfile(info, io.BytesIO(data))


def checksum(archive: str) -> str:
    """Write <archive>.sha256 next to the archive so downloads can be verified"""
    if not os.path.isfile(archive):
        raise SystemExit(f"cannot checksum, no such file: {archive}")
    digest = hashlib.sha256()
    with open(archive, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    path = archive + ".sha256"
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"{digest.hexdigest()}  {os.path.basename(archive)}\n")
    return path


def package(version: str) -> list:
    shutil.rmtree(DIST_DIR, ignore_errors=True)
    os.makedirs(DIST_DIR)
    built = []
    for os_tag, ext, installers, executables in TARGETS:
        top = f"{APP_NAME}-{version}-{os_tag}-x64"
        archive = os.path.join(DIST_DIR, top + ext)
        entries = archive_entries(installers)
        if ext == ".zip":
            write_zip(archive, top, entries)
        else:
            write_tar(archive, top, entries, executables)
        built.append(archive)
        print(f"Built {rel(archive)} ({len(entries)} files, {os.path.getsize(archive) / 1024:.1f} KB)")
        print(f"Checksum: {rel(checksum(archive))}")
    return built


def main() -> None:
    args = sys.argv[1:]
    if "--checksum" in args:
        targets = args[args.index("--checksum") + 1:]
        if not targets:
            raise SystemExit("--checksum needs at least one archive path")
        for archive in targets:
            print(f"Checksum: {checksum(archive)}")
        return
    selftest()
    if "--selftest" in args:
        return
    package(read_version())


if __name__ == "__main__":
    main()
