#!/bin/bash
# ============================================================
# LXFinderLauncher 构建脚本
#
# 用法：
#   ./build.sh            # 默认构建 Debug
#   ./build.sh Release    # 构建 Release
#
# 构建产物：
#   build/Build/Products/<配置>/LXFinderLauncher.app
# ============================================================

# set -e：脚本中任一命令返回非 0（失败），立即终止，避免带病继续。
set -e

# ------------------------------------------------------------
# 定位工程目录
#   dirname "$0"  → 脚本所在目录
#   cd ... pwd    → 转成绝对路径
# 这样无论从哪个目录调用 ./build.sh，都能正确找到工程。
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/LXFinderLauncher.xcodeproj"
SCHEME="LXFinderLauncher"

# 构建配置：取第一个参数，缺省 Debug。
CONFIG="${1:-Debug}"

# 只允许两种合法配置，防止拼错参数浪费一次全量构建。
if [[ "$CONFIG" != "Debug" && "$CONFIG" != "Release" ]]; then
    echo "❌ 无效配置：$CONFIG（仅支持 Debug / Release）"
    exit 1
fi

# 前置检查：xcodebuild 是 Xcode 自带的命令行工具，缺失则无法构建。
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ 未找到 xcodebuild，请先安装 Xcode 命令行工具。"
    exit 1
fi

echo "🔨 开始构建 LXFinderLauncher（$CONFIG）..."

# ------------------------------------------------------------
# xcodebuild 各参数说明：
#   -project <path>        指定要构建的工程文件
#   -scheme <name>         指定 scheme（自动带上测试 target 一起构建）
#   -configuration <name>  构建配置：Debug（含调试符号）/ Release（优化）
#   -derivedDataPath <dir> 指定产物输出目录。
#                          不用它时产物落在 Xcode 的 ~/Library/Developer/
#                          Xcode/DerivedData/... 深层随机路径里；
#                          指定后固定在本工程 build/ 下，路径稳定可预测。
#   build                  执行构建动作
# ------------------------------------------------------------
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$SCRIPT_DIR/build" \
    build

# ------------------------------------------------------------
# 构建成功的产物 .app 一定在这里（derivedDataPath 已知，路径可算）：
#   build/Build/Products/<Debug|Release>/LXFinderLauncher.app
# ------------------------------------------------------------
APP_PATH="$SCRIPT_DIR/build/Build/Products/$CONFIG/LXFinderLauncher.app"

if [[ -d "$APP_PATH" ]]; then
    echo ""
    echo "✅ 构建成功！产物："
    echo "   $APP_PATH"
    echo ""
    echo "启动方式："
    echo "   open \"$APP_PATH\""
else
    echo "⚠️ 构建已结束但未找到产物，请检查上方日志。"
    exit 1
fi
