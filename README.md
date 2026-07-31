# TouchBrightness

macOS 菜单栏工具，用于调节 Touch Bar 屏幕亮度。

## 起源

最初为 **无头骑士**（2016–2020 年搭载 Touch Bar 的 MacBook Pro）设计。这些机型没有实体功能键，Touch Bar 是键盘上方唯一的交互区域，但 macOS 没有提供便捷的 Touch Bar 亮度调节入口——用户必须进入系统设置才能调整。TouchBrightness 让你随时从菜单栏一键调节。

## 功能

- ☀️ 菜单栏太阳图标，点击弹出亮度控制面板
- 滑块无级调节 Touch Bar 亮度（0%–100%）
- 一键切换自动亮度 / 手动亮度
- Min / Max 快捷按钮
- 退出按钮
- Touch Bar 上同步显示亮度滑块（如果可用）
- 多语言支持：中文、英文、日文、韩文、德文、法文、西班牙文、葡萄牙文、俄文、阿拉伯文、越南文
- 无 Dock 图标，纯菜单栏应用
- 开机自启支持

## 首次使用

首次打开应用时，程序会自动从 GitHub 拉取初始化脚本并提示你运行。该脚本需要管理员权限，用于初始化 CoreBrightness 的 Touch Bar 子系统——这是应用能够读写 Touch Bar 亮度的前提。

初始化脚本存储在 `~/Library/Application Support/TouchBrightness/`。

## 编译

需要 Xcode Command Line Tools（提供 `swiftc`）：

```bash
bash compile.sh
```

编译产物为 `TouchBrightness.app`。

## 运行

```bash
open TouchBrightness.app
```

或直接双击 app。

## 开机自启

将 `TouchBrightness.app` 添加到 **系统设置 → 通用 → 登录项** 即可。

## 卸载

1. 退出应用
2. 删除 `TouchBrightness.app`
3. （可选）删除初始化脚本：`rm -rf ~/Library/Application\ Support/TouchBrightness`

## 要求

- macOS 12+ (Monterey)
- 带 Touch Bar 的 MacBook Pro
- Xcode Command Line Tools
- 首次使用需要网络连接（下载初始化脚本）

## 技术说明

- 纯 Swift 编写，单文件架构，无第三方依赖
- 通过 `CoreBrightness.framework` 私有 API 读写 Touch Bar 亮度
- 使用 `NSPanel` + `makeTouchBar()` 标准 API 在 Touch Bar 上显示控件
- `LSUIElement` 模式运行，不显示 Dock 图标
- 初始化脚本从 GitHub 动态拉取，便于独立更新

## 许可

MIT License
