#!/bin/bash
# 将 SwiftPM 可执行文件打包为标准的 Drive Protector.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DriveProtector"          # 可执行文件名（SwiftPM 产物，不可改）
BUNDLE_NAME="Drive Protector"       # .app 目录名 / Finder 显示名
BUILD_CONFIG="release"
BINARY=".build/${BUILD_CONFIG}/${APP_NAME}"
APP_BUNDLE="dist/${BUNDLE_NAME}.app"

echo "==> 编译 (${BUILD_CONFIG})…"
swift build -c ${BUILD_CONFIG}

echo "==> 组装 App Bundle…"
rm -rf "dist/${BUNDLE_NAME}.app"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Drive Protector</string>
    <key>CFBundleDisplayName</key>
    <string>Drive Protector 磁盘守护</string>
    <key>CFBundleIdentifier</key>
    <string>com.driveprotector.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DriveProtector</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Drive Protector. Disk monitoring for macOS.</string>
    <key>CFBundleIconFile</key>
    <string>DriveProtector.icns</string>
</dict>
</plist>
PLIST

# ===== 嵌入应用图标 =====
ICON_SRC="Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    echo "==> 嵌入应用图标"
    cp "$ICON_SRC" "${APP_BUNDLE}/Contents/Resources/DriveProtector.icns"
else
    echo "==> ⚠️  未找到 Resources/AppIcon.icns，使用默认图标"
fi

# ===== 嵌入 smartctl（smartmontools），实现开箱即用的 SMART 读取 =====
SMARTCTL_SYS=""
for p in /opt/homebrew/sbin/smartctl /opt/homebrew/bin/smartctl \
         /usr/local/sbin/smartctl /usr/local/bin/smartctl; do
    if [ -x "$p" ]; then SMARTCTL_SYS="$p"; break; fi
done

if [ -n "$SMARTCTL_SYS" ]; then
    echo "==> 嵌入 smartctl：$SMARTCTL_SYS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources/bin"
    cp "$SMARTCTL_SYS" "${APP_BUNDLE}/Contents/Resources/bin/smartctl"
    chmod +x "${APP_BUNDLE}/Contents/Resources/bin/smartctl"
    echo "    架构：$(lipo -info "${APP_BUNDLE}/Contents/Resources/bin/smartctl" 2>/dev/null | sed 's/^Non-//' || echo unknown)"
    # 对内置二进制单独签名（ad-hoc），避免 Gatekeeper 拦截
    codesign --force --sign - "${APP_BUNDLE}/Contents/Resources/bin/smartctl" 2>/dev/null || true
else
    echo "==> ⚠️  系统未检测到 smartctl，App 将以演示数据模式运行"
    echo "    安装后重新打包即可嵌入："
    echo "      brew install smartmontools && ./scripts/make-app.sh"
fi

echo "==> 签名 App Bundle（ad-hoc，含嵌入的 smartctl）…"
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || \
  echo "    （codesign 不可用，跳过签名；本机仍可运行）"

echo ""
echo "✅ 打包完成：$(pwd)/${APP_BUNDLE}"
if [ -n "$SMARTCTL_SYS" ]; then
    echo "   ✔ 已内置 smartctl，开箱即用读取真实 SMART"
else
    echo "   ⚠ SMART 为演示数据模式（安装 smartmontools 后重新打包即可启用）"
fi
echo "   启动方式：open ${APP_BUNDLE}"
