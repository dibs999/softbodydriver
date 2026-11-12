extends SceneTree
## Box trailer: the pause menu entry hangs it on the tow bar behind the car, it follows on its own
## wheels and brakes with the car, unhitched it stays parked, asked again from afar it is fetched
## back coupled, and a reset unhitches it instead of dragging it along.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var wheel_x0 := Vector3.ZERO
var parked_at := Vector3.ZERO

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").settings["traffic"] = false
	root.get_node("Game").settings["automatic"] = true
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func _gap() -> float:
	return scene.trailer.get_hitch_position().distance_to(scene.player.get_tow_position())

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.has_method("toggle_trailer"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	match phase:
		0:
			if _sim() - mark < 1.5: return false
			print("  ", scene.toggle_trailer())
			check(is_instance_valid(scene.trailer) and bool(scene.world.get_coupling(scene.trailer)["coupled"]), "The trailer is hung on the tow bar")
			check(scene.trailer.get_node_or_null("TrailerVisual") != null and scene.trailer.get_wheel_transforms().size() == 2, "It has its body and two wheels")
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 2.0: return false
			var f: float = scene.world.get_coupling(scene.trailer)["force"]
			check(f < 1500.0, "Standing, the hitch carries only the tongue load (%.0f N)" % f)
			check(_gap() < 0.1, "The hitch head sits on the tow ball (%.3f m)" % _gap())
			wheel_x0 = (scene.trailer.get_wheel_transforms()[0] as Transform3D).basis.x
			Input.action_press("throttle", 0.6)
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 8.0: return false
			Input.action_release("throttle")
			check(v.get_speed_kmh() > 25.0, "Towing, the car gets going (%.0f km/h)" % v.get_speed_kmh())
			check(_gap() < 0.15, "The trailer follows on the ball (%.3f m)" % _gap())
			var turned := (scene.trailer.get_wheel_transforms()[0] as Transform3D).basis.x.angle_to(wheel_x0)
			check(turned > 0.01, "Its wheels turn")
			check(not bool(scene.world.get_coupling(scene.trailer)["broken"]), "The coupling holds")
			Input.action_press("brake", 1.0)
			mark = _sim()
			phase = 3
		3:
			# Hold the brake until both stand (longer and the automatic would engage reverse).
			if absf(v.get_speed_kmh()) > 0.5 and _sim() - mark < 8.0: return false
			Input.action_release("brake")
			check(absf(v.get_speed_kmh()) < 1.0 and _sim() - mark < 8.0, "Car and trailer brake to a stop (%.1f s)" % (_sim() - mark))
			check(not bool(scene.world.get_coupling(scene.trailer)["broken"]), "still coupled")
			print("  ", scene.toggle_trailer())
			check(not bool(scene.world.get_coupling(scene.trailer)["coupled"]), "Unhitched")
			parked_at = scene.trailer.get_hitch_position()
			Input.action_press("throttle", 0.8)
			mark = _sim()
			phase = 4
		4:
			if _sim() - mark < 4.0: return false
			Input.action_release("throttle")
			check(_gap() > 3.0, "The car drives off without it (%.1f m)" % _gap())
			check(scene.trailer.get_hitch_position().distance_to(parked_at) < 0.5, "The trailer stays parked")
			check(scene.toggle_trailer() == "Zum An- und Abkuppeln anhalten", "Coupling waits for a standstill")
			Input.action_press("brake", 1.0)
			mark = _sim()
			phase = 40
		40:
			if absf(v.get_speed_kmh()) > 0.5 and _sim() - mark < 8.0: return false
			Input.action_release("brake")
			print("  ", scene.toggle_trailer())
			check(bool(scene.world.get_coupling(scene.trailer)["coupled"]) and _gap() < 0.3, "From afar it is fetched back behind the car, coupled")
			mark = _sim()
			phase = 5
		5:
			if _sim() - mark < 1.5: return false
			var ev := InputEventAction.new()
			ev.action = "reset_vehicle"
			ev.pressed = true
			Input.parse_input_event(ev)
			mark = _sim()
			phase = 6
		6:
			if _sim() - mark < 2.0: return false
			check(not bool(scene.world.get_coupling(scene.trailer)["coupled"]), "A reset unhitches the trailer")
			check(bool(scene.world.get_stats()["finite"]) if scene.world.get_stats().has("finite") else true, "and nothing is flung about")
			phase = 7
		7:
			print("TRAILER TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
