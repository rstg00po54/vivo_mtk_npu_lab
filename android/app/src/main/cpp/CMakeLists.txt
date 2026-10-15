cmake_minimum_required(VERSION 3.22.1)
project(vivo_mtk_npu_probe LANGUAGES C CXX)

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

# Official LiteRT 2.3.0 prebuilt C++ SDK target, not the older Interpreter API.
add_subdirectory("${LITERT_CC_SDK_DIR}" "${CMAKE_BINARY_DIR}/litert_cc_sdk")
include_directories("${LITERT_CC_SDK_DIR}")

add_library(npu_probe SHARED probe_jni.cc)
target_compile_features(npu_probe PRIVATE cxx_std_20)
target_compile_options(npu_probe PRIVATE -Wall -Wextra -Wno-deprecated-declarations)
target_link_libraries(npu_probe PRIVATE litert_cc_api android log)
