# TouchBrightness

> macOS 菜单栏工具，一键调节 Touch Bar 亮度。

<p align="center">
  <img src="Sources/touchbrightness500.png" width="200" alt="TouchBrightness Icon">
</p>

<p align="center">
  <a href="https://github.com/a00331111/TouchBrightness">
    <img src="https://img.shields.io/github/stars/a00331111/TouchBrightness?style=social" alt="Star">
  </a>
  <a href="https://github.com/a00331111/TouchBrightness/fork">
    <img src="https://img.shields.io/github/forks/a00331111/TouchBrightness?style=social" alt="Fork">
  </a>
  <a href="https://github.com/a00331111/TouchBrightness/issues">
    <img src="https://img.shields.io/github/issues/a00331111/TouchBrightness" alt="Issues">
  </a>
  <a href="https://github.com/a00331111/TouchBrightness/releases">
    <img src="https://img.shields.io/github/downloads/a00331111/TouchBrightness/total" alt="Downloads">
  </a>
  <a href="https://github.com/a00331111/TouchBrightness/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.5.2-blue" alt="Version">
  <img src="https://img.shields.io/badge/macOS-12%2B-brightgreen" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Swift-5-f05138?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/languages-11-orange" alt="11 Languages">
</p>

## 缘起

我买了一台 **MacBook Pro A2338 (M1, 2020)** ——没有屏幕的「无头骑士」。因为没有内置屏幕，摄像头旁边的 **环境光传感器缺失**，导致了一系列奇怪的问题：

- 🔦 **亮度异常**：开机后 Touch Bar 要么非常暗，要么非常亮，无法正常初始化
- 🔄 **亮度重置**：系统反复检测不到传感器数值，会不断把 Touch Bar 亮度重置为不可用状态
- ⚙️ **无法手动调节**：macOS 根本没有提供方便的 Touch Bar 亮度调节入口，只能在「系统设置 → 显示器」里翻找

TouchBrightness 就是为了解决这些问题而写的。它通过 LaunchDaemon 持久化亮度值，每 5 分钟同步一次，让 Touch Bar 保持在你想要的亮度——不再被系统莫名其妙地重置。

**如果你也有一台无头骑士，希望这个工具能帮到你。**

## 功能

| 功能 | 说明 |
|------|------|
| ☀️ 菜单栏控制 | 太阳图标，点击弹出亮度面板 |
| 无级滑块 | 0%–100% 连续调节 |
| 自动亮度 | 一键切换自动 / 手动模式 |
| Min / Max | 一键设为最低或最高亮度 |
| Touch Bar 同步 | 在 Touch Bar 上显示亮度滑块（需面板获焦） |
| 开机自启 | 通过 `SMAppService` 注册登录项（macOS 13+） |
| 无 Dock 图标 | `LSUIElement` 模式，纯菜单栏应用 |
| 多语言 | 中文、English、日本語、한국어、Deutsch、Français、Español、Português、Русский、العربية、Tiếng Việt |

## 截图

<p align="center">
  <img src="Sources/touchbrightness500.png" width="400" alt="TouchBrightness Screenshot">
</p>

## 快速开始

### 1. 下载

从 [Releases](https://github.com/a00331111/TouchBrightness/releases) 下载最新版本 `TouchBrightness-v1.5.2.zip`，解压后得到 `TouchBrightness.app`。

### 2. 首次运行

双击打开 `TouchBrightness.app`：

1. 程序会自动从 GitHub 拉取初始化脚本（需网络连接）
2. 弹出对话框提示「初始化触控栏」，点击「初始化」
3. 输入管理员密码（仅需一次，用于激活 CoreBrightness 的 Touch Bar 子系统）
4. 完成后 Touch Bar 亮度即可调节

### 3. 日常使用

- 点击菜单栏 ☀️ 图标，拖动滑块调节亮度
- 面板获焦时，Touch Bar 上会同步显示亮度滑块
- 支持自动亮度开关和开机自启

## 从源码编译

需要 Xcode Command Line Tools（提供 `swiftc`）：

```bash
git clone https://github.com/a00331111/TouchBrightness.git
cd TouchBrightness
bash compile.sh
open TouchBrightness.app
```

编译产物为 `TouchBrightness.app`，无第三方依赖。

## 技术架构

```
TouchBrightness.app
├── main.swift              # 核心应用（~770 行纯 Swift）
├── init_touchbar.sh        # 初始化脚本（需 sudo）
├── init_touchbar.swift     # CoreBrightness 框架初始化
├── checksums.md5           # 脚本完整性校验
├── *.lproj/                # 11 种语言本地化
└── AppIcon.icns            # 应用图标
```

### 核心原理

- **CoreBrightness 私有 API**：通过 `dlopen` 加载 `/System/Library/PrivateFrameworks/CoreBrightness.framework`，使用 `BrightnessSystemClient` 的私有方法读写 Touch Bar 亮度（Display ID = 3）
- **LaunchDaemon 持久化**：安装 `/Library/LaunchDaemons/com.touchbarbrightness.init.plist`，每 5 分钟从 `~/.tbinfo` 读取用户设定的亮度值并同步到 Touch Bar，防止系统自动重置
- **MD5 校验**：首次运行时从 GitHub 下载脚本，通过 `checksums.md5` 验证完整性，确保供应链安全
- **NSPanel + makeTouchBar()**：使用标准 API 在 Touch Bar 上显示自定义滑块控件

### 架构亮点

- **零依赖**：纯 Swift，仅依赖 Cocoa + ServiceManagement + CommonCrypto（系统框架）
- **单文件**：核心逻辑全部在 `main.swift` 一个文件中
- **远程更新**：初始化脚本从 GitHub 动态拉取，可独立于 app 更新
- **安全**：脚本下载后 MD5 校验，LaunchDaemon 仅在开机时运行一次

## 卸载

1. 退出应用
2. 删除 `TouchBrightness.app`
3. （可选）删除初始化脚本和 LaunchDaemon：
   ```bash
   rm -rf ~/Library/Application\ Support/TouchBrightness
   sudo rm /Library/LaunchDaemons/com.touchbarbrightness.init.plist
   ```

## 系统要求

- macOS 12.0+ (Monterey)
- 带 Touch Bar 的 MacBook Pro（2016–2020 款）
- 首次使用需网络连接（下载初始化脚本）

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE) 开源。

| 使用场景 | 许可 | 费用 |
|----------|------|------|
| 个人使用 | GPL-3.0 | 免费 |
| 开源项目（与本项目协议兼容） | GPL-3.0 | 免费 |
| 商业 / 闭源使用 | 商业授权 | 💰 付费 |

**商业授权**：如果你的公司或商业项目需要将 TouchBrightness 集成到闭源产品中，请通过 [Issues](https://github.com/a00331111/TouchBrightness/issues) 联系我获取商业授权。
