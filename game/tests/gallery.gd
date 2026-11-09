extends SceneTree
## Renders all cars side by side from several angles: godot -s res://tests/gallery.gd -- <out_prefix>

var frame := 0
var cam: Camera3D
var world: SBWorld
var cars: Array = []
var prefix := "/tmp/gallery"
var views := []

func _initialize() -> void:
	pass

func _setup() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		prefix = args[0]
	var game := root.get_node("Game")
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = GameSky.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.37)
	floor.material_override = fm
	scene.add_child(floor)
	world = SBWorld.new()
	world.material_library = game.make_material_library()
	scene.add_child(world)
	world.add_ground_plane(1.0)
	var i := 0
	for c in game.cars:
		var v: SBVehicle = game.spawn_vehicle(world, c["path"], Transform3D(Basis.IDENTITY, Vector3(0, 0, i * 3.2)))
		v.set_input(0, 1, 0, 1)
		cars.append(v)
		i += 1
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	views = []
	for k in cars.size():
		var z := k * 3.2
		views.append([Vector3(4.6, 1.5, z - 3.6), Vector3(0.0, 0.55, z)])
	views.append([Vector3(-4.8, 1.6, 3.2 * 2 + 3.4), Vector3(0.0, 0.6, 3.2 * 2)])
	views.append([Vector3(-4.8, 1.6, 3.2 * 3 + 3.4), Vector3(0.0, 0.6, 3.2 * 3)])
	cam.position = views[0][0]
	cam.look_at(views[0][1])

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
		return false
	var vi := (frame - 20) / 15
	if frame >= 20 and (frame - 20) % 15 == 0 and vi < views.size():
		cam.position = views[vi][0]
		cam.look_at(views[vi][1])
	if frame >= 20 and (frame - 20) % 15 == 14 and vi < views.size():
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [prefix, vi])
		print("saved view ", vi)
	return frame > 20 + 15 * views.size()
