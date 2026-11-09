extends SceneTree
## Close-up renders of the city facade shader: godot -s res://tests/facade_shots.gd -- <out.png> [style] [debug]
const City := preload("res://scripts/maps/city.gd")
var frame := 0
var out := "/tmp/facade.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var style := int(args[1]) if args.size() > 1 else 1
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = GameSky.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var colors := [Color(0.62, 0.58, 0.51), Color(0.55, 0.33, 0.24), Color(0.47, 0.49, 0.5)]
	var mat: ShaderMaterial = City._facade_material(colors[style % 3], Color(0.92, 0.92, 0.9), style)
	if args.size() > 2:
		mat.set_shader_parameter("debug", int(args[2]))
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_scale(Vector3(30, 18, 12)), Vector3(0, 9, -12))
	root3d.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 60
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(-9, 1.7, 6), Vector3(4, 6, -6))
	cam.current = true

func _process(_d: float) -> bool:
	frame += 1
	if frame == 8:
		root.get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
