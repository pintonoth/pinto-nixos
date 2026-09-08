"""Exercise the packaged shell on an isolated 4K/scale-2 Wayland output."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

config = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
source = Path(config["source"])

# Static references and the one dynamically assembled animation sequence must
# exist in the installed package, including the fonts omitted by upstream.
for qml in source.rglob("*.qml"):
    for asset in re.findall(r'"(\.\.?/Assets/[^"\n]+)"', qml.read_text()):
        if asset.endswith("/pngseq"):
            continue
        assert (qml.parent / asset).is_file(), (qml.name, asset)
for frame in range(12):
    assert (source / f"Assets/p3r menu/png/pngseq{frame:02d}.png").is_file()

env = dict(
    os.environ,
    XDG_CONFIG_HOME=str(runtime / "config"),
    XDG_CACHE_HOME=str(runtime / "cache"),
    XDG_DATA_HOME=str(runtime / "data"),
    XDG_DATA_DIRS=str(runtime / "data"),
    WLR_BACKENDS="headless",
    WLR_RENDERER="pixman",
    QT_QPA_PLATFORM="wayland",
)
for key in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "SWAYSOCK"):
    env.pop(key, None)

apps = runtime / "data/applications"
apps.mkdir(parents=True, exist_ok=True)
(runtime / "launched").unlink(missing_ok=True)
(apps / "persona-test.desktop").write_text(
    "[Desktop Entry]\nType=Application\nName=PersonaTest\n"
    f"Exec={config['touch']} {runtime}/launched\n"
)
sway_config = runtime / "sway.conf"
sway_config.write_text(
    "xwayland disable\noutput HEADLESS-1 mode 3840x2160 scale 2\n"
    "seat seat0 fallback true\n"
)
processes = []


def start(name, command):
    with (output / f"{name}.log").open("w") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
    processes.append(process)
    return process


def wait_for(predicate, process, message):
    for _ in range(200):
        if predicate():
            return
        assert process.poll() is None, f"{message}: process exited"
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {message}")


def run(*command):
    return subprocess.run(command, env=env, check=True, timeout=10, capture_output=True)


try:
    sway = start("sway", [config["sway"], "--unsupported-gpu", "-c", str(sway_config)])
    wait_for(
        lambda: any(p.is_socket() for p in runtime.glob("wayland-*")),
        sway,
        "Wayland socket",
    )
    env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.glob("wayland-*") if p.is_socket())
    # Keep a keyboard capability present while Qt creates its Wayland seat.
    # A headless compositor otherwise has no input devices between wtype calls.
    start("keyboard", [config["wtype"], "-s", "180000"])
    time.sleep(0.2)
    shell = start("shell", [config["shell"], "--no-color"])
    wait_for(
        lambda: "Configuration Loaded" in (output / "shell.log").read_text(),
        shell,
        "Persona startup",
    )
    time.sleep(1)
    run(config["grim"], str(output / "desktop.png"))
    run(config["shell"], "ipc", "call", "searchapp", "open")
    # Allow the 4K software renderer to map the launcher and deliver focus.
    time.sleep(8)
    run(config["grim"], str(output / "launcher.png"))
    run(config["wtype"], "-s", "500", "PersonaTest", "-s", "200", "-k", "Return")
    time.sleep(0.5)
    run(config["grim"], str(output / "after-launch.png"))
    wait_for(lambda: (runtime / "launched").exists(), shell, "launcher application execution")
    run(config["shell"], "ipc", "call", "searchapp", "open")
    run(config["wtype"], "-k", "Escape")
    run(config["shell"], "ipc", "call", "searchapp", "close")
    # A second startup must exit rather than drawing another shell.
    run(config["shell"], "--no-color")
    assert shell.poll() is None, "Persona exited during interaction"
    log = (output / "shell.log").read_text()
    assert not re.search(
        r"ReferenceError|TypeError|Unable to assign|No such method|"
        r"Failed to load configuration|Cannot assign|ShaderEffect:.*[Ee]rror|"
        r"Cannot open:|Cannot load library|is not installed",
        log,
    ), log
except Exception:
    for name in ("sway", "shell"):
        log_path = output / f"{name}.log"
        if log_path.exists():
            print(f"{name} log:\n{log_path.read_text()}", file=sys.stderr)
    raise
finally:
    for process in reversed(processes):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

print("Persona assets, QML startup, launcher, and duplicate-instance checks passed.")
