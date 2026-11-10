extends Node3D
## Gameplay scene: map, vehicles (player + AI traffic), cameras, HUD, audio, input and pause menu.
const UITheme := preload("res://scripts/ui_theme.gd")

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
var wipers: Node3D
var cabin_closure: Node3D
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
var _pause_first_button: Button
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
				ai[v].others = vehicles
				ai[v].signals = map_data.get("traffic_signals")

	cam = CameraRig.new()
	cam.current = true
	cam.far = Game.view_distance()
	add_child(cam)
	cam.target = player
	weather = preload("res://scripts/world_weather.gd").new()
	add_child(weather)
	weather.configure(_env, _sun, cam, surfaces, world)
	weather.set_shelters(map_data.get("rain_shelters", []))
	wipers = preload("res://scripts/vehicle_wipers.gd").new()
	wipers.name = "Wipers"
	add_child(wipers)
	cabin_closure = preload("res://scripts/cabin_closure.gd").new()
	cabin_closure.name = "CabinClosure"
	add_child(cabin_closure)
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
var _sky_mat: GameSky
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
	var sm := GameSky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
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
	# Fog only hazes the sky slightly near the horizon; at sky_affect = 1 the infinitely distant
	# sky turned completely into flat fog colour.
	e.fog_sky_affect = 0.12
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
	if cam:
		cam.far = Game.view_distance()


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
			var body: Dictionary = definition.get("body", {}) if definition is Dictionary else {}
			weather.set_vehicle_shelter(v, body)
			# Imported models bring their own wiper geometry; procedural bodies get arms.
			var imported: bool = definition is Dictionary and definition.has("visualModel")
			wipers.attach(v, body, not imported)
			cabin_closure.attach(v if imported else null, body)
			break
	hud.vehicle = v
	minimap.player = v
	hud.info = v.get_info()
	hud.in_dash_instruments = v.get_dashboard_transform() is Transform3D
	audio.configure(v, int(hud.info.get("cylinders", 4)))
	if ai.has(v):
		ai.erase(v)


## Replay of the player's last 20 seconds (F5): physics pause, the car's recorded motion loops
## at real speed, any camera can watch it (the free camera too); F5 again resumes driving.
var _replay_frames := 0
var _replay_time := 0.0
var _replay_paused_before := false

func toggle_replay() -> void:
	if _replay_frames > 0:
		player.replay_end()
		_replay_frames = 0
		world.paused = _replay_paused_before
		hud.toast("Wiederholung beendet")
		return
	_replay_paused_before = world.paused
	_replay_frames = player.replay_begin()
	if _replay_frames < 2:
		player.replay_end()
		_replay_frames = 0
		hud.toast("Noch keine Aufzeichnung")
		return
	world.paused = true
	_replay_time = 0.0
	hud.toast("Wiederholung · letzte %d s · F5 beendet" % int(_replay_frames / 30.0))

func _process(delta: float) -> void:
	if _loading_overlay or player == null or not is_instance_valid(player):
		return
	if _replay_frames > 0:
		_replay_time = fmod(_replay_time + delta, _replay_frames / 30.0)
		player.replay_show(int(_replay_time * 30.0))
	if not pause_menu.visible:
		_drive_player(delta)
	if wipers:
		wipers.update(0.0 if world.paused else delta * world.time_scale, weather.weather_index == 2, weather.wetness)
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
	if cam.mode == CameraRig.Mode.FREE:
		player.set_input(0, 0, 0, 1)   # the driving keys fly the free camera
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
	# Parked: with the engine off and the car at rest, the parking brake holds it (like P on an
	# automatic). A recovered or switched-off car otherwise rolled away on the slightest slope.
	if not bool(t["running"]) and absf(kmh) < 3.0 and thr < 0.1:
		hb = 1.0
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
	elif event.is_action_pressed("wipers"):
		hud.toast(wipers.cycle_mode())
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
	elif event.is_action_pressed("camera_free"):
		hud.camera_name = cam.toggle_free()
		hud.cockpit = cam.mode == CameraRig.Mode.COCKPIT
		minimap.cockpit = hud.cockpit
		minimap._layout()
		audio.cockpit = hud.cockpit
		hud.toast("Kamera: " + hud.camera_name)
	elif event.is_action_pressed("replay"):
		toggle_replay()
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
	# Full-screen pause: dimmed game, action sidebar on the left, tabbed options on the right.
	pause_menu = Control.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.theme = UITheme.make()
	pause_menu.visible = false
	ui.add_child(pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(dim)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 40)
	pause_menu.add_child(row)
	var sidebar := PanelContainer.new()
	sidebar.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.74), 0, 28))
	sidebar.custom_minimum_size.x = 400
	row.add_child(sidebar)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	sidebar.add_child(side)
	side.add_child(UITheme.label("PAUSE", 32, UITheme.TEXT, true))
	var where := ""
	for m in Game.MAPS:
		if m["id"] == Game.selected_map: where = m["name"]
	var subtitle := UITheme.label(where, 14, UITheme.MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 22
	side.add_child(gap)
	_pause_first_button = null
	for entry in [["Weiterfahren", _toggle_pause],
			["Neu starten", func(): get_tree().reload_current_scene()],
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
			["Hauptmenü", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
			["Beenden", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.theme_type_variation = &"SideButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		side.add_child(b)
		if _pause_first_button == null: _pause_first_button = b
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(filler)
	side.add_child(UITheme.label("%s  Zurück zur Fahrt" % DriverPrompts.hint("menu"), 13, UITheme.MUTED))

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side_name in ["margin_top", "margin_bottom", "margin_right"]:
		margin.add_theme_constant_override(side_name, 48)
	row.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.04, 0.045, 0.88), 4, 6, UITheme.BORDER, 1))
	margin.add_child(panel)
	var tabs := TabContainer.new()
	panel.add_child(tabs)
	var page := func(title: String) -> VBoxContainer:
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 10)
		scroll.add_child(v)
		return v

	var vehicle_page: VBoxContainer = page.call("Fahrzeug")
	vehicle_page.add_child(UITheme.section("Türen und Ausstattung"))
	for entry in [["Fahrertür öffnen / schließen", func():
				equipment.toggle_door(0)
				_toggle_pause()],
			["Beifahrertür öffnen / schließen", func():
				equipment.toggle_door(1)
				_toggle_pause()],
			["Scheibenwischer umschalten", func():
				hud.toast(wipers.cycle_mode())
				_toggle_pause()]]:
		var b := Button.new()
		b.text = entry[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		vehicle_page.add_child(b)

	var drive_page: VBoxContainer = page.call("Fahrt & Umgebung")
	drive_page.add_child(UITheme.section("Aktivität"))
	_pause_activity = _pause_choices(drive_page, "Fahraktivität", DrivingActivity.MODES.slice(0, 4 if Game.selected_map == "city" else 3))
	_pause_activity.item_selected.connect(func(index: int):
		activity.cancel("")
		activity.mode = index
		activity._read_best()
		activity.message = "Im Pausenmenü starten" if index else "Freie Fahrt"
		if index: lesson.notify_interruption("Andere Aktivität gewählt")
		minimap._layout())
	var activity_button := Button.new()
	activity_button.text = "Auswahl starten / laufenden Versuch abbrechen"
	activity_button.pressed.connect(func():
		if activity.mode > 0:
			activity.start()
			cam.snap()
		_toggle_pause())
	drive_page.add_child(activity_button)
	drive_page.add_child(UITheme.section("Umgebung"))
	_pause_weather = _pause_choices(drive_page, "Wetter", weather.WEATHER_NAMES)
	_pause_weather.item_selected.connect(func(index: int): weather.weather_index = index; weather._apply_lighting())
	_pause_time = _pause_choices(drive_page, "Tageszeit", weather.TIME_NAMES)
	_pause_time.item_selected.connect(func(index: int):
		weather.time_index = index
		weather.hour = weather.TIME_HOURS[index]
		weather._apply_lighting())
	_pause_clock = CheckBox.new()
	_pause_clock.text = "Tag und Nacht automatisch wechseln"
	_pause_clock.toggled.connect(func(enabled: bool): weather.automatic_time = enabled)
	drive_page.add_child(_pause_clock)

	var settings_page: VBoxContainer = page.call("Einstellungen")
	settings_page.add_child(UITheme.section("Fahrhilfen"))
	settings_page.add_child(Game.make_driving_option("steering_assist", "Lenkhilfe · Tastatur / Gamepad"))
	var steering_hint := UITheme.label("An: sanfte Eingaben und weniger Lenkeinschlag bei Tempo.\nAus: direkte Lenkung für erfahrene Fahrer.", 13, UITheme.MUTED)
	steering_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_page.add_child(steering_hint)
	settings_page.add_child(Game.make_driving_help_option())
	settings_page.add_child(UITheme.section("Grafik"))
	settings_page.add_child(Game.make_graphics_options())
	settings_page.add_child(UITheme.section("Audio"))
	settings_page.add_child(Game.make_audio_options())

	var controls_page: VBoxContainer = page.call("Steuerung")
	_control_hint = UITheme.label(DriverPrompts.control_summary(), 15)
	_control_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_page.add_child(_control_hint)
	controls_page.add_child(UITheme.label("F1 im Fahrbetrieb zeigt alle Tasten.", 13, UITheme.MUTED))
	Game.get_node("DriverPrompts").device_changed.connect(func(): _control_hint.text = DriverPrompts.control_summary())

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
		_pause_first_button.grab_focus()
