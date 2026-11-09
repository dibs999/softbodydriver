extends Node3D
## Gameplay scene: map, vehicles (player + AI traffic), cameras, HUD, audio, input and pause menu.

const MapBuilder := preload("res://scripts/map_builder.gd")
const AIDriver := preload("res://scripts/ai_driver.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Hud := preload("res://scripts/hud.gd")
const VehicleAudio := preload("res://scripts/vehicle_audio.gd")
const Minimap := preload("res://scripts/minimap.gd")
const RoadSurface := preload("res://scripts/road_surface.gd")
const RoadMarks := preload("res://scripts/road_marks.gd")
const DrivingActivity := preload("res://scripts/driving_activity.gd")
const DriverPrompts := preload("res://scripts/driver_prompts.gd")
var equipment: Node3D
var weather: Node
var lesson: Node
var activity: DrivingActivity
var surfaces := RoadSurface.new()
var road_marks: RoadMarks

var world: SBWorld
var map_data: Dictionary
var vehicles: Array[SBVehicle] = []
var ai: Dictionary = {}            # SBVehicle -> AIDriver
var player: SBVehicle
var cam: Camera3D
var hud: Control
var minimap: Minimap
var _paused_before_map := false
var _paused_before_menu := false
var audio: Node
var pause_menu: Control
var _loading_overlay: CanvasLayer
var _reverse_hold := 0.0
var _time_scales := [1.0, 0.5, 0.25, 0.1]
var _time_idx := 0
var _pause_activity: OptionButton
var _pause_weather: OptionButton
var _pause_time: OptionButton
var _pause_clock: CheckBox
var _control_hint: Label


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		_show_loading_screen()
		await RenderingServer.frame_post_draw
	_build_environment()
	_apply_graphics()
	Game.graphics_preset_changed.connect(_apply_graphics)
	world = SBWorld.new()
	world.name = "SBWorld"
	world.paused = true
	world.material_library = Game.make_material_library()
	add_child(world)
	var maproot := Node3D.new()
	maproot.name = "Map"
	add_child(maproot)
	match Game.selected_map:
		"offroad":
			map_data = preload("res://scripts/maps/offroad.gd").build(world, maproot)
		"hill_roads":
			map_data = MapBuilder.build_hill_roads(world, maproot)
		"desert":
			map_data = preload("res://scripts/maps/desert.gd").build(world, maproot)
		"autobahn":
			map_data = preload("res://scripts/maps/autobahn.gd").build(world, maproot)
		"city":
			map_data = preload("res://scripts/maps/city.gd").build(world, maproot)
		_:
			map_data = MapBuilder.build_proving_grounds(world, maproot)
	_apply_map_environment(map_data.get("environment", {}))
	surfaces.configure(Game.selected_map, map_data)
	road_marks = RoadMarks.new()
	road_marks.world = world
	add_child(road_marks)

	player = Game.spawn_vehicle(world, Game.selected_car, map_data["spawns"][0])
	if player == null:
		push_error("Failed to spawn %s" % Game.selected_car)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	vehicles.append(player)
	_apply_settings(player)
	if Game.settings["traffic"]:
		var others := Game.cars.filter(func(c): return c["path"] != Game.selected_car)
		var routes: Array = map_data.get("ai_routes", [])
		if routes.is_empty():
			for sp in map_data.get("ai_spawns", []):
				routes.append({"waypoints": map_data["waypoints"], "speeds": map_data["speeds"], "spawn": sp})
		for i in mini(routes.size(), others.size()):
			var v := Game.spawn_vehicle(world, others[i]["path"], routes[i]["spawn"])
			if v:
				vehicles.append(v)
				ai[v] = AIDriver.new(v, routes[i]["waypoints"], routes[i]["speeds"], 0.9)

	cam = CameraRig.new()
	cam.current = true
	add_child(cam)
	cam.target = player
	weather = preload("res://scripts/world_weather.gd").new()
	add_child(weather)
	weather.configure(_env, _sun, cam, surfaces, world)
	weather.set_shelters(map_data.get("rain_shelters", []))
	equipment = preload("res://scripts/vehicle_equipment.gd").new()
	add_child(equipment)
	equipment.configure(self, map_data["spawns"][0])
	cam.equipment = equipment

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = world
	hud.equipment = equipment
	hud.weather = weather
	ui.add_child(hud)
	hud.show_help = Game.settings["show_help"]
	Game.driving_help_changed.connect(hud.set_driving_help)
	minimap = Minimap.new()
	ui.add_child(minimap)
	var map_title: String = Game.selected_map
	for entry in Game.MAPS:
		if entry["id"] == Game.selected_map:
			map_title = entry["name"]
			break
	var places: Array = map_data.get("map_places", []).duplicate()
	places.append({"name": "Service / Tankstelle", "position": equipment.bay})
	map_data["map_places"] = places
	minimap.configure(map_data, vehicles, map_title)
	audio = VehicleAudio.new()
	audio.world = world
	audio.dirt = Game.selected_map == "desert"
	add_child(audio)
	audio.set_process(false)
	world.sync_visuals()
	activity = DrivingActivity.new()
	activity.world = world
	add_child(activity)
	activity.configure(Game.selected_map, map_data)
	activity.completed.connect(_on_activity_completed)
	hud.activity = activity
	minimap.activity = activity
	for v in vehicles:
		_configure_effects(v)
	_set_player(player)
	lesson = preload("res://scripts/driving_lesson.gd").new()
	add_child(lesson)
	lesson.configure(self)
	lesson.milestone_completed.connect(func(id: String):
		if not Game.progress.complete_milestone(id): hud.toast("Fortschritt konnte nicht gespeichert werden"))
	lesson.brake_result.connect(func(distance: float, start_speed: float):
		Game.progress.record_braking(String(player.get_info()["id"]), distance, start_speed)
		if Game.progress.last_error != OK: hud.toast("Bremsrekord konnte nicht gespeichert werden"))
	hud.lesson = lesson
	minimap.lesson = lesson
	if Game.start_lesson:
		lesson.start()
		Game.start_lesson = false
	_build_pause_menu(ui)
	cam.snap()
	if _loading_overlay:
		await _warm_up_rendering()
		_loading_overlay.queue_free()
		_loading_overlay = null
	audio.set_process(true)
	world.paused = false


func _on_activity_completed(result: Dictionary) -> void:
	if int(result.get("mode", 0)) == 1:
		if not Game.progress.complete_milestone("time_trial_complete"):
			hud.toast("Zeitfahren beendet · Fortschritt konnte nicht gespeichert werden")
	if not bool(result.get("record_saved", true)):
		hud.toast("Ergebnis bleibt für diese Sitzung sichtbar · Rekord konnte nicht gespeichert werden")


func _show_loading_screen() -> void:
	_loading_overlay = CanvasLayer.new()
	_loading_overlay.layer = 10
	add_child(_loading_overlay)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.07, 0.08)
	_loading_overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption := Label.new()
	caption.text = "Karte wird geladen …"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 28)
	backdrop.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _warm_up_rendering() -> void:
	# Draw the spawn view and HUD behind the cover while Godot prepares their pipelines.
	var deadline := Time.get_ticks_msec() + 4000
	var quiet_since := Time.get_ticks_msec()
	var previous := -1
	var frames := 0
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_msec()
		var compiled := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
		compiled += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)
		if compiled != previous:
			previous = compiled
			quiet_since = now
		frames += 1
		if frames >= 4 and now - quiet_since >= 300:
			break


var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D


func _apply_map_environment(e: Dictionary) -> void:
	if e.is_empty():
		return
	if e.has("sky_top"):
		_sky_mat.sky_top_color = e["sky_top"]
	if e.has("horizon"):
		_sky_mat.sky_horizon_color = e["horizon"]
		_sky_mat.ground_horizon_color = e["horizon"]
	if e.has("fog"):
		_env.fog_light_color = e["fog"]
	if e.has("fog_density"):
		_env.fog_density = e["fog_density"]
	if e.has("sun"):
		_sun.rotation_degrees = e["sun"]
	if e.has("sun_energy"):
		_sun.light_energy = e["sun_energy"]
	if e.has("sun_color"):
		_sun.light_color = e["sun_color"]


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.45, 0.78)
	sm.sky_horizon_color = Color(0.66, 0.74, 0.84)
	sm.ground_horizon_color = Color(0.6, 0.65, 0.7)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	_sky_mat = sm
	_env = e
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0
	e.glow_intensity = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.76, 0.85)
	e.fog_density = 0.00035
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
	_sun = sun


func _apply_graphics() -> void:
	Game.apply_environment_graphics(_env, _sun)


func _apply_settings(v: SBVehicle) -> void:
	v.set_tcs(Game.settings["tcs"])
	v.set_abs(Game.settings["abs"])
	v.set_automatic(Game.settings["automatic"])


func _set_player(v: SBVehicle) -> void:
	_reverse_hold = 0.0
	if lesson: lesson.notify_interruption("Fahrzeug gewechselt")
	if activity:
		activity.cancel("")
		activity.vehicle = v
		activity._read_best()
	player = v
	cam.target = v
	for car in Game.cars:
		if car.get("id", "") == v.get_info().get("id", ""):
			var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(car["path"]))
			weather.set_vehicle_shelter(v, definition.get("body", {}) if definition is Dictionary else {})
			break
	hud.vehicle = v
	minimap.player = v
	hud.info = v.get_info()
	hud.in_dash_instruments = v.get_dashboard_transform() is Transform3D
	audio.configure(v, int(hud.info.get("cylinders", 4)))
	if ai.has(v):
		ai.erase(v)


func _process(delta: float) -> void:
	if _loading_overlay or player == null or not is_instance_valid(player):
		return
	if not pause_menu.visible:
		_drive_player(delta)
	for v in ai.keys():
		ai[v].update(delta)
	for v in vehicles:
		var imp: float = v.take_impact()
		if imp > 2.0 and v == player:
			audio.impact(clampf(imp / 120.0, 0.05, 1.5))
			activity.on_impact(imp)
			cam.shake = maxf(cam.shake, clampf(imp / 150.0, 0.0, 1.0))
	if map_data.has("waypoints") and player.get_position_ws().y < -30.0:
		_reverse_hold = 0.0
		lesson.notify_interruption("Fahrzeug außerhalb des Geländes")
		activity.cancel("Lauf abgebrochen: Bergung")
		if equipment.recover_to_service():
			cam.snap()
			hud.toast("Zum Service geborgen · Schäden und Tankinhalt bleiben erhalten")


func _drive_player(delta: float) -> void:
	if world.paused:
		_reverse_hold = 0.0
		return
	if activity and activity.active and activity.countdown > 0:
		player.set_input(0, 1, 0, 1)
		return
	var t := player.get_telemetry()
	var kmh := float(t["speed_kmh"])
	var gear := int(t["gear"])
	var thr := Input.get_action_strength("throttle")
	var brk := Input.get_action_strength("brake")
	var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	if Game.settings["steering_assist"]:
		steer = preload("res://scripts/steering_assist.gd").apply(steer, kmh, float(hud.info.get("wheelbase", 2.8)))
	var hb := Input.get_action_strength("handbrake")
	# Automatic gearbox: hold brake at standstill to engage reverse, throttle to go forward again.
	if player.is_automatic():
		if gear >= 0 and kmh < 2.0 and brk > 0.5 and thr < 0.1:
			_reverse_hold += delta
			if _reverse_hold > 0.35:
				player.set_gear(-1)
				_reverse_hold = 0.0
		elif gear < 0 and kmh < 2.0 and thr > 0.5 and brk < 0.1:
			_reverse_hold += delta
			if _reverse_hold > 0.2:
				player.set_gear(1)
				_reverse_hold = 0.0
		else:
			_reverse_hold = 0.0
		if gear < 0:
			var tmp := thr
			thr = brk
			brk = tmp
		if gear == 0 and thr > 0.2:
			player.set_gear(1)
	else:
		player.set_clutch(1.0 - Input.get_action_strength("clutch") if Input.is_action_pressed("clutch") else -1.0)
	# Auto start: pressing throttle on a stalled (not seized) engine cranks it.
	if not bool(t["running"]) and not bool(t["seized"]) and thr > 0.5 and String(t["status"]) != "OUT OF FUEL":
		player.start_engine()
	player.set_input(thr, brk, steer, hb)
	cam.look_back = Input.is_action_pressed("look_back")


func _unhandled_input(event: InputEvent) -> void:
	if _loading_overlay or player == null:
		return
	if minimap.overview_open:
		if event.is_action_pressed("menu") or event.is_action_pressed("map_overview"):
			minimap.toggle_overview()
			hud.show()
			world.paused = _paused_before_map
		return
	if event.is_action_pressed("menu"):
		_toggle_pause()
		return
	if event.is_action_pressed("toggle_help"):
		Game.set_driving_help(not hud.show_help)
		if hud.show_help:
			hud.show_diagnostics = false
		return
	if event.is_action_pressed("toggle_diagnostics"):
		hud.show_diagnostics = not hud.show_diagnostics
		if hud.show_diagnostics:
			Game.set_driving_help(false)
		return
	if pause_menu.visible:
		return
	if equipment.handle_action(event):
		return
	if event.is_action_pressed("map_overview"):
		_paused_before_map = world.paused
		world.paused = true
		hud.hide()
		minimap.toggle_overview()
	elif event.is_action_pressed("map_compact"):
		minimap.toggle_compact()
	elif event.is_action_pressed("camera_next"):
		hud.camera_name = cam.cycle()
		hud.cockpit = cam.mode == CameraRig.Mode.COCKPIT
		minimap.cockpit = hud.cockpit
		minimap._layout()
		audio.cockpit = hud.cockpit
		hud.toast("Kamera: " + hud.camera_name)
	elif event.is_action_pressed("reset_vehicle"):
		_reverse_hold = 0.0
		lesson.notify_interruption("Fahrzeug zurückgesetzt")
		activity.cancel("Lauf abgebrochen: Zurücksetzen")
		player.reset_to(map_data["spawns"][0])
		cam.snap()
		hud.toast("Fahrzeug zurückgesetzt")
	elif event.is_action_pressed("repair_vehicle"):
		_reverse_hold = 0.0
		lesson.notify_interruption("Sofortreparatur verwendet")
		activity.cancel("Lauf abgebrochen: Reparatur")
		player.repair_in_place()
		hud.toast("Fahrzeug repariert")
	elif event.is_action_pressed("debug_view"):
		var on := not player.get_debug_view()
		player.set_debug_view(on)
		hud.toast("Node-Beam-Ansicht " + ("an" if on else "aus"))
	elif event.is_action_pressed("activity_next"):
		lesson.notify_interruption("Andere Aktivität gewählt")
		activity.choose()
		minimap._layout()
		hud.toast(DrivingActivity.MODES[activity.mode])
	elif event.is_action_pressed("activity_start"):
		activity.start()
		cam.snap()
	elif event.is_action_pressed("toggle_tcs"):
		player.set_tcs(not player.get_tcs())
		Game.set_driving_setting("tcs", player.get_tcs())
		hud.toast("Traktionskontrolle " + ("an" if player.get_tcs() else "aus"))
	elif event.is_action_pressed("toggle_abs"):
		player.set_abs(not player.get_abs())
		Game.set_driving_setting("abs", player.get_abs())
		hud.toast("ABS " + ("an" if player.get_abs() else "aus"))
	elif event.is_action_pressed("toggle_gearbox"):
		_reverse_hold = 0.0
		player.set_automatic(not player.is_automatic())
		Game.set_driving_setting("automatic", player.is_automatic())
		player.set_clutch(-1.0)
		hud.toast("Getriebe: " + ("Automatik" if player.is_automatic() else "Manuell (%s/%s, %s = Kupplung)" % [DriverPrompts.hint("shift_down"), DriverPrompts.hint("shift_up"), DriverPrompts.hint("clutch")]))
	elif event.is_action_pressed("shift_up"):
		player.shift_up()
	elif event.is_action_pressed("shift_down"):
		player.shift_down()
	elif event.is_action_pressed("ignition"):
		var t := player.get_telemetry()
		if bool(t["running"]):
			player.set_ignition(false)
			hud.toast("Motor aus")
		else:
			player.start_engine()
			hud.toast("Motor starten …")
	elif event.is_action_pressed("slow_motion"):
		_time_idx = (_time_idx + 1) % _time_scales.size()
		world.time_scale = _time_scales[_time_idx]
		hud.toast("Zeit x%.2f" % world.time_scale)
	elif event.is_action_pressed("pause_physics"):
		world.paused = not world.paused
	elif event.is_action_pressed("switch_vehicle"):
		var i := (vehicles.find(player) + 1) % vehicles.size()
		var old := player
		_set_player(vehicles[i])
		if old != player and map_data.has("waypoints"):
			old.set_input(0, 0.5, 0, 0.5)
		cam.snap()
		hud.toast("Fahrzeug: " + String(hud.info.get("name", "")))
	elif event.is_action_pressed("spawn_obstacle_car"):
		var fwd := player.get_forward()
		var pos := player.get_position_ws() + Vector3(fwd.x, 0, fwd.z).normalized() * 28.0
		pos.y = maxf(0.0, pos.y - 0.4)
		var right := player.get_right()
		var path: String = Game.cars[randi() % Game.cars.size()]["path"]
		var v := Game.spawn_vehicle(world, path, MapBuilder.car_xform(pos, Vector3(right.x, 0, right.z)))
		if v:
			v.set_input(0, 1, 0, 1)
			vehicles.append(v)
			_configure_effects(v)
			hud.toast("Hindernis-Fahrzeug abgestellt")


func _build_pause_menu(ui: CanvasLayer) -> void:
	pause_menu = PanelContainer.new()
	# Share the garage palette and button states with the in-game menu.
	var palette := preload("res://scripts/main_menu.gd").new()
	pause_menu.theme = palette._menu_theme()
	pause_menu.add_theme_stylebox_override("panel", palette._box(Color("0b1820"), Color("29434b"), 18, 24))
	palette.free()
	pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu.custom_minimum_size = Vector2(460, 540)
	pause_menu.position = Vector2(-230, -270)
	pause_menu.visible = false
	ui.add_child(pause_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(412, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_menu.add_child(scroll)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for entry in [["Weiterfahren", _toggle_pause],
			["Fahrertür öffnen / schließen", func():
				equipment.toggle_door(0)
				_toggle_pause()],
			["Beifahrertür öffnen / schließen", func():
				equipment.toggle_door(1)
				_toggle_pause()],
			["Zum Service bergen · Schäden bleiben", func():
				lesson.notify_interruption("Bergung zum Service")
				activity.cancel("Lauf abgebrochen: Bergung")
				equipment.recover_to_service()
				cam.snap()
				_toggle_pause()],
			["Einführung starten / wiederholen", func():
				if Game.selected_map != "proving_grounds":
					Game.selected_map = "proving_grounds"
					Game.start_lesson = true
					get_tree().reload_current_scene()
					return
				activity.cancel("")
				activity.mode = 0
				lesson.start()
				_toggle_pause()],
			["Einführung ausblenden", func(): lesson.skip(); _toggle_pause()],
			["Neu starten", func(): get_tree().reload_current_scene()],
			["Hauptmenü", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
			["Beenden", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(entry[1])
		v.add_child(b)
	_pause_activity = _pause_choices(v, "Fahraktivität", DrivingActivity.MODES.slice(0, 4 if Game.selected_map == "city" else 3))
	_pause_activity.item_selected.connect(func(index: int):
		activity.cancel("")
		activity.mode = index
		activity._read_best()
		activity.message = "Im Pausenmenü starten" if index else "Freie Fahrt"
		if index: lesson.notify_interruption("Andere Aktivität gewählt")
		minimap._layout())
	var activity_button := Button.new()
	activity_button.text = "Auswahl starten / laufenden Versuch abbrechen"
	activity_button.add_theme_font_size_override("font_size", 14)
	activity_button.pressed.connect(func():
		if activity.mode > 0:
			activity.start()
			cam.snap()
		_toggle_pause())
	v.add_child(activity_button)
	_pause_weather = _pause_choices(v, "Wetter", weather.WEATHER_NAMES)
	_pause_weather.item_selected.connect(func(index: int): weather.weather_index = index; weather._apply_lighting())
	_pause_time = _pause_choices(v, "Tageszeit", weather.TIME_NAMES)
	_pause_time.item_selected.connect(func(index: int):
		weather.time_index = index
		weather.hour = weather.TIME_HOURS[index]
		weather._apply_lighting())
	_pause_clock = CheckBox.new()
	_pause_clock.text = "Tag und Nacht automatisch wechseln"
	_pause_clock.toggled.connect(func(enabled: bool): weather.automatic_time = enabled)
	v.add_child(_pause_clock)
	_control_hint = Label.new()
	_control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_control_hint.custom_minimum_size.x = 390
	_control_hint.add_theme_font_size_override("font_size", 13)
	_control_hint.text = DriverPrompts.control_summary()
	v.add_child(_control_hint)
	Game.get_node("DriverPrompts").device_changed.connect(func(): _control_hint.text = DriverPrompts.control_summary())
	v.add_child(Game.make_driving_option("steering_assist", "Lenkhilfe · Tastatur / Gamepad"))
	var steering_hint := Label.new()
	steering_hint.text = "An: sanfte Eingaben und weniger Lenkeinschlag bei Tempo.\nAus: direkte Lenkung für erfahrene Fahrer."
	steering_hint.add_theme_font_size_override("font_size", 12)
	steering_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steering_hint.custom_minimum_size.x = 390
	v.add_child(steering_hint)
	v.add_child(Game.make_graphics_options())
	v.add_child(Game.make_driving_help_option())
	v.add_child(Game.make_audio_options())

func _pause_choices(parent: VBoxContainer, caption: String, choices: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: String in choices: options.add_item(choice)
	row.add_child(options)
	parent.add_child(row)
	return options


func _configure_effects(v: SBVehicle) -> void:
	var effects := v.get_node_or_null("VehicleEffects")
	if effects:
		effects.surfaces = surfaces
		effects.marks = road_marks


func _toggle_pause() -> void:
	if not pause_menu.visible:
		_reverse_hold = 0.0
		_paused_before_menu = world.paused
	pause_menu.visible = not pause_menu.visible
	world.paused = true if pause_menu.visible else _paused_before_menu
	hud.visible = not pause_menu.visible
	minimap.visible = not pause_menu.visible and minimap._compact_visible
	if pause_menu.visible:
		_pause_activity.select(activity.mode)
		_pause_weather.select(weather.weather_index)
		_pause_time.select(weather.time_index)
		_pause_clock.set_pressed_no_signal(weather.automatic_time)
		player.set_input(0, 0, 0, 0)
		(pause_menu.get_child(0).get_child(0).get_child(1) as Button).grab_focus()
