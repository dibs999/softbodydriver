extends SceneTree
## Node grabber: Ctrl + left mouse picks the node under the cursor, the spring lifts a corner of a
## parked car and lets go again; a click on empty sky grabs nothing.
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var node := -1
var rest := Vector3.ZERO

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

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("grabber"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	var grabber = scene.grabber
	match phase:
		0:
			if _sim() - mark < 2.0: return false
			# Picking through the screen: the car under the cursor, nothing in the sky.
			var cam: Camera3D = scene.cam
			var roof := v.get_position_ws() + v.get_up() * 1.2
			check(grabber.grab_at(cam.unproject_position(roof)), "Ctrl+click on the car grabs a node")
			check(grabber.grabbing(), "Grabber holds a node")
			grabber.release()
			check(not grabber.grab_at(Vector2(cam.get_viewport().get_visible_rect().size.x * 0.5, 4.0)), "A click on the sky grabs nothing")
			# Physics: grab the bonnet's front-left corner from above (not a tyre: a grabbed tread
			# node only turns its wheel) and pull it 1.5 m up.
			var f := v.get_forward()
			var corner := v.get_position_ws() + f * 1.3 + v.get_right() * -0.55
			node = v.pick_node(corner + Vector3.UP * 4.0, Vector3.DOWN, 0.4)
			check(node >= 0, "A body node over the front-left wheel is found")
			rest = v.get_node_position(node)
			check(rest.y > 0.7, "It is on the body, not on a tyre (%.2f m up)" % rest.y)
			v.set_grab(node, rest + Vector3.UP * 1.5)
			mark = _sim()
			phase = 1
		1:
			if _sim() - mark < 3.0: return false
			var lift := v.get_node_position(node).y - rest.y
			check(lift > 0.15, "The grabbed corner is lifted (%.2f m)" % lift)
			check(lift < 1.6, "The spring does not overshoot (%.2f m)" % lift)
			v.release_grab()
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 3.0: return false
			var back := absf(v.get_node_position(node).y - rest.y)
			check(back < 0.08, "Released, the car settles back (%.3f m)" % back)
			check(absf(v.get_speed_kmh()) < 1.0, "and stands still")
			phase = 3
		3:
			print("broken ", scene.player.get_telemetry()["broken_beams"], " deformed ", scene.player.get_telemetry()["deformed_beams"]); print("NODE GRAB TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
