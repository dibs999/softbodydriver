extends SceneTree
## Map renders without driving: godot -s res://tests/map_shots.gd -- <map_id> <out_prefix> [car] [night]
## Places the camera at five points along the map's route (eye height, looking ahead) plus one overview.
## HIGH_BEAM=1 switches the player's lamps to high beam. AT=<i,j,...> picks the route waypoints to look ahead from. PROP_VIEWS=<kind> adds close views
## of the first three props of that kind.

var frame := 0
var scene: Node
var cam: Camera3D
var prefix := "/tmp/map"
var views: Array = []
var start_frame := 5

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var game := root.get_node("Game")
	game.selected_map = args[0] if args.size() > 0 else "proving_grounds"
	prefix = args[1] if args.size() > 1 else prefix
	game.selected_car = args[2] if args.size() > 2 else "res://cars/meridian_sedan.car.json"
	game.settings["traffic"] = true
	game.settings["show_help"] = false
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	scene = current_scene
	scene.world.time_scale = 0.0
	scene.world.step_blocking(1.0)
	scene.world.sync_visuals()
	if args.size() > 3 and args[3] == "night":
		scene.weather.automatic_time = false
		scene.weather.hour = 22.0
		scene.weather._apply_lighting()
	if scene.get("hud"):
		scene.hud.visible = false
	# WEATHER=<index>: 0 clear, 1 overcast, 2 rain, 3 fog.
	if OS.has_environment("WEATHER"):
		scene.weather.weather_index = int(OS.get_environment("WEATHER"))
		scene.weather._apply_lighting()
		scene.weather.wetness = float(scene.weather.WETNESS[scene.weather.weather_index])
	# HIGH_BEAM=1: the player switched to high beam.
	if OS.has_environment("HIGH_BEAM") and scene.get("equipment"):
		var ls: Dictionary = scene.equipment.state_for(scene.player)
		ls["lights"] = true
		ls["light_mode"] = 2
		ls["manual_lights"] = true
	# TRAILER=1: the box trailer hung on behind the player's car.
	if OS.has_environment("TRAILER"):
		scene.world.time_scale = 1.0
		print(scene.toggle_trailer())
		scene.world.step_blocking(2.0)
		scene.world.sync_visuals()
		scene.world.time_scale = 0.0
	# IGNITE=0|1: set the player car on fire (engine bay / tank) and let it burn for a while.
	if OS.has_environment("IGNITE"):
		scene.player.ignite(int(OS.get_environment("IGNITE")))
		scene.world.step_blocking(15.0)
		scene.world.sync_visuals()
		scene.world.time_scale = 1.0   # particles run at the simulation's speed
		start_frame = 90               # let the flames and smoke build up
	var data: Dictionary = scene.map_data
	var wps: Array = data.get("waypoints", [])
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 3000
	scene.add_child(cam)
	cam.current = true
	if scene.get("cam"):
		scene.cam.current = false
	var n := wps.size()
	# AT=12,140,...: look ahead from these waypoint indices instead of five evenly spaced ones.
	var picks: Array[int] = []
	if OS.has_environment("AT"):
		for t in OS.get_environment("AT").split(","): picks.append(int(t))
	else:
		for k in 5: picks.append(int(float(k) / 5.0 * n))
	for i0 in picks:
		if n < 2: break
		var i := i0 % n
		var a: Vector3 = wps[i]
		var b: Vector3 = wps[(i + 3) % n]
		var dir := (b - a)
		dir.y = 0
		dir = dir.normalized()
		views.append([a + Vector3.UP * 1.6 - dir * 4.0, a + dir * 30.0 + Vector3.UP * 0.5])
	# VIEWS=x,y,z,tx,ty,tz;...: extra camera positions and look-at targets in world space.
	if OS.has_environment("VIEWS"):
		for v in OS.get_environment("VIEWS").split(";"):
			var f := v.split_floats(",")
			views.append([Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5])])
	# PROP_VIEWS=<kind>: close views of the first three props of that kind ("branch", "log", ...).
	if OS.has_environment("PROP_VIEWS"):
		var count := 0
		for pr: Dictionary in data.get("props", []):
			if String(pr.get("kind", "")) != OS.get_environment("PROP_VIEWS") or count >= 3: continue
			var at: Vector3 = pr["position"]
			views.append([at + Vector3(2.6, 1.4, 2.2), at + Vector3(0, 0.1, 0)])
			if count == 0: views.append([at + Vector3(0.9, 0.6, 0.7), at + Vector3(0, 0.05, 0)])
			if count == 0: views.append([at + Vector3(0.0, 2.6, 0.02), at])
			count += 1
	var p: Vector3 = scene.player.get_position_ws()
	# FROM_LIGHT=1: what the player's right headlight sees (anything in front of it shadows the beam).
	if OS.has_environment("FROM_LIGHT") and scene.get("equipment"):
		views.append(["light"])   # resolved when the shot is taken: the lamp rig follows the car
	# CAR_VIEWS=dx,dy,dz,tx,ty,tz;...: camera and target relative to the player car.
	if OS.has_environment("CAR_VIEWS"):
		for v in OS.get_environment("CAR_VIEWS").split(";"):
			var f := v.split_floats(",")
			views.append([p + Vector3(f[0], f[1], f[2]), p + Vector3(f[3], f[4], f[5])])
	views.append([p + Vector3(-9, 4.5, 6), p + Vector3(6, 0.5, -2)])
	views.append([p + Vector3(0, 160, 120), p + Vector3(0, 0, -40)])
	views.append([p + Vector3(-6, 1.6, 0), p + Vector3(40, 18, -25)])

func _process(_d: float) -> bool:
	frame += 1
	if views.is_empty():
		return frame > 600
	var f0 := start_frame
	var vi := (frame - f0) / 6
	if frame >= f0 and (frame - f0) % 6 == 0 and vi < views.size():
		if views[vi][0] is String:
			var lamp: SpotLight3D = scene.equipment.state_for(scene.player)["headlights"][1]
			cam.global_transform = lamp.global_transform
		else:
			cam.position = views[vi][0]
			cam.look_at(views[vi][1])
	if frame >= f0 and (frame - f0) % 6 == 5 and vi < views.size():
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
	return frame > f0 + 6 * views.size()
