extends SceneTree
## Deterministic crash renders: godot -s res://tests/crash_shots.gd -- <car.json> <out_prefix> [km/h] [front|offset|side]
## Drives into a rigid wall (or is hit from the side) with blocking physics steps, then renders four views.

var frame := 0
var cam: Camera3D
var world: SBWorld
var car: SBVehicle
var prefix := "/tmp/crash"
var views: Array = []

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://cars/meridian_sedan.car.json"
	prefix = args[1] if args.size() > 1 else prefix
	var target := float(args[2]) if args.size() > 2 else 60.0
	var mode: String = args[3] if args.size() > 3 else "front"
	var game := root.get_node("Game")
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := GameSky.new()
	sm.sky_top_color = Color(0.32, 0.47, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -50, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 80)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.40, 0.40, 0.41)
	floor.material_override = fm
	scene.add_child(floor)
	world = SBWorld.new()
	world.material_library = game.make_material_library()
	scene.add_child(world)
	world.add_ground_plane(1.0)
	var wall_pos := Vector3(61, 1.5, 0.0 if mode == "front" else 1.3)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 8 if mode == "front" else 2.6)
	wall.mesh = bm
	wall.position = wall_pos
	scene.add_child(wall)
	world.add_box(wall_pos, bm.size * 0.5, Vector3.ZERO, 0.8)
	car = game.spawn_vehicle(world, path, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	world.step_blocking(1.0)
	var hit := false
	for i in 900:
		var kmh := car.get_speed_kmh()
		car.set_input(1.0 if kmh < target and not hit else 0.0, 1.0 if hit else 0.0, 0, 0)
		world.step_blocking(0.02)
		if not hit and car.get_position_ws().x > wall_pos.x - 1.0 - float(car.get_info().get("length", 4.5)) * 0.55:
			hit = true
			print("impact at %.1f km/h" % kmh)
		if hit and absf(car.get_speed_kmh()) < 0.5 and i > 10:
			break
	world.step_blocking(1.0)
	world.sync_visuals()
	var t := car.get_telemetry()
	print("after crash: broken %d deformed %d radiator %.0f%% status '%s'" % [t["broken_beams"], t["deformed_beams"], t["radiator_damage"] * 100, t["status"]])
	cam = Camera3D.new()
	cam.fov = 50
	scene.add_child(cam)
	cam.current = true
	var c := car.get_position_ws()
	views = [[c + Vector3(4.5, 1.6, -4.0), c + Vector3(1.4, 0.5, 0)], [c + Vector3(4.5, 1.6, 4.0), c + Vector3(1.4, 0.5, 0)],
		[c + Vector3(-5.0, 2.0, -3.5), c + Vector3(0.5, 0.5, 0)], [c + Vector3(0.5, 5.5, -0.2), c + Vector3(1.5, 0.0, 0)]]

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
		return false
	var vi := (frame - 4) / 6
	if frame >= 4 and (frame - 4) % 6 == 0 and vi < views.size():
		cam.position = views[vi][0]
		cam.look_at(views[vi][1])
	if frame >= 4 and (frame - 4) % 6 == 5 and vi < views.size():
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
	return frame > 4 + 6 * views.size()
