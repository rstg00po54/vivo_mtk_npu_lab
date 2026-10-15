#!/usr/bin/env python3
"""Run independent C++/LiteRT 2.3.0 CPU/NPU compilation on a vivo Android device.

Example:
 python3 tools/run_probe.py --model 10b=/path/10b.tflite --model human=/path/human.tflite --accelerators NPU
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

PACKAGE = "com.vivomtknpulab"
ACTIVITY = PACKAGE + "/.MainActivity"
ROOT = Path(__file__).resolve().parents[1]
APK = ROOT / "android/app/build/outputs/apk/debug/app-debug.apk"


def run(argv, timeout=45, check=True):
    p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=timeout)
    if check and p.returncode:
        raise RuntimeError("Command failed: " + repr(argv) + "\n" + p.stdout[-2200:])
    return p.stdout


def adb(serial, *argv, timeout=45, check=True):
    return run(["adb", *(["-s", serial] if serial else []), *argv],
               timeout=timeout, check=check)


def pick_device(explicit):
    devices = adb(None, "devices")
    ready = [bits[0] for line in devices.splitlines()[1:]
             if len(bits := line.split()) >= 2 and bits[1] == "device"]
    if explicit and explicit not in ready:
        raise RuntimeError("ADB device not connected: " + explicit)
    if not explicit and len(ready) != 1:
        raise RuntimeError("Multiple/no ADB devices; specify --serial: " + repr(ready))
    return explicit or ready[0]


def parse_model(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError("Use --model SHORT_NAME=/path/model.tflite")
    label, path_str = value.split("=", 1)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,48}", label):
        raise argparse.ArgumentTypeError("Invalid short model name: " + label)
    path = Path(path_str).expanduser().resolve()
    if not path.is_file() or path.suffix != ".tflite":
        raise argparse.ArgumentTypeError("Model must exist as .tflite: " + str(path))
    return label + ".tflite", path


def push_model(serial, name, path):
    # Install private model without exposing it to shared storage or modifying
    # BadukaiJ. Shell protocol transports arbitrary bytes via stdin without a PTY.
    adb(serial, "shell", "run-as", PACKAGE, "mkdir", "-p", "files/models")
    cmd = ["adb", "-s", serial, "shell",
           "run-as " + PACKAGE + " sh -c 'cat > files/models/" + name + "'"]
    with path.open("rb") as source:
        process = subprocess.Popen(cmd, stdin=source, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        try:
            stdout, stderr = process.communicate(timeout=240)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise RuntimeError("Copying model to Android timed out")
    if process.returncode:
        raise RuntimeError("Model copy failed: " +
                           (stdout + stderr).decode(errors="replace")[-1300:])
    actual = adb(serial, "shell", "run-as", PACKAGE,
                 "stat", "-c", "%s", "files/models/" + name).strip()
    if not actual.isdecimal() or int(actual) != path.stat().st_size:
        raise RuntimeError("Model copy truncated: expected=" + str(path.stat().st_size) +
                           " got=" + actual)


def probe_events(serial, run_id):
    output = adb(serial, "logcat", "-d", "-v", "brief", "MTK_CPP_PROBE:V", "*:S",
                 timeout=45, check=False)
    return [line for line in output.splitlines() if ("id=" + run_id + " ") in line]


def vendor_logs(serial):
    output = adb(serial, "logcat", "-d", "-b", "all", "-v", "time",
                 timeout=60, check=False)
    pattern = re.compile(
        r"MTK_CPP_PROBE|MediaTek|Neuron|NeuroPilot|PrepareTensors|MDLA|APUSYS|"
        r"LiteRT|litert|FATAL EXCEPTION|Fatal signal|linker.*LiteRt", re.I)
    matching = [line for line in output.splitlines() if pattern.search(line)]
    return "\n".join(matching[-250:])[-32000:]


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def test_one(serial, name, accelerator, mode, timeout):
    run_id = "cpp" + uuid.uuid4().hex[:12]
    adb(serial, "shell", "am", "force-stop", PACKAGE, check=False)
    launch = adb(serial, "shell", "am", "start", "-W", "-n", ACTIVITY,
                 "--es", "run_id", run_id,
                 "--es", "model", name,
                 "--es", "accelerator", accelerator,
                 "--es", "mode", mode)
    if "Error" in launch or "Exception" in launch:
        raise RuntimeError("Failed to launch activity: " + launch)

    started = time.monotonic()
    terminal, events = None, []
    while time.monotonic() - started < timeout:
        events = probe_events(serial, run_id)
        terminal = next((line for line in events
                         if "event=PASS " in line or "event=FAIL " in line), None)
        if terminal:
            break
        time.sleep(2)
    status = ("PASS" if terminal and "event=PASS " in terminal
              else "FAIL" if terminal else "TIMEOUT_OR_NATIVE_CRASH")
    record = {
        "testId": run_id, "model": name, "accelerator": accelerator,
        "mode": mode, "status": status,
        "elapsedSeconds": round(time.monotonic() - started, 2),
        "events": events, "terminal": terminal,
        "vendorLogTail": vendor_logs(serial) if status != "PASS" else "",
    }
    adb(serial, "shell", "am", "force-stop", PACKAGE, check=False)
    return record


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", action="append", type=parse_model, required=True)
    p.add_argument("--serial", help="ADB serial if multiple USB/Wi-Fi transports")
    p.add_argument("--accelerators", default="NPU", help="NPU or CPU,NPU")
    p.add_argument("--mode", choices=["COMPILE", "BUFFERS"], default="BUFFERS")
    p.add_argument("--timeout", type=int, default=240)
    p.add_argument("--skip-install", action="store_true")
    p.add_argument("--apk", type=Path, default=APK)
    p.add_argument("--out", type=Path, default=ROOT / "reports")
    args = p.parse_args()
    accelerators = [s.strip().upper() for s in args.accelerators.split(",")]
    if not accelerators or any(a not in ("NPU", "CPU") for a in accelerators):
        p.error("--accelerators must be NPU, CPU, or CPU,NPU")
    if args.timeout < 15:
        p.error("--timeout must be >=15")

    device = pick_device(args.serial)
    if not args.skip_install:
        if not args.apk.is_file():
            p.error("APK not found. Build android:app:assembleDebug first: " + str(args.apk))
        print(adb(device, "install", "-r", str(args.apk), timeout=180))

    props = {
        key: adb(device, "shell", "getprop", key).strip()
        for key in ("ro.product.model", "ro.soc.model", "ro.build.version.release")
    }
    print("Device:", device, props, flush=True)
    args.out.mkdir(parents=True, exist_ok=True)
    ok = True
    for name, path in args.model:
        print("Copy", path, "to native test app as", name, flush=True)
        push_model(device, name, path)
        sha = sha256_file(path)
        for accelerator in accelerators:
            print("Testing", name, accelerator, flush=True)
            case = test_one(device, name, accelerator, args.mode, args.timeout)
            case.update({"device": device, "properties": props, "modelSha256": sha})
            out = args.out / (datetime.now().strftime("%Y%m%dT%H%M%S") + "_" +
                              name + "_" + accelerator + "_" + case["testId"] + ".json")
            out.write_text(json.dumps(case, ensure_ascii=False, indent=2),
                           encoding="utf-8")
            print(case["status"], "=>", out, flush=True)
            if case["terminal"]:
                print(case["terminal"][-1200:], flush=True)
            ok = ok and case["status"] == "PASS"
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(2)
