# Architecture

Codex Multi is a SwiftUI application and menu-bar launcher. It uses only Apple system frameworks. `CodexMultiCore` owns profile metadata, filesystem preparation, capability detection, launch plans, and `NSWorkspace` launching.

## Launch sequence

1. Read the profile registry under an advisory file lock. A profile name is display text; all paths use a generated UUID.
2. If a recorded process still matches its PID, launch timestamp, resolved bundle path, bundle identifier, and desktop singleton lock, focus that application.
3. Otherwise, require that no verified instance or live singleton lock exists for the profile. Unknown ownership blocks automated launch/quit/removal.
4. Validate the selected app's `Info.plist`, executable and the `CODEX_ELECTRON_USER_DATA_PATH` marker in its ASAR. The scan is streaming and retains overlap across chunk boundaries.
5. Create `codex/` and `desktop/` with `0700` permissions. Create a fresh config using file credential storage. Preserve existing config. Reject symlinks at managed paths before writes.
6. Use `NSWorkspace.OpenConfiguration`: `createsNewApplicationInstance = true`, application substitution disabled, isolated environment values and one literal user-data argument. No shell command interpolation.
7. Record the returned process identity. Wait up to 15 seconds for the desktop singleton lock to point to that process. Only then show it as running.

Environment values are passed for this launch only. The launcher never changes `HOME`, `launchctl` global environment, the default `~/.codex` directory, or installed Codex files. macOS may add its own environment variables. It is not an isolation boundary for arbitrary processes executing as the same OS user.

## Persistence and process safety

Registry writes are atomic and serialized. Unsupported or corrupt registries produce errors rather than replacement defaults. The registry stores names, UUIDs, optional application path, and process receipts, not authentication data. A receipt is metadata, not a trusted authentication result.

PID reuse is guarded by exact PID/path and launch-time checks. On normal launcher restart, recorded running instances are rediscovered. A launcher crash between launch and recording may leave an untracked live instance; the UI asks the user to quit that Codex instance manually. No force-quit fallback is provided.

Account removal moves stopped profile data to the macOS Trash and removes its registry entry. Trash is reversible; the launcher does not recursively erase user data. This is a local convenience tool, not designed to defend against another malicious process running as the same user or concurrent external manipulation of its directory.

## Development

`CODEX_MULTI_DATA_DIR` accepts an absolute directory to isolate development data. Keep it outside the source tree, or in an ignored directory. Tests use temporary directories and synthetic data. They do not inspect installed accounts, launch Codex, or use the network.

Authentication, browser callbacks, organization policy, and real application version compatibility must be tested manually. The automated tests do not claim to validate them.
