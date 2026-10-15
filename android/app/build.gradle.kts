plugins {
    id("com.android.application")
}

// LiteRT's CMake SDK unpacks Abseil and FlatBuffers into CMAKE_BINARY_DIR.
// VMware shared folders (/mnt/hgfs) cannot reliably represent some of those
// archive entries. Keep source files in the checked-out repository, but put
// the native CMake/Ninja build tree on the Ubuntu local filesystem.
// Canonical project path ensures separate clones do not share stale caches.
val nativeBuildId = Integer.toHexString(rootProject.projectDir.canonicalPath.hashCode())
val nativeStagingDir = java.io.File(
    System.getProperty("user.home"), ".cache/vivo_mtk_npu_lab/native_${nativeBuildId}"
)

android {
    namespace = "com.vivomtknpulab"
    compileSdk = 35
    // Keep the NDK in sync with the project's CI and vivo toolchain.
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "com.vivomtknpulab"
        minSdk = 31
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20", "-Wno-deprecated-declarations")
                arguments += listOf(
                    "-DLITERT_CC_SDK_DIR=${rootProject.file("../third_party/litert_cc_sdk").absolutePath}"
                )
            }
        }
    }

    buildTypes {
        getByName("release") { isMinifyEnabled = false }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
            buildStagingDirectory = nativeStagingDir
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // SDK's link-time libLiteRt.so and Maven's same-version runtime.
            pickFirsts += setOf("**/libLiteRt.so")
        }
    }
}

dependencies {
    implementation("com.google.ai.edge.litert:litert:2.3.0")
    implementation("com.google.ai.edge.litert:litert-npu-runtime-mediatek:2.3.0")
}
