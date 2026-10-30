# Architecture

ShadowApp is a SwiftUI application and menu-bar launcher. It uses only Apple system frameworks. `CodexMultiCore` owns profile metadata, filesystem preparation, capability detection, launch plans, and `NSWorkspace` launching. `CodexMultiState` owns shared observable state and account operations; both UI surfaces and the assertion runner use it.

The UI groups profiles under an application sidebar. Codex and Claude have separate AppModel instances, capability checks, registries and process matching. Legacy Codex paths remain unchanged. Codex named directories use schema 2; Claude uses schema 3 with an explicit application identity under apps/claude. See [UI design](UI_DESIGN.md) for the second-application integration boundary.

## Launch sequence

1. Read the profile registry under an advisory file lock. Paths use the immutable directory name stored for that profile, with a UUID fallback for legacy entries. Filesystem actions resolve the current registry entry instead of trusting a cached UI path.
2. If a recorded process still matches its PID, launch timestamp, resolved bundle path, bundle identifier, and desktop singleton lock, focus that application.
3. Otherwise, require that no verified instance or live singleton lock exists for the profile. Unknown ownership blocks automated launch/quit/removal.
4. Validate the selected app's `Info.plist`, executable and the `CODEX_ELECTRON_USER_DATA_PATH` marker in its ASAR. The scan is streaming and retains overlap across chunk boundaries.
5. Create `codex/` and `desktop/` with `0700` permissions. Create a fresh config using file credential storage. Preserve existing config. Reject symlinks at managed paths before writes.
6. Use `NSWorkspace.OpenConfiguration`: `createsNewApplicationInstance = true`, application substitution disabled, isolated environment values and one literal user-data argument. No shell command interpolation.
7. Record the returned process identity. Wait up to 15 seconds for the desktop singleton lock to point to that process. Only then show it as running.

Environment values are passed for this launch only. Codex and Claude launches leave `HOME` unchanged. The launcher never changes its own `HOME`, `launchctl` global environment, the default `~/.codex` directory, or installed Codex files. macOS may add its own environment variables. It is not an isolation boundary for arbitrary processes executing as the same OS user.

## Persistence and process safety

Registry writes are atomic and serialized. A separate nonblocking OS file lock per profile covers the full asynchronous launch, provider updates and removal across current launcher processes. Locks live in `.operations/<uuid>.lock`, are never unlinked, and are released by descriptor close or process exit. These locks do not coordinate older launchers or external processes. Unsupported or corrupt registries produce errors rather than replacement defaults. The registry stores names, UUIDs, optional application path, and process receipts, not authentication data. A receipt is metadata, not a trusted authentication result.

After initialization, missing registries also produce errors rather than replacement defaults. Registry read failures suspend managed-profile status refresh and account operations until the user retries successfully. Failure information stays visible without repeated timer alerts; existing cached profiles show an unavailable status.

PID reuse is guarded by exact PID/path and launch-time checks. On normal launcher restart, recorded running instances are rediscovered. A launcher crash between launch and recording may leave an untracked live instance; the UI asks the user to quit that Codex instance manually. No force-quit fallback is provided.

Account removal rechecks live receipts and singleton locks under the registry lock, moves stopped profile data to the macOS Trash, and removes its registry entry. If saving the registry fails, the directory is moved back; if recovery also fails, the user is directed to the Trash. Trash is reversible; the launcher does not recursively erase user data. This is a local convenience tool, not designed to defend against another malicious process running as the same user or concurrent external manipulation of its directory.

## Development

`CODEX_MULTI_DATA_DIR` accepts an absolute directory to isolate development data. Keep it outside the source tree, or in an ignored directory. Tests use temporary directories and synthetic data. They do not inspect installed accounts, launch Codex, or use the network.

Authentication, browser callbacks, organization policy, and real application version compatibility must be tested manually. The automated tests do not claim to validate them.

## Existing Codex instances

Fresh registries contain no example profiles. Existing registries are preserved. A separate read-only process snapshot lists running applications with the Codex bundle identifier and records only PID, launch time, and resolved bundle path. Known profile receipts and singleton-lock PIDs are excluded from this list. Focusing revalidates the process identity; external instances are never imported into the registry and offer no quit or data-management actions. This list continues refreshing while the profile registry is unavailable. Account identity is not inferred from process metadata.

## API-key profiles

`Profile.apiProvider` is optional metadata (provider name, base URL, exact model ID); old registries decode with nil. `auth.json` contains the user-entered `OPENAI_API_KEY` and uses file credential storage. The provider uses `wire_api = "responses"` and `requires_openai_auth = true`, matching Codex's API-key authentication route. The app bundle is unmodified. No secrets enter registry metadata, process arguments, or generated TOML.

Creation validates all fields before publishing the new UUID. Private credential files are created with mode 0600 before writing and atomically renamed. Updates require a stopped profile, recheck the singleton lock/receipt, locate managed scalar settings with a bounded TOML lexical scanner and preserve unrelated source bytes. Reordering, comments, quoted keys and dotted keys are supported; ambiguous or unsupported managed fields, changed routing/authentication, or extra authentication headers are rejected. This is a conservative source editor, not a general TOML validator. A base URL change requires a new key. The key write is the final atomic operation; prior failures restore config and registry without reading existing credentials. No network request is made by the launcher when saving. Real model compatibility is not inferred from saving configuration.

Run `python3 scripts/check-provider-runtime.py /path/to/codex` on macOS to build a temporary fixture, check API auth and config through app-server, and run a Responses request against localhost. It uses only synthetic credentials and temporary HOME/CODEX_HOME directories, and does not modify the user's installed Codex or default credentials.

## Profile-aware model diagnostics

`ProfileGuidance` maintains a delimited block in each profile's `AGENTS.md`, and in a non-empty `AGENTS.override.md` when present. It uses the actual profile config path as a fallback if the tool environment omits CODEX_HOME. User text outside the block is preserved, malformed markers/symlinks fail safely, and repeated application is idempotent. Applying guidance does not read or modify credentials or configuration. Fresh API creation and launch preparation install/update the block. Focusing an existing window performs no profile-file writes. Folder reveal creates at most the profile root and works even with damaged auth/config or instructions. New conversations load it; already-running conversations may retain their earlier instructions. This is model guidance, not filesystem isolation or a guarantee of correct self-identification.

API onboarding explains the product selector and offers contextual help without changing Work authentication or the vendor app. Automatic product switching was not verified for individual isolated instances, so URLs are not sent to the system-default handler.

### 可读目录名

新建空间将安全过滤后的名称与 UUID 前 8 位保存为不可变 directoryName（例如 `胜算云-cdbcde16`），配置列表版本升为 2，以阻止旧程序忽略新目录字段后打开错误目录。仍读取版本 1；没有 directoryName 的旧空间继续使用完整 UUID，绝不隐式移动。目录字段校验路径字符、编号后缀及重复路径。显示名称重命名不改变目录。

## Claude adapter (2026-10-29)

`ManagedApplication` defines bundle identity, candidate paths, API-profile capability, and app-specific root. Claude uses `--user-data-dir=<desktop>` (one argument) and independent `CLAUDE_CONFIG_DIR` / `CLAUDE_SECURESTORAGE_CONFIG_DIR` pointing to `claude-code/`. HOME is unchanged. Do not use `CLAUDE_USER_DATA_DIR`: the packaged app removes it without official signed development authentication.

Claude’s normal launch creates no SingletonLock. A recorded PID is matched against bundle ID, path, launch timestamp, and exact user-data argv obtained via KERN_PROCARGS2. Only argc arguments are decoded; environment entries are neither decoded nor logged. Missing receipts or unreadable process arguments prevent automatic launch/deletion rather than guessing that a profile is stopped. Cross-process operation leases also apply to Claude. Registry schema/application mismatches fail without rewriting data.

Claude detection verifies version 4.29.0 and the tested ASAR SHA256. This is a compatibility gate, not cryptographic verification of the entire app bundle or a promise about user configuration. Reinspect on every launch. No application files are changed. Existing windows can still be focused when a newer app is not yet verified.

`swift` fixture `scripts/claude-runtime-fixture.swift` explicitly launches two new unsigned-in temporary profiles through AppModel, checks their storage/status/deletion guards, and normally terminates only verified test receipts. It is opt-in and excluded from CI; account acceptance remains manual.

## Claude API-key profiles

API profiles use schema 4 and desktop-3p/configLibrary/<profile UUID>.json, selected by _meta.json.appliedId; claude_desktop_config.json selects deploymentMode=3p. The native app would append -3p itself, so the launch argument names that directory from the start. Account-profile paths remain desktop/.

ClaudeProviderConfiguration writes the native gateway/static/bearer fields. It preserves unknown settings and an opaque native sealed key when editing; changes to routing, active library entry or auth source stop the edit. Keys are private file data, never registry or process arguments. Messages probes select their protocol from the owning application; Codex continues to send Responses requests. Same-profile operation leases and running-process checks cover both provider editors.

ModelInformation for Claude shows configured settings only, explicitly without inferred session evidence. The configured model ID is not proof of upstream routing. Native model discovery and launcher inference probes have separate assertions in scripts/check-claude-provider.py.

## Product identity

ShadowApp replaces the Codex Multi display name and app/archive filenames. The bundle identifier `org.codexmulti.launcher`, executable/Swift module names, data roots, preferences domain, and existing profile-guidance delimiters remain stable for upgrade compatibility. `ShadowAppBrand` draws the same S-and-shadow mark for the app icon, sidebar, and monochrome menu-bar template. `scripts/build.sh` compiles the icon generator using that shared source.

## WorkBuddy capability boundary

WorkBuddy 5.8.3 uses direct `Process` launch because LaunchServices prohibits additional instances. Each child receives private HOME, WORKBUDDY_CONFIG_DIR/CODEBUDDY_CONFIG_DIR and WORKBUDDY_USER_DATA_DIR. Only necessary inherited environment keys survive. Kernel process start time replaces missing NSRunningApplication.launchDate; argv confirms the profile. Schema 5 accepts account profiles, refuses API injection and upgrades empty legacy schema 3 registries. Preparation preserves app settings while disabling startupForceAutoUpdate. See [WorkBuddy evidence and limitations](WORKBUDDY.md).
