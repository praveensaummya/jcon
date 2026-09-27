#!/usr/bin/env bash
#
# tool/build_release.sh — Build JCON release artifacts.
#
# Usage (from the repo root or anywhere):
#   ./tool/build_release.sh                # release APK only
#   ./tool/build_release.sh --appbundle    # additionally build a Play Store .aab
#   ./tool/build_release.sh --skip-analyze # skip `flutter analyze` gate
#
# Output (in dist/):
#   jcon-v<version>-<yyyymmdd>.apk   universal release APK
#   [jcon-v<version>-<yyyymmdd>.aab] with --appbundle
#   SHA256SUMS                       checksums for the artifacts
#
# Requirements: Flutter SDK on PATH (developed with 3.44.x / Dart 3.12),
# Android SDK + JDK 17 for the Android toolchain.
#
set -euo pipefail

# Always operate from the repo root, regardless of the caller's cwd.
cd "$(dirname "$0")/.."

SKIP_ANALYZE=0
BUILD_AAB=0
for arg in "$@"; do
  case "$arg" in
    --skip-analyze) SKIP_ANALYZE=1 ;;
    --appbundle)    BUILD_AAB=1 ;;
    *) echo "Unknown option: $arg (see header of this script)"; exit 1 ;;
  esac
done

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 'flutter' not found on PATH. Install the Flutter SDK first:"
  echo "       https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "==> Flutter toolchain:"
flutter --version

echo "==> Fetching dependencies..."
flutter pub get

if [ "$SKIP_ANALYZE" -eq 0 ]; then
  echo "==> Running static analysis (fails the build on errors)..."
  flutter analyze
fi

echo "==> Building universal release APK..."
flutter build apk --release

# Version string from pubspec.yaml (e.g. "1.0.0+1" -> "1.0.0").
VERSION="$(grep -E '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//;s/+.*//')"
DATE="$(date +%Y%m%d)"
OUT_DIR="dist"
mkdir -p "$OUT_DIR"

APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
APK_DST="${OUT_DIR}/jcon-v${VERSION}-${DATE}.apk"
cp "$APK_SRC" "$APK_DST"
echo "==> APK: $APK_DST"

if [ "$BUILD_AAB" -eq 1 ]; then
  echo "==> Building Play Store app bundle..."
  flutter build appbundle --release
  cp build/app/outputs/bundle/release/app-release.aab \
     "${OUT_DIR}/jcon-v${VERSION}-${DATE}.aab"
fi

echo "==> Generating checksums..."
# *.aab may not exist (only built with --appbundle); fall back to *.apk only.
( cd "$OUT_DIR" \
  && { sha256sum -- *.apk *.aab > SHA256SUMS 2>/dev/null \
       || sha256sum -- *.apk > SHA256SUMS; } \
  && cat SHA256SUMS )

echo ""
echo "==========================================================="
echo " Build finished. Artifacts:"
ls -lh "$OUT_DIR"
echo "==========================================================="
echo " To distribute: attach the APK to a GitHub Release"
echo " (or just push a 'v<version>' tag — CI builds and publishes"
echo "  it automatically, see .github/workflows/release.yml)."
