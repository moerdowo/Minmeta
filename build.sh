#!/usr/bin/env bash
# Build Minmeta as a macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_NAME="Minmeta"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Build did not produce ${BIN_PATH}" >&2
  exit 1
fi

echo "==> bundling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp App/Info.plist "${APP_DIR}/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper / TCC dialogs work nicely on first run.
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "==> done: ${APP_DIR}"
echo "    open ${APP_DIR}"
