extends SceneTree
## Driver's-eye renders in rain with the wipers at several points of their cycle:
## godot -s res://tests/rain_shots.gd -- <out_prefix> [car]   (SPEED=<km/h>: drops in the airflow)
var frame := 0
var scene: Node
var cam: Camera3D
var prefix := "/tmp/rain"
var shot := 0

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	prefix = args[0] if args.size() > 0 else prefix
	var game := root.get_node("Game")
	game.selected_map = "hill_roads"
	game.selected_car = args[1] if args.size() > 1 else "res://cars/kestrel_hatch.car.json"
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	scene = current_scene
	scene.world.step_blocking(1.0)
	scene.world.time_scale = 0.0
	scene.world.sync_visuals()
	scene.weather.weather_index = 2
	scene.weather.wetness = 1.0
	scene.weather._apply_lighting()
	scene.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 70
	scene.add_child(cam)
	cam.current = true
	# Long unwiped exposure first, then a few frames into the sweep.
	scene.wipers.mode = 1
	scene.wipers.update(60.0, true, 1.0)
	# SPEED=<km/h>: wipers parked and the drops shown as they run in that airflow.
	if OS.has_environment("SPEED"):
		scene.wipers.speed_override = float(OS.get_environment("SPEED"))
		scene.wipers.mode = 1   # off

func _process(_d: float) -> bool:
	frame += 1
	if scene == null or cam == null:
		return false
	var p: SBVehicle = scene.player
	var eye: Vector3 = p.get_driver_eye()
	cam.look_at_from_position(eye, eye + p.get_forward() * 10.0 - p.get_up() * 0.6, p.get_up())
	if frame == 30 or frame == 36 or frame == 42:
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, shot])
		shot += 1
		if OS.has_environment("SPEED"):
			scene.wipers.update(1.0, true, 1.0)
		else:
			scene.wipers.mode = 2
			scene.wipers.update(0.42, true, 1.0)
	return shot >= 3
