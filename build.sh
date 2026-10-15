#!/usr/bin/env bash
# Independent Android C++ NPU lab build: no dependencies on GoEngine-java.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Official LiteRT 2.3.0 C++ headers/CMake + matching Android runtime .so.
if [[ "${SKIP_LITERT_SETUP:-0}" != "1" ]]; then
  bash tools/setup_litert_cpp_sdk.sh
fi

# A previous release fetched LiteRT/Abseil using git clone into .cxx.
# Archive mode is now selected by CMake, so remove stale CMake state from
# that older method exactly once. Keep downloaded SDK, models and Gradle
# cache untouched. New archive-mode builds do not create this clone script.
CXX_DIR="$ROOT/android/app/.cxx"
if [[ -d "$CXX_DIR" ]] &&
   find "$CXX_DIR" -type f -name 'abseil-cpp-populate-gitclone.cmake' -print -quit |
       grep -q .; then
  echo "Removing old Git-based CMake cache: $CXX_DIR"
  rm -rf -- "$CXX_DIR"
fi

# Gradle 8.5 is installed automatically into ~/.gradle/wrapper/dists by Wrapper.
bash ./gradlew -p android :app:assembleDebug "$@"

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK not found after build: $APK" >&2
  exit 1
fi
echo "BUILD_OK: $APK"
