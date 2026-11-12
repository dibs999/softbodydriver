extends SceneTree
## Autobahn overpass: the farm road bridge can be driven - up the earth ramp, across the deck 7 m
## above the motorway and down the other side - instead of being scenery a car falls through.
const A := preload("res://scripts/maps/autobahn.gd")
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var top_y := -100.0
var over_motorway_y := -100.0
var start_z := 0.0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "autobahn"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	var x := -420.0
	var z := -A.RADIUS
	var span := 2.0 * (A.CARRIAGE_OFFSET + A.CARRIAGE_HALF + 4.0)
	var deck_half := span * 0.5 + 6.0
	match phase:
		0:
			if _sim() - mark < 1.0: return false
			# On the farm road in the field, 15 m before the ramp, facing the bridge.
			start_z = z - deck_half - 60.0 - 15.0
			var f := Vector3(0, 0, 1)
			check(v.relocate_to(Transform3D(Basis(f, Vector3.UP, f.cross(Vector3.UP)), Vector3(x, 0.0, start_z))), "Car placed on the farm road")
			Input.action_press("throttle", 0.55)
			mark = _sim()
			phase = 1
		1:
			var p: Vector3 = v.get_position_ws()
			top_y = maxf(top_y, p.y)
			if absf(p.z - z) < 4.0:
				over_motorway_y = maxf(over_motorway_y, p.y)
			if p.z > z + deck_half + 20.0 or _sim() - mark > 40.0 or p.y < -5.0:
				Input.action_release("throttle")
				check(top_y > 7.0, "Climbed onto the deck (highest %.1f m)" % top_y)
				check(over_motorway_y > 7.0, "Crossed the motorway on the deck (%.1f m)" % over_motorway_y)
				check(p.z > z + deck_half + 20.0, "Reached the far ramp (z %.0f, %.0f m travelled)" % [p.z, p.z - start_z])
				check(absf(p.x - x) < 5.5, "Stayed on the bridge road (%.1f m off centre)" % absf(p.x - x))
				phase = 2
		2:
			print("OVERPASS TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
