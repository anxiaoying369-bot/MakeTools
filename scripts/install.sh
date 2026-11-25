#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP="${ROOT_DIR}/build/MakeTools.app"
DEST_APP="/Applications/MakeTools.app"
EXT_ID="com.make.MakeTools.MarkdownQuickLook"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

LEGACY_APP="/Applications/MarkdownQuickLook.app"
LEGACY_EXT="${LEGACY_APP}/Contents/PlugIns/MarkdownPreviewExtension.appex"

if [[ ! -d "${BUILD_APP}" ]]; then
    "${ROOT_DIR}/scripts/build.sh"
fi

if [[ -d "${LEGACY_APP}" ]]; then
    echo "==> Cleaning legacy MarkdownQuickLook.app"
    if [[ -d "${LEGACY_EXT}" ]]; then
        pluginkit -r "${LEGACY_EXT}" >/dev/null 2>&1 || true
    fi
    "${LSREGISTER}" -u "${LEGACY_APP}" >/dev/null 2>&1 || true
    rm -rf "${LEGACY_APP}"
fi

echo "==> Installing to ${DEST_APP}"
rm -rf "${DEST_APP}"
cp -R "${BUILD_APP}" "${DEST_APP}"

echo "==> Registering MakeTools and Quick Look extension"
"${LSREGISTER}" -f -R "${DEST_APP}"
pluginkit -a "${DEST_APP}/Contents/PlugIns/MarkdownQuickLook.appex"
pluginkit -e use -i "${EXT_ID}"

echo "==> Resetting Quick Look server cache"
qlmanage -r
qlmanage -r cache

echo ""
echo "安装并注册完成！"
echo "1. 检查扩展状态: pluginkit -m -v -p com.apple.quicklook.preview | grep -i MakeTools"
echo "2. 测试预览效果: qlmanage -p \"${ROOT_DIR}/Samples/demo.md\""
echo "3. 或直接打开 /Applications/MakeTools.app"
