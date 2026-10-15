#!/usr/bin/env bash
# Build standalone vivo MTK NPU LiteRT 2.3.0 / C++20 APK.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

NDK_VERSION="27.2.12479018"
LOCAL_PROPERTIES="$ROOT/android/local.properties"
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_DIR" && -f "$LOCAL_PROPERTIES" ]]; then
  SDK_DIR="$(sed -n 's/^sdk\.dir=//p' "$LOCAL_PROPERTIES" | head -n 1)"
fi
SDK_DIR="${SDK_DIR:-$HOME/Android/Sdk}"
SDK_DIR="${SDK_DIR%/}"

if [[ ! -d "$SDK_DIR" ]]; then
  echo "ERROR: Android SDK is missing: $SDK_DIR" >&2
  echo "Set ANDROID_HOME to your Android SDK folder and retry." >&2
  exit 2
fi

export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
REQUIRED_NDK="$SDK_DIR/ndk/$NDK_VERSION"
NDK_CLANG="$REQUIRED_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
NDK_RANGES="$REQUIRED_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/c++/v1/ranges"

if [[ ! -x "$NDK_CLANG" || ! -f "$NDK_RANGES" ]]; then
  echo "NDK $NDK_VERSION (C++20 <ranges>) is missing under $SDK_DIR."
  SDKMANAGER=""
  for executable in "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" \
                    "$SDK_DIR"/cmdline-tools/*/bin/sdkmanager \
                    "$SDK_DIR/tools/bin/sdkmanager"; do
    if [[ -x "$executable" ]]; then SDKMANAGER="$executable"; break; fi
  done
  if [[ -z "$SDKMANAGER" ]] && command -v sdkmanager >/dev/null 2>&1; then
    SDKMANAGER="$(command -v sdkmanager)"
  fi
  if [[ -z "$SDKMANAGER" ]]; then
    echo "ERROR: No sdkmanager found. Install NDK (Side by side) $NDK_VERSION" >&2
    echo "Expected path: $REQUIRED_NDK" >&2
    exit 2
  fi
  echo "Installing Android NDK $NDK_VERSION with sdkmanager..."
  "$SDKMANAGER" --sdk_root="$SDK_DIR" "ndk;$NDK_VERSION" || {
    echo "ERROR: NDK installation failed; check SDK licenses or network." >&2
    exit 2
  }
fi

if [[ ! -x "$NDK_CLANG" || ! -f "$NDK_RANGES" ]]; then
  echo "ERROR: NDK $NDK_VERSION unavailable or lacks the C++20 <ranges> header." >&2
  exit 2
fi
echo "Selected NDK: $REQUIRED_NDK"
export ANDROID_NDK_HOME="$REQUIRED_NDK"
export ANDROID_NDK_ROOT="$REQUIRED_NDK"

# Remove only a stale, deprecated ndk.dir from this project's local.properties.
# Back it up under ignored outputs, preserving unrelated SDK settings.
if [[ -f "$LOCAL_PROPERTIES" ]] &&
   grep -Eq '^[[:space:]]*ndk[.]dir[[:space:]]*=' "$LOCAL_PROPERTIES"; then
  BACKUP_DIR="$ROOT/android/app/build/config_backups"
  mkdir -p "$BACKUP_DIR"
  cp "$LOCAL_PROPERTIES" "$BACKUP_DIR/local.properties.before_ndk_fix"
  TMP_PROPERTIES="$(mktemp)"
  grep -Ev '^[[:space:]]*ndk[.]dir[[:space:]]*=' "$LOCAL_PROPERTIES" > "$TMP_PROPERTIES" || true
  cat "$TMP_PROPERTIES" > "$LOCAL_PROPERTIES"
  rm -f "$TMP_PROPERTIES"
  echo "Removed deprecated ndk.dir (backup: $BACKUP_DIR/local.properties.before_ndk_fix)"
fi

if [[ "${SKIP_LITERT_SETUP:-0}" != "1" ]]; then
  bash tools/setup_litert_cpp_sdk.sh
fi

# CMake/Ninja temporary sources and downloaded dependencies now live under
# ~/.cache/vivo_mtk_npu_lab rather than /mnt/hgfs/android/app/.cxx.
# The old .cxx folder is unused; do not delete it automatically.
STAGING_PARENT="$HOME/.cache/vivo_mtk_npu_lab"
mkdir -p "$STAGING_PARENT"
if [[ "$(readlink -f "$STAGING_PARENT")" == /mnt/hgfs/* ]]; then
  echo "ERROR: The native build staging area must be on Ubuntu local storage: $STAGING_PARENT" >&2
  exit 2
fi
echo "Native CMake staging: $STAGING_PARENT (separate directory per checkout)"
echo "Building independent NPU C++ Android app with NDK $NDK_VERSION..."
bash ./gradlew --no-daemon -p android :app:assembleDebug "$@"

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK not found after build: $APK" >&2
  exit 1
fi
echo "BUILD_OK: $APK"
