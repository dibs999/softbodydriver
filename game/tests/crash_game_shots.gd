extends SceneTree
## Crash into the proving-ground wall in the full game scene and render the damage as the player
## sees it (lamps, cracked or shattered glass, bumpers, debris):
## godot -s res://tests/crash_game_shots.gd -- <car.json> <out_prefix> [km/h]

const DT := 0.02
var prefix := "/tmp/crash_game"
var kmh := 55.0
var frame := 0
var scene: Node
var cam: Camera3D
var views: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	game.selected_car = args[0] if args.size() > 0 else "res://cars/kestrel_hatch.car.json"
	prefix = args[1] if args.size() > 1 else prefix
	kmh = float(args[2]) if args.size() > 2 else kmh
	game.selected_map = "proving_grounds"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _tick(car: SBVehicle) -> void:
	scene.world.step_blocking(DT)
	scene.world.sync_visuals()
	scene.equipment._process(DT)

func _crash() -> void:
	scene.set_process(false)
	scene.world.time_scale = 0.0
	var car: SBVehicle = scene.player
	# The soak test's authored approach to the crash wall.
	car.relocate_to(Transform3D(Basis.IDENTITY, Vector3(150, 0, -40)))
	for i in 50: _tick(car)
	var hit := false
	for i in 1500:
		var v := car.get_speed_kmh()
		car.set_input(1.0 if v < kmh and not hit else 0.0, 0.0, 0.0, 0.0)
		if car.take_impact() > 30.0: hit = true
		_tick(car)
		if hit and v < 1.0: break
	print("impact speed setting %.0f km/h, hit %s" % [kmh, hit])
	car.set_input(0, 1, 0, 1)
	for i in 60: _tick(car)
	for g in car.get_glass_states(): print("  pane %s damage %.2f" % [g["name"], g["damage"]])
	for l in car.get_lamp_states(): print("  lamp %s broken %s" % [l["name"], l["broken"]])
	var c := car.get_position_ws()
	var f := car.get_forward()
	var r := car.get_right()
	var eye := car.get_driver_eye()
	views = [[c - f * 1.0 + r * 4.0 + Vector3.UP * 1.4, c + f * 1.2],
		[c - f * 5.0 - r * 3.0 + Vector3.UP * 1.8, c],
		[eye, eye + f * 3.0 - Vector3.UP * 0.3],
		[c + f * 4.5 + r * 2.8 + Vector3.UP * 1.0, c + f * 1.0 + Vector3.UP * 0.6]]

func _process(_d: float) -> bool:
	frame += 1
	if scene == null:
		scene = current_scene
		if scene == null or not scene.get("player"): scene = null
		return frame > 600
	if frame == 30:
		if scene.get("hud"): scene.hud.visible = false
		_crash()
		cam = Camera3D.new()
		cam.fov = 60
		scene.add_child(cam)
		cam.current = true
	if cam == null: return false
	var vi := (frame - 32) / 8
	if frame >= 32 and vi < views.size():
		cam.global_position = views[vi][0]
		cam.look_at(views[vi][1])
		if (frame - 32) % 8 == 7:
			root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
	return frame >= 32 + 8 * views.size()
