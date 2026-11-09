extends Node
## Global game state (autoload "Game"): selected vehicle / map, settings and the input map.

const CARS_DIR := "res://cars"
const GRAPHICS_CONFIG := "user://graphics.cfg"

signal graphics_preset_changed
signal driving_help_changed(visible: bool)
signal driving_setting_changed(key: String, enabled: bool)

const DRIVING_SETTINGS := ["tcs", "abs", "automatic", "steering_assist", "traffic"]
# An explicit path also allows isolated profile tests without touching the player profile.
var settings_config_path := GRAPHICS_CONFIG

## Individual graphics options. Presets only fill these in; every option can be changed on its own.
## Options marked "map" take effect when a map is (re)loaded.
const GRAPHICS_OPTIONS := [
	{"key": "render_scale", "caption": "3D-Auflösung", "values": [0.5, 0.6, 0.67, 0.75, 0.8, 0.9, 1.0],
		"labels": ["50 %", "60 %", "67 %", "75 %", "80 %", "90 %", "100 %"]},
	{"key": "upscaler", "caption": "Hochskalierung", "values": [0, 1, 2], "labels": ["Bilinear", "AMD FSR 1", "AMD FSR 2"]},
	{"key": "aa", "caption": "Kantenglättung", "values": [0, 1, 2, 3, 4], "labels": ["Aus", "FXAA", "TAA", "MSAA 2×", "MSAA 4×"]},
	{"key": "shadows", "caption": "Schatten", "values": [0, 1, 2, 3], "labels": ["Aus", "Niedrig", "Mittel", "Hoch"]},
	{"key": "ssao", "caption": "Umgebungsverdeckung (SSAO)", "values": [false, true], "labels": ["Aus", "An"]},
	{"key": "glow", "caption": "Leuchteffekte", "values": [false, true], "labels": ["Aus", "An"]},
	{"key": "view_distance", "caption": "Sichtweite", "values": [600.0, 1200.0, 2500.0, 4000.0], "labels": ["Kurz", "Mittel", "Weit", "Maximal"]},
	{"key": "vegetation", "caption": "Bäume und Büsche", "values": [0.3, 0.6, 1.0], "labels": ["Wenig", "Mittel", "Voll"], "map": true},
	{"key": "grass", "caption": "Gras", "values": [0.0, 45.0, 85.0, 130.0], "labels": ["Aus", "Nah", "Normal", "Weit"], "map": true},
	{"key": "facades", "caption": "Fassaden", "values": [0, 1], "labels": ["Einfach", "Detailliert"]},
	{"key": "mirrors", "caption": "Spiegel", "values": [0, 1, 2], "labels": ["Aus", "Niedrig", "Hoch"]},
	{"key": "effects", "caption": "Partikel und Regen", "values": [0, 1], "labels": ["Reduziert", "Voll"]},
	{"key": "fps_limit", "caption": "Bildrate begrenzen", "values": [0, 30, 60, 120, 144], "labels": ["Aus", "30", "60", "120", "144"]},
	{"key": "vsync", "caption": "VSync", "values": [false, true], "labels": ["Aus", "An"]},
]

const GRAPHICS_PRESETS := [
	{"name": "Sehr niedrig", "hint": "Für schwache Laptops: 50 % Auflösung, ohne Schatten, Gras und Spiegel",
		"values": {"render_scale": 0.5, "upscaler": 1, "aa": 0, "shadows": 0, "ssao": false, "glow": false, "view_distance": 600.0,
			"vegetation": 0.3, "grass": 0.0, "facades": 0, "mirrors": 0, "effects": 0, "fps_limit": 60, "vsync": true}},
	{"name": "Niedrig", "hint": "67 % Auflösung mit FSR, einfache Schatten, wenig Vegetation",
		"values": {"render_scale": 0.67, "upscaler": 1, "aa": 1, "shadows": 1, "ssao": false, "glow": false, "view_distance": 1200.0,
			"vegetation": 0.6, "grass": 45.0, "facades": 0, "mirrors": 1, "effects": 0, "fps_limit": 60, "vsync": true}},
	{"name": "Mittel", "hint": "80 % Auflösung mit FSR, Schatten, volle Vegetation",
		"values": {"render_scale": 0.8, "upscaler": 1, "aa": 1, "shadows": 2, "ssao": false, "glow": false, "view_distance": 2500.0,
			"vegetation": 1.0, "grass": 85.0, "facades": 1, "mirrors": 1, "effects": 1, "fps_limit": 0, "vsync": true}},
	{"name": "Hoch", "hint": "Volle Auflösung, 4× MSAA, SSAO und Leuchteffekte",
		"values": {"render_scale": 1.0, "upscaler": 0, "aa": 4, "shadows": 3, "ssao": true, "glow": true, "view_distance": 2500.0,
			"vegetation": 1.0, "grass": 85.0, "facades": 1, "mirrors": 2, "effects": 1, "fps_limit": 0, "vsync": true}},
	{"name": "Ultra", "hint": "Wie Hoch, zusätzlich maximale Sichtweite und weites Gras",
		"values": {"render_scale": 1.0, "upscaler": 0, "aa": 4, "shadows": 3, "ssao": true, "glow": true, "view_distance": 4000.0,
			"vegetation": 1.0, "grass": 130.0, "facades": 1, "mirrors": 2, "effects": 1, "fps_limit": 0, "vsync": true}},
]
const CUSTOM_PRESET := -1

## Index into GRAPHICS_PRESETS, or CUSTOM_PRESET after individual changes.
var _graphics_preset: int = 2
var graphics: Dictionary = GRAPHICS_PRESETS[2]["values"].duplicate()

var cars: Array[Dictionary] = []          # {path, id, name, brand, description, ...}
var progress := preload("res://scripts/player_progress.gd").new()
var start_lesson := false
var selected_car := "res://cars/kestrel_hatch.car.json"
var selected_map := "proving_grounds"
var settings := {
	"tcs": true,
	"abs": true,
	"automatic": true,
	"steering_assist": true,     # speed sensitive steering limit
	"traffic": true,             # AI cars on the map
	"show_help": false,
	"master_volume": 0.8,
	"engine_volume": 0.8,
}

const MAPS := [
	{"id": "offroad", "name": "Wald & Weide · Offroad", "description": "Feldwege statt Asphalt: große Rundstrecke, Waldpfade, Höhenweg und Geröllpassage. Hof, Holzlager und Weideland. SUV oder Rallye-Auto empfohlen."},
	{"id": "proving_grounds", "name": "Testgelände", "description": "Über 1 km Oval, Handling-Parcours, Boxen, Sprungrampen und Crashwand."},
	{"id": "autobahn", "name": "Autobahn", "description": "8,5 km Autobahnring mit Raststätte, Lkw-Stellplatz, Windpark und Gegenverkehr."},
	{"id": "city", "name": "Stadt", "description": "Altstadtgasse, Werkstatthöfe, Hochstraße, Parkdeck und Markt. Mit Zeitfahren, Drifts und Lieferfahrten (F3)."},
	{"id": "desert", "name": "Wüste", "description": "Knapp 4 km Rallye-Schleife mit Sprüngen, Red-Mesa-Lager und Nebenroute zur alten Mine."},
	{"id": "hill_roads", "name": "Hügelland", "description": "Rund 2,5 km Landstraße durch Wald und Wiesen mit Gehöften und Aussichtspunkt."},
]


func _ready() -> void:
	load_settings()
	_apply_viewport_graphics()
	_setup_input()
	scan_cars()
	progress.load_profile()
	var selection: Dictionary = progress.get_selection()
	for car in cars:
		if car["path"] == selection.get("last_car", ""):
			selected_car = car["path"]
	for map in MAPS:
		if map["id"] == selection.get("last_map", ""):
			selected_map = map["id"]


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_config_path) == OK:
		var saved: Variant = config.get_value("graphics", "preset", _graphics_preset)
		if saved is int and saved >= CUSTOM_PRESET and saved < GRAPHICS_PRESETS.size():
			_graphics_preset = saved
			if saved >= 0:
				graphics = GRAPHICS_PRESETS[saved]["values"].duplicate()
		for option: Dictionary in GRAPHICS_OPTIONS:
			var value: Variant = config.get_value("graphics", option["key"], graphics[option["key"]])
			if typeof(value) == typeof(graphics[option["key"]]) or (value is float and graphics[option["key"]] is int) or (value is int and graphics[option["key"]] is float):
				graphics[option["key"]] = value
		var show_help: Variant = config.get_value("interface", "show_help", false)
		if show_help is bool:
			settings["show_help"] = show_help
		for key in ["master_volume", "engine_volume"]:
			var volume: Variant = config.get_value("audio", key, settings[key])
			if volume is float or volume is int:
				settings[key] = clampf(float(volume), 0.0, 1.0)
		for key in DRIVING_SETTINGS:
			var enabled: Variant = config.get_value("driving", key, settings[key])
			if enabled is bool:
				settings[key] = enabled


func set_driving_setting(key: String, enabled: bool) -> void:
	if key not in DRIVING_SETTINGS or settings[key] == enabled:
		return
	settings[key] = enabled
	driving_setting_changed.emit(key, enabled)
	_save_display_settings()


func make_driving_option(key: String, caption: String) -> CheckBox:
	var option := CheckBox.new()
	option.text = caption
	option.set_pressed_no_signal(settings[key])
	option.toggled.connect(func(enabled: bool): set_driving_setting(key, enabled))
	var refresh := func(changed_key: String, enabled: bool):
		if is_instance_valid(option) and changed_key == key:
			option.set_pressed_no_signal(enabled)
	driving_setting_changed.connect(refresh)
	option.tree_exiting.connect(func(): driving_setting_changed.disconnect(refresh), CONNECT_ONE_SHOT)
	return option


## Preset selector plus one row per option. Changing a single option switches to "Benutzerdefiniert".
func make_graphics_options() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var rows: Array[OptionButton] = []
	var preset_row := _option_row(box, "Voreinstellung")
	var preset := preset_row
	for p: Dictionary in GRAPHICS_PRESETS:
		preset.add_item(p["name"])
		preset.set_item_tooltip(preset.item_count - 1, p["hint"])
	preset.add_item("Benutzerdefiniert")
	var sync := func() -> void:
		preset.select(_graphics_preset if _graphics_preset >= 0 else GRAPHICS_PRESETS.size())
		for i in GRAPHICS_OPTIONS.size():
			var values: Array = GRAPHICS_OPTIONS[i]["values"]
			var current: Variant = graphics[GRAPHICS_OPTIONS[i]["key"]]
			var best := 0
			for k in values.size():
				if typeof(values[k]) == TYPE_BOOL or typeof(current) == TYPE_BOOL:
					if values[k] == current: best = k
				elif absf(float(values[k]) - float(current)) < absf(float(values[best]) - float(current)):
					best = k
			rows[i].select(best)
	preset.item_selected.connect(func(index: int):
		if index < GRAPHICS_PRESETS.size():
			_set_graphics_preset(index))
	for option: Dictionary in GRAPHICS_OPTIONS:
		var row := _option_row(box, option["caption"] + (" *" if option.get("map", false) else ""))
		for label: String in option["labels"]:
			row.add_item(label)
		var key: String = option["key"]
		var values: Array = option["values"]
		row.item_selected.connect(func(index: int): set_graphics_option(key, values[index]))
		rows.append(row)
	var note := Label.new()
	note.text = "* gilt beim nächsten Laden der Karte"
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(note)
	sync.call()
	graphics_preset_changed.connect(sync)
	box.tree_exiting.connect(func(): graphics_preset_changed.disconnect(sync), CONNECT_ONE_SHOT)
	return box


func _option_row(parent: Container, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 230
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var options := OptionButton.new()
	options.custom_minimum_size.x = 190
	row.add_child(options)
	return options


func set_graphics_option(key: String, value: Variant) -> void:
	if graphics.get(key) == value:
		return
	graphics[key] = value
	_graphics_preset = CUSTOM_PRESET
	for i in GRAPHICS_PRESETS.size():
		if GRAPHICS_PRESETS[i]["values"] == graphics:
			_graphics_preset = i
	_apply_viewport_graphics()
	graphics_preset_changed.emit()
	_save_display_settings()


func make_audio_options() -> VBoxContainer:
	var box := VBoxContainer.new()
	for entry in [["master_volume", "Gesamtlautstärke"], ["engine_volume", "Motorlautstärke"]]:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size.x = 140
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = settings[entry[0]]
		slider.custom_minimum_size.x = 100
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = entry[0]
		slider.value_changed.connect(func(value: float): settings[key] = value)
		slider.drag_ended.connect(func(_changed: bool): _save_display_settings())
		slider.focus_exited.connect(_save_display_settings)
		row.add_child(slider)
	return box


func _set_graphics_preset(preset: int) -> void:
	_graphics_preset = preset
	graphics = GRAPHICS_PRESETS[preset]["values"].duplicate()
	_apply_viewport_graphics()
	graphics_preset_changed.emit()
	_save_display_settings()


func make_driving_help_option() -> CheckBox:
	var option := CheckBox.new()
	option.text = "Steuerung einblenden (F1)"
	option.set_pressed_no_signal(settings["show_help"])
	option.toggled.connect(set_driving_help)
	driving_help_changed.connect(option.set_pressed_no_signal)
	return option


func set_driving_help(visible: bool) -> void:
	if settings["show_help"] == visible:
		return
	settings["show_help"] = visible
	driving_help_changed.emit(visible)
	_save_display_settings()


func _save_display_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_config_path)
	config.set_value("graphics", "preset", _graphics_preset)
	for key in graphics:
		config.set_value("graphics", key, graphics[key])
	config.set_value("interface", "show_help", settings["show_help"])
	for key in ["master_volume", "engine_volume"]:
		config.set_value("audio", key, settings[key])
	for key in DRIVING_SETTINGS:
		config.set_value("driving", key, settings[key])
	var err := config.save(settings_config_path)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


func _apply_viewport_graphics() -> void:
	var viewport := get_viewport()
	var advanced := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var scale := clampf(float(graphics["render_scale"]), 0.25, 1.0)
	var upscaler := int(graphics["upscaler"]) if advanced else 0
	if scale >= 0.999 and upscaler == 1: upscaler = 0
	viewport.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][upscaler]
	viewport.scaling_3d_scale = scale
	var aa := int(graphics["aa"])
	viewport.msaa_3d = Viewport.MSAA_4X if aa == 4 else (Viewport.MSAA_2X if aa == 3 else Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if advanced and aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = advanced and aa == 2 and upscaler != 2
	Engine.max_fps = int(graphics["fps_limit"])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if graphics["vsync"] else DisplayServer.VSYNC_DISABLED)
	RenderingServer.global_shader_parameter_set("facade_detail", float(graphics["facades"]))
	var shadows := int(graphics["shadows"])
	RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096][shadows], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][shadows])


func apply_environment_graphics(environment: Environment, sun: DirectionalLight3D) -> void:
	environment.ssao_enabled = bool(graphics["ssao"])
	environment.glow_enabled = bool(graphics["glow"])
	var shadows := int(graphics["shadows"])
	sun.shadow_enabled = shadows > 0
	sun.directional_shadow_max_distance = [0.0, 60.0, 120.0, 220.0][shadows]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadows < 3 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## Map-build time quality: share of trees/bushes kept, grass draw distance (0 = no grass).
func vegetation_density() -> float:
	return float(graphics.get("vegetation", 1.0))


func grass_distance() -> float:
	return float(graphics.get("grass", 85.0))


func view_distance() -> float:
	return float(graphics.get("view_distance", 2500.0))


func scan_cars() -> void:
	cars.clear()
	var dir := DirAccess.open(CARS_DIR)
	if dir == null:
		push_error("Cannot open %s" % CARS_DIR)
		return
	for f in dir.get_files():
		if not f.ends_with(".car.json"):
			continue
		var path := CARS_DIR + "/" + f
		var txt := FileAccess.get_file_as_string(path)
		var data = JSON.parse_string(txt)
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("Invalid car file %s" % path)
			continue
		var info := {
			"path": path,
			"id": data.get("id", f),
			"name": data.get("name", f),
			"brand": data.get("brand", ""),
			"description": data.get("description", ""),
			"engine": data.get("engine", {}).get("name", ""),
			"layout": data.get("engine", {}).get("layout", ""),
			"mass": data.get("chassis", {}).get("curbMass", 0.0),
			"paint": data.get("body", {}).get("paint", [0.5, 0.5, 0.5]),
			"paint_metallic": data.get("body", {}).get("paintMetallic", 0.5),
			"style": data.get("body", {}).get("style", ""),
			"length": data.get("body", {}).get("length", 4.3),
			"visual_model": data.get("visualModel", {}),
			"credits": data.get("credits", ""),
		}
		var peak_t := 0.0
		var peak_p := 0.0
		for p in data.get("engine", {}).get("torqueCurve", []):
			peak_t = maxf(peak_t, p[1])
			peak_p = maxf(peak_p, p[1] * p[0] * TAU / 60.0 / 1000.0)
		info["torque"] = peak_t
		info["power"] = peak_p
		cars.append(info)
	# Detailed (imported) models first, then the procedural ones; alphabetical within each group.
	cars.sort_custom(func(a, b):
		var da: bool = not (a["visual_model"] as Dictionary).is_empty()
		var db: bool = not (b["visual_model"] as Dictionary).is_empty()
		return a["name"] < b["name"] if da == db else da)
	print("SoftBodyDriver: %d vehicles found in %s" % [cars.size(), CARS_DIR])


func car_info(path: String) -> Dictionary:
	for c in cars:
		if c["path"] == path:
			return c
	return {}


## Spawns a car and, if its definition references a 3D model, replaces the procedural body with
## that model (bound to the soft-body nodes as a flexbody).
func spawn_vehicle(world: SBWorld, path: String, xform: Transform3D) -> SBVehicle:
	var v := world.spawn_car(path, xform)
	if v:
		apply_visual_model(v, car_info(path))
		var effects := preload("res://scripts/vehicle_effects.gd").new()
		effects.name = "VehicleEffects"
		effects.vehicle = v
		effects.world = world
		effects.dirt = selected_map == "desert"
		v.add_child(effects)
	return v


static func _axis(s: String) -> Vector3:
	var sign := -1.0 if s.begins_with("-") else 1.0
	match s.trim_prefix("-").trim_prefix("+"):
		"x": return Vector3(sign, 0, 0)
		"y": return Vector3(0, sign, 0)
	return Vector3(0, 0, sign)


static func _model_point(value: Variant) -> Variant:
	if value is Array and value.size() == 3 and value.all(func(component): return component is float or component is int):
		return Vector3(value[0], value[1], value[2])
	return null


func apply_visual_model(v: SBVehicle, info: Dictionary) -> void:
	var cfg: Dictionary = info.get("visual_model", {})
	if cfg.is_empty() or not cfg.has("path"):
		return
	var res = load(cfg["path"])
	if res == null or not (res is PackedScene):
		push_warning("Cannot load visual model %s" % cfg["path"])
		return
	var root: Node3D = res.instantiate()
	# Model axes -> car build axes (+x forward, +y up, +z right).
	var f := _axis(cfg.get("forward", "+z"))
	var u := _axis(cfg.get("up", "+y"))
	var r := f.cross(u)
	var rot := Basis(f, u, r).transposed()
	var wheel_names: Array = []
	for entry in cfg.get("wheels", {}).values():
		if entry is Array: wheel_names.append_array(entry)
		else: wheel_names.append(entry)
	var hide: Array = cfg.get("hide", [])
	var bounds := [Vector3.INF, -Vector3.INF]
	var wheel_bounds := [Vector3.INF, -Vector3.INF]
	_measure(root, Transform3D(rot, Vector3.ZERO), wheel_names, hide, false, bounds, wheel_bounds, true)
	var lo: Vector3 = bounds[0]
	var hi: Vector3 = bounds[1]
	var scale := float(cfg.get("scale", 1.0))
	if cfg.get("fitLength", false) and hi.x > lo.x:
		scale = float(info.get("length", 4.3)) / (hi.x - lo.x)
	var ground: float = wheel_bounds[0].y if wheel_bounds[0].y < INF else lo.y
	var offset := Vector3(-lo.x, -ground, -(lo.z + hi.z) * 0.5) * scale
	var xf := Transform3D(rot.scaled(Vector3(scale, scale, scale)), offset)
	var overrides := {}
	var lib := material_library()
	for k in cfg.get("materialOverrides", {}).keys():
		var target: String = cfg["materialOverrides"][k]
		if target == "paint" and lib.get("paint") is StandardMaterial3D:
			# Each car keeps its own colour from body.paint (the library paint is only the template).
			var own: StandardMaterial3D = (lib["paint"] as StandardMaterial3D).duplicate()
			var rgb: Array = info.get("paint", [])
			if rgb.size() >= 3:
				own.albedo_color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
			own.metallic = float(info.get("paint_metallic", own.metallic))
			overrides[k] = own
		elif lib.has(target):
			overrides[k] = lib[target]
	var options := {"wheels": cfg.get("wheels", {}), "hide": hide, "keep_procedural": cfg.get("keepProcedural", []),
		"material_overrides": overrides, "ao_on_uv2": bool(cfg.get("aoOnUV2", false)), "parts": cfg.get("parts", {})}
	var eye: Variant = _model_point(cfg.get("driverEye"))
	if eye is Vector3:
		options["driver_eye"] = xf * eye
	var dashboard: Variant = _model_point(cfg.get("dashboard"))
	if dashboard is Vector3:
		options["dashboard"] = xf * dashboard
	var steering: Variant = cfg.get("steeringWheel")
	if steering is Dictionary:
		var pivot: Variant = _model_point(steering.get("pivot"))
		var axis: Variant = _model_point(steering.get("axis"))
		var parts: Variant = steering.get("parts")
		if pivot is Vector3 and axis is Vector3 and not axis.is_zero_approx() and parts is Array:
			options["steering_wheel"] = {"pivot": xf * pivot, "axis": rot * axis, "parts": parts}
	v.attach_model(root, xf, options)
	root.free()


func _measure(n: Node, xf: Transform3D, wheel_names: Array, hide: Array, in_wheel: bool, bounds: Array, wheel_bounds: Array, is_root := false) -> void:
	var x := xf
	if n is Node3D and not is_root:
		x = xf * (n as Node3D).transform
	for h in hide:
		if not is_root and String(n.name).findn(h) >= 0:
			return
	var w := in_wheel or wheel_names.has(String(n.name))
	if n is MeshInstance3D and n.mesh:
		var a: AABB = x * (n as MeshInstance3D).mesh.get_aabb()
		var target: Array = wheel_bounds if w else bounds
		target[0] = target[0].min(a.position)
		target[1] = target[1].max(a.end)
	for c in n.get_children():
		_measure(c, x, wheel_names, hide, w, bounds, wheel_bounds)


# --------------------------------------------------------------------------- input
func _key(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _joy_button(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _action(name: String, deadzone := 0.2) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, deadzone)


func _setup_input() -> void:
	if not has_node("DriverPrompts"):
		var prompts := preload("res://scripts/driver_prompts.gd").new()
		prompts.name = "DriverPrompts"
		add_child(prompts)
	_action("throttle", 0.05); _key("throttle", [KEY_W, KEY_UP]); _joy_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_action("brake", 0.05); _key("brake", [KEY_S, KEY_DOWN]); _joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_action("steer_left", 0.08); _key("steer_left", [KEY_A, KEY_LEFT]); _joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_action("steer_right", 0.08); _key("steer_right", [KEY_D, KEY_RIGHT]); _joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_action("handbrake"); _key("handbrake", [KEY_SPACE]); _joy_button("handbrake", JOY_BUTTON_A)
	_action("clutch"); _key("clutch", [KEY_SHIFT]); _joy_button("clutch", JOY_BUTTON_X)
	_action("shift_up"); _key("shift_up", [KEY_E]); _joy_button("shift_up", JOY_BUTTON_RIGHT_SHOULDER)
	_action("shift_down"); _key("shift_down", [KEY_Q]); _joy_button("shift_down", JOY_BUTTON_LEFT_SHOULDER)
	_action("toggle_gearbox"); _key("toggle_gearbox", [KEY_M]); _joy_button("toggle_gearbox", JOY_BUTTON_DPAD_DOWN)
	_action("ignition"); _key("ignition", [KEY_I]); _joy_button("ignition", JOY_BUTTON_BACK)
	_action("reset_vehicle"); _key("reset_vehicle", [KEY_R]); _joy_button("reset_vehicle", JOY_BUTTON_B)
	_action("repair_vehicle"); _key("repair_vehicle", [KEY_BACKSPACE, KEY_INSERT])
	_action("camera_next"); _key("camera_next", [KEY_C]); _joy_button("camera_next", JOY_BUTTON_Y)
	_action("debug_view"); _key("debug_view", [KEY_B])
	_action("toggle_tcs"); _key("toggle_tcs", [KEY_T])
	_action("toggle_abs"); _key("toggle_abs", [KEY_Z, KEY_Y])
	_action("slow_motion"); _key("slow_motion", [KEY_J])
	_action("pause_physics"); _key("pause_physics", [KEY_P])
	_action("switch_vehicle"); _key("switch_vehicle", [KEY_TAB])
	_action("spawn_obstacle_car"); _key("spawn_obstacle_car", [KEY_F6])
	_action("toggle_help"); _key("toggle_help", [KEY_F1])
	_action("toggle_diagnostics"); _key("toggle_diagnostics", [KEY_F2])
	_action("activity_next"); _key("activity_next", [KEY_F3])
	_action("activity_start"); _key("activity_start", [KEY_F4])
	_action("map_overview"); _key("map_overview", [KEY_K])
	_action("map_compact"); _key("map_compact", [KEY_N])
	_action("menu"); _key("menu", [KEY_ESCAPE]); _joy_button("menu", JOY_BUTTON_START)
	_action("bonnet_release"); _key("bonnet_release", [KEY_O])
	_action("headlights"); _key("headlights", [KEY_L]); _joy_button("headlights", JOY_BUTTON_DPAD_UP)
	_action("wipers"); _key("wipers", [KEY_X])
	_action("indicator_left"); _key("indicator_left", [KEY_COMMA])
	_action("indicator_right"); _key("indicator_right", [KEY_PERIOD])
	_action("hazards"); _key("hazards", [KEY_H])
	_action("refuel"); _key("refuel", [KEY_F]); _joy_button("refuel", JOY_BUTTON_DPAD_LEFT)
	_action("service_repair"); _key("service_repair", [KEY_G]); _joy_button("service_repair", JOY_BUTTON_DPAD_RIGHT)
	_action("driver_door"); _key("driver_door", [KEY_U])
	_action("passenger_door")
	var passenger_door_key := InputEventKey.new()
	passenger_door_key.physical_keycode = KEY_U
	passenger_door_key.shift_pressed = true
	InputMap.action_add_event("passenger_door", passenger_door_key)
	_action("look_back"); _key("look_back", [KEY_V])


# --------------------------------------------------------------------------- materials
var _material_library := {}

func material_library() -> Dictionary:
	if _material_library.is_empty():
		_material_library = make_material_library()
	return _material_library


## Shared PBR material library handed to SBWorld (names match the C++ car generator).
func make_material_library() -> Dictionary:
	var lib := {}
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.6, 0.05, 0.04)
	paint.metallic = 0.5
	paint.roughness = 0.28
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.08
	lib["paint"] = paint

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.09, 0.42)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.3
	glass.roughness = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	lib["glass"] = glass

	lib["chrome"] = _metal(Color(0.85, 0.86, 0.88), 1.0, 0.12)
	lib["mirror"] = _metal(Color(0.9, 0.92, 0.95), 1.0, 0.02)
	lib["rim"] = _metal(Color(0.72, 0.73, 0.75), 0.9, 0.22)
	lib["brake_disc"] = _metal(Color(0.42, 0.41, 0.4), 0.85, 0.45)
	lib["engine"] = _metal(Color(0.32, 0.33, 0.35), 0.7, 0.55)
	lib["chassis"] = _metal(Color(0.08, 0.08, 0.085), 0.4, 0.7)
	lib["trim"] = _plastic(Color(0.03, 0.03, 0.035), 0.55)
	lib["seam"] = _plastic(Color(0.01, 0.01, 0.01), 0.9)
	lib["grille"] = _plastic(Color(0.02, 0.02, 0.025), 0.35)
	lib["interior"] = _plastic(Color(0.07, 0.07, 0.075), 0.85)
	lib["upholstery"] = _plastic(Color(0.24, 0.19, 0.145), 0.94)
	lib["tire"] = _plastic(Color(0.035, 0.035, 0.035), 0.92)
	lib["radiator"] = _metal(Color(0.15, 0.15, 0.16), 0.6, 0.5)
	lib["spring"] = _plastic(Color(0.75, 0.08, 0.06), 0.35)
	lib["caliper"] = _plastic(Color(0.78, 0.1, 0.06), 0.3)
	lib["plate"] = _plastic(Color(0.92, 0.92, 0.88), 0.4)

	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.9, 0.92, 0.95)
	head.metallic = 0.6
	head.roughness = 0.08
	head.emission_enabled = true
	head.emission = Color(1.0, 0.97, 0.9)
	head.emission_energy_multiplier = 1.2
	lib["headlight"] = head

	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.55, 0.02, 0.02)
	tail.roughness = 0.15
	tail.emission_enabled = true
	tail.emission = Color(0.9, 0.05, 0.03)
	tail.emission_energy_multiplier = 0.9
	lib["taillight"] = tail
	return lib


func _metal(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


func _plastic(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
