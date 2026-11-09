extends SceneTree
## Close-up renders of the procedural vegetation: godot -s res://tests/vegetation_shots.gd -- <out.png>
const V := preload("res://scripts/maps/vegetation.gd")
const C := preload("res://scripts/maps/common.gd")
var frame := 0
var out := "/tmp/vegetation.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = GameSky.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	ground.material_override = C.surface_material("grass", 3.1, Color(0.50, 0.66, 0.50))
	root3d.add_child(ground)
	var kinds := ["broadleaf", "conifer", "poplar", "bush", "dry_shrub"]
	for k in kinds.size():
		var pts: Array[Vector3] = []
		for j in 3:
			pts.append(Vector3(-24 + k * 12, 0, -10 - j * 14))
		V.plant(root3d, kinds[k], pts, 3 + k)
	var tufts: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	for i in 6000:
		tufts.append(Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-50, 14)))
	V.grass(root3d, tufts, 7)
	var cam := Camera3D.new()
	cam.fov = 60
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 16), Vector3(0, 5, -14))
	cam.current = true

func _process(_d: float) -> bool:
	frame += 1
	if frame == 12:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
