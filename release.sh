#!/bin/bash
# ============================================================
# LXFinderLauncher Release 发布脚本（路径 B：需 Apple Developer 账号，$99/年）
#
# 作用：构建 Release → 校验 Developer ID 签名 → 公证 → 装订 → 打 DMG。
#       签名 + 公证后的 App，任何人下载双击即可运行，Gatekeeper 完全放行。
#
# ── 前置条件（一次性）──────────────────────────────
#   1. 注册 Apple Developer Program（$99/年），个人账号即可；
#   2. Xcode → Settings → Accounts → 登录付费账号；
#      Xcode → Settings → Accounts → Manage Certificates →
#      生成/下载「Developer ID Application」证书；
#   3. 在工程 Signing & Capabilities 里把 Team 切换为付费账号
#      （Release 会自动用 Developer ID Application 证书签名）。
#
# ── 运行前设置环境变量 ─────────────────────────────
#   APPLE_ID      你的 Apple ID 邮箱
#   TEAM_ID       你的 Team ID（Xcode → Settings → Accounts → 账号详情）
#   APP_PASSWORD  Apple ID 的「App 专用密码」
#                 （appleid.apple.com → 登录与安全 → App 专用密码，生成一个）
#                 注意：不是你的 Apple ID 登录密码。
#
# 用法：
#   APPLE_ID=you@example.com TEAM_ID=ABCDE12345 APP_PASSWORD=xxxx-xxxx-xxxx-xxxx ./release.sh
#
# 产物：release/LXFinderLauncher.dmg（已签名 + 公证 + 装订）
# ============================================================

# 任一命令失败立即退出。
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/LXFinderLauncher.xcodeproj"
SCHEME="LXFinderLauncher"
OUT="$SCRIPT_DIR/release"

# ------------------------------------------------------------
# 0) 校验环境变量：:? 语法在变量为空时直接报错退出。
# ------------------------------------------------------------
: "${APPLE_ID:?❌ 请设置 APPLE_ID（你的 Apple ID 邮箱）}"
: "${TEAM_ID:?❌ 请设置 TEAM_ID（Xcode 账号里的 Team ID）}"
: "${APP_PASSWORD:?❌ 请设置 APP_PASSWORD（Apple ID 的 App 专用密码）}"

# ------------------------------------------------------------
# 1) 构建 Release
#    产物固定到 build/（与 distribute-free.sh 共用）。
# ------------------------------------------------------------
echo "🔨 构建 Release ..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
           -derivedDataPath "$SCRIPT_DIR/build" build

APP="$SCRIPT_DIR/build/Build/Products/Release/LXFinderLauncher.app"
if [[ ! -d "$APP" ]]; then
    echo "❌ 构建产物不存在：$APP"
    exit 1
fi

# ------------------------------------------------------------
# 2) 校验签名确为 Developer ID Application
#    防止误用了免费账号的 Apple Development 签名（公证会失败）。
#    codesign -dv 打印签名信息，grep 找 "Developer ID Application"。
# ------------------------------------------------------------
echo "🔍 校验 Developer ID 签名 ..."
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
    echo "❌ 当前签名不是 Developer ID Application 证书。"
    echo "   请到 Xcode 工程 Signing & Capabilities 把 Team 切为付费账号后重试。"
    exit 1
fi

# ------------------------------------------------------------
# 3) 公证（Notarization）
#    把 .app 压缩后提交给苹果服务器做安全扫描。
#    --wait 表示一直等到出结果（0=通过，否则失败）。
# ------------------------------------------------------------
echo "☁️  提交公证 ..."
xcrun notarytool submit "$APP" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

# ------------------------------------------------------------
# 4) 装订（Staple）
#    把公证通过的凭证贴回 .app 内部。
#    装订后即使离线运行也能通过 Gatekeeper，避免每次联网验证。
# ------------------------------------------------------------
echo "📌 装订公证凭证 ..."
xcrun stapler staple "$APP"

# ------------------------------------------------------------
# 5) 制作 DMG
#    只读压缩映像（UDZO），拖入 /Applications 即可安装。
# ------------------------------------------------------------
echo "📦 制作 DMG ..."
rm -rf "$OUT"
mkdir -p "$OUT"
hdiutil create -volname LXFinderLauncher -srcfolder "$APP" \
               -ov -format UDZO "$OUT/LXFinderLauncher.dmg" >/dev/null

# ------------------------------------------------------------
# 6) 完成提示
# ------------------------------------------------------------
echo ""
echo "✅ 发布完成！产物：$OUT/LXFinderLauncher.dmg"
echo "   任何人下载后双击即可运行（已签名 + 公证，Gatekeeper 放行）。"
echo ""
echo "后续：把 DMG 传到 GitHub Releases / 官网 / 网盘即可对外分发。"
echo "提示：改代码后重新执行本脚本即可产出新版本。"
