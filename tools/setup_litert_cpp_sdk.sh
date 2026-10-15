#!/usr/bin/env bash
# Install the matching official prebuilt LiteRT C++ 2.3.0 SDK + runtime.
# Nothing in third_party/ is committed; do NOT mix SDK and libLiteRt versions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/third_party/litert_cc_sdk"
VERSION="2.3.0"
SDK_URL="https://github.com/google-ai-edge/LiteRT/releases/download/v${VERSION}/litert_cc_sdk.zip"
AAR_URL="https://dl.google.com/dl/android/maven2/com/google/ai/edge/litert/litert/${VERSION}/litert-${VERSION}.aar"

command -v curl >/dev/null || { echo "Missing curl" >&2; exit 1; }
command -v unzip >/dev/null || { echo "Missing unzip" >&2; exit 1; }
command -v file >/dev/null || true

if [[ -f "$DEST/CMakeLists.txt" && -s "$DEST/libLiteRt.so" ]]; then
  echo "SDK/runtime already staged: $DEST"
  echo "Delete third_party/litert_cc_sdk to re-download the matching version."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$DEST"

echo "Downloading official LiteRT C++ SDK v$VERSION..."
curl --fail --location --retry 3 --connect-timeout 20 \
     --output "$TMP/sdk.zip" "$SDK_URL"
unzip -q "$TMP/sdk.zip" -d "$TMP/sdk"
if [[ -f "$TMP/sdk/litert_cc_sdk/CMakeLists.txt" ]]; then
  cp -a "$TMP/sdk/litert_cc_sdk/." "$DEST/"
elif [[ -f "$TMP/sdk/CMakeLists.txt" ]]; then
  cp -a "$TMP/sdk/." "$DEST/"
else
  echo "Unexpected LiteRT SDK zip directory structure" >&2
  exit 2
fi

echo "Downloading matching Android runtime AAR v$VERSION..."
curl --fail --location --retry 3 --connect-timeout 20 \
     --output "$TMP/litert.aar" "$AAR_URL"
unzip -p "$TMP/litert.aar" 'jni/arm64-v8a/libLiteRt.so' > "$TMP/libLiteRt.so"
if [[ ! -s "$TMP/libLiteRt.so" ]]; then
  echo "Missing arm64-v8a/libLiteRt.so in official AAR" >&2
  exit 3
fi
cp -f "$TMP/libLiteRt.so" "$DEST/libLiteRt.so"
echo "LiteRT v$VERSION SDK and runtime ready at $DEST"
sha256sum "$DEST/libLiteRt.so" || true
