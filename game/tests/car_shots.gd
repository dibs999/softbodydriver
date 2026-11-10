extends SceneTree
## Renders one car from fixed angles: godot -s res://tests/car_shots.gd -- <car.json> <out_prefix> [map]
## Views: front 3/4, rear 3/4, side, wheel close-up, cockpit. Use under a real display or Xvfb.

var frame := 0
var cam: Camera3D
var car: SBVehicle
var world: SBWorld
var prefix := "/tmp/car"
var views: Array = []

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://cars/meridian_sedan.car.json"
	prefix = args[1] if args.size() > 1 else prefix
	var game := root.get_node("Game")
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := GameSky.new()
	sm.sky_top_color = Color(0.32, 0.47, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sm.ground_bottom_color = Color(0.22, 0.21, 0.2)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.64)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.42, 0.43)
	fm.roughness = 0.85
	floor.material_override = fm
	scene.add_child(floor)
	world = SBWorld.new()
	world.material_library = game.make_material_library()
	scene.add_child(world)
	world.add_ground_plane(1.0)
	car = game.spawn_vehicle(world, path, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	car.set_input(0, 1, 0, 1)
	world.step_blocking(2.0)
	if args.size() > 2 and args[2] == "open":
		for d in car.get_door_states().size():
			print("door ", d, " ", car.set_door_open(d, true))
		print("bonnet ", car.release_bonnet())
		for i in 40:
			world.step_blocking(0.1)
			world.sync_visuals()
	world.sync_visuals()
	cam = Camera3D.new()
	cam.fov = 45
	scene.add_child(cam)
	cam.current = true
	var info: Dictionary = car.get_info()
	var L: float = float(info.get("length", 4.5))
	var c: Vector3 = car.get_position_ws()
	var f: Vector3 = car.get_forward()
	f.y = 0
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var eye: Vector3 = car.get_driver_eye()
	if args.size() > 2 and args[2] == "open":
		r = -r
	views = [
		[c + f * (L * 0.85) + r * (L * 0.65) + Vector3.UP * 1.2, c + Vector3.UP * 0.6],
		[c - f * (L * 0.85) - r * (L * 0.65) + Vector3.UP * 1.3, c + Vector3.UP * 0.6],
		[c + r * (L * 1.15) + Vector3.UP * 0.8, c + Vector3.UP * 0.6],
		[c + f * (L * 0.30) + r * 1.9 + Vector3.UP * 0.45, c + f * (L * 0.30) + r * 0.7 + Vector3.UP * 0.33],
		[eye, eye + f * 3.0 - Vector3.UP * 0.35],
	]

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
		return false
	var vi := (frame - 10) / 8
	if frame >= 10 and (frame - 10) % 8 == 0 and vi < views.size():
		cam.position = views[vi][0]
		cam.look_at(views[vi][1])
	if frame >= 10 and (frame - 10) % 8 == 7 and vi < views.size():
		root.get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, vi])
		print("saved ", vi)
	return frame > 10 + 8 * views.size()
