extends SceneTree
## Drives a car into a wall and renders the deformed body: godot -s res://tests/crash.gd -- <out> [car]

var frame := 0
var cam: Camera3D
var world: SBWorld
var car: SBVehicle
var prefix := "/tmp/crash"
var shots := 0
var impact_frame := -1

func _initialize() -> void:
	pass

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	var path := args[1] if args.size() > 1 else "res://cars/aurora_sedan.car.json"
	var game := root.get_node("Game")
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -60, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 60)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.37)
	floor.material_override = fm
	scene.add_child(floor)
	world = SBWorld.new()
	world.material_library = game.make_material_library()
	scene.add_child(world)
	world.add_ground_plane(1.0)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 8)
	wall.mesh = bm
	wall.position = Vector3(41, 1.5, 1.0)
	scene.add_child(wall)
	world.add_box(Vector3(41, 1.5, 1.0), Vector3(1, 1.5, 4), Vector3.ZERO, 0.8)
	car = world.spawn_car(path, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	car.set_tcs(true)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
		return false
	# Physics runs in real time on its own thread; drive with full throttle until 55 km/h.
	var kmh := car.get_speed_kmh()
	if impact_frame < 0:
		car.set_input(1.0 if kmh < 55.0 else 0.0, 0, 0, 0)
	var p := car.get_position_ws()
	cam.position = p + Vector3(-3.5, 2.2, -5.5)
	cam.look_at(p + Vector3(1.2, 0.4, 0))
	if impact_frame < 0 and p.x > 30.0 and p.x < 30.5:
		root.get_viewport().get_texture().get_image().save_png(prefix + "_pre.png")
	if impact_frame < 0 and p.x > 36.5:
		impact_frame = frame
		print("impact at %.1f km/h" % kmh)
	if impact_frame > 0 and frame == impact_frame + 40:
		car.set_input(0, 1, 0, 1)
		cam.position = p + Vector3(5.5, 3.2, -4.0)
		cam.look_at(p + Vector3(1.0, 0.6, 0))
	if impact_frame > 0 and frame == impact_frame + 42:
		root.get_viewport().get_texture().get_image().save_png(prefix + "_0.png")
		var t := car.get_telemetry()
		print("after crash: front %.0f%% radiator %.0f%% status '%s' deformed %d broken %d" % [t["zones"][0] * 100, t["radiator_damage"] * 100, t["status"], t["deformed_beams"], t["broken_beams"]])
		car.set_debug_view(true)
		car.set_body_visible(false)
	if impact_frame > 0 and frame == impact_frame + 45:
		root.get_viewport().get_texture().get_image().save_png(prefix + "_1.png")
		return true
	return frame > 3000
