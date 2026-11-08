extends Node
## Global game state (autoload "Game"): selected vehicle / map, settings and the input map.

const CARS_DIR := "res://cars"
const GRAPHICS_CONFIG := "user://graphics.cfg"

signal graphics_preset_changed
signal driving_help_changed(visible: bool)

enum GraphicsPreset { PERFORMANCE, BALANCED, HIGH, NATIVE }

const GRAPHICS_PRESETS := [
	{"name": "Leistung", "scale": 0.60, "hint": "60 % 3D-Auflösung, ohne Schatten und Kantenglättung"},
	{"name": "Ausgewogen", "scale": 0.80, "hint": "80 % 3D-Auflösung mit FSR-Schärfung und Schatten"},
	{"name": "Hoch", "scale": 1.0, "hint": "Volle 3D-Auflösung, 4× MSAA, SSAO und Leuchteffekte"},
	{"name": "Scharf (nativ)", "scale": 1.0, "hint": "Volle 3D-Auflösung, Schatten und FXAA"},
]

var _graphics_preset: int = GraphicsPreset.BALANCED

var cars: Array[Dictionary] = []          # {path, id, name, brand, description, ...}
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
	var config := ConfigFile.new()
	if config.load(GRAPHICS_CONFIG) == OK:
		var saved: Variant = config.get_value("graphics", "preset", _graphics_preset)
		if saved is int and saved >= 0 and saved < GRAPHICS_PRESETS.size():
			_graphics_preset = saved
		var show_help: Variant = config.get_value("interface", "show_help", false)
		if show_help is bool:
			settings["show_help"] = show_help
		for key in ["master_volume", "engine_volume"]:
			var volume: Variant = config.get_value("audio", key, settings[key])
			if volume is float or volume is int:
				settings[key] = clampf(float(volume), 0.0, 1.0)
	_apply_viewport_graphics()
	_setup_input()
	scan_cars()


func make_graphics_options() -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Grafikqualität"
	row.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in GRAPHICS_PRESETS:
		options.add_item(preset["name"])
		options.set_item_tooltip(options.item_count - 1, preset["hint"])
	options.select(_graphics_preset)
	options.item_selected.connect(_set_graphics_preset)
	row.add_child(options)
	return row


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
	config.load(GRAPHICS_CONFIG)
	config.set_value("graphics", "preset", _graphics_preset)
	config.set_value("interface", "show_help", settings["show_help"])
	for key in ["master_volume", "engine_volume"]:
		config.set_value("audio", key, settings[key])
	var err := config.save(GRAPHICS_CONFIG)
	if err != OK:
		push_warning("Could not save display settings: %s" % error_string(err))


func _apply_viewport_graphics() -> void:
	var viewport := get_viewport()
	var high := _graphics_preset == GraphicsPreset.HIGH
	var balanced := _graphics_preset == GraphicsPreset.BALANCED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if balanced else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = GRAPHICS_PRESETS[_graphics_preset]["scale"]
	viewport.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if balanced or _graphics_preset == GraphicsPreset.NATIVE else Viewport.SCREEN_SPACE_AA_DISABLED


func apply_environment_graphics(environment: Environment, sun: DirectionalLight3D) -> void:
	var high := _graphics_preset == GraphicsPreset.HIGH
	environment.ssao_enabled = high
	environment.glow_enabled = high
	sun.shadow_enabled = _graphics_preset != GraphicsPreset.PERFORMANCE


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
	cars.sort_custom(func(a, b): return a["name"] < b["name"])
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
	var wheel_names: Array = cfg.get("wheels", {}).values()
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
		if lib.has(target):
			overrides[k] = lib[target]
	var options := {"wheels": cfg.get("wheels", {}), "hide": hide, "keep_procedural": cfg.get("keepProcedural", []),
		"material_overrides": overrides}
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
	_action("throttle", 0.05); _key("throttle", [KEY_W, KEY_UP]); _joy_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_action("brake", 0.05); _key("brake", [KEY_S, KEY_DOWN]); _joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_action("steer_left", 0.08); _key("steer_left", [KEY_A, KEY_LEFT]); _joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_action("steer_right", 0.08); _key("steer_right", [KEY_D, KEY_RIGHT]); _joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_action("handbrake"); _key("handbrake", [KEY_SPACE]); _joy_button("handbrake", JOY_BUTTON_A)
	_action("clutch"); _key("clutch", [KEY_SHIFT])
	_action("shift_up"); _key("shift_up", [KEY_E]); _joy_button("shift_up", JOY_BUTTON_RIGHT_SHOULDER)
	_action("shift_down"); _key("shift_down", [KEY_Q]); _joy_button("shift_down", JOY_BUTTON_LEFT_SHOULDER)
	_action("toggle_gearbox"); _key("toggle_gearbox", [KEY_M])
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
