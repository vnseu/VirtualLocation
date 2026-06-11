#!/bin/bash
# ============================================================
#  VirtualLocation 一键构建脚本
# ============================================================
#
#  用法:
#    ./Scripts/build.sh            # 构建所有组件
#    ./Scripts/build.sh dylib      # 仅构建 dylib
#    ./Scripts/build.sh app        # 仅构建 App
#    ./Scripts/build.sh clean      # 清理构建产物
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="${1:-all}"

case "$TARGET" in
    all)
        echo "============================================"
        echo "  VirtualLocation 完整构建"
        echo "============================================"
        echo ""

        # 构建 dylib
        echo ">>> Step 1/2: 构建 Dylib"
        bash "$SCRIPT_DIR/build_dylib.sh" release

        echo ""
        echo ">>> Step 2/2: 构建 App"
        bash "$SCRIPT_DIR/build_app.sh" ipa

        echo ""
        echo "============================================"
        echo "  ✅ 全部构建完成！"
        echo "============================================"
        echo ""
        echo "产物:"
        echo "  output/VirtualLocation.dylib  — 注入目标 App 的 Hook 引擎"
        echo "  output/VirtualLocation.ipa    — TrollStore 配置器 App"
        echo ""
        echo "下一步:"
        echo "  python3 Patcher/patcher.py 目标App.ipa"
        ;;

    dylib)
        bash "$SCRIPT_DIR/build_dylib.sh" release
        ;;

    app)
        bash "$SCRIPT_DIR/build_app.sh" ipa
        ;;

    clean)
        echo "🧹 清理构建产物..."
        rm -rf "$SCRIPT_DIR/../build"
        rm -rf "$SCRIPT_DIR/../output"
        echo "   ✅ 清理完成"
        ;;

    *)
        echo "用法: $0 [all|dylib|app|clean]"
        exit 1
        ;;
esac
