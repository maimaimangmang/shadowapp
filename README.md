# Codex Multi

在 Mac 上同时打开多个 Codex 账号。每个账号独立登录，保存各自的会话和设置。

[English](README.en.md) · [兼容性与验证](docs/COMPATIBILITY.md) · [发布到 GitHub](docs/PUBLISHING.md)

**v0.1.0 预览版。** 这是一个独立的社区启动器，不隶属于 OpenAI。需要你已经安装 Codex 桌面应用。启动器使用了尚未公开的桌面数据目录参数，Codex 更新可能影响兼容性。两个不同账号的完整登录与退出验证仍需人工完成，详见验证记录。

已在 Apple Silicon Mac 上验证启动两个独立实例、切换、单独退出及重开启动器后的识别；13 项核心检查通过。

## 下载预览版

[下载 Apple Silicon 应用 ZIP](https://github.com/maimaimangmang/codex-multi/releases/download/v0.1.0/Codex-Multi-0.1.0-arm64.zip) · [版本说明与校验和](https://github.com/maimaimangmang/codex-multi/releases/tag/v0.1.0)

适用于 M 系列芯片 Mac。解压后打开 `Codex Multi.app`，也可以拖入「应用程序」。需要自行安装 Codex 桌面应用。此构建使用临时签名，未经 Apple 公证；若 macOS 阻止打开，可在确认来源后通过「系统设置 → 隐私与安全性」批准，或从源码构建。

## 使用

1. 打开 `Codex Multi.app`，确认页面检测到了你的 Codex。没有检测到时，点击「选择应用」。应用名称可能是 `Codex.app` 或 `ChatGPT.app`，程序会核对其标识。
2. 点击「个人账号」的「打开 Codex」，在新窗口中登录第一个账号。
3. 完成登录后，再打开「工作账号」，登录另一个账号。浏览器如果自动选中了旧账号，请在登录流程里改选所需账号。
4. 两个窗口可以同时工作。以后从启动器或菜单栏点击账号名，即可打开对应空间或切换到已有窗口。

每个空间首次使用都需要登录。启动器不导入原有 Codex 的凭据或历史。「运行中」只表示实例已运行，不代表已登录。首次登录请逐个完成，避免多个浏览器登录回调同时等待。

支持添加、重命名、单独退出、在访达中查看数据，以及将已停止空间的数据移至废纸篓。退出启动器后，已打开的 Codex 会继续运行。

## 从源码构建

需要 macOS 13 或更高版本、Swift 5.9 或更高版本，以及 Apple Command Line Tools 或 Xcode。Codex 自身可能有更高的系统或硬件要求，以安装的版本为准。

```bash
# 如果尚未安装 Apple 开发工具，手动执行：
xcode-select --install

# 在本项目根目录执行：
bash scripts/test.sh
bash scripts/build.sh
```

生成的应用和 ZIP 位于 `dist/`。构建没有第三方 Swift 包依赖，不会下载 Codex、模型或账号数据。测试使用一个小型断言运行器，Command Line Tools 即可执行，不需要 XCTest。

可以指定启动器的目标架构：

```bash
bash scripts/build.sh arm64
bash scripts/build.sh x86_64
```

Intel 构建仅表示启动器可编译；是否可以运行 Codex 取决于用户安装的 Codex 版本。默认构建使用本地临时签名，未经 Apple 公证。下载分发的构建可能需要在「系统设置 → 隐私与安全性」中批准打开；只对你信任的构建这样操作。也可以自行从源码构建。

## 数据保存在哪里

```text
~/Library/Application Support/Codex Multi/
├── profiles.json                # 名称、应用路径、实例标识；不含令牌
└── profiles/<随机 UUID>/
    ├── codex/                   # 配置、登录、会话、SQLite 状态等
    └── desktop/                 # 窗口、浏览器存储和缓存等
```

每次启动都为对应空间传递 `CODEX_HOME`、`CODEX_SQLITE_HOME`、`CODEX_ELECTRON_USER_DATA_PATH` 和 `--user-data-dir`。新空间的配置使用 `cli_auth_credentials_store = "file"`，让凭据留在该空间内；已有配置会保留。不要把这些目录、`auth.json` 或登录日志上传到 GitHub。目录权限为 `0700`，新配置文件为 `0600`。

这是本地状态隔离，不是操作系统安全沙箱：同一 macOS 用户下的进程仍可访问用户有权限读取的文件；两个账号同时修改同一个项目也可能冲突。组织策略、外部浏览器登录状态、系统权限和部分系统级集成仍可能共享。自行修改配置里的凭据存储或 `sqlite_home` 可能改变隔离行为。

官方参考：[状态目录环境变量](https://learn.chatgpt.com/docs/config-file/environment-variables)、[凭据存储](https://learn.chatgpt.com/docs/auth)。桌面数据目录参数来自已安装应用的本地兼容性检查，不是官方多账号支持承诺。

## 常见问题

**为何不能直接复制应用来多开？** 应用副本通常仍会使用相同的状态目录。本工具为每个空间分配独立目录，并用 macOS 的新实例启动接口打开已安装应用。

**点击多次会创建多个同账号窗口吗？** 运行中的空间会直接切换窗口。启动过程中按钮被禁用；Codex 自身的实例锁也保留。状态无法确认时会停止继续启动或退出，提示用户检查对应窗口。

**新开的窗口为何仍叫 ChatGPT / Codex？** 窗口和 Dock 名称来自原应用，不会跟随空间名称改变。同名不代表数据共用；分别检查两个窗口的登录账号，确认邮箱不同。

**退出一个账号会影响其他账号吗？** 启动器只向验证过的那个进程请求正常退出，不使用 `killall`。在 Codex 内退出登录的跨账号影响仍需按兼容性清单验证。

**更新 Codex 后打不开？** 再次选择应用。每次启动都会检查应用标识和桌面目录参数；检查不通过时保留数据并停止。检查通过也不保证所有新版本都兼容。

**如何卸载？** 退出启动器和由它打开的 Codex 实例，删除启动器应用。账号空间默认保留；若不需要，可将上面的 `Codex Multi` 数据目录移至废纸篓。

## 项目结构

```text
Sources/CodexMulti/        SwiftUI 界面与账号操作
Sources/CodexMultiCore/    目录、注册表、应用检查、原生启动
Tests/                    隔离、数据保护、进程身份等检查
scripts/                  测试、构建、图标生成
.github/workflows/        macOS 自动测试与构建
docs/                     兼容性记录、架构、发布说明
```

MIT License。欢迎提交兼容性记录与修复；请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
