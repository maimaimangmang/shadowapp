# ShadowApp v0.2.0 — Preview

一个入口，多个应用，各自的账号空间。本次是从 Codex Multi 更名后的首个 ShadowApp 安装包。

## 下载与安装

- **ShadowApp-0.2.0-arm64.dmg**：推荐，适用于 M 系列芯片 Mac，macOS 13+。打开后将 ShadowApp 拖到 Applications。
- **ShadowApp-0.2.0-arm64.zip**：同一应用的 ZIP 版本，解压后拖入「应用程序」。
- 两种格式都提供 `.sha256` 校验文件。无需 Xcode、Swift 或命令行；目标应用需要提前安装。
- 采用本地临时签名，尚未通过 Apple 公证。若 macOS 阻止打开，请确认来源后在「系统设置 → 隐私与安全性」选择「仍要打开」。

## 本次更新

- 全新 ShadowApp 名称、Logo 和中英文界面，按应用管理空间。
- Codex 支持 ChatGPT 账号或 API Key，可配置胜算云、自定义网关与模型 ID。
- Claude 支持账号空间和第三方推理 API Key 空间，提供 Anthropic Messages 连接测试。
- 新增 WorkBuddy 多开预览，以及保留 App Sandbox 的微信独立副本（实验性）。
- 显示、复制和打开空间路径；改进重名提示、连接测试、模型信息与错误反馈。
- 微信空间可归档和恢复，保留应用副本、登录状态及聊天数据。

## 兼容范围

| 应用 | 已适配版本 | 说明 |
| --- | --- | --- |
| Codex | 26.1016.51333 | 启动时检查所需能力；API 模式需 Responses API |
| Claude | 4.29.0 的已验证构建 | API 模式需 Anthropic Messages 与 Claude 模型 |
| WorkBuddy | 5.8.3 的已验证构建 | 仍需 WorkBuddy 账号；自定义模型在应用内配置 |
| 微信 | Mac App Store 4.1.15（270115） | 仅 Apple Silicon；首次扫码，可能需要手机确认 |

应用更新可能需要重新适配。微信副本使用本地签名并放宽动态库签名校验，保护与原版不完全相同；不包含系统分享、文件提供器扩展与外部微信链接入口。多实例启动与单空间登录已验证，双账号持续同时在线及完整消息、音视频、通知功能仍待验证。

完整验证范围见仓库的兼容性记录。此次提供 Apple Silicon 包；Intel 启动器可交叉构建，但尚不提供经过实机验收的 Intel 安装包。

## 已有用户升级

退出旧启动器后替换应用即可；已有应用实例可继续运行。空间仍使用现有数据目录（默认 `~/CodexMulti`），不需要迁移账号文件。不要删除这个目录，也不要移动正在使用的空间。

Codex API Key 不代替 ChatGPT Work 浏览器账号登录；应用数据分离也不等于独立 macOS 用户或账号风控规避。

---

## English

**ShadowApp v0.2.0 Preview** is the first packaged release after the Codex Multi rename. It adds a refreshed launcher, Codex and Claude API-key profiles, WorkBuddy multi-instance support, and experimental WeChat profiles with archive/restore.

Download the **arm64 DMG** for an Apple Silicon Mac running macOS 13 or later, open it, and drag ShadowApp to Applications. A ZIP alternative and SHA-256 files are also attached. Install the target apps separately; no developer tools are required to run the launcher.

This build is ad-hoc signed and **not Apple-notarized**. If blocked, verify the source and approve it in System Settings → Privacy & Security. Existing data remains in its current location, normally `~/CodexMulti`.

Compatibility: Codex 26.1016.51333, verified Claude 4.29.0 and WorkBuddy 5.8.3 builds, and Mac App Store WeChat 4.1.15 (270115) on Apple Silicon. Updates may require adapter changes. WeChat copies retain App Sandbox but relax library signature validation; extensions and external URL handlers are excluded. Sustained simultaneous two-account use and complete messaging/media/notification coverage remain unverified. No validated Intel package is provided in this release.
