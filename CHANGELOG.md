# Changelog

## Unreleased

- Rewrite the Chinese and English READMEs around ShadowApp, with bilingual interface images, current compatibility, API-key setup, data lifecycle and reproducible documentation rendering.

- Add experimental WeChat profiles for the verified Mac App Store 4.1.15 (270115) build on Apple Silicon. Prepare per-profile locally signed copies with App Sandbox, unique identities and system data containers; check integrity and runtime sandbox before use.
- Add WeChat navigation, installed-app icons, account data paths, window focus, targeted quit, process-receipt recovery, and archive/restore that preserves app copies and account data. System sharing extensions and external WeChat URL handlers are excluded from copies; library validation is relaxed only in the local copies.

- Add WorkBuddy 5.8.3 multi-instance preview using direct child launch, private per-profile HOME and app directories, version verification, kernel process identity, and safe registry migration. Preserve settings while disabling silent startup update installation. Custom models remain configured inside WorkBuddy.

- Rename the product to ShadowApp and share an S-and-shadow icon across the app, sidebar, and menu bar; update app/archive names while retaining bundle identity and existing profile storage.
- Avoid a duplicate-name error flashing after successful creation while the profile editor dismisses.

- Add Claude API-key profiles using native third-party Gateway configuration, with independent keys/model IDs and Anthropic Messages connection tests.
- Preserve native sealed keys and unrelated settings on edits; reject changed routes/selections and non-Claude model IDs before launch.

- Add Claude desktop profiles (preview), app-specific registries/navigation/menu actions and installed-app icons; preserve existing Codex paths.
- Verify Claude 4.29.0 by ASAR fingerprint, isolate desktop/Code directories, and match live profiles by exact process arguments where no singleton lock exists.
- Protect running Claude profiles even if their process receipt is missing; test two temporary unsigned-in instances through the shared application state.

- Edit client-reordered provider configuration while retaining unrelated settings/comments and rejecting routing or authentication conflicts.
- Serialize same-profile launches, connection edits and removal across launcher processes with OS-owned operation leases; verify release after process death.

- Keep folder reveal and window focus independent of configuration writes; resolve current profile paths before filesystem operations.
- Recheck process state before trashing, restore the folder on registry-save failure, and atomically write the private registry within its readable size limit.
- Reject removed profiles before launching and run connection-probe checks in CI.

- Show duplicate-name validation immediately and keep save errors visible above the editor buttons.
- Add an optional Responses API connection test with cancellation and safe error messages; no automatic requests on save.

- 空间卡片显示实际目录并支持打开、复制；新空间使用名称加短编号，兼容已有 UUID 路径，不自动迁移运行中的空间。

- 新增「模型信息」：分别显示启动器设置和最近本地会话的模型记录，不采用模型自报的名称。目录指引要求核实后才能声称已读取元数据。

- Add isolated-profile instructions to prevent model diagnostics from reading the default Codex home; preserve existing user guidance.
- Explain the Codex product selector for API profiles and distinguish Work browser authentication from provider-key errors.

- Add API-key profiles with a Shengsuanyun preset, custom base URLs and exact model IDs.
- Allow stopped API profiles to change model/key while preserving unrelated configuration; store credentials privately per profile.

- Simplify the dashboard into compact window and profile rows, with one create action and less repeated guidance.

- Hide successful application detection from the dashboard; show recovery actions only when detection fails.

- Show already-open Codex instances separately, with a verified focus action and no credential import.
- Start fresh installations with no example profiles; label managed spaces explicitly and preserve existing profiles.

- Application sidebar and shared profile layout prepared for future supported apps; Claude is now included as a preview.
- Retry profile-registry reads after an error without restarting, and preserve a missing registry during refresh.
- Keep account operations disabled while registry state is unavailable.
- Show application detection failures and offer rechecking; surface operation errors through the menu bar.
- Share application state with dependency-free regression checks for recovery and compatibility diagnostics.

## 0.1.0 — Preview

- Native SwiftUI dashboard and menu-bar launcher.
- Separate Codex and desktop state directories for each named profile.
- Launch, focus, normal quit, rename, Finder reveal, and Trash removal.
- Application marker checks and process identity validation.
- Private directory permissions, atomic registry writes, and symlink checks.
- Dependency-free build scripts, core checks, documentation, and macOS CI.
- Menu-bar status continues refreshing when the dashboard window is closed.
- Verified native UI creation/rename, two-instance startup, focus, targeted quit, and rediscovery after launcher restart on the recorded Apple Silicon environment.

Real two-account login/logout acceptance remains manual and must be recorded before claiming full account isolation.
