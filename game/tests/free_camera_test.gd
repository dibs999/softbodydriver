extends SceneTree
## Free camera: its own key (F9) toggles it, the camera cycle skips it, the driving keys fly it,
## and the car holds still.
## godot --headless -s res://tests/free_camera_test.gd

var frame := 0
var failed := false
var start_cam := Vector3.ZERO
var start_car := Vector3.ZERO

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	if frame == 30:
		var CameraRig: GDScript = load("res://scripts/camera_rig.gd")
		for k in 8:
			scene.cam.cycle()
			check(scene.cam.mode != CameraRig.Mode.FREE, "Cycling the driving cameras never enters the free camera (%d)" % k)
		scene.cam.toggle_free()
		check(CameraRig.MODE_NAMES[scene.cam.mode] == "Freie Kamera", "Its own key switches to the free camera")
		start_cam = scene.cam.global_position
		start_car = scene.player.get_position_ws()
		Input.action_press("throttle")
	if frame == 150:
		Input.action_release("throttle")
		var forward: Vector3 = -scene.cam.global_basis.z
		var moved: Vector3 = scene.cam.global_position - start_cam
		print("  camera moved %.1f m, car moved %.2f m" % [moved.length(), scene.player.get_position_ws().distance_to(start_car)])
		check(moved.length() > 3.0 and moved.normalized().dot(forward) > 0.9, "Throttle key flies the camera forward")
		check(scene.player.get_position_ws().distance_to(start_car) < 0.5, "The car holds still while the free camera flies")
		scene.cam.toggle_free()
		var Rig: GDScript = load("res://scripts/camera_rig.gd")
		check(scene.cam.mode != Rig.Mode.FREE, "The same key returns to the driving camera")
		print("TEST OK" if not failed else "TEST FAILED")
		quit(1 if failed else 0)
		return true
	return false
