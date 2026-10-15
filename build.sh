#!/usr/bin/env bash
# Independent Android C++ NPU lab build: no dependencies on GoEngine-java.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Official LiteRT 2.3.0 C++ headers/CMake + matching Android runtime .so.
if [[ "${SKIP_LITERT_SETUP:-0}" != "1" ]]; then
  bash tools/setup_litert_cpp_sdk.sh
fi

# VMware /mnt/hgfs shared folders can report synthetic owners. LiteRT 2.3.0
# downloads Abseil (and other CMake dependencies) into android/app/.cxx.
# Git's protected safe.directory check then blocks tag checkout even though the
# clone succeeded. Scope this exception ONLY to dependency clones under this
# project's CMake build directory, and ONLY for this build invocation.
# Do not write to global gitconfig or disable Git ownership checks everywhere.
if [[ "$(readlink -f "$ROOT" 2>/dev/null || printf '%s' "$ROOT")" == /mnt/hgfs/* ||
      "$ROOT" == /mnt/hgfs/* ]]; then
  cfg_index="${GIT_CONFIG_COUNT:-0}"
  if ! [[ "$cfg_index" =~ ^[0-9]+$ ]]; then
    echo "Invalid existing GIT_CONFIG_COUNT: $cfg_index" >&2
    exit 2
  fi
  export "GIT_CONFIG_KEY_${cfg_index}=safe.directory"
  export "GIT_CONFIG_VALUE_${cfg_index}=$ROOT/android/app/.cxx/*"
  export "GIT_CONFIG_COUNT=$((cfg_index + 1))"
  echo "VMware shared folder detected: scoped Git safe.directory to android/app/.cxx/*"
fi

# Gradle 8.5 is installed automatically into ~/.gradle/wrapper/dists by Wrapper.
bash ./gradlew -p android :app:assembleDebug "$@"

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK not found after build: $APK" >&2
  exit 1
fi
echo "BUILD_OK: $APK"
