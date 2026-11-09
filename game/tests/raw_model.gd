extends SceneTree
## Renders a glTF model directly (no physics) for comparison: godot -s res://tests/raw_model.gd -- model out.png

var frame := 0
func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var args := OS.get_cmdline_user_args()
		var s := Node3D.new()
		root.add_child(s)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		var sky := Sky.new()
		sky.sky_material = GameSky.new()
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		s.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 35, 0)
		sun.shadow_enabled = true
		s.add_child(sun)
		var m: Node3D = load(args[0]).instantiate()
		m.rotation_degrees = Vector3(0, 60, 0)
		s.add_child(m)
		var cam := Camera3D.new()
		s.add_child(cam)
		cam.position = Vector3(4.5, 1.6, 4.5)
		cam.look_at(Vector3(0, 0.5, 0))
		cam.current = true
	if frame == 30:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[1])
		return true
	return false
