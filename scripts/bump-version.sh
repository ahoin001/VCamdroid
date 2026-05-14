#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
ANDROID_GRADLE="$REPO_ROOT/android/app/build.gradle.kts"
IOS_PLIST="$REPO_ROOT/ios/VCamdroidiOS/Sources/VCamdroidiOS/Info.plist"
WINDOWS_VCPKG="$REPO_ROOT/windows/vcpkg.json"

BUMP_TYPE="${1:-}"

if [[ -z "$BUMP_TYPE" ]] || [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
  echo "Usage: $0 <patch|minor|major>"
  exit 1
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP_TYPE" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

echo "Bumping version: $CURRENT → $NEW_VERSION"

# --- VERSION file ---
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "  ✓ VERSION"

# --- Android: versionName + versionCode ---
if [[ -f "$ANDROID_GRADLE" ]]; then
  CURRENT_CODE=$(grep 'versionCode' "$ANDROID_GRADLE" | head -1 | grep -o '[0-9]\+')
  NEW_CODE=$((CURRENT_CODE + 1))

  sed -i.bak "s/versionName = \"[^\"]*\"/versionName = \"$NEW_VERSION\"/" "$ANDROID_GRADLE"
  sed -i.bak "s/versionCode = [0-9]*/versionCode = $NEW_CODE/" "$ANDROID_GRADLE"
  rm -f "${ANDROID_GRADLE}.bak"
  echo "  ✓ android/app/build.gradle.kts (versionName=$NEW_VERSION, versionCode=$NEW_CODE)"
fi

# --- iOS: CFBundleShortVersionString + CFBundleVersion ---
if [[ -f "$IOS_PLIST" ]]; then
  # CFBundleShortVersionString: replace the string after it
  sed -i.bak "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>$NEW_VERSION</string>|;}" "$IOS_PLIST"
  # CFBundleVersion: use incremented build number
  CURRENT_BUILD=$(grep -A1 'CFBundleVersion' "$IOS_PLIST" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
  if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    NEW_BUILD=$((CURRENT_BUILD + 1))
  else
    NEW_BUILD=1
  fi
  sed -i.bak "/<key>CFBundleVersion<\/key>/{n;s|<string>[^<]*</string>|<string>$NEW_BUILD</string>|;}" "$IOS_PLIST"
  rm -f "${IOS_PLIST}.bak"
  echo "  ✓ ios/.../Info.plist (version=$NEW_VERSION, build=$NEW_BUILD)"
fi

# --- Windows: vcpkg.json ---
if [[ -f "$WINDOWS_VCPKG" ]]; then
  sed -i.bak "s/\"version-string\": \"[^\"]*\"/\"version-string\": \"$NEW_VERSION\"/" "$WINDOWS_VCPKG"
  rm -f "${WINDOWS_VCPKG}.bak"
  echo "  ✓ windows/vcpkg.json ($NEW_VERSION)"
fi

echo ""
echo "Version bumped to $NEW_VERSION"
