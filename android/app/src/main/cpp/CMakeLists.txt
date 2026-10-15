cmake_minimum_required(VERSION 3.22.1)
project(vivo_mtk_npu_probe LANGUAGES C CXX)

# Catch old NDK toolchains before building hundreds of LiteRT/Abseil objects.
if(ANDROID AND DEFINED ANDROID_NDK)
  if(NOT "${ANDROID_NDK}" MATCHES "/ndk/27[.]2[.]12479018/?$")
    message(FATAL_ERROR
      "LiteRT C++20 needs NDK 27.2.12479018, but CMake received "
      "ANDROID_NDK=${ANDROID_NDK}. Use ./build.sh to select NDK 27.2 "
      "and invalidate old android/app/.cxx native cache.")
  endif()
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT DEFINED LITERT_CC_SDK_DIR OR
   NOT EXISTS "${LITERT_CC_SDK_DIR}/CMakeLists.txt" OR
   NOT EXISTS "${LITERT_CC_SDK_DIR}/libLiteRt.so")
  message(FATAL_ERROR
    "Matching LiteRT C++ 2.3.0 SDK/so missing. Run bash tools/setup_litert_cpp_sdk.sh "
    "from the repository root before Gradle. Expected ${LITERT_CC_SDK_DIR}")
endif()

# LiteRT 2.3.0 uses OverridableFetchContent to fetch Abseil and other
# dependencies. Its own CMake file hardcodes source directories below
# CMAKE_BINARY_DIR. On VMware /mnt/hgfs, Git reports "dubious ownership"
# when a new dependency clone checks out its tag. Ask the official SDK
# helper to fetch *archives* instead of running git clone/checkout.
# Supported by its OverridableFetchContent.cmake implementation.
set(OVERRIDABLE_FETCH_CONTENT_GIT_REPOSITORY_AND_TAG_TO_URL ON
    CACHE BOOL "Download LiteRT dependency source archives instead of Git clones" FORCE)
message(STATUS "LiteRT dependencies: GitHub source archives (no git checkout)")

# Official LiteRT 2.3.0 prebuilt C++ SDK target, not the older Interpreter API.
add_subdirectory("${LITERT_CC_SDK_DIR}" "${CMAKE_BINARY_DIR}/litert_cc_sdk")
include_directories("${LITERT_CC_SDK_DIR}")

add_library(npu_probe SHARED probe_jni.cc)
target_compile_features(npu_probe PRIVATE cxx_std_20)
target_compile_options(npu_probe PRIVATE -Wall -Wextra -Wno-deprecated-declarations)
target_link_libraries(npu_probe PRIVATE litert_cc_api android log)
