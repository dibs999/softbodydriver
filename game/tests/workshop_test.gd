extends SceneTree
## Werkstatt: an engine swap (the Vortex GT's 5.0 V8 into the Kestrel), all-wheel drive and
## semi-slicks rebuild the car where it stands; it is heavier by the engine's mass difference, pulls
## harder, keeps its place in the vehicle list, and the factory build comes back on request. The
## configuration is stored per car in the profile (a scratch profile here).
const PROFILE := "user://workshop_test_profile.json"
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var base_mass := 0.0
var base_engine := ""
var base_speed := 0.0
var tuned_speed := 0.0
var vehicle_count := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	var game := root.get_node("Game")
	if FileAccess.file_exists(PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	game.progress.profile_path = PROFILE
	game.progress.load_profile()
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.settings["automatic"] = true
	game.settings["career"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("rebuild_player"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	match phase:
		0:
			if _sim() - mark < 1.5: return false
			base_mass = float(v.get_info()["mass"])
			base_engine = str(v.get_info()["engine"])
			Input.action_press("throttle", 1.0)
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 4.0: return false
			Input.action_release("throttle")
			base_speed = v.get_speed_kmh()
			Input.action_press("brake", 1.0)
			mark = _sim()
			phase = 2
		2:
			if absf(v.get_speed_kmh()) > 0.5 and _sim() - mark < 8.0: return false
			Input.action_release("brake")
			vehicle_count = scene.vehicles.size()
			var cfg := {"engine": "vortex_gt", "gearbox": "own", "layout": "AWD", "compound": 3}
			print("  ", scene.rebuild_player(cfg))
			var n: SBVehicle = scene.player
			check(n != v and is_instance_valid(n), "The car is rebuilt")
			check(str(n.get_info()["engine"]) == "5.0 V8", "with the V8 (%s)" % n.get_info()["engine"])
			check(str(n.get_info()["layout"]) == "AWD", "and all-wheel drive")
			var swap: Dictionary = {}
			for e: Dictionary in root.get_node("Game").engine_catalogue():
				if e["id"] == "vortex_gt": swap = e
			var expected := base_mass + float(swap.get("mass", 0.0)) - 140.0
			check(absf(float(n.get_info()["mass"]) - expected) < 1.0, "Heavier by the engines' mass difference (%.0f -> %.0f kg)" % [base_mass, float(n.get_info()["mass"])])
			check(scene.vehicles.size() == vehicle_count and scene.vehicles.has(n), "It takes the old car's place in the vehicle list")
			check(not root.get_node("Game").progress.get_config("kestrel_hatch").is_empty(), "The configuration is stored for this car")
			mark = _sim()
			phase = 3
		3:
			if _sim() - mark < 1.5: return false
			check(bool(scene.world.get_stats().get("finite", true)), "The new build settles without blowing up")
			Input.action_press("throttle", 1.0)
			mark = _sim()
			phase = 4
		4:
			if _sim() - mark < 4.0: return false
			Input.action_release("throttle")
			tuned_speed = scene.player.get_speed_kmh()
			check(tuned_speed > base_speed * 1.15, "It pulls harder (%.0f vs %.0f km/h after 4 s)" % [tuned_speed, base_speed])
			Input.action_press("brake", 1.0)
			mark = _sim()
			phase = 5
		5:
			if absf(scene.player.get_speed_kmh()) > 0.5 and _sim() - mark < 8.0: return false
			Input.action_release("brake")
			print("  ", scene.rebuild_player({}))
			check(str(scene.player.get_info()["engine"]) == base_engine, "Werkszustand brings the factory engine back")
			check(root.get_node("Game").progress.get_config("kestrel_hatch").is_empty(), "and clears the stored configuration")
			# Pure data checks of the remaining options.
			var W := preload("res://scripts/vehicle_workshop.gd")
			var def := W.read_definition("res://cars/kestrel_hatch.car.json")
			var cat: Array = root.get_node("Game").engine_catalogue()
			var boosted := W.apply(def, {"boost": 0.3}, cat)
			var low: float = boosted["engine"]["torqueCurve"][0][1]
			var mid: float = boosted["engine"]["torqueCurve"][3][1]
			check(is_equal_approx(low, def["engine"]["torqueCurve"][0][1]) and mid > def["engine"]["torqueCurve"][3][1] * 1.25, "More boost: no gain off boost, +30 %% from mid revs (%.0f -> %.0f Nm)" % [def["engine"]["torqueCurve"][3][1], mid])
			var close := W.apply(def, {"gear_spread": 0.8}, cat)
			check(close["engine"]["gears"][0] < def["engine"]["gears"][0] and is_equal_approx(close["engine"]["gears"][-1], def["engine"]["gears"][-1]), "Close-ratio box: shorter steps, same top gear")
			check(W.apply(def, {"wing": 2}, cat)["body"]["rearWing"] == 20.0, "Wing on a generated body")
			var g2 := W.apply(def, {"g2": 0.9}, cat)
			check(is_equal_approx(g2["engine"]["gears"][1], def["engine"]["gears"][1] * 0.9) and is_equal_approx(g2["engine"]["gears"][0], def["engine"]["gears"][0]), "Single gear ratio: only 2nd gear changes")
			check(not W.apply(W.read_definition("res://cars/meridian_sedan.car.json"), {"wing": 2}, cat)["body"].has("rearWing"), "but not on an imported model")
			var msg: String = scene.rebuild_player({"power": 1.2})
			check(msg == "Werkstatt: Leistung +20 %", "A plain engine tune rebuilds as well (%s)" % msg)
			Input.action_press("throttle", 1.0)
			mark = _sim()
			phase = 6
		6:
			if _sim() - mark < 3.0: return false
			check(scene.rebuild_player({}) == "Für die Werkstatt anhalten", "Only at a standstill (%.0f km/h)" % scene.player.get_speed_kmh())
			Input.action_release("throttle")
			if FileAccess.file_exists(PROFILE):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
			print("WORKSHOP TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
