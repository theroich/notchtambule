#!/usr/bin/env bash
#
# Builds Notchtambule.app (a proper LSUIElement bundle) from the Swift package.
#
# Usage: ./Scripts/build-app.sh [debug|release]
#
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swift >/dev/null 2>&1; then
    echo "error: no se encontró el toolchain de Swift." >&2
    exit 1
fi

# DynamicNotchKit uses the SwiftUI @Entry macro. Its macro plugin ships with
# Xcode, not with the standalone Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: se requiere Xcode (no solo Command Line Tools) para compilar DynamicNotchKit." >&2
    echo "       Instala Xcode y ejecuta: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

echo "==> Compilando ($CONFIGURATION)…"
swift build -c "$CONFIGURATION" --product NotchTubeAudio

# User-visible app name (bundle, executable and CFBundleName). The SwiftPM
# product/target stays `NotchTubeAudio`.
APP_NAME="Notchtambule"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"

echo "==> Creando el bundle…"
rm -rf "$APP_DIR"
# Remove the previous bundle name so macOS doesn't list two copies of the app.
rm -rf "$ROOT_DIR/build/NotchTubeAudio.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/NotchTubeAudio" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
if [[ -d "$BIN_DIR/NotchTubeAudio_NotchTubeAudio.bundle" ]]; then
    cp -R "$BIN_DIR/NotchTubeAudio_NotchTubeAudio.bundle" "$APP_DIR/Contents/Resources/"
fi
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Keep CFBundleExecutable in sync with the copied binary name.
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_DIR/Contents/Info.plist" >/dev/null

# Unique build number so macOS sees each bundle as a new build.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP_DIR/Contents/Info.plist" >/dev/null

# Ad-hoc signature: enough to run locally, no developer account required.
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || {
    echo "warning: no se pudo firmar el bundle (la app se puede abrir igualmente)." >&2
}

echo "==> Listo: $APP_DIR"
echo "    Ábrela con: open \"$APP_DIR\""
