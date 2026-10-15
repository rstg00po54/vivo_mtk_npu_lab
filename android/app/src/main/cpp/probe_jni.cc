// Independent MediaTek NPU compile probe. C++20 / Android NDK / LiteRT 2.3.0.
// All model loading, compilation and buffer creation happen in native code.
// No automatic CPU fallback: a result of PASS is compilation success only.

#include <jni.h>
#include <android/log.h>
#include <chrono>
#include <exception>
#include <string>
#include <vector>

#include "litert/cc/litert_compiled_model.h"
#include "litert/cc/litert_environment.h"
#include "litert/cc/litert_options.h"

namespace {

constexpr char kTag[] = "MTK_CPP_PROBE";

std::string GetUtf8(JNIEnv* env, jstring value) {
  if (!value) return {};
  const char* p = env->GetStringUTFChars(value, nullptr);
  if (!p) return {};
  std::string out(p);
  env->ReleaseStringUTFChars(value, p);
  return out;
}

std::string Flatten(std::string s) {
  for (char& c : s) {
    if (c == '\n' || c == '\r' || c == '\t') c = ' ';
  }
  if (s.size() > 1000) s.resize(1000);
  return s;
}

void Emit(const std::string& id, const char* event,
          const std::string& detail) {
  __android_log_print(ANDROID_LOG_INFO, kTag, "id=%s event=%s %s",
                      id.c_str(), event, Flatten(detail).c_str());
}

int64_t ElapsedMs(std::chrono::steady_clock::time_point start) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now() - start).count();
}

std::string Probe(const std::string& id, const std::string& model_path,
                  const std::string& native_lib_dir,
                  const std::string& accelerator, bool create_buffers) {
  using Clock = std::chrono::steady_clock;
  const auto started = Clock::now();
  std::string stage = "ARGUMENTS";

  auto fail = [&](const std::string& detail) {
    const std::string line =
        "stage=" + stage + " detail=" + Flatten(detail) +
        " totalMs=" + std::to_string(ElapsedMs(started));
    Emit(id, "FAIL", line);
    return std::string("FAIL ") + line;
  };
  auto enter = [&](const char* next) {
    stage = next;
    Emit(id, "STAGE", std::string("name=") + stage);
  };

  try {
    if (model_path.empty() || native_lib_dir.empty())
      return fail("Model path or nativeLibraryDir is empty");
    if (accelerator != "NPU" && accelerator != "CPU")
      return fail("Accelerator must be NPU or CPU");

    Emit(id, "START", "backend=LiteRT_CPP_2.3.0 accel=" + accelerator +
                      " model=" + model_path);

    enter("ENVIRONMENT");
    // JIT compiler and dispatch libraries are installed by the MediaTek Maven
    // AAR into the app's nativeLibraryDir. This matches the Java provider's
    // library locations without invoking Java CompiledModel.
    std::vector<litert::Environment::Option> env_options = {
        {litert::Environment::OptionTag::DispatchLibraryDir,
         native_lib_dir.c_str()},
        {litert::Environment::OptionTag::CompilerPluginLibraryDir,
         native_lib_dir.c_str()},
    };
    auto environment = litert::Environment::Create(env_options);
    if (!environment) return fail(environment.Error().Message());

    enter("OPTIONS");
    auto options = litert::Options::Create();
    if (!options) return fail(options.Error().Message());
    const auto hardware = (accelerator == "NPU")
                              ? litert::HwAccelerators::kNpu
                              : litert::HwAccelerators::kCpu;
    auto set_accel = options.Value().SetHardwareAccelerators(hardware);
    if (!set_accel) return fail(set_accel.Error().Message());

    enter("COMPILED_MODEL_CREATE");
    const auto compiling = Clock::now();
    auto compiled = litert::CompiledModel::Create(
        environment.Value(), model_path, options.Value());
    if (!compiled) return fail(compiled.Error().Message());
    const auto compile_ms = ElapsedMs(compiling);
    Emit(id, "COMPILED", "compileMs=" + std::to_string(compile_ms));

    size_t input_count = 0;
    size_t output_count = 0;
    if (create_buffers) {
      enter("INPUT_BUFFERS");
      auto inputs = compiled.Value().CreateInputBuffers();
      if (!inputs) return fail(inputs.Error().Message());
      input_count = inputs.Value().size();

      enter("OUTPUT_BUFFERS");
      auto outputs = compiled.Value().CreateOutputBuffers();
      if (!outputs) return fail(outputs.Error().Message());
      output_count = outputs.Value().size();
      // Owns buffers until scope exit; compiled model/environment still alive.
    }

    const std::string summary =
        "accel=" + accelerator +
        " model=" + model_path +
        " compileMs=" + std::to_string(compile_ms) +
        " inputs=" + std::to_string(input_count) +
        " outputs=" + std::to_string(output_count) +
        " totalMs=" + std::to_string(ElapsedMs(started)) +
        " validation=COMPILE_ONLY_NOT_NPU_OFFLOAD_PROOF";
    Emit(id, "PASS", summary);
    return std::string("PASS ") + summary;
  } catch (const std::exception& ex) {
    return fail(std::string("std_exception: ") + ex.what());
  } catch (...) {
    return fail("unknown native exception");
  }
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_vivomtknpulab_MainActivity_nativeCompile(
    JNIEnv* env, jclass /* clazz */, jstring jrun_id,
    jstring jmodel_path, jstring jnative_lib_dir,
    jstring jaccelerator, jboolean jcreate_buffers) {
  const std::string run_id = GetUtf8(env, jrun_id);
  const std::string model_path = GetUtf8(env, jmodel_path);
  const std::string native_lib_dir = GetUtf8(env, jnative_lib_dir);
  const std::string accelerator = GetUtf8(env, jaccelerator);
  const std::string result = Probe(run_id, model_path, native_lib_dir,
                                   accelerator, jcreate_buffers == JNI_TRUE);
  return env->NewStringUTF(result.c_str());
}
