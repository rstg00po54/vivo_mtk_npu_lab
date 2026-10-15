#!/usr/bin/env bash
# Independent Android C++ NPU lab build: no dependencies on GoEngine-java.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Official LiteRT 2.3.0 C++ headers/CMake + matching Android runtime .so.
if [[ "${SKIP_LITERT_SETUP:-0}" != "1" ]]; then
  bash tools/setup_litert_cpp_sdk.sh
fi

# Gradle 8.5 is installed automatically into ~/.gradle/wrapper/dists by Wrapper.
bash ./gradlew -p android :app:assembleDebug "$@"

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -s "$APK" ]]; then
  echo "ERROR: APK not found after build: $APK" >&2
  exit 1
fi
echo "BUILD_OK: $APK"
