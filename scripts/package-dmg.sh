#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_NAME="MakeTools"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
ARCH="$(uname -m)"

if [[ ! -d "${APP_BUNDLE}" ]]; then
    "${ROOT_DIR}/scripts/build.sh"
fi

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${APP_BUNDLE}/Contents/Info.plist")"
VOLUME_NAME="${APP_NAME}"
DMG_NAME="${APP_NAME}-v${VERSION}-macos-${ARCH}.dmg"
DMG_PATH="${1:-${BUILD_DIR}/${DMG_NAME}}"

STAGING_DIR="$(mktemp -d "${BUILD_DIR}/dmg-staging.XXXXXX")"
RW_DMG="${STAGING_DIR}/${APP_NAME}-rw.dmg"
DEVICE=""
MOUNT_DIR=""

cleanup() {
    if [[ -n "${DEVICE}" ]]; then
        hdiutil detach "${DEVICE}" -quiet >/dev/null 2>&1 || hdiutil detach "${DEVICE}" -force -quiet >/dev/null 2>&1 || true
    elif [[ -n "${MOUNT_DIR}" && -d "${MOUNT_DIR}" ]]; then
        hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || hdiutil detach "${MOUNT_DIR}" -force -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

echo "==> Staging DMG contents for ${APP_NAME} v${VERSION} (${ARCH})"
mkdir -p "${STAGING_DIR}/root/.background"
ditto "${APP_BUNDLE}" "${STAGING_DIR}/root/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/root/Applications"

if [[ -f "${ROOT_DIR}/Assets/MakeTools.icns" ]]; then
    cp "${ROOT_DIR}/Assets/MakeTools.icns" "${STAGING_DIR}/root/.VolumeIcon.icns"
fi

echo "==> Rendering Retina installer background"
swift "${ROOT_DIR}/scripts/render-dmg-bg.swift" \
    "${STAGING_DIR}/root/.background/installer-bg.png" \
    "v${VERSION}"

# Compute disk image size with generous headroom for HFS+ metadata and Finder .DS_Store
APP_KB="$(du -sk "${STAGING_DIR}/root" | awk '{print $1}')"
SIZE_MB="$(( (APP_KB / 1024) + 32 ))"

echo "==> Creating read-write disk image (${SIZE_MB} MB)"
hdiutil create \
    -srcfolder "${STAGING_DIR}/root" \
    -volname "${VOLUME_NAME}" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${SIZE_MB}m" \
    "${RW_DMG}" >/dev/null

echo "==> Mounting read-write disk image for Finder layout"
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
DEVICE="$(echo "${ATTACH_OUT}" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_DIR="$(echo "${ATTACH_OUT}" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"

if [[ -z "${MOUNT_DIR}" || ! -d "${MOUNT_DIR}" ]]; then
    echo "Failed to determine mounted DMG path." >&2
    exit 1
fi

if command -v SetFile >/dev/null 2>&1; then
    if [[ -f "${MOUNT_DIR}/.VolumeIcon.icns" ]]; then
        SetFile -a C "${MOUNT_DIR}" || true
        SetFile -a V "${MOUNT_DIR}/.VolumeIcon.icns" || true
    fi
    SetFile -a V "${MOUNT_DIR}/.background" || true
fi

if [[ "${MAKETOOLS_SKIP_FINDER_LAYOUT:-0}" != "1" ]] && pgrep -x Finder >/dev/null 2>&1 && [[ "$(launchctl managername 2>/dev/null || true)" == "Aqua" ]]; then
    echo "==> Applying Finder drag-to-Applications window layout"
    osascript - "${MOUNT_DIR}" "${APP_NAME}" <<'APPLESCRIPT' || echo "Warning: Finder layout styling skipped (non-interactive session)."
on run argv
    set mountPath to item 1 of argv
    set appName to item 2 of argv
    set mountFolder to (POSIX file mountPath) as alias
    set bgFile to (POSIX file (mountPath & "/.background/installer-bg.png")) as alias
    tell application "Finder"
        open mountFolder
        set win to container window of mountFolder
        set current view of win to icon view
        set toolbar visible of win to false
        set statusbar visible of win to false
        set the bounds of win to {180, 140, 840, 588}
        set viewOptions to the icon view options of win
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 13
        set background picture of viewOptions to bgFile
        set position of item (appName & ".app") of win to {178, 224}
        set position of item "Applications" of win to {482, 224}
        close win
        open mountFolder
        set win to container window of mountFolder
        update mountFolder without registering applications
        delay 1
        close win
    end tell
end run
APPLESCRIPT
else
    echo "==> Skipping Finder AppleScript layout (no active Aqua Finder session)"
fi

sync
sleep 1

echo "==> Detaching temporary disk image"
hdiutil detach "${DEVICE:-${MOUNT_DIR}}" -quiet || {
    sleep 2
    hdiutil detach "${DEVICE:-${MOUNT_DIR}}" -force -quiet
}
DEVICE=""
MOUNT_DIR=""

echo "==> Compressing final DMG: ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil convert "${RW_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_PATH}" >/dev/null

echo "==> Verifying DMG integrity"
hdiutil verify "${DMG_PATH}" >/dev/null

echo "==> DMG ready: ${DMG_PATH}"
