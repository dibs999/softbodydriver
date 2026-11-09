extends Node3D
## Main menu: vehicle + map selection with a live soft-body preview of the selected car.

var world: SBWorld
var preview_car: SBVehicle
var cam: Camera3D
var cam_angle := 1.12
var car_list: ItemList
var car_name: Label
var car_info: Label
var car_stats: Array[Label] = []
var map_option: OptionButton
var progress_info: Label
var map_info: Label
var _settings_panel: PanelContainer
var _stage: VBoxContainer
var _preview_area: Control
var _env: Environment
var _sun: DirectionalLight3D

const INK := Color("0b1820")
const PANEL := Color("132a33")
const BORDER := Color("29434b")
const TEXT := Color("eef2f6")
const MUTED := Color("a6b6c7")
const ACCENT := Color("71e0cb")


func _ready() -> void:
	_build_scene()
	_apply_graphics()
	Game.graphics_preset_changed.connect(_apply_graphics)
	_build_ui()
	var idx := 0
	for i in Game.cars.size():
		if Game.cars[i]["path"] == Game.selected_car:
			idx = i
	if Game.cars.size() > 0:
		car_list.select(idx)
		car_list.ensure_current_is_visible()
		_on_car_selected(idx)


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("24364a")
	sm.sky_horizon_color = Color("53657b")
	sm.ground_bottom_color = Color("111823")
	sm.ground_horizon_color = Color("3b4d63")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_env = e

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.5
	add_child(sun)
	_sun = sun
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4, 3, -4)
	fill.omni_range = 14
	fill.light_energy = 0.85
	fill.light_color = Color("b4d4ff")
	add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 0.1
	floor_mesh.mesh = cyl
	floor_mesh.position = Vector3(0, -0.05, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("2d3946")
	fm.roughness = 0.72
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.95
	ring.outer_radius = 2.98
	ring.rings = 64
	ring.ring_segments = 8
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.mesh = ring
	ring_mesh.position.y = 0.014
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color("4c988d")
	ring_mesh.material_override = ring_material
	add_child(ring_mesh)

	world = SBWorld.new()
	world.material_library = Game.make_material_library()
	add_child(world)
	world.add_ground_plane(1.0)

	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)


func _apply_graphics() -> void:
	Game.apply_environment_graphics(_env, _sun)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := MarginContainer.new()
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = _menu_theme()
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 20)
	root.add_theme_constant_override("margin_bottom", 16)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	root.add_child(layout)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _box(INK, BORDER, 14, 15))
	layout.add_child(header)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	header.add_child(title_row)
	var mark := ColorRect.new()
	mark.color = ACCENT
	mark.custom_minimum_size.x = 4
	title_row.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	title_row.add_child(titles)
	titles.add_child(_label("DRIVE / EXPLORE / BREAK", 11, ACCENT))
	titles.add_child(_label("Softbody Driver", 32, TEXT, true))
	var exit := Button.new()
	exit.text = "Beenden"
	exit.custom_minimum_size = Vector2(92, 34)
	exit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exit.pressed.connect(func(): get_tree().quit())
	title_row.add_child(exit)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	_settings_panel = PanelContainer.new()
	_settings_panel.add_theme_stylebox_override("panel", _box(INK, BORDER, 14, 14))
	body.add_child(_settings_panel)
	var setup := VBoxContainer.new()
	setup.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(setup)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	v.add_child(_label("DEINE GARAGE", 13, ACCENT, true))
	car_list = ItemList.new()
	car_list.custom_minimum_size.y = 140
	for c in Game.cars:
		car_list.add_item(c["name"])
	car_list.item_selected.connect(_on_car_selected)
	v.add_child(car_list)

	v.add_child(_label("DEIN ZIEL", 13, ACCENT, true))
	map_option = OptionButton.new()
	map_option.custom_minimum_size.y = 36
	for m in Game.MAPS:
		map_option.add_item(m["name"])
	map_option.item_selected.connect(_on_map_selected)
	v.add_child(map_option)
	map_info = _label("", 13, MUTED)
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.custom_minimum_size.y = 40
	v.add_child(map_info)
	for i in Game.MAPS.size():
		if Game.MAPS[i]["id"] == Game.selected_map:
			map_option.select(i)
			_on_map_selected(i)

	var settings_toggle := Button.new()
	settings_toggle.text = "Fahrhilfen & Darstellung  +"
	v.add_child(settings_toggle)
	var options := VBoxContainer.new()
	options.visible = false
	options.add_theme_constant_override("separation", 10)
	v.add_child(options)
	settings_toggle.pressed.connect(func():
		options.visible = not options.visible
		settings_toggle.text = "Fahrhilfen & Darstellung  −" if options.visible else "Fahrhilfen & Darstellung  +"
	)
	options.add_child(Game.make_audio_options())
	options.add_child(Game.make_graphics_options())
	options.add_child(Game.make_driving_help_option())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	options.add_child(grid)
	for key in [["tcs", "Traktionskontrolle"], ["abs", "ABS"], ["automatic", "Automatikgetriebe"],
			["steering_assist", "Lenkhilfe"], ["traffic", "KI-Verkehr"]]:
		var cb := Game.make_driving_option(key[0], key[1])
		cb.add_theme_font_size_override("font_size", 13)
		if key[0] == "steering_assist":
			cb.tooltip_text = "Glättet Tastatureingaben und begrenzt Lenkeinschlag bei Tempo. Aus: direkte Lenkung für erfahrene Fahrer."
		grid.add_child(cb)

	var start := Button.new()
	start.text = "Losfahren  →"
	start.custom_minimum_size.y = 48
	start.theme_type_variation = &"DriveButton"
	start.disabled = Game.cars.is_empty()
	start.pressed.connect(_on_start)
	setup.add_child(start)
	var lesson_button := Button.new()
	lesson_button.text = "Fahreinführung wiederholen" if Game.progress.is_completed("first_drive_complete") else "Fahreinführung · Fahren, Bremsen & Service"
	lesson_button.custom_minimum_size.y = 42
	lesson_button.disabled = Game.cars.is_empty()
	lesson_button.pressed.connect(func():
		Game.start_lesson = true
		Game.selected_map = "proving_grounds"
		Game.progress.set_selection(Game.selected_car, Game.selected_map)
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	setup.add_child(lesson_button)
	progress_info = Label.new()
	progress_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_info.add_theme_font_size_override("font_size", 12)
	setup.add_child(progress_info)
	if not start.disabled:
		start.grab_focus()

	_stage = VBoxContainer.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_theme_constant_override("separation", 9)
	body.add_child(_stage)
	var tag := PanelContainer.new()
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_theme_stylebox_override("panel", _box(INK, BORDER, 8, 9))
	tag.add_child(_label("DEIN NÄCHSTES ABENTEUER", 12, ACCENT, true))
	_stage.add_child(tag)
	_preview_area = Control.new()
	_preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_preview_area)
	var spec_card := PanelContainer.new()
	spec_card.add_theme_stylebox_override("panel", _box(INK, BORDER, 14, 15))
	_stage.add_child(spec_card)
	var specs := VBoxContainer.new()
	specs.add_theme_constant_override("separation", 7)
	spec_card.add_child(specs)
	car_name = _label("Fahrzeug auswählen", 26, TEXT, true)
	car_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	specs.add_child(car_name)
	car_info = _label("", 13, MUTED)
	car_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	specs.add_child(car_info)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	specs.add_child(stats)
	for title in ["LEISTUNG", "DREHMOMENT", "MASSE"]:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 8, 8))
		stats.add_child(chip)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 0)
		chip.add_child(content)
		content.add_child(_label(title, 11, MUTED))
		var value := _label("–", 18, TEXT, true)
		content.add_child(value)
		car_stats.append(value)

	var footer := HBoxContainer.new()
	layout.add_child(footer)
	var hint := _label("W/S  Gas & Bremse     A/D  Lenken     C  Kamera     F1  Hilfe     F3  Aktivitäten", 13, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var credits_button := Button.new()
	credits_button.text = "Quellen & Lizenzen"
	footer.add_child(credits_button)
	credits_button.pressed.connect(func():
		var dialog := AcceptDialog.new()
		dialog.title = "Audio- und Bildquellen"
		dialog.theme = _menu_theme()
		dialog.theme.set_stylebox("embedded_border", &"Window", _box(INK, BORDER, 12, 12))
		dialog.theme.set_color("title_color", &"Window", TEXT)
		dialog.min_size = Vector2i(580, 380)
		add_child(dialog)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.selection_enabled = true
		text.custom_minimum_size = Vector2(560, 350)
		text.text = FileAccess.get_file_as_string("res://ASSET_CREDITS.md")
		var links := RegEx.new()
		links.compile("\\[([^\\]]+)\\]\\((https://[^)]+)\\)")
		text.text = links.sub(text.text, "[url=$2]$1[/url]", true)
		links.compile("(?m)^#{1,3} (.+)$")
		text.text = links.sub(text.text, "[b]$1[/b]", true)
		text.meta_clicked.connect(func(url): OS.shell_open(str(url)))
		dialog.add_child(text)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(600, 420)))
	get_viewport().size_changed.connect(_layout_preview)
	_layout_preview()


func _layout_preview() -> void:
	var window_size := get_viewport().get_visible_rect().size
	_stage.visible = window_size.x >= 720.0 and window_size.y >= 470.0
	_settings_panel.custom_minimum_size.x = clampf(window_size.x * 0.30, 290.0, 410.0)
	_settings_panel.size_flags_horizontal = Control.SIZE_FILL if _stage.visible else Control.SIZE_EXPAND_FILL
	car_list.custom_minimum_size.y = 130.0 if window_size.y < 590.0 else 204.0


func _label(value: String, font_size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		var font := FontVariation.new()
		font.base_font = ThemeDB.fallback_font
		font.variation_embolden = 0.65
		label.add_theme_font_override("font", font)
	return label


func _box(color: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style


func _menu_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	var focus := _box(Color.TRANSPARENT, ACCENT, 7, 6)
	focus.draw_center = false
	for kind in [&"Button", &"OptionButton"]:
		theme.set_stylebox("normal", kind, _box(PANEL, BORDER, 8, 8))
		theme.set_stylebox("hover", kind, _box(Color("233141"), Color("4a6279"), 8, 8))
		theme.set_stylebox("pressed", kind, _box(Color("293b4d"), ACCENT, 8, 8))
		theme.set_stylebox("focus", kind, focus)
		theme.set_color("font_color", kind, TEXT)
	var check := _box(PANEL, BORDER, 6, 4)
	var check_hover := _box(Color("233141"), Color("4a6279"), 6, 4)
	theme.set_stylebox("normal", &"CheckBox", check)
	theme.set_stylebox("pressed", &"CheckBox", check)
	theme.set_stylebox("hover", &"CheckBox", check_hover)
	theme.set_stylebox("hover_pressed", &"CheckBox", check_hover)
	theme.set_stylebox("focus", &"CheckBox", focus)
	theme.set_stylebox("panel", &"ItemList", _box(PANEL, BORDER, 8, 6))
	theme.set_stylebox("selected", &"ItemList", _box(Color("344253"), ACCENT, 5, 2))
	theme.set_stylebox("selected_focus", &"ItemList", _box(Color("344253"), ACCENT, 5, 2))
	theme.set_stylebox("hovered", &"ItemList", _box(Color("233141"), BORDER, 5, 2))
	theme.set_stylebox("focus", &"ItemList", focus)
	theme.set_color("font_color", &"ItemList", MUTED)
	theme.set_color("font_selected_color", &"ItemList", TEXT)
	theme.set_constant("v_separation", &"ItemList", 5)
	theme.set_stylebox("panel", &"PopupMenu", _box(INK, BORDER, 8, 6))
	theme.set_stylebox("hover", &"PopupMenu", _box(Color("293b4d"), BORDER, 5, 2))
	theme.set_type_variation(&"DriveButton", &"Button")
	theme.set_stylebox("normal", &"DriveButton", _box(ACCENT, ACCENT, 8, 8))
	theme.set_stylebox("hover", &"DriveButton", _box(Color("a4f4df"), ACCENT, 8, 8))
	theme.set_stylebox("pressed", &"DriveButton", _box(Color("50bba8"), ACCENT, 8, 8))
	var drive_focus := _box(Color.TRANSPARENT, Color("fff0da"), 8, 6)
	drive_focus.draw_center = false
	theme.set_stylebox("focus", &"DriveButton", drive_focus)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		theme.set_color(state, &"DriveButton", INK)
	theme.set_font_size("font_size", &"DriveButton", 19)
	return theme


func _on_car_selected(i: int) -> void:
	var c: Dictionary = Game.cars[i]
	Game.selected_car = c["path"]
	if progress_info:
		var record: Dictionary = Game.progress.get_best_braking(str(c["id"]))
		progress_info.text = "Einführung abgeschlossen" if Game.progress.is_completed("first_drive_complete") else "Einführung optional · Fortschritt wird gespeichert"
		if Game.progress.is_completed("time_trial_complete"):
			progress_info.text += " · Zeitfahren abgeschlossen"
		if not record.is_empty():
			progress_info.text += "\nBremsrekord: %.1f m aus %.0f km/h" % [record["distance_m"], record["start_speed_kmh"]]
		if Game.progress.read_only:
			progress_info.text = "Fortschritt kann nicht gespeichert werden. Das vorhandene Profil bleibt erhalten."
	car_name.text = c["name"]
	car_info.text = "%s  ·  %s  ·  %s" % [c["engine"], c["layout"], c["description"]]
	car_stats[0].text = "%.0f kW" % c["power"]
	car_stats[1].text = "%.0f Nm" % c["torque"]
	car_stats[2].text = "%.0f kg" % c["mass"]
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
	Game.start_lesson = false
	Game.progress.set_selection(Game.selected_car, Game.selected_map)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _process(delta: float) -> void:
	cam_angle += delta * 0.15
	var target := Vector3(0, 0.7, 0)
	if preview_car:
		target = preview_car.get_chase_target()
	var viewport_size := get_viewport().get_visible_rect().size
	var preview_rect := _preview_area.get_global_rect()
	var distance := 6.8
	if _stage.visible and preview_rect.size.x > 0.0 and preview_rect.size.y > 0.0:
		var available := minf(preview_rect.size.x, preview_rect.size.y * 1.8)
		distance *= maxf(1.0, 0.84 * viewport_size.y / available)
	cam.position = target + Vector3(cos(cam_angle) * distance, distance * 0.22, sin(cam_angle) * distance)
	cam.look_at(target - Vector3.UP * 0.22, Vector3.UP)
	var shift := preview_rect.get_center() - viewport_size * 0.5 if _stage.visible else Vector2.ZERO
	var world_per_pixel := 2.0 * distance * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, viewport_size.y)
	cam.h_offset = -shift.x * world_per_pixel
	cam.v_offset = shift.y * world_per_pixel
