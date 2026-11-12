extends SceneTree
## Pos1 recovery: a car lying on its roof goes back upright to where it last stood on its wheels,
## keeping its damage; repeated presses walk further back, and after a reset there is nothing to
## go back to. Also: V is only the cruise control, looking back moved to ^.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var spawn_pos := Vector3.ZERO
var damage_before := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _has_key(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
			return true
	return false

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("recovery"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	match phase:
		0:
			# Stand on the wheels for a while so the trail holds poses older than 2.5 s.
			if _sim() - mark < 5.0: return false
			spawn_pos = v.get_position_ws()
			check(_has_key("cruise_control", KEY_V) and not _has_key("look_back", KEY_V), "V is only the cruise control")
			check(_has_key("look_back", KEY_QUOTELEFT), "Looking back sits on ^")
			# Roll the car onto its roof 12 m further on.
			var f: Vector3 = v.get_forward()
			f.y = 0.0
			f = f.normalized()
			var down := Vector3.DOWN
			var flipped := Transform3D(Basis(f, down, f.cross(down)), spawn_pos + f * 12.0 + Vector3.UP * 3.0)   # dropped: the roof dents
			check(v.relocate_to(flipped), "Car placed on its roof")
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 3.0: return false
			check(v.get_up().y < -0.5, "Car lies on its roof")
			damage_before = int(v.get_telemetry()["deformed_beams"])
			check(damage_before > 0, "The roll damaged the car (%d deformed beams)" % damage_before)
			check(scene.recover_player(), "Recovery finds an earlier pose")
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 1.5: return false
			var p: Vector3 = v.get_position_ws()
			check(v.get_up().y > 0.95, "Recovered car stands upright (up.y %.2f)" % v.get_up().y)
			check(Vector2(p.x - spawn_pos.x, p.z - spawn_pos.z).length() < 1.0, "Recovered where it last stood (%.2f m)" % Vector2(p.x - spawn_pos.x, p.z - spawn_pos.z).length())
			check(absf(v.get_speed_kmh()) < 2.0, "Recovered car is at rest")
			check(int(v.get_telemetry()["deformed_beams"]) >= damage_before, "Damage is kept, not repaired (%d deformed beams)" % int(v.get_telemetry()["deformed_beams"]))
			check(scene.recover_player(), "A second press goes further back")
			scene.player.reset_to(scene.map_data["spawns"][0])
			scene.recovery.clear()   # what the R key does
			check(not scene.recover_player(), "Nothing to go back to right after a reset")
			phase = 3
		3:
			print("RECOVERY TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
