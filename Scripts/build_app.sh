#!/bin/bash
# ============================================================
#  VirtualLocation App 构建脚本
#  在 macOS 上运行，需要 Xcode
# ============================================================
#
#  用法:
#    ./Scripts/build_app.sh            # 构建 App (Release)
#    ./Scripts/build_app.sh debug      # 构建 Debug 版本
#    ./Scripts/build_app.sh ipa        # 构建并打包 IPA
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_DIR/App"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/output"

MODE="${1:-release}"
CREATE_IPA=false
if [ "$MODE" = "ipa" ]; then
    MODE="release"
    CREATE_IPA=true
fi

echo "============================================"
echo "  VirtualLocation App Builder"
echo "  Mode: $MODE"
echo "============================================"

# 清理
rm -rf "$BUILD_DIR/App"
mkdir -p "$BUILD_DIR/App"
mkdir -p "$OUTPUT_DIR"

# 检查 Xcode
if ! xcode-select -p &>/dev/null; then
    echo "❌ 请安装 Xcode 或 Command Line Tools"
    exit 1
fi

# SDK 路径
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK_PATH"

# Swift 源文件
SWIFT_FILES=(
    "$APP_DIR/VirtualLocationApp.swift"
    "$APP_DIR/ContentView.swift"
    "$APP_DIR/MapPickerView.swift"
    "$APP_DIR/LocationViewModel.swift"
    "$APP_DIR/LocationPresetManager.swift"
    "$APP_DIR/PresetListView.swift"
    "$APP_DIR/SettingsView.swift"
    "$APP_DIR/ConfigWriter.swift"
)

# 编译参数
if [ "$MODE" = "release" ]; then
    SWIFT_FLAGS="-O -whole-module-optimization"
else
    SWIFT_FLAGS="-Onone -g"
fi

echo ""
echo "📦 编译 Swift 源文件..."

# Swift 编译为单一可执行文件
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "$SDK_PATH" \
    $SWIFT_FLAGS \
    -framework SwiftUI \
    -framework UIKit \
    -framework Foundation \
    -framework MapKit \
    -framework CoreLocation \
    -framework Combine \
    -parse-as-library \
    -module-name VirtualLocation \
    "${SWIFT_FILES[@]}" \
    -o "$BUILD_DIR/App/VirtualLocation"

echo "   ✅ 编译完成"

# 创建 .app bundle 结构
APP_BUNDLE="$BUILD_DIR/App/VirtualLocation.app"
mkdir -p "$APP_BUNDLE"

# 移动可执行文件
mv "$BUILD_DIR/App/VirtualLocation" "$APP_BUNDLE/"

# 复制 Info.plist
cp "$APP_DIR/Info.plist" "$APP_BUNDLE/"

# 复制 entitlements
cp "$APP_DIR/entitlements.plist" "$APP_BUNDLE/"

# 创建 PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/PkgInfo"

# 签名
echo ""
echo "✍️  签名..."
if command -v ldid &> /dev/null; then
    ldid -S"$APP_BUNDLE/entitlements.plist" "$APP_BUNDLE/VirtualLocation"
    echo "   ✅ ldid 签名完成"
else
    echo "   ⚠️ ldid 未安装，跳过签名"
fi

# 创建 IPA
if [ "$CREATE_IPA" = true ]; then
    echo ""
    echo "📦 打包 IPA..."

    IPA_BUILD="$BUILD_DIR/ipa"
    rm -rf "$IPA_BUILD"
    mkdir -p "$IPA_BUILD/Payload"
    cp -R "$APP_BUNDLE" "$IPA_BUILD/Payload/"

    IPA_PATH="$OUTPUT_DIR/VirtualLocation.ipa"
    cd "$IPA_BUILD"
    zip -qr "$IPA_PATH" Payload/
    cd "$PROJECT_DIR"

    echo "   ✅ IPA: $IPA_PATH"
    ls -lh "$IPA_PATH"
    rm -rf "$IPA_BUILD"
fi

echo ""
echo "============================================"
echo "  ✅ App 构建完成！"
echo "============================================"
echo ""
echo "输出: $APP_BUNDLE"
echo ""
echo "安装方式:"
echo "  1. 用 TrollStore 安装 $OUTPUT_DIR/VirtualLocation.ipa"
echo "  2. 打开 App，在地图上选择目标位置"
echo "  3. 点击「激活虚拟定位」"
echo "  4. 打开已注入 dylib 的目标 App → 看到假定位"
