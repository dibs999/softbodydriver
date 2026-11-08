extends Node3D
## Main menu: vehicle + map selection with a live soft-body preview of the selected car.

var world: SBWorld
var preview_car: SBVehicle
var cam: Camera3D
var cam_angle := 0.6
var car_list: ItemList
var info_label: RichTextLabel
var map_option: OptionButton
var map_info: Label


func _ready() -> void:
	_build_scene()
	_build_ui()
	var idx := 0
	for i in Game.cars.size():
		if Game.cars[i]["path"] == Game.selected_car:
			idx = i
	if Game.cars.size() > 0:
		car_list.select(idx)
		_on_car_selected(idx)


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.18, 0.24, 0.34)
	sm.sky_horizon_color = Color(0.55, 0.6, 0.66)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.11)
	sm.ground_horizon_color = Color(0.45, 0.47, 0.5)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4, 3, -4)
	fill.omni_range = 14
	fill.light_energy = 0.6
	add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 0.1
	floor_mesh.mesh = cyl
	floor_mesh.position = Vector3(0, -0.05, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.17, 0.18)
	fm.metallic = 0.2
	fm.roughness = 0.35
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	world = SBWorld.new()
	world.material_library = Game.make_material_library()
	add_child(world)
	world.add_ground_plane(1.0)

	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)

	var title := Label.new()
	title.text = "SOFTBODY DRIVER"
	title.add_theme_font_size_override("font_size", 46)
	title.position = Vector2(40, 26)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "Node-Beam-Physik mit 2000 Hz · echte Verformung · Kühlung, Öl & Motorschaden"
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.position = Vector2(44, 86)
	root.add_child(sub)

	var panel := PanelContainer.new()
	panel.position = Vector2(40, 130)
	panel.custom_minimum_size = Vector2(430, 640)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var h1 := Label.new()
	h1.text = "Fahrzeug"
	h1.add_theme_font_size_override("font_size", 22)
	v.add_child(h1)
	car_list = ItemList.new()
	car_list.custom_minimum_size = Vector2(400, 150)
	for c in Game.cars:
		car_list.add_item(c["name"])
	car_list.item_selected.connect(_on_car_selected)
	v.add_child(car_list)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(400, 120)
	v.add_child(info_label)

	var h2 := Label.new()
	h2.text = "Karte"
	h2.add_theme_font_size_override("font_size", 22)
	v.add_child(h2)
	map_option = OptionButton.new()
	for m in Game.MAPS:
		map_option.add_item(m["name"])
	map_option.item_selected.connect(_on_map_selected)
	v.add_child(map_option)
	map_info = Label.new()
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.custom_minimum_size = Vector2(400, 40)
	v.add_child(map_info)
	for i in Game.MAPS.size():
		if Game.MAPS[i]["id"] == Game.selected_map:
			map_option.select(i)
			_on_map_selected(i)

	var h3 := Label.new()
	h3.text = "Fahrhilfen"
	h3.add_theme_font_size_override("font_size", 22)
	v.add_child(h3)
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for key in [["tcs", "Traktionskontrolle"], ["abs", "ABS"], ["automatic", "Automatikgetriebe"],
			["steering_assist", "Lenkhilfe (geschwindigkeitsabh.)"], ["traffic", "KI-Verkehr"]]:
		var cb := CheckBox.new()
		cb.text = key[1]
		cb.button_pressed = Game.settings[key[0]]
		cb.toggled.connect(func(on): Game.settings[key[0]] = on)
		grid.add_child(cb)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var start := Button.new()
	start.text = "  Losfahren  "
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(_on_start)
	buttons.add_child(start)
	var quit := Button.new()
	quit.text = "  Beenden  "
	quit.add_theme_font_size_override("font_size", 22)
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)
	start.grab_focus()

	var hint := Label.new()
	hint.text = "W/S Gas/Bremse · A/D Lenken · Leertaste Handbremse · C Kamera · B Node-Beam-Ansicht · R Reset · F1 Hilfe"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(44, 860)
	root.add_child(hint)


func _on_car_selected(i: int) -> void:
	var c: Dictionary = Game.cars[i]
	Game.selected_car = c["path"]
	info_label.text = "[b]%s[/b]  %s\n%s\n\n[color=#9ab]Motor:[/color] %s · %.0f kW · %.0f Nm\n[color=#9ab]Antrieb:[/color] %s   [color=#9ab]Masse:[/color] %.0f kg" % [
		c["name"], c["brand"], c["description"], c["engine"], c["power"], c["torque"], c["layout"], c["mass"]]
	if preview_car:
		world.remove_vehicle(preview_car)
		preview_car = null
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(-30)), Vector3.ZERO)
	preview_car = Game.spawn_vehicle(world, c["path"], xf)
	if preview_car:
		preview_car.set_input(0, 1, 0, 1)


func _on_map_selected(i: int) -> void:
	Game.selected_map = Game.MAPS[i]["id"]
	map_info.text = Game.MAPS[i]["description"]


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _process(delta: float) -> void:
	cam_angle += delta * 0.15
	var target := Vector3(0, 0.7, 0)
	if preview_car:
		target = preview_car.get_chase_target()
	cam.position = target + Vector3(cos(cam_angle) * 6.5, 1.6, sin(cam_angle) * 6.5)
	cam.look_at(target + Vector3(0, -0.15, 0), Vector3.UP)
