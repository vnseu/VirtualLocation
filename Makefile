# ============================================================
#  VirtualLocation Makefile
# ============================================================

.PHONY: all dylib app clean help inject

all: dylib app

dylib:
	bash Scripts/build_dylib.sh release

app:
	bash Scripts/build_app.sh ipa

clean:
	rm -rf build/ output/

# 注入目标 IPA
# 用法: make inject IPA=WeChat.ipa
inject:
	@if [ -z "$(IPA)" ]; then \
		echo "用法: make inject IPA=目标App.ipa [OUT=输出.ipa]"; \
		exit 1; \
	fi
	python3 Patcher/patcher.py $(IPA) $(if $(OUT),-o $(OUT))

help:
	@echo "VirtualLocation — TrollStore 虚拟定位工具"
	@echo ""
	@echo "make all         构建所有 (dylib + app)"
	@echo "make dylib       仅构建 VirtualLocation.dylib"
	@echo "make app         仅构建 VirtualLocation.ipa"
	@echo "make clean       清理构建产物"
	@echo "make inject IPA=微信.ipa    注入虚拟定位 dylib"
	@echo "make inject IPA=微信.ipa OUT=out.ipa  指定输出"
