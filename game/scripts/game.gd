extends Node3D
## Gameplay scene: map, vehicles (player + AI traffic), cameras, HUD, audio, input and pause menu.

const MapBuilder := preload("res://scripts/map_builder.gd")
const AIDriver := preload("res://scripts/ai_driver.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")
const Hud := preload("res://scripts/hud.gd")
const VehicleAudio := preload("res://scripts/vehicle_audio.gd")

var world: SBWorld
var map_data: Dictionary
var vehicles: Array[SBVehicle] = []
var ai: Dictionary = {}            # SBVehicle -> AIDriver
var player: SBVehicle
var cam: Camera3D
var hud: Control
var audio: Node
var pause_menu: Control
var _reverse_hold := 0.0
var _time_scales := [1.0, 0.5, 0.25, 0.1]
var _time_idx := 0


func _ready() -> void:
	_build_environment()
	world = SBWorld.new()
	world.name = "SBWorld"
	world.material_library = Game.make_material_library()
	add_child(world)
	var maproot := Node3D.new()
	maproot.name = "Map"
	add_child(maproot)
	if Game.selected_map == "hill_roads":
		map_data = MapBuilder.build_hill_roads(world, maproot)
	else:
		map_data = MapBuilder.build_proving_grounds(world, maproot)

	player = Game.spawn_vehicle(world, Game.selected_car, map_data["spawns"][0])
	if player == null:
		push_error("Failed to spawn %s" % Game.selected_car)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	vehicles.append(player)
	_apply_settings(player)
	if Game.settings["traffic"]:
		var others := Game.cars.filter(func(c): return c["path"] != Game.selected_car)
		var spawns: Array = map_data.get("ai_spawns", [])
		for i in mini(spawns.size(), others.size()):
			var v := Game.spawn_vehicle(world, others[i]["path"], spawns[i])
			if v:
				vehicles.append(v)
				ai[v] = AIDriver.new(v, map_data["waypoints"], map_data["speeds"], 0.9)

	cam = CameraRig.new()
	cam.current = true
	add_child(cam)
	cam.target = player

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = world
	ui.add_child(hud)
	hud.show_help = Game.settings["show_help"]
	audio = VehicleAudio.new()
	add_child(audio)
	_set_player(player)
	_build_pause_menu(ui)
	await get_tree().process_frame
	cam.snap()


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
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.7, 0.76, 0.85)
	e.fog_density = 0.00035
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func _apply_settings(v: SBVehicle) -> void:
	v.set_tcs(Game.settings["tcs"])
	v.set_abs(Game.settings["abs"])
	v.set_automatic(Game.settings["automatic"])


func _set_player(v: SBVehicle) -> void:
	player = v
	cam.target = v
	hud.vehicle = v
	hud.info = v.get_info()
	audio.vehicle = v
	audio.cylinders = int(hud.info.get("cylinders", 4))
	audio.redline = float(hud.info.get("redline_rpm", 6500))
	if ai.has(v):
		ai.erase(v)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not pause_menu.visible:
		_drive_player(delta)
	for v in ai.keys():
		ai[v].update(delta)
	for v in vehicles:
		var imp: float = v.take_impact()
		if imp > 2.0 and v == player:
			audio.impact(clampf(imp / 120.0, 0.05, 1.5))
			cam.shake = maxf(cam.shake, clampf(imp / 150.0, 0.0, 1.0))
	if map_data.has("waypoints") and player.get_position_ws().y < -30.0:
		player.reset_to(map_data["spawns"][0])


func _drive_player(delta: float) -> void:
	var t := player.get_telemetry()
	var kmh := float(t["speed_kmh"])
	var gear := int(t["gear"])
	var thr := Input.get_action_strength("throttle")
	var brk := Input.get_action_strength("brake")
	var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	if Game.settings["steering_assist"]:
		steer *= clampf(1.0 - kmh / 230.0, 0.32, 1.0)
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
	if event.is_action_pressed("menu"):
		_toggle_pause()
		return
	if pause_menu.visible:
		return
	if event.is_action_pressed("camera_next"):
		hud.camera_name = cam.cycle()
		hud.toast("Kamera: " + hud.camera_name)
	elif event.is_action_pressed("reset_vehicle"):
		player.reset_to(map_data["spawns"][0])
		cam.snap()
		hud.toast("Fahrzeug zurückgesetzt")
	elif event.is_action_pressed("repair_vehicle"):
		player.repair_in_place()
		hud.toast("Fahrzeug repariert")
	elif event.is_action_pressed("debug_view"):
		var on := not player.get_debug_view()
		player.set_debug_view(on)
		hud.toast("Node-Beam-Ansicht " + ("an" if on else "aus"))
	elif event.is_action_pressed("toggle_tcs"):
		player.set_tcs(not player.get_tcs())
		hud.toast("Traktionskontrolle " + ("an" if player.get_tcs() else "aus"))
	elif event.is_action_pressed("toggle_abs"):
		player.set_abs(not player.get_abs())
		hud.toast("ABS " + ("an" if player.get_abs() else "aus"))
	elif event.is_action_pressed("toggle_gearbox"):
		player.set_automatic(not player.is_automatic())
		hud.toast("Getriebe: " + ("Automatik" if player.is_automatic() else "Manuell (Q/E, Shift = Kupplung)"))
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
			hud.toast("Hindernis-Fahrzeug abgestellt")
	elif event.is_action_pressed("toggle_help"):
		hud.show_help = not hud.show_help
		Game.settings["show_help"] = hud.show_help


func _build_pause_menu(ui: CanvasLayer) -> void:
	pause_menu = PanelContainer.new()
	pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu.custom_minimum_size = Vector2(360, 300)
	pause_menu.position = Vector2(-180, -150)
	pause_menu.visible = false
	ui.add_child(pause_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_menu.add_child(v)
	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	for entry in [["Weiterfahren", _toggle_pause], ["Neu starten", func(): get_tree().reload_current_scene()],
			["Hauptmenü", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
			["Beenden", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(entry[1])
		v.add_child(b)


func _toggle_pause() -> void:
	pause_menu.visible = not pause_menu.visible
	world.paused = pause_menu.visible
	if pause_menu.visible:
		player.set_input(0, 0, 0, 0)
		(pause_menu.get_child(0).get_child(1) as Button).grab_focus()
