#!/bin/bash
#
# Touch Bar Initialization Script
# 一次性初始化 CoreBrightness 的 Touch Bar 子系统，使 app 能正常访问私有 API。
# 需要 root 权限运行（通过 sudo）。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_SCRIPT="${SCRIPT_DIR}/init_touchbar.swift"

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

# ── 执行 ──────────────────────────────────────────────────────────────────────
info "正在初始化 Touch Bar（需要管理员权限）..."
if swift "$SWIFT_SCRIPT"; then
    info "Touch Bar 初始化完成！请重新打开应用。"
else
    error "Touch Bar 初始化失败"
fi
