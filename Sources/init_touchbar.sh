#!/bin/bash
#
# Touch Bar Initialization Script
# 一次性初始化 CoreBrightness 的 Touch Bar 子系统，使 app 能正常访问私有 API。
# 需要 root 权限运行（通过 sudo）。
#
# 用法:
#   bash init_touchbar.sh              # 仅初始化
#   bash init_touchbar.sh --daemon     # 初始化 + 安装开机自启 LaunchDaemon
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_SCRIPT="${SCRIPT_DIR}/init_touchbar.swift"
INSTALL_DAEMON=false

if [[ "${1:-}" == "--daemon" ]]; then
    INSTALL_DAEMON=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✔]${NC} $*"; }
error() { echo -e "${RED}[✘]${NC} $*"; exit 1; }

# ── 环境检查 ──────────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    error "仅支持 macOS"
fi

MODEL=$(sysctl -n hw.model 2>/dev/null || echo "")
if [[ "$MODEL" != MacBookPro* ]]; then
    error "仅支持 MacBook Pro（当前: $MODEL）"
fi

if ! ioreg -r -c "AppleARMBacklight" 2>/dev/null | grep -q "CurrentNits"; then
    error "未检测到 Touch Bar 背光设备"
fi

if [[ ! -f "$SWIFT_SCRIPT" ]]; then
    error "初始化脚本不存在: $SWIFT_SCRIPT"
fi

# ── 执行初始化 ────────────────────────────────────────────────────────────────
info "正在初始化 Touch Bar（需要管理员权限）..."
if swift "$SWIFT_SCRIPT"; then
    info "Touch Bar 初始化完成！请重新打开应用。"
else
    error "Touch Bar 初始化失败"
fi

# ── 安装 LaunchDaemon（开机自动初始化）───────────────────────────────────────
if $INSTALL_DAEMON; then
    DAEMON_PLIST="/Library/LaunchDaemons/com.touchbarbrightness.init.plist"
    WRAPPER_DIR="${SCRIPT_DIR}/daemon"
    WRAPPER_PATH="${WRAPPER_DIR}/run_init.sh"

    mkdir -p "$WRAPPER_DIR"

    # 创建 shell 包装脚本
    # 通过 /dev/console owner 获取真实用户 home（LaunchDaemon 以 root 运行）
    cat > "$WRAPPER_PATH" << WRAPPER
#!/bin/bash
# TouchBrightness daemon wrapper — 开机自动初始化 Touch Bar
# 由 TouchBrightness.app 自动生成，请勿手动修改
REAL_USER=\$(stat -f%Su /dev/console)
USER_HOME=\$(eval echo ~\$REAL_USER)
exec swift "${SWIFT_SCRIPT}" "\$USER_HOME"
WRAPPER
    chmod 755 "$WRAPPER_PATH"

    # 写入 LaunchDaemon plist
    cat > "$DAEMON_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.touchbarbrightness.init</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${WRAPPER_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>/tmp/touchbarbrightness_init.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/touchbarbrightness_init.log</string>
</dict>
</plist>
PLIST

    # 加载 LaunchDaemon
    launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
    launchctl load "$DAEMON_PLIST"
    info "LaunchDaemon 已安装：每次开机将自动初始化 Touch Bar"
fi
