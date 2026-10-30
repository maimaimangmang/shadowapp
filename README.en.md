<p align="center">
  <img src="Resources/ShadowApp.png" alt="ShadowApp logo" width="100" height="100">
</p>
<h1 align="center">ShadowApp</h1>
<p align="center"><strong>One launcher. Multiple apps. Separate account spaces.</strong></p>
<p align="center">Manage Codex, Claude, WorkBuddy and WeChat instances on your Mac.</p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-222222?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/SwiftUI-native-F05138?logo=swift&logoColor=white" alt="Native SwiftUI">
  <img src="https://img.shields.io/badge/status-preview-8B7CF8" alt="Preview">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555" alt="MIT license"></a>
</p>
<p align="center">
  <a href="README.md">简体中文</a> · English · <a href="#get-started">Get started</a> · <a href="docs/COMPATIBILITY.md">Compatibility</a> · <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <strong><a href="https://github.com/maimaimangmang/shadowapp/releases/download/v0.2.0/ShadowApp-0.2.0-arm64.dmg">Download for Mac · Apple Silicon</a></strong><br>
  <a href="https://github.com/maimaimangmang/shadowapp/releases/tag/v0.2.0">v0.2.0 Preview · Release notes and checksums</a>
</p>

![ShadowApp dashboard with separate personal, work and model profiles](docs/images/en/overview.png)

<p align="center"><sub>Rendered from the current SwiftUI views with example profiles. No real accounts or keys. ShadowApp-Preview is a temporary demonstration directory.</sub></p>

Keep personal accounts, work accounts and model configurations in separate profiles, then open the one you need. ShadowApp uses apps already installed on your Mac, without running a virtual machine or switching macOS users.

- **Organize by app.** Choose an app in the sidebar, then create and name its profiles.
- **Choose an account or an API key.** Codex and Claude support provider URLs, keys and model IDs.
- **Find the right window.** Open an instance, bring an existing window forward or quit a specific profile. Apps keep running when the launcher closes.
- **See where data lives.** Each profile shows its actual data path, with copy and Finder actions.

> **v0.2.0 Preview.** ShadowApp was previously Codex Multi. Existing profile data is retained; you do not need to migrate it. The older v0.1.0 release remains available for reference.

## Supported apps

| App | Connection | Current compatibility |
| --- | --- | --- |
| **Codex** | ChatGPT account / API key | Verified on `26.1016.51333`; required capabilities checked at launch |
| **Claude** | Claude account / API key | Preview for the verified `4.29.0` build |
| **WorkBuddy** | WorkBuddy account; models configured in the app | Multi-instance preview for the verified `5.8.3` build |
| **WeChat** | QR sign-in and phone confirmation | Experimental; Apple Silicon + Mac App Store `4.1.15 (270115)` only |

Data separation and feature coverage vary by app. Updates may require adapter changes. See the [compatibility record](docs/COMPATIBILITY.md), [WorkBuddy notes](docs/WORKBUDDY.md) and [WeChat notes](docs/WECHAT.md) for validation scope (technical records are in Chinese).

## Get started

### 1. Download and install

| Package | For |
| --- | --- |
| [Download DMG](https://github.com/maimaimangmang/shadowapp/releases/download/v0.2.0/ShadowApp-0.2.0-arm64.dmg) | Recommended for Apple Silicon Macs (M series), macOS 13+ |
| [Download ZIP](https://github.com/maimaimangmang/shadowapp/releases/download/v0.2.0/ShadowApp-0.2.0-arm64.zip) | The same app in a ZIP archive |
| [Release notes and checksums](https://github.com/maimaimangmang/shadowapp/releases/tag/v0.2.0) | Compatibility, known limitations and SHA-256 files |

1. Open the DMG and drag **ShadowApp.app** into **Applications**.
2. Open ShadowApp from Applications. No Xcode, Swift or terminal commands are needed.
3. Install each target app separately; their own system requirements still apply.

This preview uses an ad-hoc signature and is not Apple-notarized. If macOS blocks it, confirm the download source and use **System Settings → Privacy & Security → Open Anyway**. Intel builds are available for developers, but an Intel release package is not provided until runtime validation is complete.

### 2. Create a profile

1. Select an app and choose **New profile**. Give it a recognizable name, such as “Work”.
2. Codex and Claude default to **API Key**. Switch to the account option when you want to sign in with that app's account.
3. Save and choose **Open**. For account profiles, sign in inside the new window. Complete sign-ins one at a time and check which account the browser selects.
4. Return through ShadowApp or its menu bar. Running instances offer **Show window**.

A profile name is your label, not an authenticated account identity. “Running” only means the process exists; it does not confirm sign-in or a working model connection. Existing windows can be brought forward without importing their credentials or history.

## BYOK: bring your own API key

<p align="center">
  <img src="docs/images/en/api-key.png" alt="BYOK settings with a custom provider, base URL, API key, model ID and connection test" width="440">
</p>

ShadowApp supports **BYOK (Bring Your Own Key)**. Use your chosen provider or self-hosted gateway, provided its API and model are compatible with the target client.

Choose **API Key → Custom provider**, then enter the provider name, base URL, API key and full model ID to save the connection as a separate profile.

| Setting | Codex | Claude |
| --- | --- | --- |
| Required protocol | OpenAI **Responses API** | **Anthropic Messages API** |
| Base URL | The Responses API base URL supplied by your provider | The Anthropic Messages root URL supplied by your provider, without `/v1` |
| Model ID | Full model ID supported by the provider | Claude model or its gateway routing ID |
| Where to start | Select **Codex** and create a new chat | Use the configured third-party inference provider |

Get the API key, endpoint and model ID from your chosen provider's console and documentation.

- **Try the connection.** Once the fields are complete, choose “Test connection”. This sends a short request and may incur a small charge. Saving alone does not run a test.
- **Match the protocol.** A Chat Completions-only endpoint is not sufficient for Codex. Streaming and tool use must also be compatible; a basic connection test does not establish full feature support. Renaming a DeepSeek or GLM model to Claude will not make it compatible with Claude Desktop.
- **Edit later.** Quit the profile, then choose “… → Model & API key”. Leave the key blank to retain it; changing the endpoint requires entering the corresponding key again.
- **Check model evidence.** Codex's “Model information” separates configured values from recent local session records. A model's self-description does not prove its actual route; consult provider records as well.

Keys are saved in local profile configuration, with sensitive files restricted to the current user, and are not written to the profile registry. Profile backups contain credentials and should be handled as account data. WorkBuddy models are configured in **Settings → Models** inside WorkBuddy, which still requires a WorkBuddy account.

## WeChat · Experimental

![WeChat profiles with separate account data paths and usage notes](docs/images/en/wechat.png)

Select **WeChat → New profile → Open**. The first launch prepares a locally signed copy and shows WeChat's QR sign-in screen. Reopening may still require phone confirmation. SMS and API-key sign-in are not provided.

Each profile has its own app identity and macOS data container. The original installation is preserved. Copies retain App Sandbox and Hardened Runtime, but relax library signature validation, so their protections differ from the original. System sharing, File Provider extensions and external WeChat URL handlers are excluded from copies.

**Archiving preserves the app copy, sign-in information and chat data, and can be reversed.** Permanent deletion and importing earlier research copies are not currently available.

Independent launch, window identification, targeted quit, archive/restore and a single research profile's QR sign-in/reopen confirmation have been verified. **Two running instances do not prove that two accounts can remain online simultaneously.** Switching accounts on a phone may sign out the desktop. Full messaging, attachments, notifications and audio/video coverage remain pending. See the [implementation and validation record](docs/WECHAT.md).

## Where profiles are stored

Every profile card shows its path. The default root remains `~/CodexMulti` so existing data does not need to move after the rename. New folders use a name plus a short ID; renaming a profile does not relocate its data.

```text
~/CodexMulti/
├── profiles/                         Codex profiles
│   └── Work-a1b2c3d4/
│       ├── codex/                    Configuration, credentials, sessions
│       └── desktop/                  Desktop state
└── apps/
    ├── claude/profiles/               Claude profiles
    ├── workbuddy/profiles/            WorkBuddy profiles, including private HOME
    └── wechat/profiles/               WeChat copies and management records

~/Library/Containers/
└── org.shadowapp.wechat.space.<ID>/   Actual WeChat account data
```

If you use a legacy or custom location, follow the path shown in the app. Do not move a profile while it is running.

| Action | Effect |
| --- | --- |
| Quit ShadowApp | Opened apps continue running |
| Quit this instance | Requests a normal exit of that profile's app |
| Move to Trash (Codex / Claude / WorkBuddy) | Moves the whole profile folder, including local settings, credentials and history |
| Archive profile (WeChat) | Hides the profile and retains its app copy and system container for restoration |

## FAQ

**Why does an API profile ask for ChatGPT Work authentication?**

`Work browser access requires an authenticated account` concerns Work browser features. Switch to **Codex** in the top-left product menu and create a new chat. A provider key does not authenticate a ChatGPT Work account.

**Are profiles fully isolated?**

ShadowApp separates supported app data and configuration. Browser sign-in, system permissions and some link callbacks can still be shared. Profiles are not separate macOS users and do not bypass regional restrictions or account enforcement.

**What if an app stops opening after an update?**

Unrecognized Claude, WorkBuddy and WeChat builds are blocked while existing data is preserved. Read the compatibility notice. When reporting an issue, include macOS/app versions and the error text, without keys, authentication files or chat data.

**How do I switch languages?**

The interface follows the system's app language. In macOS, use **System Settings → General → Language & Region → Applications** to choose Chinese or English for ShadowApp.

## Development

Native SwiftUI and system frameworks, with no third-party Swift package dependencies.

Source builds require Swift 5.9+ and Xcode or Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/maimaimangmang/shadowapp.git
cd shadowapp
bash scripts/build.sh
open "dist/$(uname -m)/ShadowApp.app"
```

```bash
bash scripts/test.sh                 # Core and state checks
bash scripts/build.sh arm64          # Apple Silicon
bash scripts/build.sh x86_64         # Intel build; target-app support varies
bash scripts/package-dmg.sh arm64    # Package a built app as a DMG
bash scripts/render-docs.sh          # Render bilingual images using temporary examples
```

Runtime checks launch target apps and should be run explicitly following their documentation. Normal tests and CI do not sign in to WeChat. Include the app, version, reproduction steps and expected behavior with issues and pull requests.

- [Architecture](docs/ARCHITECTURE.md) · [UI design](docs/UI_DESIGN.md)
- [Compatibility record](docs/COMPATIBILITY.md) · [Distribution](docs/PUBLISHING.md)
- [Image generation](docs/images/README.md) · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/maimaimangmang/shadowapp/issues)

Licensed under the [MIT License](LICENSE). ShadowApp is an independent community project, with no affiliation or authorized partnership with OpenAI, Anthropic or Tencent. App names, icons and trademarks belong to their respective owners.
