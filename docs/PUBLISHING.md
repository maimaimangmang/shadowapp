# 发布到 GitHub

建议仓库名称：`codex-multi`。项目采用 MIT 许可证，公开源码即可供他人构建。

## 上传源码

在 GitHub 创建一个空仓库，然后在本项目根目录执行以下命令。将 `YOUR_ACCOUNT` 换成你实际的 GitHub 用户名或组织名。

```bash
git init -b main
git add .
git status --short
git commit -m "Initial Codex Multi preview"
git remote add origin https://github.com/YOUR_ACCOUNT/codex-multi.git
git push -u origin main
```

提交前检查暂存文件。`.gitignore` 排除了构建目录和常见账号状态文件；账号数据默认存放在源码目录之外。不要把运行目录复制进仓库。

仓库已经包含 GitHub Actions 工作流，推送或提交 PR 后运行测试、构建两个架构的启动器，并保存 ZIP 与校验和。工作流不会自动创建公开 Release。GitHub 上的 CI 仍需在实际仓库中首次运行验证。

## 发布可下载应用

1. 执行 `bash scripts/test.sh` 和目标架构的构建脚本。
2. 按 [兼容性清单](COMPATIBILITY.md) 完成两个实际账号的手工验收，记录哪些系统和 Codex 版本验证过。
3. 在 GitHub 的 Releases 新建 `v0.1.0`，选择 **Set as a pre-release**。
4. 上传 `dist/Codex-Multi-0.1.0-arm64.zip` 及其 `.sha256`。仅在确认目标 Codex 版本支持 Intel 且已验证时再发布 Intel 包。
5. 使用 [RELEASE_NOTES.md](RELEASE_NOTES.md) 作为说明基础，准确保留尚未验证的项目。

普通用户下载应用 ZIP 后即可运行启动器，不需要自己安装开发工具。Codex 桌面应用仍需另行安装。

## 签名与公证

默认脚本使用本地临时签名，适合自行构建及开发测试。面向广泛分发，可使用自己的 Apple Developer ID 证书，并完成 Apple 公证与 stapling。仓库不包含证书、密钥或账号。

```bash
CODEX_MULTI_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  bash scripts/build.sh arm64
```

设置此变量时，构建脚本启用 hardened runtime 和安全时间戳。签名本身不等于已公证；正式分发前还要通过自己的凭据运行 `xcrun notarytool submit`，对应用执行 `xcrun stapler staple`，然后重新打 ZIP 和校验和。遵循 [Apple 的 macOS 分发说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
