#!/usr/bin/env python3
"""Prepare a local, sandboxed WeChat compatibility probe; never launch or log in.

This is a diagnostic tool, not supported WeChat integration. See docs/WECHAT.md.
Only the verified Mac App Store 4.1.15 build is accepted. The original app and
its containers are never edited. Output must not exist; no cleanup is automatic.
"""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import uuid


KNOWN_EXECUTABLE_SHA256 = (
    "0a6eb182d2ccf2bd005d778d2be8f3e675df3bfa7a7e9c904348e93d0ae8a10a"
)
UNSUPPORTED_EXTENSIONS = {
    "WeChatFileProviderExtension.appex",
    "WeChatMacShare.appex",
}
IDENTITY_ENTITLEMENTS = {
    "com.apple.application-identifier",
    "com.apple.developer.team-identifier",
    "com.apple.security.application-groups",
}
SANDBOX_ENTITLEMENTS = {
    "com.apple.security.app-sandbox",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.device.audio-input",
    "com.apple.security.device.camera",
    "com.apple.security.files.bookmarks.app-scope",
    "com.apple.security.files.downloads.read-write",
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.network.client",
    "com.apple.security.network.server",
    "com.apple.security.personal-information.location",
    "com.apple.security.personal-information.photos-library",
    "com.apple.security.print",
}


def run(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("/Applications/WeChat.app"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bundle-id", default="org.shadowapp.wechat.probe." + uuid.uuid4().hex)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This probe requires macOS.")
    if not re.fullmatch(r"org\.shadowapp\.wechat\.probe\.[a-z0-9]{8,32}", args.bundle_id):
        parser.error("Use org.shadowapp.wechat.probe. followed by 8–32 lowercase letters/digits.")

    source = args.source.resolve(strict=True)
    output = args.output.absolute()
    if output.exists() or output.is_symlink() or output.suffix != ".app":
        parser.error("Output must be a new .app path.")
    parent = output.parent.resolve(strict=True)
    output = parent / output.name
    if parent == source or source in parent.parents:
        parser.error("Output must be outside the original app.")
    manifest = parent / (output.stem + "-probe.json")
    entitlements_file = parent / (output.stem + "-entitlements.plist")
    if any(p.exists() or p.is_symlink() for p in (manifest, entitlements_file)):
        parser.error("Probe metadata already exists; choose a new output name.")

    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    executable = source / "Contents/MacOS/WeChat"
    if (info.get("CFBundleIdentifier") != "com.tencent.xinWeChat"
            or info.get("CFBundleShortVersionString") != "4.1.15"
            or str(info.get("CFBundleVersion")) != "270115"
            or digest(executable) != KNOWN_EXECUTABLE_SHA256):
        parser.error("Unverified WeChat build. Do not reuse this probe across versions.")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R",
        '=anchor apple generic and identifier "com.tencent.xinWeChat"', str(source))
    original = plistlib.loads(run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(source)))
    if original.get("com.apple.security.app-sandbox") is not True:
        parser.error("Expected original App Sandbox entitlement.")
    if set(original) - IDENTITY_ENTITLEMENTS - SANDBOX_ENTITLEMENTS:
        parser.error("Unreviewed original entitlements; stop instead of silently dropping them.")
    plugins = source / "Contents/PlugIns"
    if not plugins.is_dir() or plugins.is_symlink():
        parser.error("Unexpected extension directory layout.")
    if {p.name for p in plugins.iterdir()} != UNSUPPORTED_EXTENSIONS:
        parser.error("Unreviewed app extensions; stop instead of inheriting their identities.")
    if any(p.is_symlink() or not p.is_dir() for p in plugins.iterdir()):
        parser.error("Unexpected app extension type.")

    # This prefix is local to the probe, not Tencent's signing/team identity.
    group = "group." + args.bundle_id
    entitlements = {key: value for key, value in original.items() if key in SANDBOX_ENTITLEMENTS}
    entitlements["com.apple.security.application-groups"] = [group]
    # A locally signed main executable cannot otherwise load Tencent-signed libraries.
    # Keep Hardened Runtime and sandbox, but disclose this reduced code validation.
    entitlements["com.apple.security.cs.disable-library-validation"] = True
    with entitlements_file.open("xb") as file:
        plistlib.dump(entitlements, file)
    run("/bin/cp", "-cR", str(source), str(output))
    # These system-launched extensions do not inherit the main app's sandbox.
    # Remove only the copied, reviewed extensions: they retain Tencent's group.
    for name in sorted(UNSUPPORTED_EXTENSIONS):
        copied_extension = output / "Contents/PlugIns" / name
        if copied_extension.is_symlink() or not copied_extension.is_dir():
            raise RuntimeError("Unexpected copied extension; do not launch this probe.")
        shutil.rmtree(copied_extension)
    info["CFBundleIdentifier"] = args.bundle_id
    info["TeamIdentifier"] = "group."
    # Avoid competing with the original installation for weixin/wechat URLs.
    info.pop("CFBundleURLTypes", None)
    (output / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    # Sign ONLY the outer app; nested helpers retain sandbox+inherit and vendor signatures.
    run("/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime",
        "--entitlements", str(entitlements_file), str(output))
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(output))
    if digest(executable) != KNOWN_EXECUTABLE_SHA256:
        raise RuntimeError("Source changed during preparation; do not launch this probe.")
    report = {
        "schema_version": 2,
        "status": "prepared_not_launched",
        "source": str(source), "output": str(output), "bundle_id": args.bundle_id,
        "source_version": "4.1.15 (270115)", "source_main_sha256": KNOWN_EXECUTABLE_SHA256,
        "app_group": group, "sandbox": True, "hardened_runtime": True,
        "library_validation_exception": True, "signature": "local_ad_hoc",
        "disabled_extensions": sorted(UNSUPPORTED_EXTENSIONS),
        "registers_wechat_url_schemes": False,
        "integrity": {
            "main_sha256": digest(output / "Contents/MacOS/WeChat"),
            "info_sha256": digest(output / "Contents/Info.plist"),
            "resources_sha256": digest(output / "Contents/_CodeSignature/CodeResources"),
        },
        "container": str(Path.home() / "Library/Containers" / args.bundle_id),
        "untested": ["account_login", "login_persistence", "messaging", "updates", "notifications", "media"],
    }
    with manifest.open("x") as file:
        json.dump(report, file, ensure_ascii=False, indent=2)
        file.write("\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, plistlib.InvalidFileException) as error:
        sys.exit(f"Probe preparation failed: {error}")
