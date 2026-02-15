#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PRODUCT_NAME="VoiceSearchCLI"
INFO_PLIST="${ROOT_DIR}/AppResources/CLIInfo.plist"
APP_BUNDLE="${ROOT_DIR}/.build/${PRODUCT_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"

if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "error: missing Info.plist at ${INFO_PLIST}" >&2
  exit 1
fi

swift build --product "${PRODUCT_NAME}" -c debug --package-path "${ROOT_DIR}" >/dev/null

BIN_DIR="$(swift build --show-bin-path --package-path "${ROOT_DIR}")"
BIN_PATH="${BIN_DIR}/${PRODUCT_NAME}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_MACOS}"
cp "${BIN_PATH}" "${APP_MACOS}/${PRODUCT_NAME}"
cp "${INFO_PLIST}" "${APP_CONTENTS}/Info.plist"
chmod +x "${APP_MACOS}/${PRODUCT_NAME}"

# Ad-hoc sign to avoid launch issues on some systems.
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

"${APP_MACOS}/${PRODUCT_NAME}" "$@"
