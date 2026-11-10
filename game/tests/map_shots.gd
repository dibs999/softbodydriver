extends SceneTree
## Map renders without driving: godot -s res://tests/map_shots.gd -- <map_id> <out_prefix> [car] [night]
## Places the camera at five points along the map's route (eye height, looking ahead) plus one overview.
## AT=<i,j,...> picks the route waypoints to look ahead from.

var frame := 0
var scene: Node
var cam: Camera3D
var prefix := "/tmp/map"
var views: Array = []

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
	var p: Vector3 = scene.player.get_position_ws()
	views.append([p + Vector3(-9, 4.5, 6), p + Vector3(6, 0.5, -2)])
	views.append([p + Vector3(0, 160, 120), p + Vector3(0, 0, -40)])
	views.append([p + Vector3(-6, 1.6, 0), p + Vector3(40, 18, -25)])

func _process(_d: float) -> bool:
	frame += 1
	if views.is_empty():
		return frame > 600
	var vi := (frame - 5) / 6
	if frame >= 5 and (frame - 5) % 6 == 0 and vi < views.size():
		cam.position = views[vi][0]
		cam.look_at(views[vi][1])
	if frame >= 5 and (frame - 5) % 6 == 5 and vi < views.size():
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
	return frame > 5 + 6 * views.size()
