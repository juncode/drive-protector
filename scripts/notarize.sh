#!/bin/bash
# Developer ID 签名 + Apple 公证脚本
# 用法:
#   ./scripts/notarize.sh \
#       --identity "Developer ID Application: Your Name (TEAMID)" \
#       --apple-id "you@example.com" \
#       --team-id "TEAMID" \
#       --app-specific-password "xxxx-xxxx-xxxx-xxxx"
set -euo pipefail

cd "$(dirname "$0")/.."

# ===== 参数解析 =====
IDENTITY=""
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity) IDENTITY="$2"; shift 2 ;;
        --apple-id) APPLE_ID="$2"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --app-specific-password) APP_PASSWORD="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -z "$IDENTITY" ] || [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$APP_PASSWORD" ]; then
    echo "用法: $0 --identity \"Developer ID Application: ...\" --apple-id ... --team-id ... --app-specific-password ..."
    echo ""
    echo "  --identity               Developer ID Application 证书名（security find-identity -v -p codesigning 查看）"
    echo "  --apple-id               Apple ID 邮箱"
    echo "  --team-id                开发者团队 ID（10位字符）"
    echo "  --app-specific-password  App 专用密码（appleid.apple.com 生成）"
    exit 1
fi

BUNDLE_NAME="Drive Protector"
APP_BUNDLE="dist/${BUNDLE_NAME}.app"
ENTITLEMENTS="Resources/DriveProtector.entitlements"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ 未找到 $APP_BUNDLE，请先运行 ./scripts/make-app.sh 打包"
    exit 1
fi

echo "==> 1/4  签名内置 smartctl（先签子组件）"
codesign --force --sign "$IDENTITY" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "${APP_BUNDLE}/Contents/Resources/bin/smartctl"

echo "==> 2/4  签名主 App（含 entitlements + Hardened Runtime）"
codesign --force --deep --sign "$IDENTITY" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

echo "==> 3/4  提交公证（zip 后上传 Apple 公证服务）"
ZIP_PATH="dist/DriveProtector-for-notary.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "    上传中（首次可能需要 1-3 分钟）…"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo ""
echo "==> 4/4  Staple 公证票据到 App"
xcrun stapler staple "$APP_BUNDLE"

echo ""
echo "==> 验证签名与公证"
echo "--- 签名信息 ---"
codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep -E "Authority|Runtime" | head -5
echo "--- 公证状态 ---"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$ZIP_PATH"
echo ""
echo "✅ 签名+公证完成！"
echo "   App 路径: $(pwd)/${APP_BUNDLE}"
echo "   现在可分发给他人，Gatekeeper 不会拦截。"
