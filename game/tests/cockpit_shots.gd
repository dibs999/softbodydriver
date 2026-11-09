extends SceneTree
## In-game cabin views of the player's car on a map, with the full game scene (instruments,
## cabin closure, lighting): godot -s res://tests/cockpit_shots.gd -- <car.json> <out_prefix> [map]
## Views: ahead from the driver's seat, towards the driver's door, back over the rear seats.

var frame := 0
var prefix := "/tmp/cockpit"
var cam: Camera3D
var views: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	game.selected_car = args[0] if args.size() > 0 else "res://cars/kestrel_hatch.car.json"
	prefix = args[1] if args.size() > 1 else prefix
	game.selected_map = args[2] if args.size() > 2 else "hill_roads"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	var car: SBVehicle = scene.player
	if cam == null and frame > 40:
		cam = Camera3D.new()
		cam.fov = 70
		scene.add_child(cam)
		cam.current = true
		if scene.get("hud"): scene.hud.visible = false
		# Freeze the simulation: software rendering is slow and the camera would lag a rolling car.
		car.set_input(0, 1, 0, 1)
		scene.world.time_scale = 0.0
	if cam == null:
		return false
	var eye := car.get_driver_eye()
	var f := car.get_forward()
	var r := car.get_right()
	var u := car.get_up()
	views = [
		[eye, eye + f * 3.0 - u * 0.4],
		[eye + r * 0.15, eye - r * 2.0 + f * 0.6 - u * 0.5],
		[eye + r * 0.30 + f * 0.25, eye + r * 0.3 - f * 3.0 - u * 0.6],
	]
	var vi := (frame - 60) / 10
	if frame >= 60 and vi < views.size():
		cam.global_position = views[vi][0]
		cam.look_at(views[vi][1], u)
		if (frame - 60) % 10 == 9:
			root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
			print("saved ", vi)
	return frame >= 60 + 10 * views.size()
