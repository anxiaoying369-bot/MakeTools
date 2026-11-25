ROOT_DIR := $(shell pwd)
ARCH := $(shell uname -m)
SDK_PATH := $(shell xcrun --show-sdk-path)
TARGET := $(ARCH)-apple-macos14.0
TEST_BIN := $(ROOT_DIR)/build/MarkdownRendererTests
ISLAND_TEST_BIN := $(ROOT_DIR)/build/DynamicIslandTests

.PHONY: build test run package install preview-demo clean

build:
	@chmod +x scripts/build.sh scripts/install.sh
	@./scripts/build.sh

test:
	@mkdir -p build
	@swiftc -target $(TARGET) -sdk "$(SDK_PATH)" -parse-as-library \
		Sources/Tools/MarkdownPreview/ThemeCSS.swift \
		Sources/Tools/MarkdownPreview/MarkdownRenderer.swift \
		Tests/MarkdownRendererTests.swift \
		-o $(TEST_BIN)
	@$(TEST_BIN)
	@swiftc -target $(TARGET) -sdk "$(SDK_PATH)" -parse-as-library \
		-framework AppKit -framework Foundation -framework UniformTypeIdentifiers -framework IOKit -framework CoreAudio -framework AudioToolbox \
		Sources/Tools/DynamicIsland/DynamicIslandMetrics.swift \
		Tests/DynamicIslandTests.swift \
		-o $(ISLAND_TEST_BIN)
	@$(ISLAND_TEST_BIN)

run: build
	@open build/MakeTools.app

package: build
	@set -eu; \
		version=$$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$(ROOT_DIR)/build/MakeTools.app/Contents/Info.plist"); \
		archive="MakeTools-v$$version-macos-$(ARCH).zip"; \
		staging=$$(/usr/bin/mktemp -d "$(ROOT_DIR)/build/package.XXXXXX"); \
		trap 'rm -rf "$$staging"' EXIT; \
		/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$(ROOT_DIR)/build/MakeTools.app" "$$staging/$$archive"; \
		mv -f "$$staging/$$archive" "$(ROOT_DIR)/build/$$archive"; \
		printf '==> Package: %s\n' "$(ROOT_DIR)/build/$$archive"

install: build
	@./scripts/install.sh

preview-demo:
	@qlmanage -p Samples/demo.md

clean:
	@rm -rf build
