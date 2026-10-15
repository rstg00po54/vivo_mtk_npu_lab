package com.vivomtknpulab;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

import java.io.File;
import java.util.Locale;

/**
 * Only the Android lifecycle/ADB entry point is Java.
 * C++ performs model loading, LiteRT compilation and buffer allocation.
 */
public final class MainActivity extends Activity {
    private static final String TAG = "MTK_CPP_PROBE";
    private TextView result;

    private static native String nativeCompile(
            String runId, String modelPath, String nativeLibraryDir,
            String accelerator, boolean createBuffers);

    @Override
    public void onCreate(Bundle bundle) {
        super.onCreate(bundle);
        result = new TextView(this);
        result.setTextSize(16);
        result.setPadding(24, 24, 24, 24);
        result.setText("Vivo MediaTek NPU Lab - native C++ LiteRT 2.3.0\n"
                + "Run tests using tools/run_probe.py on a host computer.");
        setContentView(result);

        final String model = getIntent().getStringExtra("model");
        if (model == null) return;

        String id = getIntent().getStringExtra("run_id");
        if (id == null || !id.matches("[A-Za-z0-9_-]{1,64}")) id = "invalid_id";
        final String runId = id;
        String mode = getIntent().getStringExtra("mode");
        if (mode == null) mode = "BUFFERS";
        final boolean buffers = !"COMPILE".equalsIgnoreCase(mode);
        String requested = getIntent().getStringExtra("accelerator");
        final String accelerator = requested == null
                ? "NPU" : requested.toUpperCase(Locale.ROOT);

        new Thread(() -> {
            try {
                if (!model.matches("[A-Za-z0-9_.-]{1,100}\\.tflite")
                        || model.contains("..")) {
                    emitFailure(runId, "ARGUMENTS", "Invalid model filename");
                    return;
                }
                File file = new File(new File(getFilesDir(), "models"), model);
                if (!file.isFile() || file.length() < 8) {
                    emitFailure(runId, "MODEL_IO", "Model missing or empty: " + file);
                    return;
                }
                System.loadLibrary("npu_probe");
                final String answer = nativeCompile(runId, file.getAbsolutePath(),
                        getApplicationInfo().nativeLibraryDir, accelerator, buffers);
                runOnUiThread(() -> result.setText(answer));
            } catch (Throwable ex) {
                emitFailure(runId, "NATIVE_LIBRARY_OR_THREAD",
                        ex.getClass().getSimpleName() + ": " + ex.getMessage());
                Log.e(TAG, "id=" + runId + " native launch error", ex);
            }
        }, "cpp-npu-probe").start();
    }

    private void emitFailure(String id, String stage, String message) {
        final String line = "id=" + id + " event=FAIL stage=" + stage
                + " detail=" + String.valueOf(message).replace('\n', ' ');
        Log.e(TAG, line);
        runOnUiThread(() -> result.setText(line));
    }
}
