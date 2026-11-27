#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="MakeTools"
EXT_NAME="MarkdownQuickLook"

APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
EXT_BUNDLE="${APP_BUNDLE}/Contents/PlugIns/${EXT_NAME}.appex"

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"
SDK_PATH="$(xcrun --show-sdk-path)"

echo "==> Cleaning previous build at ${BUILD_DIR}"
rm -rf "${APP_BUNDLE}"

mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
mkdir -p "${EXT_BUNDLE}/Contents/MacOS"

echo "==> Building ${EXT_NAME}.appex (${TARGET})"
swiftc \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    -module-name "${EXT_NAME}" \
    -parse-as-library \
    -application-extension \
    -O \
    -framework AppKit \
    -framework Foundation \
    -framework QuickLookUI \
    -framework UniformTypeIdentifiers \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "${ROOT_DIR}/Sources/Core/ClipboardHelper.swift" \
    "${ROOT_DIR}/Sources/Core/ToolAppearance.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/ThemeCSS.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/MarkdownRenderer.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/NativeMarkdownView.swift" \
    "${ROOT_DIR}/Sources/Extensions/MarkdownQuickLook/PreviewViewController.swift" \
    -o "${EXT_BUNDLE}/Contents/MacOS/${EXT_NAME}"

cp "${ROOT_DIR}/Sources/Extensions/MarkdownQuickLook/Info.plist" "${EXT_BUNDLE}/Contents/Info.plist"
printf 'XPC!????' > "${EXT_BUNDLE}/Contents/PkgInfo"

echo "==> Building ${APP_NAME}.app (${TARGET})"
swiftc \
    -target "${TARGET}" \
    -sdk "${SDK_PATH}" \
    -module-name "${APP_NAME}" \
    -O \
    -framework AppKit \
    -framework WebKit \
    -framework Foundation \
    -framework UniformTypeIdentifiers \
    -framework IOKit \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework ImageIO \
    -framework Security \
    -framework ServiceManagement \
    -framework QuickLookUI \
    -framework QuickLookThumbnailing \
    "${ROOT_DIR}/Sources/Core/ClipboardHelper.swift" \
    "${ROOT_DIR}/Sources/Core/ToolAppearance.swift" \
    "${ROOT_DIR}/Sources/Core/WebClipboardBridge.swift" \
    "${ROOT_DIR}/Sources/Core/ToolModule.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/ThemeCSS.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/MarkdownRenderer.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/NativeMarkdownView.swift" \
    "${ROOT_DIR}/Sources/Tools/MarkdownPreview/MarkdownToolViewController.swift" \
    "${ROOT_DIR}/Sources/Tools/DynamicIsland/DynamicIslandMetrics.swift" \
    "${ROOT_DIR}/Sources/Tools/DynamicIsland/DynamicIslandManager.swift" \
    "${ROOT_DIR}/Sources/Tools/DynamicIsland/DynamicIslandWindowController.swift" \
    "${ROOT_DIR}/Sources/Tools/DynamicIsland/DynamicIslandViewController.swift" \
    "${ROOT_DIR}/Sources/Tools/PasswordBook/PasswordBookStore.swift" \
    "${ROOT_DIR}/Sources/Tools/PasswordBook/PasswordBookWindowController.swift" \
    "${ROOT_DIR}/Sources/Tools/Calendar/CalendarCountdown.swift" \
    "${ROOT_DIR}/Sources/Tools/Calendar/CalendarMonthGrid.swift" \
    "${ROOT_DIR}/Sources/Tools/Calendar/ChinaHolidayCalendar.swift" \
    "${ROOT_DIR}/Sources/Tools/Calendar/CalendarCountdownWindowController.swift" \
    "${ROOT_DIR}/Sources/Tools/WebBookmarks/WebBookmarkStore.swift" \
    "${ROOT_DIR}/Sources/Tools/WebBookmarks/WebBookmarksWindowController.swift" \
    "${ROOT_DIR}/Sources/Tools/ExtensionsOverview/ExtensionsOverviewViewController.swift" \
    "${ROOT_DIR}/Sources/Tools/Installation/InstallationSupport.swift" \
    "${ROOT_DIR}/Sources/Tools/Installation/InstallationViewController.swift" \
    "${ROOT_DIR}/Sources/App/MainWindowController.swift" \
    "${ROOT_DIR}/Sources/App/AppDelegate.swift" \
    "${ROOT_DIR}/Sources/App/main.swift" \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${ROOT_DIR}/Sources/App/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${ROOT_DIR}/Samples/demo.md" "${APP_BUNDLE}/Contents/Resources/demo.md"
cp "${ROOT_DIR}/Assets/MakeTools.icns" "${APP_BUNDLE}/Contents/Resources/"
printf 'APPL????' > "${APP_BUNDLE}/Contents/PkgInfo"

echo "==> Ad-hoc code signing bundle"
codesign --force --sign - --timestamp=none \
    --entitlements "${ROOT_DIR}/Sources/Extensions/MarkdownQuickLook/Extension.entitlements" \
    "${EXT_BUNDLE}"

codesign --force --sign - --timestamp=none \
    --entitlements "${ROOT_DIR}/Sources/App/App.entitlements" \
    "${APP_BUNDLE}"

echo "==> Verifying bundle signature"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Build complete: ${APP_BUNDLE}"
