#!/usr/bin/env python3
"""Check a prepared probe's identity, signature, extensions and optional runtime.

Diagnostic only. Never launches, signs, repairs or logs in to WeChat. A failed
check must block the launch workflow; it must not trigger an unsandboxed fallback.
"""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*args):
    result = subprocess.run(args, capture_output=True)
    require(result.returncode == 0, result.stderr.decode(errors="replace").strip())
    return result


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def check_bundle(manifest):
    report = json.loads(manifest.read_text())
    require(report.get("schema_version") == 2, "Recreate this probe with the current preparation tool.")
    identifier = report["bundle_id"]
    require(re.fullmatch(r"org\.shadowapp\.wechat\.probe\.[a-z0-9]{8,32}", identifier),
            "Invalid probe identity.")
    app = Path(report["output"])
    require(app.is_absolute() and app.suffix == ".app" and not app.is_symlink(), "Invalid probe path.")
    app = app.resolve(strict=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == identifier, "Bundle identity changed.")
    require(info.get("TeamIdentifier") == "group.", "IPC prefix changed.")
    require(info.get("CFBundleShortVersionString") == "4.1.15"
            and str(info.get("CFBundleVersion")) == "270115", "Unverified version.")
    require(not info.get("CFBundleURLTypes"), "Probe must not register WeChat URL schemes.")
    require(not any(app.rglob("*.appex")), "Unreviewed app extension present.")
    require(not any(app.rglob("*.xpc")), "Unreviewed XPC service present.")
    for name, relative in {
        "main_sha256": "Contents/MacOS/WeChat",
        "info_sha256": "Contents/Info.plist",
        "resources_sha256": "Contents/_CodeSignature/CodeResources",
    }.items():
        require(digest(app / relative) == report["integrity"][name], "Probe was changed: " + relative)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    entitlements = plistlib.loads(run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)).stdout)
    require(entitlements.get("com.apple.security.app-sandbox") is True, "App Sandbox missing.")
    require(entitlements.get("com.apple.security.application-groups") == ["group." + identifier],
            "Unexpected shared application group.")
    require(not any(key in entitlements for key in (
        "com.apple.application-identifier", "com.apple.developer.team-identifier",
        "com.apple.security.inherit", "keychain-access-groups",
    )), "Unexpected identity or inheritance entitlement.")
    signature = run("/usr/bin/codesign", "-dv", str(app)).stderr.decode(errors="replace")
    require(re.search(r"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b", signature), "Hardened Runtime missing.")
    # Validate every remaining executable helper, including helpers not yet started.
    helpers = sorted(app.rglob("*.app"))
    helpers.append(app / "Contents/Frameworks/crashpad_handler")
    for helper in helpers:
        e = plistlib.loads(run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(helper)).stdout)
        require(e.get("com.apple.security.app-sandbox") is True
                and e.get("com.apple.security.inherit") is True,
                "Helper does not inherit sandbox: " + str(helper.relative_to(app)))
        require(set(e) <= {"com.apple.security.app-sandbox", "com.apple.security.inherit",
                           "com.apple.security.cs.allow-jit"},
                "Unreviewed helper permissions: " + str(helper.relative_to(app)))
    container = Path.home() / "Library/Containers" / identifier
    require(str(container) == report["container"], "Unexpected data container.")
    return app, container, identifier, len(helpers)


def check_runtime(pid, app, container):
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    libproc.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    require(libproc.proc_pidpath(pid, buffer, len(buffer)) > 0, "Cannot identify process.")
    require(Path(os.fsdecode(buffer.value)).resolve() == app / "Contents/MacOS/WeChat",
            "PID does not belong to this probe.")
    library = ctypes.CDLL("/usr/lib/libsandbox.1.dylib", use_errno=True)
    check = library.sandbox_check
    check.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    check.restype = ctypes.c_int
    ctypes.set_errno(0)
    sandbox_result = check(pid, None, 0)
    require(sandbox_result == 1,
            f"Runtime sandbox check failed (result={sandbox_result}, errno={ctypes.get_errno()}).")
    no_report = ctypes.c_int.in_dll(library, "SANDBOX_CHECK_NO_REPORT").value
    own_directory = container / "Data/Documents"
    require(own_directory.is_dir(), "Probe data directory is not initialized.")
    # Use only brand-new synthetic files. Do not read any real account data.
    canaries = []
    try:
        for directory in (own_directory, Path.home()):
            fd, path = tempfile.mkstemp(prefix=".shadowapp-check-", dir=directory)
            os.close(fd)
            canaries.append(Path(path))
        for operation in (b"file-read-data", b"file-write-data"):
            for path, expected in zip(canaries, (0, 1)):
                result = check(pid, operation, 1 | no_report, ctypes.c_char_p(os.fsencode(path.resolve())))
                require(result == expected, "Unexpected sandbox access result for synthetic file.")
    finally:
        for path in canaries:
            path.unlink(missing_ok=True)
    return {"pid": pid, "sandbox_active": True, "own_canary_allowed": True,
            "outside_canary_denied": True, "operations": ["read", "write"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--pid", type=int, help="Also verify the already-running main process.")
    args = parser.parse_args()
    require(sys.platform == "darwin", "This diagnostic requires macOS.")
    app, container, identifier, helpers = check_bundle(args.manifest)
    result = {"status": "passed", "bundle_id": identifier, "verified_helpers": helpers,
              "signature_and_integrity": True, "system_extensions": "absent", "url_schemes": "absent"}
    if args.pid is not None:
        result["runtime"] = check_runtime(args.pid, app, container)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        sys.exit(f"Probe check failed: {error}")
