<p align="center">
  <img src="assets/icon.svg" width="96" height="96" alt="LiteMouse 图标">
</p>

<h1 align="center">LiteMouse</h1>

<p align="center">
  <strong>极简原生 macOS 鼠标辅助工具 —— 专注物理滚轮与侧键导航。</strong><br>
  纯 AppKit · 零 SwiftUI · 零 IOHIDManager · 空闲零唤醒 · Universal（Apple 芯片 &amp; Intel）
</p>

<p align="center">
  <a href="https://github.com/MUMU-DADA/LiteMouse/actions/workflows/ci.yml"><img src="https://github.com/MUMU-DADA/LiteMouse/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/MUMU-DADA/LiteMouse/releases/latest"><img src="https://img.shields.io/github/v/release/MUMU-DADA/LiteMouse" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20Universal-lightgrey.svg" alt="macOS 14+ Universal">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

---

## 简介

**LiteMouse** 专注于解决 macOS 外接普通鼠标时的两大痛点——系统自带的非线性滚轮加速与侧键前进/后退失效——同时拒绝一切冗余开销：无 SwiftUI、无后台电量轮询、无 `IOHIDManager` 常驻扫描，也不拦截日常光标移动与按键事件。

### 设计原则

- **极窄事件拦截掩码（`kCGSessionEventTap`）** — 仅拦截 `scrollWheel`、`otherMouseDown`、`otherMouseUp` 三类事件。正常移动鼠标（`mouseMoved`）、左右键点击、拖拽与打字完全不触发回调（**0 µs 额外延迟**）。
- **兼容软件 KVM（如 Deskflow）** — 钩子挂载在 `kCGSessionEventTap`（高于 Deskflow 使用的 `kCGHIDEventTap`），光标切至远端设备时不会干扰远端滚轮与侧键。
- **暂停即彻底卸载钩子** — 暂停 LiteMouse 或关闭全部功能后，立即销毁 `CFMachPort` 并退出独立 RunLoop 线程，彻底释放事件钩子。
- **仅作用于有级物理滚轮** — 严格判断 `scrollWheelEventIsContinuous == 0`，开启滚轮方向反转也不会影响触控板或 Magic Mouse。
- **线性定步进 / 高刷平滑滚动** — 支持彻底剥离 macOS 加速曲线的固定行数线性滚动，以及带亚像素余数累积的指数衰减平滑滚动；帧同步定时器自动匹配主屏刷新率（60Hz / 120Hz / 240Hz），滚动结束立即停表，空闲零唤醒。
- **侧键前进/后退智能路由** — 按目标应用的 Bundle ID 自动选择最佳方案：
  - **原生 `navigationSwipe` 手势**：Apple 原生应用（`com.apple.*`）、Firefox、ForkLift、Opera
  - **`⌘[` / `⌘]` 快捷键**：Obsidian、Notion、Slack、Spotify
  - **默认直通**：VS Code、Chrome 等原生支持 Mouse 4/5 的应用
- **零第三方依赖** — 纯 Swift + AppKit + CoreGraphics（Universal 二进制仅约 600 KB），仅需 Xcode 命令行工具即可编译。

---

## 下载与安装

1. 前往 [Releases](https://github.com/MUMU-DADA/LiteMouse/releases) 下载最新版本的 `LiteMouse-<版本>-macos-universal.dmg`。
2. 双击打开磁盘映像，将 **LiteMouse.app** 拖入 **Applications（应用程序）**。
3. 启动 **LiteMouse**：
   - 发行版采用本机临时签名（ad-hoc），首次运行若遇 Gatekeeper 拦截，请前往「系统设置 › 隐私与安全性」点击「仍要打开」。
   - 点击菜单栏鼠标图标，按提示授予「辅助功能」权限（「系统设置 › 隐私与安全性 › 辅助功能」），授权后自动激活，无需手动重启。

---

## 配置文件（支持热重载）

配置文件位于 `~/.config/litemouse/config.json`，常用项可直接通过菜单栏切换；手动修改文件后通过 `kqueue` 自动热重载，即时生效。

```json
{
  "backForward": {
    "backButtonNumber": 3,
    "cmdBracketBundleIds": [
      "md.obsidian",
      "notion.id",
      "com.tinyspeck.slackmacgap",
      "com.spotify.client"
    ],
    "fallback": "passthrough",
    "forwardButtonNumber": 4,
    "mode": "auto",
    "swipeBundleIds": [
      "com.apple.*",
      "org.mozilla.firefox*",
      "com.binarynights.ForkLift*",
      "com.operasoftware.Opera"
    ]
  },
  "enabled": true,
  "scroll": {
    "horizontalLines": 3,
    "mode": "linear",
    "reverseHorizontal": false,
    "reverseVertical": false,
    "smoothDurationMs": 130,
    "smoothPixelsPerLine": 18,
    "verticalLines": 4
  }
}
```

| 配置项 | 可选值 | 说明 |
|---|---|---|
| `enabled` | `true` / `false` | 总开关；关闭后彻底销毁 `CGEventTap` |
| `scroll.mode` | `"linear"`、`"smooth"`、`"disabled"` | 线性定步进、帧同步平滑滚动、或关闭滚轮接管 |
| `scroll.verticalLines` / `horizontalLines` | `1`–`30` | 每格滚轮滚动行数（默认 `4` / `3`） |
| `scroll.reverseVertical` / `reverseHorizontal` | `true` / `false` | 反转物理鼠标滚轮方向（不影响触控板） |
| `scroll.smoothPixelsPerLine` | `4`–`120` | 平滑模式下每行对应像素距离（默认 `18`） |
| `scroll.smoothDurationMs` | `30`–`500` | 平滑衰减持续时间（毫秒，默认 `130`） |
| `backForward.mode` | `"auto"`、`"swipe"`、`"cmdBracket"`、`"disabled"` | 侧键前进/后退路由模式 |
| `backForward.fallback` | `"passthrough"`、`"cmdBracket"`、`"swipe"` | 未命中规则应用时的默认行为 |
| `backForward.backButtonNumber` / `forwardButtonNumber` | 整数 | CoreGraphics 侧键编号（默认 `3` / `4`） |

---

## 从源码构建

### 环境要求
- macOS 14.0+
- Swift 6.0+（Xcode 或 Xcode 命令行工具）

### 运行单元测试

```bash
./scripts/test.sh
```

### 构建 `.app` 应用包

```bash
# 本机架构（快速本地编译）
./scripts/build-app.sh release

# Universal 通用二进制（arm64 + x86_64）
UNIVERSAL=1 ./scripts/build-app.sh release
```

### 打包并校验 `.dmg`

```bash
./scripts/package-dmg.sh
```

### 一键安装到 `/Applications`

```bash
./scripts/install.sh
```

---

## 项目结构

```text
LiteMouse/
├── Package.swift                             # SwiftPM 配置（零第三方依赖）
├── Sources/
│   ├── LiteMouseCore/                        # 纯逻辑核心库（可独立单测）
│   │   ├── Config.swift                      # 配置模型与 ~/.config/litemouse 读写
│   │   ├── ScrollPhysics.swift               # 线性步进计算与指数衰减平滑滚动积分器
│   │   └── BackForwardRouter.swift           # 按 Bundle ID 分发的侧键路由
│   └── LiteMouse/                            # AppKit 菜单栏应用
│       ├── main.swift                        # Accessory 模式入口
│       ├── AppDelegate.swift                 # 菜单栏 UI、kqueue 配置热重载与权限监听
│       ├── EventTapController.swift          # 独立线程 CGEventTap（仅 3 类事件）
│       ├── SmoothScrollAnimator.swift        # 按需启停的高刷帧同步定时器
│       ├── EventSynthesizer.swift            # 原生导航手势、⌘[/⌘] 与连续滚动合成
│       └── LaunchAgentManager.swift          # LaunchAgent 开机自启管理
├── Tests/LiteMouseCoreTests/                 # Swift Testing 单元测试
├── scripts/                                  # 测试、应用打包、图标生成、DMG 打包与安装脚本
└── assets/icon.svg                           # 矢量应用图标
```

---

## 开源许可

本项目采用 [MIT License](LICENSE) 开源。
