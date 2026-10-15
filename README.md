# vivo MTK NPU Lab

Dedicated experiments for **vivo X300 Pro / MediaTek MT6993 (Dimensity 9500)**
with the Android NPU, MediaTek Neuron/NeuroPilot and LiteRT.

This repository is **separate from KataGo/BadukaiJ**. It contains no proprietary
model weights. Do not commit personal device logs, model files, or vendor binaries.

## First experiment — C++ LiteRT 2.3.0 on MT6993

The `android/` project is a minimal debug APK:
- **C++20/NDK** drives LiteRT `Environment`, `Options`,
  `CompiledModel::Create`, buffer allocation and detailed stage/error logging.
- Tiny **Java Activity** only loads the JNI .so, passes model paths, and prints
  the C++ result; there is **no Java inference implementation**.
- Same LiteRT **2.3.0** and `litert-npu-runtime-mediatek:2.3.0` Maven
  coordinates as the existing Go Android project.
- **No automatic NPU-to-CPU fallback** by this test runner. A successful
  `CompiledModel::Create` is *not proof that 100% of ops execute on silicon*.
- Test existing 9x9 `10b` and `Human SL b18` TFLite graphs independently to
  isolate a `PrepareTensors`/dynamic-shape compiler failure.

### Prerequisites

Ubuntu host: Android SDK 35, NDK 27.2.12479018, CMake 3.22.1, Java 17,
Python 3, ADB. Phone: vivo X300 Pro; USB/wireless ADB enabled.

1. Clone the repository and prepare matching LiteRT C++ SDK/so binaries:

```bash
git clone https://github.com/rstg00po54/vivo_mtk_npu_lab.git
cd vivo_mtk_npu_lab
bash tools/setup_litert_cpp_sdk.sh
```

The setup script downloads official **v2.3.0** `litert_cc_sdk.zip` and the
same `libLiteRt.so` from `litert-2.3.0.aar` (Google Maven). Third-party
binaries are downloaded locally and ignored by Git.

2. Build the isolated APK from the existing working Gradle 8.5 wrapper,
   or any compatible installed Gradle:

```bash
# If installed Gradle is available:
gradle -p android :app:assembleDebug

# Or reuse an existing wrapper without changing the other project:
../GoEngine-java/gradlew -p "$PWD/android" :app:assembleDebug
```

3. Compare both TFLite models on the vivo (change paths to suit your machine):

```bash
python3 tools/run_probe.py \
  --model 10b=/path/to/katago_10b_9x9.tflite \
  --model human=/path/to/katago_human_9x9.tflite \
  --accelerators NPU
```

You can also use `--accelerators CPU,NPU`, `--serial YOUR_ADB_SERIAL`,
`--skip-install`, or `--mode COMPILE`.

The script installs **com.vivomtknpulab** side-by-side with BadukaiJ, copies
models into the test app's private files directory via `run-as`, and captures
C++ stage markers and relevant MediaTek/Neuron logcat lines. Reports are saved
under `reports/`.

### What PASS/FAIL means

| C++ compilation | Meaning |
| --- | --- |
| 10b NPU PASS, b18 NPU FAIL | Distinguishes b18 graph/compiler from Java/KataGo startup; not yet a specific bad op |
| Both NPU FAIL | First check NPU plugin/library loading and device API version |
| Both NPU PASS | Recheck model hashes, version/options/cache differences with BadukaiJ |
| b18 CPU PASS, NPU FAIL | Strong signal of NPU-specific graph/compiler incompatibility |

**Not yet validated on the user's vivo or by Android Gradle build in this
environment.** Treat this initial commit as a testable starting point, not a
confirmed repair.

## Future experiments

- `operators/`: standalone single-operator/compound-operator compatibility
- `compiler/`: graph bisection and static shape diagnostics
- `benchmark/`: compilation time, buffer allocation, inference timing
- `models/`: *scripts/manifests only*, not weights or large binaries

GitHub Actions also performs an Android NDK build on changes to main and 
keeps the debug APK as a short-lived workflow artifact. Do not infer NPU\nhardware correctness from a CI build.\n\nDocumentation for the C++ SDK:
https://developers.google.com/edge/litert/next/android_cpp_sdk
