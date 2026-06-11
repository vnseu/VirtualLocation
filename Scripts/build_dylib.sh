#!/bin/bash
# ============================================================
#  VirtualLocation Dylib 构建脚本
#  在 macOS 上运行，需要 Xcode Command Line Tools
# ============================================================
#
#  用法:
#    ./Scripts/build_dylib.sh            # 构建 arm64 dylib
#    ./Scripts/build_dylib.sh debug      # 构建 Debug 版本
#    ./Scripts/build_dylib.sh release    # 构建 Release 版本（默认）
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DYLIB_DIR="$PROJECT_DIR/Dylib"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/output"

CONFIG="${1:-release}"
if [ "$CONFIG" = "release" ]; then
    OPT_FLAGS="-Os -flto"
    DEBUG_FLAG=""
else
    OPT_FLAGS="-O0 -g"
    DEBUG_FLAG="-DDEBUG=1"
fi

echo "============================================"
echo "  VirtualLocation Dylib Builder"
echo "  Config: $CONFIG"
echo "============================================"

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# SDK 检测
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [ -z "$SDK_PATH" ]; then
    echo "❌ 未找到 iPhoneOS SDK，请安装 Xcode"
    exit 1
fi
echo "SDK: $SDK_PATH"

TARGET="arm64-apple-ios14.0"
MIN_VER="-miphoneos-version-min=14.0"

# 编译源文件
echo ""
echo "📦 编译源文件..."

SOURCES=(
    "$DYLIB_DIR/VirtualLocationLoader.m"
    "$DYLIB_DIR/HookLocation.m"
    "$DYLIB_DIR/ConfigReader.m"
    "$DYLIB_DIR/fishhook.c"
)

OBJ_FILES=()
for src in "${SOURCES[@]}"; do
    base=$(basename "$src")
    obj="$BUILD_DIR/${base%.*}.o"
    echo "  → $base"

    if [[ "$src" == *.c ]]; then
        xcrun -sdk iphoneos clang \
            -arch arm64 \
            -target "$TARGET" \
            $MIN_VER \
            $OPT_FLAGS $DEBUG_FLAG \
            -isysroot "$SDK_PATH" \
            -fobjc-arc \
            -fvisibility=hidden \
            -c "$src" \
            -o "$obj"
    else
        xcrun -sdk iphoneos clang \
            -arch arm64 \
            -target "$TARGET" \
            $MIN_VER \
            $OPT_FLAGS $DEBUG_FLAG \
            -isysroot "$SDK_PATH" \
            -fobjc-arc \
            -fvisibility=hidden \
            -I"$DYLIB_DIR" \
            -c "$src" \
            -o "$obj"
    fi
    OBJ_FILES+=("$obj")
done

# 链接 dylib
echo ""
echo "🔗 链接 dylib..."

xcrun -sdk iphoneos clang \
    -arch arm64 \
    -target "$TARGET" \
    $MIN_VER \
    -isysroot "$SDK_PATH" \
    -dynamiclib \
    -install_name "@rpath/VirtualLocation.dylib" \
    -current_version 1.0.0 \
    -compatibility_version 1.0.0 \
    -Xlinker -dead_strip \
    -Xlinker -S \
    -fobjc-arc \
    -framework Foundation \
    -framework CoreLocation \
    -framework UIKit \
    "${OBJ_FILES[@]}" \
    -o "$BUILD_DIR/VirtualLocation.dylib"

# 签名（使用 ldid，TrollStore 兼容）
echo ""
echo "✍️  签名..."

if command -v ldid &> /dev/null; then
    ldid -S "$BUILD_DIR/VirtualLocation.dylib"
    echo "  ✅ ldid 签名完成"
else
    echo "  ⚠️ ldid 未安装，跳过签名"
    echo "  安装: brew install ldid"
fi

# 复制到输出目录
cp "$BUILD_DIR/VirtualLocation.dylib" "$OUTPUT_DIR/"

# 显示信息
echo ""
echo "============================================"
echo "  ✅ 构建完成！"
echo "============================================"
echo ""
echo "输出: $OUTPUT_DIR/VirtualLocation.dylib"
echo ""
ls -lh "$OUTPUT_DIR/VirtualLocation.dylib"

# 检查依赖
echo ""
echo "🔍 动态库依赖:"
xcrun vtool -arch arm64 -show "$OUTPUT_DIR/VirtualLocation.dylib" 2>/dev/null || true

# 检查导出符号
echo ""
echo "📋 导出符号 (前20个):"
nm -gU "$OUTPUT_DIR/VirtualLocation.dylib" 2>/dev/null | head -20 || true

echo ""
echo "完成！下一步:"
echo "  1. 构建 App: ./Scripts/build_app.sh"
echo "  2. 注入目标 IPA: python3 Patcher/patcher.py"
