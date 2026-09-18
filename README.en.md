# Codex Multi

A small native macOS launcher for running separate Codex account profiles side by side.

[中文](README.md) · [Compatibility](docs/COMPATIBILITY.md) · [Architecture](docs/ARCHITECTURE.md)

**v0.1.0 preview.** Independent community software, not affiliated with OpenAI. Bring your own installed Codex desktop app. This relies on an undocumented desktop data-directory override, so Codex updates may break it. Complete authentication and logout isolation with two real accounts still requires manual verification.

Verified on the recorded Apple Silicon environment: two independent instances, focus, targeted quit, and rediscovery after launcher restart. All 13 core checks passed.

## Download the preview

[Apple Silicon app ZIP](https://github.com/maimaimangmang/codex-multi/releases/download/v0.1.0/Codex-Multi-0.1.0-arm64.zip) · [Release notes and checksum](https://github.com/maimaimangmang/codex-multi/releases/tag/v0.1.0)

For M-series Macs. Extract and open `Codex Multi.app`, or move it into Applications. Install Codex separately. This build is ad-hoc signed and not notarized; macOS may require approval under System Settings → Privacy & Security. Only approve builds you trust, or build from source.

## Quick start

1. Open **Codex Multi.app**. It detects an installed application with bundle identifier `com.openai.codex`; use **Choose app** if needed.
2. Open **Personal** and sign in inside Codex.
3. Finish that login, then open **Work** and choose your other account in the browser login flow.
4. Use the dashboard or menu bar to reopen or focus each profile.

First sign-ins should be completed one at a time. The launcher does not import your existing login or conversation history. “Running” means the process is running, not that authentication succeeded. You can add or rename profiles, request a normal quit of one verified instance, or move a stopped profile to the Trash. Quitting the launcher leaves Codex running.

Windows and Dock entries retain the original ChatGPT / Codex app name. Matching names do not mean matching profile directories. Check the account email in each window to confirm you signed in to different accounts.

## Build

macOS 13+, Swift 5.9+, and Apple Command Line Tools or Xcode. Codex itself may impose newer OS or hardware requirements.

```bash
bash scripts/test.sh
bash scripts/build.sh            # current machine architecture
bash scripts/build.sh arm64
bash scripts/build.sh x86_64
```

Apps and ZIPs appear in `dist/`. No third-party Swift packages. Tests use a lightweight assertion runner so full Xcode/XCTest is not required. Intel launcher builds do not imply that a compatible Intel Codex build is available.

Builds are ad-hoc signed by default and are not notarized. For downloaded builds you trust, macOS may require approval in System Settings → Privacy & Security. Alternatively, build from source. Publishing instructions cover Developer ID signing.

## Isolation and privacy

Profiles live under `~/Library/Application Support/Codex Multi/profiles/<UUID>/`. Every launch passes separate `CODEX_HOME`, `CODEX_SQLITE_HOME`, `CODEX_ELECTRON_USER_DATA_PATH`, and `--user-data-dir` values. Fresh profiles select file credential storage; existing config is preserved. The launcher never reads credential contents or sends telemetry. The installed Codex app continues to use its own network services.

Profile directories are private to the macOS user (`0700`); registry and initial config are `0600`. Do not publish the profile directory, authentication files, or raw login logs. State isolation is not a security sandbox. Browser login sessions, OS permissions, organization policies, and some system integrations can still be shared. Custom configuration may change credential/SQLite behavior. Concurrent edits to one working directory may conflict.

The application bundle is never copied, modified, or redistributed. Each launch checks its identifier and scans for the isolation marker; that is a compatibility heuristic, not a guarantee. Process management validates PID, launch time, bundle path, and the profile lock before requesting quit. Unknown instances require manual intervention; there is no forced kill or global process shutdown.

References: [Codex state variables](https://learn.chatgpt.com/docs/config-file/environment-variables), [credential storage](https://learn.chatgpt.com/docs/auth).

MIT licensed. Contributions and version compatibility reports are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To uninstall, quit this launcher and its Codex instances, then remove the app. Profile data remains until explicitly moved to the Trash.
