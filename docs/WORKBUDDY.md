# WorkBuddy 多开预览

2026-10-29：ShadowApp 支持为 WorkBuddy 创建、显示、正常退出和移除独立空间。每个空间使用独立的配置、聊天、浏览器数据和认证文件目录。原有 WorkBuddy 实例仍可继续使用。真实双账号登录和退出互不影响的验证仍待用户完成；当前验证使用全新、未登录的临时空间。

## 实现

已验证安装版本：macOS WorkBuddy 5.8.3，bundle identifier `com.tencent.workbuddy.mac`。`app.asar` SHA-256：`a7eff702411704d140d7d8d706fe9e711d9b13e304928481c9eba0af9c06f731`。每次启动前重新校验，未知版本停止启动并保留数据。

仅复制 `.app` 或指定 `--user-data-dir` 不足以隔离认证。安装包的 `module-base.js`、`file-authentication-storage.js`、`workbuddy-product-config.js` 均通过 `os.homedir()` 使用 `Library/Application Support/CodeBuddyExtension/Data/Public/auth`。因此只对新建的 WorkBuddy 子进程设置独立 HOME，不修改启动器、系统或其他应用的 HOME。

空间位于 `~/CodexMulti/apps/workbuddy/profiles/<名称-短ID>/`：

| 子目录 | 用途 |
| --- | --- |
| `home/` | WorkBuddy 子进程 HOME；包含上述认证目录 |
| `workbuddy/` | WORKBUDDY_CONFIG_DIR / CODEBUDDY_CONFIG_DIR，配置、数据库、日志 |
| `desktop/` | WORKBUDDY_USER_DATA_DIR 与 --user-data-dir，桌面及浏览器状态 |

所有目录在启动前创建为私有目录，并逐层拒绝认证路径上的符号链接。应用设置保留原有字段，合并 `startupForceAutoUpdate: false` 以关闭启动时静默安装更新。坏配置不会被覆盖。

WorkBuddy 的 Info.plist 禁止 LaunchServices 创建多个实例，因此直接启动已验证安装包中的 `Contents/MacOS/Electron`。只继承必要环境项，不继承启动器中的模型密钥或 Node 注入参数。进程记录使用内核启动时间、PID、应用路径和精确空间参数，防止 PID 复用误认实例。注册表升级为 schema 5；早期只有打开入口的空 schema 3 注册表可以升级，其他应用不能接管此注册表。

## 使用与限制

- 在 WorkBuddy 页选择「新建空间」，起名、保存，再打开。请逐个完成浏览器登录，并确认所选账号；外部浏览器的 Cookie 仍共享。
- 自定义模型在 WorkBuddy「设置 → 模型」中填写 URL、API Key、模型名；仍需要 WorkBuddy 账号登录。启动器暂不代写其模型配置。
- 独立 HOME 意味着原有 Git、SSH、CLI 配置不会自动可见，需自行在新空间设置。不要把共享认证目录链接进来。
- 更新检查、后台下载和强制升级提示仍由 WorkBuddy 管理。避免在空间内直接执行更新重启；退出空间后通过原应用更新，再从 ShadowApp 打开。新版本须重新验证兼容性。
- 普通账号登录使用服务端状态轮询；全局 deep link、部分连接器回跳和系统权限仍共享，不能保证所有辅助授权都打开正确实例。
- 这是应用数据隔离，不是操作系统安全沙箱，也不是地区、账号资格或平台风控的规避机制。

## 验证

本机验收：81 项自动检查通过；完整 WorkBuddy 运行时测试通过，原有实例保留、测试实例及临时数据已清理。arm64 与 x86_64 构建和签名校验通过；运行时实测平台为 Apple Silicon。

`bash scripts/test.sh` 覆盖目录隔离、配置保留、坏配置/符号链接拒绝、注册表升级与跨应用拒绝、凭据环境过滤、精确路径匹配和进程身份。

`bash scripts/check-workbuddy-runtime.sh` 是显式运行的 macOS 集成测试：创建两个临时未登录空间，检查实际数据库、认证初始化日志、子进程 HOME、打开的文件路径、状态恢复、丢失进程记录后的删除保护、定向退出和重启。仅关闭测试创建的进程，不读取真实账号凭据、不发起模型请求。认证 watcher 可能使用 FSEvents，不能仅凭 lsof 无认证文件就断言登录隔离成功；需结合目录、子进程 HOME 和初始化日志，最终仍须真实双账号验收。

## 静态证据与官方参考

REA 对三个原样提取文件的有限分析父证据：`ev_5830b75cf3b15f76084d3fcdcb7de0e0810f2a9b2c317b360122c645a0009055`，目录摘要 `dcf822960e6103d7dd1111878ea5091171574e145e0e0b4f5ce2d086112359d1`。完整 ASAR 分析曾因 unpacked 文件摘要差异及超时未完成；不将有限分析描述为完整应用审计。认证存储、登录轮询和更新行为另由对应安装包原始代码交叉核查。

- [WorkBuddy 模型配置](https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Model)
- [WorkBuddy macOS 安装与登录](https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Installation-Mac-Guide)
