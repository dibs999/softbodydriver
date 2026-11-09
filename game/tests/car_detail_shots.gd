extends SceneTree
## Detail views of one car: godot -s res://tests/car_detail_shots.gd -- <car.json> <out_prefix> [flip]
## Underside (or with `flip`: on its roof, from above), wheel arch from below and from the side, cabin from the passenger door, from the
## rear seat and through the side window. Use under a real display or Xvfb.

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
	var flipped := args.size() > 2 and args[2] == "flip"
	car = game.spawn_vehicle(world, path, Transform3D(Basis(Vector3.RIGHT, PI) if flipped else Basis.IDENTITY, Vector3(0, 1.7, 0) if flipped else Vector3.ZERO))
	car.set_input(0, 1, 0, 1)
	world.step_blocking(2.0)
	if args.size() > 2 and args[2] == "open":
		print("door ", car.set_door_open(0, true), " bonnet ", car.release_bonnet())
		for i in 40:
			world.step_blocking(0.1)
			world.sync_visuals()
	world.sync_visuals()
	cam = Camera3D.new()
	cam.fov = 62
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
	var up := Vector3.UP
	if flipped:
		# On its roof in the sun: the underside as it is seen after a rollover.
		c = car.get_position_ws()
		views = [[c + Vector3(0.3, 3.2, 0.5), c], [c + Vector3(2.6, 1.8, 2.4), c], [c + Vector3(-2.4, 1.4, -2.2), c]]
		return
	views = [
		[c - up * 2.6 + f * 0.4 + r * 0.6, c + f * 0.2],
		[c - up * 1.2 + f * (L * 0.48) + r * 1.9, c + f * (L * 0.30) + r * 0.6 + up * 0.25],
		[c + f * (L * 0.30) + r * 1.25 + up * 0.32, c + f * (L * 0.30) + r * 0.5 + up * 0.45],
		[eye + r * 0.72 + f * 0.1, eye - r * 0.2 + f * 1.0 - up * 0.45],
		[eye + r * 0.36 - f * 1.0 + up * 0.05, eye + r * 0.2 + f * 1.5 - up * 0.3],
		[eye + r * 1.6 + f * 0.0 + up * 0.15, eye - r * 0.3 - f * 0.4 - up * 0.4],
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
