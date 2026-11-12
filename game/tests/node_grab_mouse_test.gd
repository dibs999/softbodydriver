extends SceneTree
## Node grabber driven like a player does it, through the input system: Ctrl + left button down on
## the car, the mouse moves up, the grabbed corner follows, the button comes up and the car lets go.
## Needs a window (run under Xvfb): godot -s res://tests/node_grab_mouse_test.gd
var failures := 0
var scene: Node
var phase := 0
var mark := 0.0
var press_at := Vector2.ZERO
var node := -1
var rest := Vector3.ZERO

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	if DisplayServer.get_name() == "headless":
		# Mouse events need a window to land in; node_grab_test covers the grabber headless.
		print("NODE GRAB MOUSE TEST skipped (headless: run under a display, e.g. Xvfb)")
		print("NODE GRAB MOUSE TEST OK")
		quit(0)
		return
	root.get_node("Game").selected_map = "proving_grounds"
	root.get_node("Game").settings["traffic"] = false
	change_scene_to_file("res://scenes/game.tscn")

func _sim() -> float:
	return float(scene.world.get_stats()["sim_time"])

func mouse_button(pos: Vector2, pressed: bool, ctrl: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func mouse_move(pos: Vector2, ctrl: bool) -> void:
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.ctrl_pressed = ctrl
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _process(_d: float) -> bool:
	if scene == null:
		if current_scene and current_scene.get("player") and current_scene.get("grabber"):
			scene = current_scene
			mark = _sim()
		return false
	var v: SBVehicle = scene.player
	var grabber = scene.grabber
	var cam: Camera3D = scene.cam
	match phase:
		0:
			if _sim() - mark < 2.5: return false
			# Aim at the front-left corner of the bonnet, as a player would click on it.
			var corner := v.get_position_ws() + v.get_forward() * 1.3 + v.get_right() * -0.55 + Vector3.UP * 0.75
			press_at = cam.unproject_position(corner)
			mouse_move(press_at, true)
			mouse_button(press_at, true, true)
			check(grabber.grabbing(), "Ctrl + left click on the car grabs a node")
			node = grabber._node
			rest = v.get_node_position(node)
			mark = _sim()
			phase = 1
		1:
			# Drag the mouse 150 px up over half a second, then hold.
			var t := clampf((_sim() - mark) / 0.5, 0.0, 1.0)
			mouse_move(press_at + Vector2(0, -150) * t, true)
			if _sim() - mark < 3.0: return false
			var lift := v.get_node_position(node).y - rest.y
			check(lift > 0.15, "Dragging the mouse up lifts the grabbed corner (%.2f m)" % lift)
			check(grabber._mesh.get_surface_count() > 0, "The pull line is drawn")
			mouse_button(press_at + Vector2(0, -150), false, true)
			check(not grabber.grabbing(), "Releasing the button lets go")
			mark = _sim()
			phase = 2
		2:
			if _sim() - mark < 3.0: return false
			var back := absf(v.get_node_position(node).y - rest.y)
			check(back < 0.08, "The car settles back (%.3f m)" % back)
			# Without Ctrl a click is the camera's, not a grab.
			mouse_button(press_at, true, false)
			check(not grabber.grabbing(), "A plain left click does not grab")
			mouse_button(press_at, false, false)
			phase = 3
		3:
			print("NODE GRAB MOUSE TEST ", "OK" if failures == 0 else "FAILED")
			quit(1 if failures else 0)
	return false
