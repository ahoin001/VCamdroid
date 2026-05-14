#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build"
XCODEGEN_BIN="/tmp/xcodegen_bin/xcodegen/bin/xcodegen"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip"

if [ -n "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR
elif [ -d "/Users/alexanderhoinville/Downloads/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Users/alexanderhoinville/Downloads/Xcode.app/Contents/Developer"
fi

if ! command -v xcodegen &>/dev/null && [ ! -x "$XCODEGEN_BIN" ]; then
  echo "==> XcodeGen not found, downloading..."
  curl -sL "$XCODEGEN_URL" -o /tmp/xcodegen.zip
  rm -rf /tmp/xcodegen_bin
  unzip -oq /tmp/xcodegen.zip -d /tmp/xcodegen_bin
  chmod +x "$XCODEGEN_BIN"
  rm /tmp/xcodegen.zip
fi

XCODEGEN_CMD="xcodegen"
if ! command -v xcodegen &>/dev/null; then
  XCODEGEN_CMD="$XCODEGEN_BIN"
fi

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"

echo "==> Generating Xcode project..."
"$XCODEGEN_CMD" generate --spec "$PROJECT_DIR/project.yml"

echo "==> Archiving (unsigned)..."
xcodebuild archive \
  -project "$PROJECT_DIR/VCamdroidiOS.xcodeproj" \
  -scheme VCamdroidiOS \
  -configuration Release \
  -archivePath "$BUILD_DIR/VCamdroidiOS.xcarchive" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "==> Packaging IPA..."
mkdir -p "$BUILD_DIR/Payload"
cp -r "$BUILD_DIR/VCamdroidiOS.xcarchive/Products/Applications/VCamdroidiOS.app" "$BUILD_DIR/Payload/"
cd "$BUILD_DIR"
zip -rq VCamdroidiOS.ipa Payload/
rm -rf Payload

IPA_PATH="$BUILD_DIR/VCamdroidiOS.ipa"
echo ""
echo "IPA ready: $IPA_PATH"
echo "Size: $(du -h "$IPA_PATH" | cut -f1)"
