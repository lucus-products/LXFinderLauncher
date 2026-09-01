#!/bin/bash
# ============================================================
# LXFinderLauncher 免费分发脚本（路径 A：无需 Apple Developer 账号，$0）
#
# 用法：
#   ./scripts/distribute-free.sh            # 构建 Release 并打包
#   ./scripts/distribute-free.sh Debug      # 仅自测用（见下方「为什么默认 Release」）
#
# 产物：
#   dist-free/LXFinderLauncher.app   原始 App
#   dist-free/LXFinderLauncher.zip   通用压缩包（推荐发给别人）
#   dist-free/LXFinderLauncher.dmg   拖拽安装的磁盘映像
#
# 分发限制：
#   未签名 Developer ID 的 App，别人首次运行会被 Gatekeeper 拦截。
#   对方需：右键 → 打开（多一次确认），或终端执行
#     xattr -dr com.apple.quarantine '/path/to/LXFinderLauncher.app'
#   适合：自己用 / 给信任的朋友 / 学习分享。
# ============================================================

# 任一命令失败立即退出。
set -e

# 定位工程根目录：脚本统一放在 scripts/ 下，根目录 = 脚本上一级，
# 构建产物稳定落在工程根目录的 dist-build/ 与 dist-free/ 下。
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_ROOT/LXFinderLauncher.xcodeproj"
SCHEME="LXFinderLauncher"
CONFIG="${1:-Release}"          # 默认 Release，可传 Debug
DIST="$PROJECT_ROOT/dist-free"

# 只允许两种合法配置。
if [[ "$CONFIG" != "Debug" && "$CONFIG" != "Release" ]]; then
    echo "❌ 无效配置：$CONFIG（仅支持 Debug / Release）"
    exit 1
fi

# 为什么默认 Release：
#   Xcode 26 的 Debug 构建会把代码打进 LXFinderLauncher.debug.dylib，
#   主二进制只是薄壳 —— 这种产物只适合本机调试，发到别人机器不稳定。
#   Release 构建会合并成单一二进制，才是可分发的形态。
if [[ "$CONFIG" == "Debug" ]]; then
    echo "⚠️  Debug 产物含 debug.dylib，仅供本机自测，分发请用 Release。"
fi

# ------------------------------------------------------------
# 1) 构建
#    -derivedDataPath 固定产物到 dist-build/，路径可预测。
# ------------------------------------------------------------
echo "🔨 构建 $CONFIG ..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
           -derivedDataPath "$PROJECT_ROOT/dist-build" build >/dev/null

APP_SRC="$PROJECT_ROOT/dist-build/Build/Products/$CONFIG/LXFinderLauncher.app"
if [[ ! -d "$APP_SRC" ]]; then
    echo "❌ 构建产物不存在：$APP_SRC"
    exit 1
fi

# ------------------------------------------------------------
# 2) 复制到干净的 dist-free/ 目录
# ------------------------------------------------------------
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP_SRC" "$DIST/LXFinderLauncher.app"

# ------------------------------------------------------------
# 3) 打包 zip 与 dmg
#    ditto 是 macOS 官方打 zip 的方式（保留符号链接与权限）。
#    hdiutil 制作只读压缩 dmg（UDZO）。
# ------------------------------------------------------------
echo "📦 打包 zip / dmg ..."
ditto -c -k --sequesterRsrc --keepParent "$DIST/LXFinderLauncher.app" "$DIST/LXFinderLauncher.zip"
hdiutil create -volname LXFinderLauncher -srcfolder "$DIST/LXFinderLauncher.app" \
               -ov -format UDZO "$DIST/LXFinderLauncher.dmg" >/dev/null

# ------------------------------------------------------------
# 4) 完成提示
# ------------------------------------------------------------
echo ""
echo "✅ 完成！产物目录：$DIST"
echo "    LXFinderLauncher.app / .zip / .dmg"
echo ""
echo "本机双击 dist-free/LXFinderLauncher.app 即可运行（本机产物无隔离属性）。"
echo ""
echo "⚠️  发给他人后首次运行会被 Gatekeeper 拦截（未签名 Developer ID）："
echo "    方式一：右键 LXFinderLauncher.app → 打开（多一次确认）"
echo "    方式二：终端执行  xattr -dr com.apple.quarantine 'App 路径'"
echo ""
echo "    想让别人双击直接运行、无需手动放行 → 用 release.sh（需 \$99/年 开发者账号）。"
