ROOT_DIR := $(shell pwd)
ARCH := $(shell uname -m)
SDK_PATH := $(shell xcrun --show-sdk-path)
TARGET := $(ARCH)-apple-macos14.0
TEST_BIN := $(ROOT_DIR)/build/MarkdownRendererTests
ISLAND_TEST_BIN := $(ROOT_DIR)/build/DynamicIslandTests
INSTALL_TEST_BIN := $(ROOT_DIR)/build/InstallationTests

.PHONY: build test run dmg package install preview-demo clean

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
		-framework AppKit -framework Foundation -framework UniformTypeIdentifiers -framework IOKit -framework CoreAudio -framework AudioToolbox -framework EventKit \
		Sources/Tools/DynamicIsland/DynamicIslandMetrics.swift \
		Sources/Tools/Calendar/CalendarCountdown.swift \
		Sources/Tools/Calendar/SystemCalendarStore.swift \
		Sources/Tools/Calendar/ChinaHolidayCalendar.swift \
		Sources/Tools/WebBookmarks/WebBookmarkStore.swift \
		Tests/DynamicIslandTests.swift \
		-o $(ISLAND_TEST_BIN)
	@$(ISLAND_TEST_BIN)
	@swiftc -target $(TARGET) -sdk "$(SDK_PATH)" -parse-as-library \
		-framework AppKit -framework Foundation -framework ServiceManagement \
		Sources/Tools/Installation/InstallationSupport.swift \
		Tests/InstallationTests.swift \
		-o $(INSTALL_TEST_BIN)
	@$(INSTALL_TEST_BIN)

run: build
	@open build/MakeTools.app

dmg: build
	@chmod +x scripts/package-dmg.sh scripts/render-dmg-bg.swift
	@./scripts/package-dmg.sh

package: dmg

install: build
	@./scripts/install.sh

preview-demo:
	@qlmanage -p Samples/demo.md

clean:
	@rm -rf build
