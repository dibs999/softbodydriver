extends SceneTree
## Renders the menu thumbnails of every vehicle: godot -s res://tests/thumbnails.gd [-- <car_id>]
## Output: res://ui/cars/<id>.png (studio three-quarter view, 480x270).
var frame := 0
var queue: Array = []
var world: SBWorld
var car: SBVehicle
var cam: Camera3D
var current := ""
var settle := 0

func _initialize() -> void:
	var game := root.get_node("Game")
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("17191c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("9aa3ad")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.fog_enabled = true
	e.fog_light_color = Color("17191c")
	e.fog_density = 0.035
	e.fog_sky_affect = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.environment = e
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.7
	rim.light_color = Color("ffd9b0")
	stage.add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2a2d31")
	fm.roughness = 0.55
	floor_mesh.material_override = fm
	stage.add_child(floor_mesh)
	world = SBWorld.new()
	world.material_library = game.make_material_library()
	stage.add_child(world)
	world.add_ground_plane(1.0)
	cam = Camera3D.new()
	cam.fov = 30
	stage.add_child(cam)
	cam.current = true

func _process(_d: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		var args := OS.get_cmdline_user_args()
		for c in root.get_node("Game").cars:
			if args.is_empty() or str(c["id"]) in args:
				queue.append(c)
	if car == null:
		if queue.is_empty():
			return true
		var c: Dictionary = queue.pop_front()
		current = str(c["id"])
		car = root.get_node("Game").spawn_vehicle(world, c["path"], Transform3D(Basis(Vector3.UP, deg_to_rad(-28)), Vector3.ZERO))
		world.step_blocking(1.5)
		world.sync_visuals()
		world.time_scale = 0.0
		settle = 0
		var target := car.get_position_ws()
		target.y = float(car.get_info().get("height", 1.45)) * 0.42
		var length := float(car.get_info().get("length", 4.4))
		var dist := length * 1.42
		var f := car.get_forward()
		f.y = 0
		var r := car.get_right()
		r.y = 0
		var dir := (f.normalized() * 0.62 + r.normalized() * 0.78).normalized()
		cam.look_at_from_position(target + dir * dist + Vector3.UP * dist * 0.18, target, Vector3.UP)
		return false
	settle += 1
	if settle == 6:
		var img := root.get_viewport().get_texture().get_image()
		img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path("res://ui/cars/%s.png" % current))
		print("thumbnail ", current)
		world.remove_vehicle(car)
		car = null
	return false
