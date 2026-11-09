#!/usr/bin/env python3
"""Exercise a copied exported package with isolated settings and no editor executable."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

package, logs = (Path(arg).resolve() for arg in sys.argv[1:])
logs.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="softbody-standalone-") as tmp:
    base = Path(tmp)
    isolated = base / "package"
    shutil.copytree(package, isolated)
    exe = isolated / "SoftBodyDriver.x86_64"
    env = os.environ.copy()
    for key, subdir in (("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"), ("XDG_CONFIG_HOME", "config")):
        env[key] = str(base / subdir)
        (base / subdir).mkdir()
    # Do not accidentally resolve shared libraries from a developer's environment.
    env.pop("LD_LIBRARY_PATH", None)

    def run(name, args, expected=None):
        result = subprocess.run([str(exe), "--headless", *args], cwd=isolated, env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (logs / name).write_text(result.stdout)
        if result.returncode or re.search(r"(?m)^ERROR:|SCRIPT ERROR:", result.stdout):
            raise SystemExit(f"{name} failed (exit {result.returncode}); see {logs / name}")
        if expected and expected not in result.stdout:
            raise SystemExit(f"{name}: missing success marker; see {logs / name}")

    run("standalone-menu.log", ["--quit-after", "90"])
    script = base / "standalone_check.gd"
    script.write_text('''extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var game = root.get_node("Game")
    game.selected_map = "proving_grounds"
    game.settings["traffic"] = false
    if game.cars.size() < 1:
        push_error("Export omitted car definitions")
        quit(1)
        return
    var flagship: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://cars/kestrel_hatch.car.json"))
    if not flagship is Dictionary or not bool(flagship.get("body", {}).get("detachableBumpers", false)) or not bool(flagship.get("body", {}).get("detachableDoors", false)):
        push_error("Export omitted current flagship detachable-panel definition")
        quit(1)
        return
    for car_id in ["kestrel_hatch", "concept_gt"]:
        game.selected_car = "res://cars/" + car_id + ".car.json"
        if change_scene_to_file("res://scenes/game.tscn") != OK:
            quit(1)
            return
        for i in 120: await process_frame
        var scene = current_scene
        if not is_instance_valid(scene.player):
            push_error("Standalone vehicle did not spawn: " + car_id)
            quit(1)
            return
        var info: Dictionary = scene.player.get_info()
        if info.get("id", "") != car_id or (car_id == "kestrel_hatch" and not info.get("bonnet_supported", false)):
            push_error("Standalone flagship metadata/native interface mismatch")
            quit(1)
            return
        if scene.player.get_mirror_surfaces().size() != 2:
            push_error("Exported native mirror surfaces missing: " + car_id)
            quit(1)
            return
        for optical in scene.player.get_mirror_surfaces():
            var toward_eye: Vector3 = (scene.player.get_driver_eye() - optical.center).normalized()
            var ray: Vector3 = -toward_eye + 2 * optical.normal * toward_eye.dot(optical.normal)
            if ray.dot(-scene.player.get_forward()) < 0.95 or absf(ray.dot(scene.player.get_visual_basis().y)) > 0.12:
                push_error("Exported physical mirror aims away from rear horizon: " + car_id)
                quit(1)
                return
        if car_id == "kestrel_hatch" and scene.player.get_door_states().size() != 2:
            push_error("Exported native front-door mechanisms missing")
            quit(1)
            return
        scene.world.paused = true
        scene.player.set_input(1, 0, 0, 0)
        scene.world.step_blocking(3)
        scene.world.sync_visuals()
        var telemetry: Dictionary = scene.player.get_telemetry()
        if float(telemetry.get("speed_kmh", 0)) < 10 or not scene.player.get_position_ws().is_finite():
            push_error("Standalone native simulation did not drive: " + car_id)
            quit(1)
            return
        print("STANDALONE GAMEPLAY OK: ", info["name"], " ", telemetry["speed_kmh"], " km/h")
        if change_scene_to_file("res://scenes/main_menu.tscn") != OK:
            quit(1)
            return
        await process_frame
        await process_frame
    print("STANDALONE COVERAGE OK: Kestrel and Concept, returned to menu")
    quit(0)
''')
    run("standalone-gameplay.log", ["--script", str(script)], "STANDALONE COVERAGE OK:")
print("Standalone package: menu and native gameplay passed")
