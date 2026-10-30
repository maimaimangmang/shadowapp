# README 界面图 / README images

`overview.png` 为用户提供的 v0.2.0 实际界面截图，按原样保存，不由渲染脚本覆盖。

其他图片直接渲染项目的 SwiftUI 视图，使用临时示例数据，没有读取真实账号、Key、聊天记录或运行中的应用实例，也没有启动目标应用。应用图标来自本机安装的对应应用；图标和商标属于各自权利人。

`overview.png` is a user-provided screenshot of v0.2.0, preserved as supplied and excluded from the renderer output.

The other images render the production SwiftUI views with disposable example data. They do not read real accounts, credentials, chats or running instances, and do not launch target apps. App icons come from local installations and belong to their respective owners.

| 文件 / File | 内容 / Content |
| --- | --- |
| `overview.png` | 中文 README 首页实际界面图 / User-provided screenshot for the Chinese README |
| `zh/overview.png`, `en/overview.png` | 应用侧栏与示例空间 / Sidebar and example profiles |
| `zh/api-key.png`, `en/api-key.png` | 自定义供应商 BYOK 配置 / Custom-provider BYOK settings |
| `zh/wechat.png`, `en/wechat.png` | 微信实验性空间 / Experimental WeChat profiles |

在 macOS 项目根目录重新生成 / Regenerate from the project root on macOS:

```bash
bash scripts/render-docs.sh
# 仅更新 BYOK 配置图 / Update only the BYOK images
bash scripts/render-docs.sh --api-only
```

脚本编译视图渲染器，生成中英文图片；`~/ShadowApp-Preview` 只用于此过程并在结束时清理。如果该目录已经存在，脚本拒绝复用，避免修改已有数据。微信示例只创建管理记录，不创建应用副本或系统容器。未安装对应应用时，图标显示占位符。

The script compiles a view renderer and produces both language variants. It creates and removes `~/ShadowApp-Preview` for this purpose, refusing to reuse an existing directory. WeChat examples create registry entries only, not app copies or system containers. Missing installed apps display placeholder icons.
