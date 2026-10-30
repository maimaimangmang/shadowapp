# 发布到 GitHub

产品名称与仓库名称已统一为 ShadowApp，仓库地址为 `maimaimangmang/shadowapp`。项目采用 MIT 许可证，公开源码即可供他人构建。

## 更新现有仓库

在已有 checkout 中整理本地修改，确认远端与当前分支，再提交并正常推送：

```bash
git remote -v
git fetch origin
git status --short --branch
# 明确添加本次准备发布的文件；检查暂存区，勿添加账号数据
git diff --cached --stat
git diff --cached --check
git commit -m "Describe the change"
git push origin main
```

若远端已有新提交，先合并或变基并处理冲突，不要强制覆盖远端。`.gitignore` 排除了构建目录和常见账号状态文件；账号数据默认存放在源码目录之外。不要把运行目录复制进仓库。

GitHub Actions 在推送或提交 PR 后运行检查、构建两个架构的启动器，并保存 `shadowapp-preview` ZIP 与校验和。源码推送不会创建 Release；源码、CI 产物和已有 Release 是不同交付物。README 中的新版功能以 `main` 为准，旧 v0.1.0 仍为 Codex Multi。

## 发布可下载应用

1. 执行 `bash scripts/test.sh` 和目标架构的构建脚本。
2. 按 [兼容性清单](COMPATIBILITY.md) 完成两个实际账号的手工验收，记录各应用、系统及版本的验证范围。
3. 先更新 Info.plist 中的版本号，再在 GitHub 的 Releases 创建对应的新版本（不要覆盖已有 v0.1.0），选择 **Set as a pre-release**。
4. 上传 `dist/ShadowApp-<version>-arm64.zip` 及其 `.sha256`。仅在确认目标应用版本支持 Intel 且已验证时再发布 Intel 包。
5. 使用 [RELEASE_NOTES.md](RELEASE_NOTES.md) 作为说明基础，准确保留尚未验证的项目。

普通用户下载应用 ZIP 后即可运行启动器，不需要自己安装开发工具。目标应用仍需另行安装。

## 签名与公证

默认脚本使用本地临时签名，适合自行构建及开发测试。面向广泛分发，可使用自己的 Apple Developer ID 证书，并完成 Apple 公证与 stapling。仓库不包含证书、密钥或账号。

```bash
CODEX_MULTI_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  bash scripts/build.sh arm64
```

设置此变量时，构建脚本启用 hardened runtime 和安全时间戳。签名本身不等于已公证；正式分发前还要通过自己的凭据运行 `xcrun notarytool submit`，对应用执行 `xcrun stapler staple`，然后重新打 ZIP 和校验和。遵循 [Apple 的 macOS 分发说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
