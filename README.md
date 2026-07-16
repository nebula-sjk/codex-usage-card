# Codex 使用量卡片

一个轻量的桌面悬浮卡片，用于在 macOS 或 Windows 上查看 Codex 的 7 天使用额度和限额重置次数。

> 非 OpenAI 官方应用。它仅读取本机 Codex 客户端产生的使用记录，不会发送任何用量数据到网络。

![macOS](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)
![Swift](https://img.shields.io/badge/language-Swift-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-2ea44f)

## 功能

- 显示 7 天窗口的剩余额度、重置时间与套餐类型
- 以“充足 / 适中 / 告急”三档颜色反馈余额状态
- 显示限额重置次数和最近到期时间（服务端未提供时会明确提示）
- 静止时收起为 50 × 50 的浮球；悬停 0.5 秒后展开卡片
- 仅当 Codex / ChatGPT 桌面窗口可见时显示浮球
- 支持拖动位置；macOS 版还可调整展开卡片尺寸

## 项目亮点

1. **抬眼即见**：把 7 天额度放在桌面上，无需反复打开 Codex 的用量面板。
2. **贴合当前规则**：聚焦当前的 7 天窗口，并区分周额度重置与限额重置卡到期时间。
3. **状态一眼分辨**：以“充足 / 适中 / 告急”文字和对应色彩共同表达余额，不只依赖颜色。
4. **低打扰常驻**：静止时收起为 50 × 50 浮球；悬停后才展开完整信息。
5. **跟随工作场景**：仅在 Codex / ChatGPT 窗口可见时显示，避免无关桌面状态下的干扰。
6. **本地优先、开箱即用**：只读取本机日志，不上传用量数据；既可下载安装包，也可从源码自行构建。

## 三档状态

| 充足（≥ 60%） | 适中（30–59%） | 告急（＜ 30%） |
| --- | --- | --- |
| ![充足状态](assets/screenshots/abundant.png) | ![适中状态](assets/screenshots/moderate.png) | ![告急状态](assets/screenshots/critical.png) |

### 收起浮球

| 充足 | 适中 | 告急 |
| --- | --- | --- |
| ![充足浮球](assets/screenshots/ball-abundant.png) | ![适中浮球](assets/screenshots/ball-moderate.png) | ![告急浮球](assets/screenshots/ball-critical.png) |

## 下载安装

普通使用者无需安装 Git、Swift 或 Python，直接前往：

**[打开最新版下载页](https://github.com/nebula-sjk/codex-usage-card/releases/latest)**

| 平台 | 推荐文件 | 使用方式 |
| --- | --- | --- |
| macOS（Apple 芯片与 Intel） | [`CodexUsageCard-macos-universal.dmg`](https://github.com/nebula-sjk/codex-usage-card/releases/latest/download/CodexUsageCard-macos-universal.dmg) | 打开 DMG，把“Codex使用量卡片”拖入“应用程序”，再启动应用 |
| Windows 10/11 x64 | [`CodexUsageCard-windows-x64-setup.exe`](https://github.com/nebula-sjk/codex-usage-card/releases/latest/download/CodexUsageCard-windows-x64-setup.exe) | 运行安装程序，按向导完成安装 |
| Windows 便携版 | [`CodexUsageCard-windows-x64.exe`](https://github.com/nebula-sjk/codex-usage-card/releases/latest/download/CodexUsageCard-windows-x64.exe) | 无需安装，下载后直接运行 |

这些公开构建暂未购买商业代码签名证书。macOS 首次运行若被 Gatekeeper 拦截，请在 Finder 中按住 Control 点击应用并选择“打开”；Windows 若出现 SmartScreen 提示，请先确认下载地址属于本仓库，再选择“更多信息”继续运行。

首次启动后，卡片只会在 Codex / ChatGPT 桌面窗口可见时出现。若暂时没有读到用量，请打开 Codex 并发起一次请求，卡片会自动刷新。

## 从源码构建（开发者）

### macOS

要求 macOS 13 或更高版本，并安装 Xcode Command Line Tools：

```zsh
git clone https://github.com/nebula-sjk/codex-usage-card.git
cd codex-usage-card
./scripts/build.sh
open "build/Codex使用量卡片.app"
```

默认构建当前 Mac 的原生架构；发布工作流会分别构建 Apple 芯片和 Intel 二进制，再合并为通用应用。

### Windows

要求 Windows 10/11 x64 与 Python 3.10 或更高版本：

```powershell
git clone https://github.com/nebula-sjk/codex-usage-card.git
cd codex-usage-card
powershell -ExecutionPolicy Bypass -File .\windows\build.ps1
.\dist\CodexUsageCard-windows-x64.exe
```

构建脚本会在本地安装 PyInstaller。只有制作安装程序时才需要另外安装 Inno Setup 6，并传入 `-Installer`。

## 隐私与限制

- 不包含 API Key、账户凭据或网络上传逻辑。
- 使用量数据来自本机 `~/.codex/logs_2.sqlite`；Codex 的内部日志字段可能随版本变化，卡片会在无法读取时显示相应状态。
- “限额重置次数”的到期时间优先读取服务端字段；字段缺失时只展示明确的未读取状态。
- 发布页中的未签名构建适合公开测试；正式代码签名与公证需要相应的平台开发者证书。

## 项目结构

```text
Sources/                 macOS Swift/Cocoa 源码
Resources/               macOS 应用包资源
windows/                 Windows 应用与安装程序源码
scripts/                 macOS 构建和打包脚本
.github/workflows/       双平台构建与 Release 自动发布
docs/development/        开发记录与历史排查资料
build/、dist/            本地构建产物（不纳入 Git）
```

## 贡献

欢迎通过 Issue 提交兼容性问题、日志字段变化或界面建议。提交前请至少运行对应平台的构建脚本。

## 开源许可证

本项目采用 [MIT License](LICENSE)。
