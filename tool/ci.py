#!/usr/bin/env python3
"""Evora CI helper.

  python3 tool/ci.py prepare   Create the Android project and apply settings.
  python3 tool/ci.py pubget    Install packages (repairs a package conflict).
  python3 tool/ci.py build     Build the release APK. If the build fails it
                               recognises known problems, repairs them and
                               tries again (up to 4 attempts).

Everything is written to build.log and to the GitHub job summary.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

LOG = ROOT / "build.log"
APK = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
MIN_COMPILE_SDK = 36

# Gradle init script: every Android module (the app and all plugins) must
# compile against at least this SDK. Fixes ":plugin:checkReleaseAarMetadata".
INIT_SCRIPT = """
allprojects {
    afterEvaluate { p ->
        def ext = p.extensions.findByName('android')
        if (ext == null) { return }
        try {
            def cur = ext.compileSdk
            if (cur == null || cur < __SDK__) { ext.compileSdk = __SDK__ }
        } catch (Throwable t) {
            try { ext.compileSdkVersion(__SDK__) } catch (Throwable t2) { }
        }
    }
}
"""

PERMISSIONS = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>',
    '<uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION"/>',
    '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>',
]


def sh(cmd, check=True):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=check)


def write_init_script(sdk):
    d = Path.home() / ".gradle" / "init.d"
    d.mkdir(parents=True, exist_ok=True)
    (d / "eventroll.gradle").write_text(INIT_SCRIPT.replace("__SDK__", str(sdk)))
    print(f"Gradle init script written (compile SDK >= {sdk})", flush=True)


# --------------------------------------------------------------------------
# prepare
# --------------------------------------------------------------------------

def patch_manifest():
    p = Path("android/app/src/main/AndroidManifest.xml")
    xml = p.read_text()
    block = ""
    for perm in PERMISSIONS:
        name = re.search(r'android:name="([^"]+)"', perm).group(1)
        if f'android:name="{name}"' not in xml:
            block += "    " + perm + "\n"
    if block:
        xml = xml.replace("<application", block + "    <application", 1)
    xml = xml.replace('android:label="event_roll"', 'android:label="Evora"')
    p.write_text(xml)


def tune_gradle_properties(jvm="-Xmx4g -XX:MaxMetaspaceSize=1g"):
    p = Path("android/gradle.properties")
    lines = p.read_text().splitlines() if p.exists() else []
    out, seen_jvm, seen_sup = [], False, False
    for line in lines:
        if line.startswith("org.gradle.jvmargs"):
            out.append("org.gradle.jvmargs=" + jvm)
            seen_jvm = True
        elif line.startswith("android.suppressUnsupportedCompileSdk"):
            out.append("android.suppressUnsupportedCompileSdk=35,36,37")
            seen_sup = True
        else:
            out.append(line)
    if not seen_jvm:
        out.append("org.gradle.jvmargs=" + jvm)
    if not seen_sup:
        out.append("android.suppressUnsupportedCompileSdk=35,36,37")
    p.write_text("\n".join(out) + "\n")


def install_signing_key():
    """Sign every build with the same key, so a new APK installs over the old one."""
    src = Path("tool/debug.keystore")
    if src.exists():
        d = Path.home() / ".android"
        d.mkdir(exist_ok=True)
        shutil.copy(src, d / "debug.keystore")
        print("Signing key installed.", flush=True)


def prepare():
    LOG.write_text("")
    scaffold = Path("/tmp/eventroll_scaffold")
    if scaffold.exists():
        shutil.rmtree(scaffold)
    sh([
        "flutter", "create", "--platforms=android", "--org", "com.eventroll",
        "--project-name", "event_roll", str(scaffold),
    ])
    if Path("android").exists():
        shutil.rmtree("android")
    shutil.copytree(scaffold / "android", "android")

    patch_manifest()
    install_signing_key()
    # launcher icons made from the Evora logo
    shutil.copytree("tool/icons/res", "android/app/src/main/res", dirs_exist_ok=True)
    tune_gradle_properties()
    write_init_script(MIN_COMPILE_SDK)
    print("Android project ready.", flush=True)


# --------------------------------------------------------------------------
# build with automatic repair
# --------------------------------------------------------------------------

def run_logged(cmd):
    out = []
    with LOG.open("a") as lf:
        lf.write("$ " + " ".join(cmd) + "\n")
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            lf.write(line)
            out.append(line)
        proc.wait()
    return proc.returncode, "".join(out)


KEYS = (
    "Error:", "error:", "FAILURE", "What went wrong", "Execution failed",
    "requires libraries", "AAR metadata", "Namespace not specified",
    "Could not resolve", "OutOfMemory", "Java heap", "Unsupported",
    "version solving failed", "Because ", "depends on",
)


def extract_errors(text, limit=40):
    lines = text.splitlines()
    found = []
    for i, line in enumerate(lines):
        if any(k in line for k in KEYS):
            found.append(line.strip())
            if "What went wrong" in line:
                found.extend(x.strip() for x in lines[i + 1:i + 4])
    seen, out = set(), []
    for line in found:
        if line and line not in seen:
            seen.add(line)
            out.append(line)
    return out[:limit]


def summary(ok, history, errors):
    lines = ["## Evora build " + ("succeeded" if ok else "FAILED"), ""]
    lines += ["- " + h for h in history]
    if errors:
        lines += ["", "### Error lines (copy these and send them to Claude)", "```"]
        lines += errors
        lines += ["```"]
    text = "\n".join(lines) + "\n"
    print("\n" + text, flush=True)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write(text)


def strip_file_picker():
    """Last resort: build without the file_picker plugin (Files page becomes a placeholder)."""
    p = Path("pubspec.yaml")
    kept = [l for l in p.read_text().splitlines() if not l.strip().startswith("file_picker:")]
    p.write_text("\n".join(kept) + "\n")
    shutil.copy("tool/files_page_stub.dart", "lib/files_page.dart")
    sh(["flutter", "pub", "get"], check=False)


def lower_memory():
    tune_gradle_properties("-Xmx3g -XX:MaxMetaspaceSize=768m")
    with Path("android/gradle.properties").open("a") as f:
        f.write("org.gradle.workers.max=2\n")


def pubget():
    """flutter pub get. If packages conflict because of file_picker, drop it and retry."""
    code, out = run_logged(["flutter", "pub", "get"])
    if code == 0:
        return 0
    history = ["flutter pub get failed"]
    if "file_picker" in out:
        history.append("Repair: removed file_picker (package version conflict)")
        strip_file_picker()
        code, out = run_logged(["flutter", "pub", "get"])
        if code == 0:
            history.append("flutter pub get now works (Files page is a placeholder in this build)")
            summary(True, history, [])
            return 0
    summary(False, history, extract_errors(out))
    return 1


def build():
    sdk = MIN_COMPILE_SDK
    stub = Path("lib/files_page.dart")
    stripped = stub.exists() and "not available in this build" in stub.read_text()
    history = []

    for attempt in range(1, 5):
        print(f"\n===== Build attempt {attempt} =====", flush=True)
        build_cmd = ["flutter", "build", "apk", "--release"]
        build_name = os.getenv("EVORA_BUILD_NAME")
        build_number = os.getenv("EVORA_BUILD_NUMBER")
        if build_name:
            build_cmd.append(f"--build-name={build_name}")
        if build_number:
            build_cmd.append(f"--build-number={build_number}")
        code, out = run_logged(build_cmd)

        if code == 0 and APK.exists():
            history.append(f"Attempt {attempt}: success")
            if stripped:
                history.append("Note: built without file_picker (Files page is a placeholder).")
            summary(True, history, [])
            return 0

        history.append(f"Attempt {attempt}: failed")
        errors = extract_errors(out)

        # A mistake in the Dart code itself cannot be repaired by a script.
        if re.search(r"lib/\S+\.dart:\d+:\d+: Error", out):
            history.append("Dart code error: needs a code change (send the lines below to Claude).")
            summary(False, history, errors)
            return 1

        msg = None
        needs = [int(x) for x in re.findall(r"compile against version (\d+) or later", out)]
        if needs and max(needs) > sdk:
            sdk = max(needs)
            write_init_script(sdk)
            msg = f"Raised the compile SDK to {sdk} for all modules"
        elif any(k in out for k in ("java.lang.OutOfMemoryError", "Java heap space", "GC overhead")):
            lower_memory()
            msg = "Reduced Gradle memory use"
        elif not stripped and ("file_picker" in out or "AAR metadata" in out):
            strip_file_picker()
            stripped = True
            msg = "Removed file_picker so the rest of the app can build"
        elif attempt == 1:
            sh(["flutter", "clean"], check=False)
            sh(["flutter", "pub", "get"], check=False)
            msg = "Cleaned the project and retried"

        if msg is None:
            history.append("No automatic repair is known for this error.")
            summary(False, history, errors)
            return 1
        history.append("Repair: " + msg)

    summary(False, history, extract_errors(LOG.read_text()))
    return 1


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "prepare":
        prepare()
    elif cmd == "pubget":
        sys.exit(pubget())
    elif cmd == "build":
        sys.exit(build())
    else:
        print(__doc__)
        sys.exit(2)
