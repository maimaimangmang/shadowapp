# 微信多开兼容性核查（macOS）

2026-10-29，Apple Silicon / macOS 26.5.2，本机 Mac App Store 微信
4.1.15（270115），原 bundle ID `com.tencent.xinWeChat`。

**已验证保留 App Sandbox 的微信副本可以与原微信同时运行，并显示扫码登录窗口。**
这修正了早先「本地重签就一定失去沙盒」的判断。目前已验证单空间扫码登录、退出后
记住账号、手机确认后恢复登录。双账号持续同时在线及完整功能仍未验证。2026-10-30 已作为实验性功能加入
ShadowApp 源码开发版应用列表；尚未发布到 GitHub Release。

## 可行路线

每个空间使用一个本地应用副本、唯一 bundle ID、唯一应用组和系统数据容器。
主程序保留 App Sandbox，本地重新签名；辅助程序保留原签名及沙盒继承权限。
不需要额外启动操作系统，不修改原微信、原账号数据、SIP 或 Gatekeeper。

关键点是微信 `Info.plist` 的 `TeamIdentifier` 前缀必须与副本应用组对应。
例如实验中的 `TeamIdentifier = group.`，bundle ID 为
`org.shadowapp.wechat.sandboxprobe`，应用组为
`group.org.shadowapp.wechat.sandboxprobe`。这里是本地通信命名，**不是冒充腾讯团队身份**。

系统沙盒规则允许同一应用组前缀内的 Mach 通信。新应用身份、通信前缀和沙盒权限
必须一起调整，仅改 bundle ID 或删除应用组都会遗漏这一点。

## 失败原因与修正证据

| 实验 | 结果与证据 |
| --- | --- |
| 原版 `open -n` / 直接启动 | 未得到可用的独立第二实例。 |
| 改 bundle ID 并删除全部权限 | 4.1.15、官网 4.2.0 都曾显示第二个窗口，但没有 App Sandbox；不作为当前推荐配置。 |
| 保留沙盒，但残留原团队权限 | `amfid` 返回 `Code=-424: The file is adhoc signed but contains restricted entitlements`；启动报 Code 163。不能由此推出本地签名不支持沙盒。 |
| 移除身份权限但没有新应用组 | 进程启动后崩溃。日志明确拒绝 `5A4RE8SF68.<新 bundle ID>.MachPortRendezvousServer.<pid>` 和 crashpad 的 `mach-register`。 |
| 新应用组与 Info 前缀匹配 | 成功显示扫码窗口，与原微信同时运行。 |
| 再启用 Hardened Runtime，未加例外 | dyld 拒绝加载 `libwxld.dylib`：主程序和原动态库的 Team ID 不同。 |
| 沙盒 + Hardened Runtime + 库验证例外 | 主程序及已启动辅助进程成功运行；沙盒运行时检查和容器外拒绝检查通过。 |

不要用 `codesign --deep --entitlements …` 为全部组件套用主程序权限。
辅助进程的 `app-sandbox + inherit` 与主程序的权限不是一回事。本次只重新签名外层应用，
`codesign --verify --deep --strict` 用于**验证**整个包。

## 已验证的范围

- 原微信与沙盒副本同时存在；副本能显示扫码登录界面。
- `sandbox_check(pid, NULL, 0)`：主程序、crashpad、WeChatAppEx、网络和 GPU
  辅助进程均返回 `1`；普通未沙盒化的诊断进程返回 `0` 作为对照。
- 对实际存在的合成测试文件做权限查询：副本自己的容器文件允许访问，用户主目录
  中的容器外测试文件拒绝访问；未读取真实账号、认证或聊天内容。
- `lsof` 的主程序检查发现 41 个自身容器文件，原微信容器和原腾讯应用组路径计数为 0。
  这是该时刻的文件描述符观察，不能证明以后所有功能都不访问其他位置。
- 辅助程序启动参数使用副本的容器路径和独立通信标识。
- 已用复现脚本制作第二个副本，与第一个副本及原微信同时运行。两个副本均显示扫码窗口；
  双向交叉容器测试均为「自己的合成文件允许，另一个副本的合成文件拒绝」。
- 第一个副本从菜单正常退出后重新启动，仍能显示扫码窗口并通过沙盒检查。
  这只验证未登录状态的重启，不等于登录态持久化已通过。
- 原主程序 SHA-256 保持不变，原安装包未修改。

## 与原版保护的区别

本地副本保留 App Sandbox 和 Hardened Runtime 标志，但不保留腾讯的外层签名身份。
为了加载腾讯原动态库，需要增加
`com.apple.security.cs.disable-library-validation = true`。这会放宽**副本自身**加载代码的
签名校验，不能宣传为「与原版安全机制完全相同」。没有关闭系统级安全开关，也没有
用该例外扩大文件访问权限。

Apple 文档说明 App Sandbox 和 macOS App Groups 权限本身不需要 provisioning profile；
应用身份、团队等受限制权限不能直接复制给 ad-hoc 签名。这是两个不同问题。

第一轮副本中的分享、File Provider 扩展仍保留原标识和权限。第二轮已从新副本中移除
这两个扩展，详见下节。历史实验副本不能继续作为可登录的验证版本使用。

## 第二轮：扩展、链接入口与退出重启

2026-10-29，继续对相同安装包做本地验证：

| 问题 | 处理及证据 |
| --- | --- |
| 系统分享扩展 | `WeChatMacShare.appex` 有原腾讯应用组、没有 `inherit`。新制备脚本从副本删除此扩展，原安装包保留。 |
| 文件提供器扩展 | `WeChatFileProviderExtension.appex` 同样不继承主进程沙盒；`NSExtensionFileProviderDocumentGroup` 还指向原腾讯组。新副本删除该扩展。 |
| 外部微信链接 | 从副本删除顶层 `CFBundleURLTypes`，避免注册原版的 `wechat`、`weixin`、`xweixin` 入口。网页登录回调、外部链接唤起不在当前支持范围。 |
| 其余后台组件 | 包内 8 个辅助应用及 crashpad 均保留 `app-sandbox + inherit`，没有原应用组权限；校验工具逐个检查。 |
| 基础启动 | 移除扩展和 URL 注册后，两个副本仍各自显示扫码窗口；沙盒对双方合成文件的交叉读、写查询均拒绝。 |
| 正常退出 | 从副本菜单退出后，没有留下来自该副本包路径的主进程或辅助进程。原微信及另一个副本继续运行。 |
| 未登录重启 | 再次打开成功；重新校验通过，仍使用原来的专属容器。采样从启动后约 0.4 秒至 10 秒，16 次均报告已沙盒化。 |
| 版本更新入口 | 实际点击此版本的「版本更新」打开 App Store 微信产品页；未下载或安装。这不证明不存在其他更新路径。 |

更新组件的静态清点未发现独立 `Sparkle.framework` 或 updater，虽然顶层存在 `SU*`
配置字段，也不能据此断言 Sparkle 已启用或已被禁用。当前采用版本、签名和完整性检查
作为未来启动器的前置条件，不通过时应停止，不得退回无沙盒启动。

`XPlayer.app` 及媒体辅助进程仍需在真实播放场景验证。发布包中可见独立 XPlayer Mach
通信名模板，但当前未观察到视频播放，不能由扫码窗口成功推出音视频正常。

一次早期运行时检查曾返回失败，当时未记录底层返回值。随后同进程的检查以及一次
完整重启采样均通过；诊断工具现已记录失败的返回值和 errno。此项仍应在后续启动测试
中观察，不能用静态权限声明代替每次运行时检查。

第二轮结束时只保留 `.build/wechat-sandbox-research/Verified.app` 的扫码窗口，身份为
`org.shadowapp.wechat.probe.researchv2`，等待用户登录验证。它的主程序及当时运行的
4 个辅助进程均报告已沙盒化；文件描述符检查未观察到原微信容器或腾讯原组目录。
旧实验应用包已移至废纸篓；对应系统容器中的未登录实验数据没有作为用户数据迁移或删除。
主程序中尚未触发的媒体等功能，仍保持「未验证」状态。

## 第三轮：用户登录及手机确认

用户在测试副本中完成扫码登录。随后从菜单正常退出，所有属于副本的进程结束；
重新校验并打开后，界面保留原账号，提供「登录」按钮，没有要求重新扫码。
点击登录后界面提示「需在手机上完成登录」。用户确认后，副本恢复主界面。
因此验证结果是**账号信息保留、重新登录需要手机确认**，不是自动登录或免验证登录。

登录后及重开后观察到包括 XPlayer、WeChatHelper 和 Renderer 在内的 11 个进程。
它们均报告已沙盒化，容器外合成测试文件的读、写查询均被拒绝。登录后的文件描述符
观察未发现原微信容器或原腾讯应用组数据路径；没有读取认证文件或聊天内容。
XPlayer 启动通过，不代表视频解码、播放或通话已验证。

**双账号同时在线保持待验证。** 用户只有一部手机，并报告切换手机微信账号验证时，
先前电脑端微信会自动退出。这个测试条件会影响服务端登录状态，不能用此时的掉线
现象认定本地容器隔离失败，也不能由两个进程均存在推断两个账号持续在线。
已停止来回登录两个账号的测试；在无需切换手机账号的条件下才能进一步判定。

`Verified.app` 关联的系统容器现已包含用户登录数据，不能再按未登录的一次性测试
夹具清理，也不能自动更换其 bundle ID。当前仅保留验证记录，未将用户数据迁移至
ShadowApp 的正式空间管理。不要通过反复重签或替换应用来尝试绕过手机确认。

## 可复现工具

`scripts/prepare-wechat-probe.py` 只接受此次验证过的原版 4.1.15（270115），先核对
原代码签名、版本、主程序哈希和权限，再准备独立副本及 JSON 清单。输出位置必须不存在，
不会覆盖原应用，不会自动启动、扫码登录、清理容器或迁移账号。

```sh
mkdir -p .build/wechat-probe
python3 scripts/prepare-wechat-probe.py --output .build/wechat-probe/WeChatTest.app
```

脚本输出的 `container` 是真正的系统数据目录，不能将应用副本目录当成账号数据目录。
当前脚本默认删除两个系统扩展和 URL 注册，并保存制备后主程序、Info.plist 和签名
资源清单的哈希。复现工具不是完整产品功能。生成的副本只用于本机兼容性验证，不随仓库分发。

制备后、每次启动前可以运行：

```sh
python3 scripts/check-wechat-probe.py .build/wechat-probe/WeChatTest-probe.json
```

如果副本已运行，可以追加 `--pid <该副本的主进程 PID>` 检查真正的可执行路径、
运行时沙盒和合成文件的读写权限。该工具不启动或修复应用；运行时诊断使用私有 Sandbox
SPI，仅用于本机研究，不作为已确认可发布的 API。

完整性检查已使用一次性的 APFS 克隆验证：原样克隆通过；改成未知版本、增加未签名
资源、修改签名资源清单都被拒绝。测试夹具已清理，没有对真实账号数据做破坏性测试。

## 2026-10-30：接入 ShadowApp 实验性入口

新增 `WeChatProfile.swift`，将已验证的副本准备和校验步骤实现为原生 Swift，无需用户安装 Python。仅接受已验证原版的版本、主程序指纹和 Apple 签名。使用 APFS 克隆准备独立副本，分配由空间 UUID 确定的 bundle ID 和应用组；只签名外层应用，保留辅助程序的沙盒继承，移除两个扩展及外部 URL 注册。

- 微信注册表独立使用 schema 6；不导入旧研究副本，不迁移已登录数据。
- 每次新启动检查副本哈希、完整签名、权限和辅助程序；已有副本损坏时停止，不自动重签或覆盖。使用本机 Sandbox SPI 确认运行时沙盒，不可用时停止；这是实验性本机功能，不代表已满足 App Store 分发要求。
- 实际应用路径和唯一标识用于进程识别；可恢复管理器重启或记录丢失后的实例，检测残留辅助进程，避免运行中归档。
- 卡片展示并可打开/复制真正的系统数据容器路径。首次打开前不伪造容器。
- 微信使用归档/恢复，保留应用与账号数据，不能把删除应用副本当成删除聊天数据。
- 全部 88 项自动检查通过。通过 `scripts/check-wechat-runtime.sh` 在全新未登录夹具中验证双副本启动、重复打开复用、丢失记录恢复、单独退出、归档恢复、重开及篡改副本阻断；原微信进程保留。没有扫码登录或发送消息。这不证明双账号持续在线。
- 已构建本地 Apple Silicon ShadowApp 并打开微信页面，检查新建表单可见、未显示 API Key 或短信登录入口。

运行可选实机检查（仅开发者主动执行，不在普通测试或 CI 自动启动微信）：

```sh
bash scripts/check-wechat-runtime.sh /absolute/path/to/new-fixture-directory
```

该工具留下测试清单供检查，不自动清除系统容器。此前已登录的 `Verified.app` 和对应容器继续原样保留。

## 仍待验证

1. 在手机账号无需切换的测试条件下验证双账号持续同时在线；单空间登录与重开后手机确认已通过。
2. 用户验证消息收发、附件、通知、音视频；不由自动化代替用户发送消息。
3. 验证 XPlayer 的实际播放、通知及其他功能；其启动和沙盒检查已通过，系统分享和文件提供扩展暂时保持禁用。
4. 微信空间的彻底清理和旧研究副本导入尚未提供；当前归档可恢复且保留所有账号数据。
5. 更新后重新验证。当前不能保证未来版本兼容，也不能保证平台不会限制修改过的客户端。

## 证据和资料

原主程序 SHA-256：`0a6eb182d2ccf2bd005d778d2be8f3e675df3bfa7a7e9c904348e93d0ae8a10a`。
REA 签名证据 `ev_a0f53be35db29af5bf08168f1caf726c5c66f14c57da4b47872987cca5b3aae8`，
Info.plist 证据 `ev_5f7cb056e0c6733f431840f7e871def1ccff003b0a9ca3f06c71c2fdce8fb9fb`。
扩展配置证据：File Provider `ev_4371e40d9c5ef943e6480cddc322ffd6d7d6d52d414c3fa56fa646e7cf3a18a1`，
系统分享 `ev_9e576fe0ac37a6b304aebaca6af5c31c818b97a0c2d601562638a1b78206cab0`。
关键本机诊断记录为 `WeChat-2026-10-29-155859.ips`（Mach 通信失败）和
`WeChat-2026-10-29-160703.ips`（不同签名身份的动态库加载失败）。

- [Apple：Provisioning Profiles 与受限制权限](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Apple：沙盒辅助程序继承](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)
- [Apple：macOS App Groups](https://developer.apple.com/forums/thread/721701)
- [Apple：为 Mac 代码签名](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Electron 上游：对应的 MachPortRendezvousServer 命名问题](https://github.com/electron/electron/issues/51351)
- [Apple WebKit：诊断所用 Sandbox SPI 声明](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/spi/darwin/SandboxSPI.h)
- [Apple：扩展与主应用的容器和共享数据](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)
- [Sparkle：默认配置与运行时设置的区别](https://sparkle-project.org/documentation/customization/)

未对完整微信内部调用路径做反编译；没有可用的 Hopper、Ghidra 或 IDA 深度分析引擎。
以上结论仅适用于此次本机实验，不等于微信官方支持多开。
