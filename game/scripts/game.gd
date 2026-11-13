extends Node3D
## Gameplay scene: map, vehicles (player + AI traffic), cameras, HUD, audio, input and pause menu.
const Career := preload("res://scripts/career.gd")
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
var grabber: Node3D   # Ctrl + left mouse: pull a node of any car (node_grabber.gd)
var trailer: SBProp   # the box trailer (pause menu: Anhänger), coupled to the player's tow bar or parked
var trailer_load := 0.0   # kg of cargo on the trailer's deck (pause menu: Anhänger-Ladung)
const Workshop := preload("res://scripts/vehicle_workshop.gd")
const LSD_CHOICES := [["Original", -1.0], ["Offen", 0.0], ["Straße", 8.0], ["Sport", 20.0], ["Rennsport", 40.0]]
var _ws := {}   # Werkstatt controls by configuration key
var _ws_info: Label
var _ws_engine_ids: Array = []
var _trailer_was_coupled := false
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
var pedestrians: Node3D   # people on the city's footways (pedestrians.gd)
var _maproot: Node3D
var _travelling := false
var _fade: ColorRect
var props: Array[SBProp] = []          # loose cones and drums of the map
var _tune_front: HSlider
var _tune_rear: HSlider
var _tune_bias: HSlider
var ai: Dictionary = {}            # SBVehicle -> AIDriver
var player: SBVehicle
var cam: Camera3D
var hud: Control
var minimap: Minimap
var _paused_before_map := false
var _paused_before_menu := false
var audio: Node
var traffic_audio: Node3D   # 3D engine and tyre sound of the other cars
var _pause_first_button: Button
var pause_menu: Control
var _loading_overlay: CanvasLayer
var _reverse_hold := 0.0
var recovery: RefCounted = preload("res://scripts/recovery_trail.gd").new()   # where the player stood on its wheels lately (Pos1)
var _clutch_pedal := 0.0     # smoothed clutch pedal for the manual clutch (0 up, 1 down)
var _was_running := true
## Cruise control: target speed in km/h (< 0 off) and the speed controller's integral term.
var cruise_kmh := -1.0
var _cruise_i := 0.0
## Auto Hold (automatic gearbox): after braking to a stop, and at the start, the brakes hold the car
## until the driver accelerates, instead of it creeping away in gear.
var _auto_hold := true
var _last_brake_sim := -10.0   # simulation time the brake was last pressed (Auto Hold)
var _time_scales := [1.0, 0.5, 0.25, 0.1]
var _time_idx := 0
var _pause_activity: OptionButton
var _pause_weather: OptionButton
var _pause_time: OptionButton
var _pause_clock: CheckBox
var _control_hint: Label


func _ready() -> void:
	if Game.settings.get("career", false) and not Career.map_unlocked(Game.progress, Game.selected_map):
		Game.selected_map = "proving_grounds"   # the career has not opened this map yet
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
	_build_map()
	road_marks = RoadMarks.new()
	road_marks.world = world
	add_child(road_marks)
	_finish_ready()


## Traffic on the map's routes, one car of each other model.
func _spawn_traffic() -> void:
	if not Game.settings["traffic"]:
		return
	var others := Game.cars.filter(func(c): return c["path"] != Game.selected_car)
	var routes: Array = map_data.get("ai_routes", [])
	if routes.is_empty():
		for sp in map_data.get("ai_spawns", []):
			routes.append({"waypoints": map_data["waypoints"], "speeds": map_data["speeds"], "spawn": sp})
	for i in mini(routes.size(), others.size()):
		# A route may name its car (a 4x4 on the trails); otherwise traffic takes the next one.
		var v := Game.spawn_vehicle(world, routes[i].get("car", others[i]["path"]), routes[i]["spawn"])
		if v:
			vehicles.append(v)
			ai[v] = AIDriver.new(v, routes[i]["waypoints"], routes[i]["speeds"], 0.9)
			ai[v].others = vehicles
			ai[v].signals = map_data.get("traffic_signals")
			ai[v].reacts_to_crashes = true
			if equipment:   # a map change: the rest of the game is there already
				ai[v].lamps = equipment.state_for(v)
				ai[v].player = player
				_configure_effects(v)


## Through a tunnel at the edge of the map onto the next one: the screen goes dark, the old map
## (geometry, props, traffic, people) goes, the next one is built round the player's car, which
## comes out of the matching tunnel there at the speed it went in, with its damage, fuel and
## everything else as it was. map_data "exits": [{"to", "gate", "width"}], "entrances": {from: xform}.
func _check_exits() -> void:
	if _travelling or not is_instance_valid(player) or world.paused:
		return
	var p := player.get_position_ws()
	for e: Dictionary in map_data.get("exits", []):
		var local: Vector3 = (e["gate"] as Transform3D).affine_inverse() * p
		if local.z < 0.0 and local.z > -12.0 and absf(local.x) < float(e["width"]) * 0.5 + 1.0 and absf(local.y) < 6.0:
			var to := String(e["to"])
			if Game.settings.get("career", false) and not Career.map_unlocked(Game.progress, to):
				hud.toast("%s ist in der Karriere noch gesperrt" % _map_name(to))
				continue
			travel(to)
			return


func _map_name(id: String) -> String:
	for entry in Game.MAPS:
		if entry["id"] == id:
			return String(entry["name"])
	return id


func travel(to: String) -> void:
	if _travelling:
		return
	_travelling = true
	var from := Game.selected_map
	if activity and activity.active:
		activity.cancel("Karte verlassen")
	uncouple_trailer()
	if _fade == null:
		_fade = ColorRect.new()
		_fade.color = Color.BLACK
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.get_parent().add_child(_fade)
	_fade.modulate.a = 1.0
	_fade.show()
	await get_tree().process_frame
	var was_paused := world.paused
	world.paused = true
	# Everything of the old map but the player's car.
	for v in vehicles.duplicate():
		if v != player:
			vehicles.erase(v)
			ai.erase(v)
			world.remove_vehicle(v)
	_parked.clear()
	for prop in props:
		if is_instance_valid(prop):
			world.remove_prop(prop)
	props.clear()
	world.clear_colliders()
	if is_instance_valid(_maproot):
		_maproot.free()
	if is_instance_valid(pedestrians):
		pedestrians.free()
	pedestrians = null
	Game.selected_map = to
	_build_map()
	var entrances: Dictionary = map_data.get("entrances", {})
	var arrive: Transform3D = entrances.get(from, map_data["spawns"][0])
	player.relocate_to(arrive, entrances.has(from))
	weather.set_shelters(map_data.get("rain_shelters", []))
	equipment.configure(self, map_data["spawns"][0])
	var places: Array = map_data.get("map_places", []).duplicate()
	places.append({"name": "Service / Tankstelle", "position": equipment.bay})
	map_data["map_places"] = places
	minimap.configure(map_data, vehicles, _map_name(to))
	audio.dirt = to == "desert"
	activity.configure(to, map_data)
	_spawn_traffic()
	world.sync_visuals()
	cam.snap()
	world.paused = was_paused
	hud.toast(_map_name(to))
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_fade.hide)
	_travelling = false


## The selected map: its geometry, props, surfaces, light and its people.
func _build_map() -> void:
	var maproot := Node3D.new()
	maproot.name = "Map"
	add_child(maproot)
	_maproot = maproot
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
	if not (map_data.get("pedestrian_loops", []) as Array).is_empty():
		pedestrians = preload("res://scripts/pedestrians.gd").new()
		pedestrians.name = "Pedestrians"
		add_child(pedestrians)
		pedestrians.visible_max = 90 if int(Game.graphics.get("effects", 1)) == 0 else 220
		pedestrians.setup(self, map_data["pedestrian_loops"], 22)
	for p: Dictionary in map_data.get("props", []):
		var prop := Game.spawn_prop(world, String(p["kind"]), Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), p["position"]))
		if prop:
			props.append(prop)
	surfaces.configure(Game.selected_map, map_data)


func _finish_ready() -> void:

	if Game.settings.get("career", false):
		var info: Dictionary = Game.car_info(Game.selected_car)
		if not info.is_empty() and not Career.owns(Game.progress, str(info["id"])):
			Game.selected_car = "res://cars/%s.car.json" % Career.STARTER_CAR
	player = Game.spawn_vehicle(world, Game.selected_car, map_data["spawns"][0], true)
	if player == null:
		push_error("Failed to spawn %s" % Game.selected_car)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	Game.apply_chosen_paint(player)
	vehicles.append(player)
	_apply_settings(player)
	_neutral_for_own_clutch()
	_spawn_traffic()

	cam = CameraRig.new()
	cam.current = true
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP   # passing cars change pitch
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
	for v in ai:
		ai[v].lamps = equipment.state_for(v)
		ai[v].player = player
	grabber = preload("res://scripts/node_grabber.gd").new()
	grabber.name = "NodeGrabber"
	grabber.game = self
	add_child(grabber)
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
	traffic_audio = preload("res://scripts/traffic_audio.gd").new()
	traffic_audio.name = "TrafficAudio"
	traffic_audio.game = self
	add_child(traffic_audio)
	world.sync_visuals()
	activity = DrivingActivity.new()
	activity.world = world
	add_child(activity)
	activity.configure(Game.selected_map, map_data)
	activity.completed.connect(_on_activity_completed)
	activity.spawn_opponents = _spawn_opponents
	activity.release_opponents = _release_opponents
	activity.spawn_police = _spawn_police
	_ensure_contract()
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


## Career: charge `amount` for `what`; false (with a message) if the balance does not cover it.
## Outside the career everything is free.
func career_charge(amount: float, what: String) -> bool:
	if not Game.settings.get("career", false) or amount <= 0.0:
		return true
	if Game.progress.change_money(-amount):
		hud.toast("%s: −%s · Konto %s" % [what, Career.money_text(amount), Career.money_text(Game.progress.get_money())])
		return true
	hud.toast("%s kostet %s · Konto %s reicht nicht" % [what, Career.money_text(amount), Career.money_text(Game.progress.get_money())])
	return false


## Career: make sure this map has an open contract the map can actually offer.
func _ensure_contract() -> void:
	if not Game.settings.get("career", false) or not activity: return
	var modes: Array = activity.available_modes()
	var c: Dictionary = Game.progress.get_contract(Game.selected_map)
	if c.is_empty() or not int(c.get("mode", 0)) in modes:
		c = Career.make_contract(Game.selected_map, modes, int(c.get("serial", -1)) + 1, Game.progress.contracts_done())
		if c.is_empty() or not Game.progress.set_contract(Game.selected_map, c): return
	hud.toast("Auftrag: " + Career.contract_text(c))

func _on_activity_completed(result: Dictionary) -> void:
	if Game.settings.get("career", false):
		var pay := Career.payout(result)
		if pay > 0.0 and Game.progress.change_money(pay):
			hud.toast("Verdient: +%s · Konto %s" % [Career.money_text(pay), Career.money_text(Game.progress.get_money())])
		var contract: Dictionary = Game.progress.get_contract(Game.selected_map)
		if Career.fulfils(contract, result):
			var bonus := float(contract.get("bonus", 0.0))
			var next := Career.make_contract(Game.selected_map, activity.available_modes(), int(contract.get("serial", 0)) + 1, Game.progress.contracts_done() + 1)
			if Game.progress.complete_contract(Game.selected_map, bonus, next):
				hud.toast("Auftrag erfüllt: +%s Prämie" % Career.money_text(bonus))
				hud.toast("Neuer Auftrag: " + Career.contract_text(next))
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
	if is_instance_valid(player) and player != v:
		uncouple_trailer()
	_reverse_hold = 0.0
	recovery.clear()
	_auto_hold = true
	if lesson: lesson.notify_interruption("Fahrzeug gewechselt")
	if activity:
		activity.cancel("")
		activity.vehicle = v
		activity._read_best()
	player = v
	cam.target = v
	_neutral_for_own_clutch()
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


## Pause menu "Anhänger": hangs the box trailer on the tow bar (spawned behind the car the first
## time), unhitches it (it stays parked on its drawbar), or couples it again when the tow ball is
## within a metre of its hitch; otherwise it is fetched back behind the car.
func toggle_trailer() -> String:
	if absf(player.get_speed_kmh()) > 3.0:
		return "Zum An- und Abkuppeln anhalten"
	if is_instance_valid(trailer):
		if bool(world.get_coupling(trailer)["coupled"]):
			uncouple_trailer()
			return "Anhänger abgekuppelt"
		if trailer.get_hitch_position().distance_to(player.get_tow_position()) < 1.0 and world.couple_trailer(player, trailer):
			_trailer_was_coupled = true
			return "Anhänger angekuppelt"
		world.remove_prop(trailer)
		trailer = null
	var f := player.get_forward()
	f.y = 0.0
	f = f.normalized()
	var basis := Basis(f, Vector3.UP, f.cross(Vector3.UP))   # the trailer's +x along the car
	var tow := player.get_tow_position()
	var origin := tow - basis * Vector3(2.3, 0.45, 0.0)   # its hitch head on the tow ball
	origin.y = maxf(origin.y, player.get_position_ws().y)   # wheels on the ground, not in it
	trailer = Game.spawn_prop(world, "trailer", Transform3D(basis, origin))
	if trailer != null and trailer_load > 0.0:
		_apply_trailer_load()
	if trailer == null or not world.couple_trailer(player, trailer):
		return "Anhänger konnte nicht angekuppelt werden"
	_trailer_was_coupled = true
	return "Anhänger angekuppelt · Auflaufbremse folgt der Bremse"


## Pause menu "Anhänger-Ladung": empty, 250 kg or 500 kg of crated goods on the deck (a box
## trailer's payload is about 550 kg). The mass sits on the deck nodes slightly ahead of the axle,
## so the tongue load grows with it; braking distance and sway change accordingly.
const TRAILER_LOADS := [0.0, 250.0, 500.0]
func cycle_trailer_load() -> String:
	var i := TRAILER_LOADS.find(trailer_load)
	trailer_load = TRAILER_LOADS[(i + 1) % TRAILER_LOADS.size()]
	if not is_instance_valid(trailer):
		return "Anhänger-Ladung: %s (gilt beim nächsten Ankuppeln)" % _load_text()
	_apply_trailer_load()
	return "Anhänger-Ladung: %s" % _load_text()


func _load_text() -> String:
	return "leer" if trailer_load <= 0.0 else "%d kg" % int(trailer_load)


func _apply_trailer_load() -> void:
	trailer.set_load(trailer_load)
	var visual := trailer.get_node_or_null("TrailerVisual")
	if visual:
		visual.set_cargo(trailer_load)


## Unhitches before the car is moved by a reset, a recovery or a vehicle switch: the coupling
## would otherwise yank the trailer after it (or tear apart).
func uncouple_trailer() -> void:
	if is_instance_valid(trailer):
		world.uncouple_trailer(trailer)
		trailer.set_brake(1.0)   # parked: its brake holds it
	_trailer_was_coupled = false


func _update_trailer() -> void:
	if not is_instance_valid(trailer):
		return
	var visual := trailer.get_node_or_null("TrailerVisual")
	var coupling: Dictionary = world.get_coupling(trailer)
	if bool(coupling["coupled"]):
		# Overrun brake: the trailer brakes with the car.
		trailer.set_brake(float(player.get_telemetry().get("brake", 0.0)))
		if visual:
			visual.towing = player
			visual.lamp_state = equipment.state_for(player)
	elif visual:
		visual.towing = null
		visual.lamp_state = {}
	if _trailer_was_coupled and bool(coupling["broken"]):
		_trailer_was_coupled = false
		hud.toast("Anhängerkupplung abgerissen")


## Pos1: back to where the car last stood on its wheels a few seconds ago, upright and at rest,
## damage kept (BeamNG's "recover"). A timed run does not survive it, like a reset.
func recover_player() -> bool:
	if _replay_frames > 0:
		return false
	var pose: Variant = recovery.take(float(world.get_stats()["sim_time"]))
	if pose != null:
		uncouple_trailer()
	if pose == null or not player.relocate_to(pose):
		hud.toast("Keine frühere Position · %s setzt an den Start zurück" % DriverPrompts.hint("reset_vehicle"))
		return false
	_reverse_hold = 0.0
	set_cruise(false)
	lesson.notify_interruption("Fahrzeug zurückgestellt")
	activity.cancel("Lauf abgebrochen: Zurückstellen")
	_auto_hold = true
	cam.snap()
	hud.toast("Zurückgestellt · Schäden bleiben · nochmals drücken für weiter zurück")
	return true


## Replay of the player's last 20 seconds (F5): physics pause, the car's recorded motion loops
## at real speed, any camera can watch it (the free camera too); F5 again resumes driving.
var _replay_frames := 0
var _replay_time := 0.0
var _replay_paused_before := false
var _slow_physics := 0.0      # seconds the physics has lagged behind real time
var _slow_hint_given := false

## On a slow CPU the soft-body physics falls behind real time (the F2 page shows it as
## "Physik % Echtzeit"); every traffic car is a full soft body. After 8 s below 85 % with
## traffic on, say once where to switch it off.
func _watch_physics_load(delta: float) -> void:
	if _slow_hint_given or world.paused or world.time_scale < 0.99 or not Game.settings["traffic"] or ai.is_empty():
		return
	check_physics_load(delta, float(world.get_stats().get("realtime_factor", 1.0)))

## The decision itself, with the measured real-time factor passed in. Returns true when it shows
## the hint.
func check_physics_load(delta: float, rt: float) -> bool:
	if _slow_hint_given:
		return false
	_slow_physics = _slow_physics + delta if rt < 0.85 else maxf(0.0, _slow_physics - delta)
	if _slow_physics <= 8.0:
		return false
	_slow_hint_given = true
	hud.toast("Die Physik schafft nur %d %% Echtzeit · KI-Verkehr unter Einstellungen › Fahrhilfen ausschalten entlastet die CPU" % int(rt * 100.0))
	return true


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
	if _replay_frames == 0:
		recovery.record(player, float(world.get_stats()["sim_time"]))
	_update_trailer()
	_check_exits()
	_watch_physics_load(delta)
	if wipers:
		wipers.update(0.0 if world.paused else delta * world.time_scale, weather.weather_index == weather.RAIN, weather.wetness)
	var weather_speed: float = weather.TRAFFIC_SPEED[weather.weather_index]
	for v in ai.keys():
		ai[v].weather_speed = weather_speed
		ai[v].update(delta)
	for v in vehicles:
		var imp: float = v.take_impact()
		if ai.has(v):
			ai[v].on_impact(imp)
		if imp > 2.0 and v == player:
			audio.impact(clampf(imp / 120.0, 0.05, 1.5))
			activity.on_impact(imp)
			cam.shake = maxf(cam.shake, clampf(imp / 150.0, 0.0, 1.0))
	if map_data.has("waypoints") and player.get_position_ws().y < -30.0:
		_reverse_hold = 0.0
		lesson.notify_interruption("Fahrzeug außerhalb des Geländes")
		activity.cancel("Lauf abgebrochen: Bergung")
		_auto_hold = true
		uncouple_trailer()
		if equipment.recover_to_service():
			cam.snap()
			hud.toast("Zum Service geborgen · Schäden und Tankinhalt bleiben erhalten")


func _drive_player(delta: float) -> void:
	if audio: audio.horn = false
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
	# Reverse waits 0.8 s at a real standstill: braking to a stop from speed with the pedal still
	# down must stop the car, not roll it straight back (it engaged after 0.35 s below 2 km/h).
	if player.is_automatic():
		if gear >= 0 and kmh < 1.0 and brk > 0.5 and thr < 0.1:
			_reverse_hold += delta
			if _reverse_hold > 0.8:
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
		# Auto Hold engages when the car comes to rest under the brake. Measured in simulation time:
		# under load one frame can cover the last 0.1 s of a stop, and a brake released in that
		# frame left the car rolling in gear.
		var now_sim := float(world.get_stats()["sim_time"])
		if brk > 0.3:
			_last_brake_sim = now_sim
		if thr > 0.05:
			_auto_hold = false
		elif absf(kmh) < 0.8 and (brk > 0.3 or now_sim - _last_brake_sim < 0.5):
			_auto_hold = true
		# Like an electric parking brake taking over from Auto Hold: with the handbrake pulled, the
		# service brakes are released (holding with both preloaded the body enough that a rear door
		# could stop 2 deg short of its latch).
		if _auto_hold and thr <= 0.05 and absf(kmh) < 3.0 and hb < 0.5:
			brk = maxf(brk, 0.6)
	elif Game.settings["manual_clutch"]:
		# Clutch pedal with travel: a key pushes it down quickly and lets it come up over ~0.45 s
		# (an analogue trigger is followed as closely as the rate allows). Pedal up = engaged.
		var target := Input.get_action_strength("clutch")
		_clutch_pedal = move_toward(_clutch_pedal, target, (9.0 if target > _clutch_pedal else 2.2) * delta)
		player.set_clutch(1.0 - _clutch_pedal)
	else:
		player.set_clutch(1.0 - Input.get_action_strength("clutch") if Input.is_action_pressed("clutch") else -1.0)
	var running := bool(t["running"])
	var own_clutch: bool = not player.is_automatic() and Game.settings["manual_clutch"]
	if _was_running and not running and own_clutch and not bool(t["seized"]) and String(t["status"]) != "OUT OF FUEL":
		hud.toast("Motor abgewürgt · %s treten und Gas geben zum Starten" % DriverPrompts.hint("clutch"))
	_was_running = running
	# Auto start: pressing throttle on a stalled (not seized) engine cranks it. With the clutch in
	# the driver's foot only with the clutch down or in neutral, like a real starter interlock.
	var may_start: bool = not own_clutch or _clutch_pedal > 0.6 or gear == 0
	if not running and not bool(t["seized"]) and thr > 0.5 and String(t["status"]) != "OUT OF FUEL" and may_start:
		player.start_engine()
	# Parked: with the engine off and the car at rest, the parking brake holds it (like P on an
	# automatic). A recovered or switched-off car otherwise rolled away on the slightest slope.
	if not bool(t["running"]) and absf(kmh) < 3.0 and thr < 0.1:
		hb = 1.0
	thr = _cruise_throttle(thr, brk, kmh, gear, delta)
	player.set_input(thr, brk, steer, hb)
	cam.look_back = Input.is_action_pressed("look_back")
	if audio: audio.horn = Input.is_action_pressed("horn")


## With the clutch in the driver's foot, a car standing in gear would stall the moment it appears:
## spawn, reset and switching to the manual gearbox leave it in neutral.
func _neutral_for_own_clutch() -> void:
	_clutch_pedal = 0.0
	_was_running = true
	if player and not player.is_automatic() and Game.settings["manual_clutch"] \
			and absf(float(player.get_telemetry().get("speed_kmh", 0.0))) < 3.0:
		player.set_gear(0)


## Cruise control: holds the set speed with the throttle (PI on the speed error); more throttle
## from the driver overtakes and the speed comes back down afterwards. The brake, reverse, the
## manual clutch or a stalled engine switch it off.
func _cruise_throttle(thr: float, brk: float, kmh: float, gear: int, delta: float) -> float:
	if cruise_kmh < 0.0: return thr
	if brk > 0.1 or gear < 0 or Input.is_action_pressed("clutch") or not bool(player.get_telemetry()["running"]):
		set_cruise(false)
		return thr
	var err := cruise_kmh - kmh
	_cruise_i = clampf(_cruise_i + err * delta * 0.03, 0.0, 0.8)
	var hold := clampf(0.12 * err + _cruise_i, 0.0, 1.0)
	return maxf(thr, hold)

## Switch cruise control on at the current speed (from 30 km/h) or off. Returns whether it is on.
func set_cruise(on: bool) -> bool:
	var kmh := float(player.get_telemetry()["speed_kmh"]) if player else 0.0
	if on and kmh < 30.0:
		hud.toast("Tempomat ab 30 km/h")
		on = false
	var was := cruise_kmh > 0.0
	if on:
		cruise_kmh = roundf(kmh)
		_cruise_i = 0.25
		hud.toast("Tempomat %d km/h" % int(cruise_kmh))
	else:
		cruise_kmh = -1.0
		if was: hud.toast("Tempomat aus")
	hud.cruise_kmh = cruise_kmh
	return cruise_kmh > 0.0


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
	if event.is_action_pressed("cruise_control"):
		set_cruise(cruise_kmh < 0.0)
		return
	if event.is_action_pressed("siren"):
		var beacons := player.get_node_or_null("Beacons")
		if beacons:
			beacons.active = not beacons.active
			hud.toast("Sondersignal an" if beacons.active else "Sondersignal aus")
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
		set_cruise(false)
		lesson.notify_interruption("Fahrzeug zurückgesetzt")
		activity.cancel("Lauf abgebrochen: Zurücksetzen")
		uncouple_trailer()
		player.reset_to(map_data["spawns"][0])
		recovery.clear()
		_neutral_for_own_clutch()
		_auto_hold = true
		cam.snap()
		hud.toast("Fahrzeug zurückgesetzt")
	elif event.is_action_pressed("recover_vehicle"):
		recover_player()
	elif event.is_action_pressed("repair_vehicle"):
		# In the career an instant repair is towing plus the workshop bill.
		var bill := Career.repair_cost(player.get_telemetry())
		if Game.settings.get("career", false) and bill > 0.0 and not career_charge(bill + Career.RECOVERY_FEE, "Abschleppen und Reparatur"):
			return
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
		_neutral_for_own_clutch()
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
		activity.cancel("")   # a race's opponents leave before one of them could be picked
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


## Race opponents (Rennen): AI cars on the grid, removed again when the race ends.
func _spawn_opponents(grid: Array[Transform3D]) -> Array:
	var pick: Array = {"offroad": ["trailhead_4x4", "basalt_suv"], "desert": ["kestrel_rally", "trailhead_4x4"]}.get(
		Game.selected_map, ["kestrel_hatch", "aurora_sedan", "vortex_sprint"])
	# Traffic on the grid (or about to arrive there) moves half a lap away first.
	var start_area: Array[Vector3] = [player.get_position_ws()]
	for xf in grid: start_area.append(xf.origin)
	var moved := 0
	for v: SBVehicle in ai.keys():
		var driver = ai[v]
		var near := start_area.any(func(p: Vector3) -> bool: return p.distance_to(v.get_position_ws()) < 40.0)
		if near or start_area.any(func(p: Vector3) -> bool: return p.distance_to(driver.waypoints[driver.idx]) < 60.0):
			# Distinct slots half a lap from the start, so moved cars never land on each other.
			var n: int = driver.waypoints.size()
			var start_idx := 0
			for k in n:
				if driver.waypoints[k].distance_squared_to(start_area[0]) < driver.waypoints[start_idx].distance_squared_to(start_area[0]):
					start_idx = k
			var j: int = (start_idx + n / 2 + moved * 12) % n
			moved += 1
			v.reset_to(MapBuilder.car_xform(driver.waypoints[j], driver.waypoints[(j + 1) % n] - driver.waypoints[j]))
			driver.idx = j
	var drivers: Array = []
	for i in grid.size():
		var v := Game.spawn_vehicle(world, "res://cars/%s.car.json" % pick[i % pick.size()], grid[i])
		if v == null:
			continue
		vehicles.append(v)
		_configure_effects(v)
		var driver := AIDriver.new(v, map_data["waypoints"], map_data["speeds"], 1.0)
		driver.racing = true
		driver.hold = true
		driver.others = vehicles
		ai[v] = driver
		drivers.append(driver)
	return drivers


func _spawn_police(xf: Transform3D, fugitive: SBVehicle):
	var v := Game.spawn_vehicle(world, "res://cars/meridian_interceptor.car.json", xf)
	if v == null:
		return null
	vehicles.append(v)
	_configure_effects(v)
	var driver := AIDriver.new(v, map_data["waypoints"], map_data["speeds"], 1.0)
	driver.pursue = fugitive
	driver.others = vehicles
	ai[v] = driver
	var beacons := v.get_node_or_null("Beacons")
	if beacons: beacons.active = true
	return driver


func _release_opponents(drivers: Array) -> void:
	for driver in drivers:
		var v: SBVehicle = driver.vehicle
		ai.erase(v)
		vehicles.erase(v)
		if is_instance_valid(v) and v != player:
			world.remove_vehicle(v)


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
			["Auf letzte Position zurückstellen", func():
				_toggle_pause()
				recover_player()],
			["Zum Service bergen · Schäden bleiben", func():
				lesson.notify_interruption("Bergung zum Service")
				activity.cancel("Lauf abgebrochen: Bergung")
				_auto_hold = true
				uncouple_trailer()
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
			["Beenden", func(): Game.quit_cleanly()]]:
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
	_build_vehicle_picker(vehicle_page)
	vehicle_page.add_child(UITheme.section("Türen und Ausstattung"))
	for entry in [["Fahrertür öffnen / schließen", func():
				equipment.toggle_door(0)
				_toggle_pause()],
			["Beifahrertür öffnen / schließen", func():
				equipment.toggle_door(1)
				_toggle_pause()],
			["Hintertüren öffnen / schließen", func():
				if player.get_door_states().size() >= 4:
					equipment.toggle_door(2)
					player.toggle_door(3)
				else:
					hud.toast("Dieses Modell hat keine beweglichen Hintertüren")
				_toggle_pause()],
			["Motorhaube öffnen / schließen", func():
				equipment.release_bonnet()
				_toggle_pause()],
			["Heckklappe / Kofferraum öffnen / schließen", func():
				equipment.release_tailgate()
				_toggle_pause()],
			["Pylonen und Fässer zurückstellen", func():
				for p in props:
					if is_instance_valid(p): p.reset()
				hud.toast("Pylonen und Fässer stehen wieder an ihrem Platz" if not props.is_empty() else "Keine Pylonen oder Fässer auf dieser Karte")
				_toggle_pause()],
			["Anhänger ankuppeln / abkuppeln", func():
				hud.toast(toggle_trailer())
				_toggle_pause()],
			["Anhänger-Ladung: leer / 250 kg / 500 kg", func():
				hud.toast(cycle_trailer_load())
				_toggle_pause()],
			["Scheibenwischer umschalten", func():
				hud.toast(wipers.cycle_mode())
				_toggle_pause()]]:
		var b := Button.new()
		b.text = entry[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		vehicle_page.add_child(b)

	vehicle_page.add_child(UITheme.section("Abstimmung"))
	var retune := func(_v: float) -> void: _apply_tuning()
	_tune_front = _pause_slider(vehicle_page, "Reifendruck vorn", 18.0, 50.0, 0.5, "%.1f psi", retune)
	_tune_rear = _pause_slider(vehicle_page, "Reifendruck hinten", 18.0, 50.0, 0.5, "%.1f psi", retune)
	_tune_bias = _pause_slider(vehicle_page, "Bremskraft vorn", 50.0, 80.0, 1.0, "%.0f %%", retune)
	var reset_tuning := Button.new()
	reset_tuning.text = "Abstimmung auf Werkswerte"
	reset_tuning.alignment = HORIZONTAL_ALIGNMENT_LEFT
	reset_tuning.pressed.connect(func():
		var t: Dictionary = player.get_tuning()
		_tune_front.value = t["default_psi"]
		_tune_rear.value = t["default_psi"]
		_tune_bias.value = float(t["default_brake_bias"]) * 100.0
		_apply_tuning())
	vehicle_page.add_child(reset_tuning)

	_build_workshop(page.call("Werkstatt"))

	var drive_page: VBoxContainer = page.call("Fahrt & Umgebung")
	drive_page.add_child(UITheme.section("Aktivität"))
	var offered := activity.available_modes()
	_pause_activity = _pause_choices(drive_page, "Fahraktivität", offered.map(func(m: int): return DrivingActivity.MODES[m]))
	_pause_activity.item_selected.connect(func(index: int):
		activity.cancel("")
		activity.mode = offered[index]
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
	settings_page.add_child(Game.make_driving_option("manual_clutch", "Kupplung selbst treten (Schaltgetriebe, Motor kann abwürgen)"))
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

## Werkstatt page: parts and tuning for the player's car (vehicle_workshop.gd). The choices are
## stored per car and take effect when the car is rebuilt with "Übernehmen".
func _build_workshop(ws_page: VBoxContainer) -> void:
	var note := func(_v: Variant = null) -> void: _workshop_preview()
	ws_page.add_child(UITheme.section("Motor und Antrieb"))
	var engines: Array = Game.engine_catalogue()
	_ws_engine_ids = [""]
	var names: Array = ["Serienmotor"]
	for e: Dictionary in engines:
		_ws_engine_ids.append(e["id"])
		names.append("%s · %d kW · %d Nm (%s)" % [e["name"], int(round(e["power_kw"])), int(round(e["torque_nm"])), e["car"]])
	_ws["engine"] = _pause_choices(ws_page, "Motor", names)
	_ws["gearbox"] = _pause_choices(ws_page, "Getriebe", ["Eigenes Getriebe", "Getriebe des Spendermotors"])
	_ws["power"] = _pause_slider(ws_page, "Leistung (Kennfeld)", 70.0, 150.0, 5.0, "%.0f %%", note)
	_ws["boost"] = _pause_slider(ws_page, "Ladedruck", 0.0, 40.0, 5.0, "%+.0f %%", note)
	_ws["limiter"] = _pause_slider(ws_page, "Drehzahlbegrenzer", -500.0, 800.0, 100.0, "%+.0f U/min", note)
	_ws["gear_spread"] = _pause_slider(ws_page, "Getriebeabstufung", 75.0, 125.0, 5.0, "%.0f %%", note)
	# Each gear on its own (only the car's gears are shown, see _workshop_load).
	for g in 8:
		_ws["g%d" % (g + 1)] = _pause_slider(ws_page, "%d. Gang" % (g + 1), 80.0, 120.0, 1.0, "%.0f %%", note)
	_ws["final_drive"] = _pause_slider(ws_page, "Achsübersetzung", 80.0, 125.0, 1.0, "%.0f %%", note)
	_ws["layout"] = _pause_choices(ws_page, "Antrieb", Workshop.LAYOUTS.map(func(l): return l[0]))
	_ws["lsd"] = _pause_choices(ws_page, "Sperrdifferenzial", LSD_CHOICES.map(func(l): return l[0]))
	ws_page.add_child(UITheme.section("Fahrwerk"))
	_ws["spring_f"] = _pause_slider(ws_page, "Federn vorn", 60.0, 180.0, 5.0, "%.0f %%", note)
	_ws["spring_r"] = _pause_slider(ws_page, "Federn hinten", 60.0, 180.0, 5.0, "%.0f %%", note)
	_ws["damp_f"] = _pause_slider(ws_page, "Dämpfer vorn", 60.0, 180.0, 5.0, "%.0f %%", note)
	_ws["damp_r"] = _pause_slider(ws_page, "Dämpfer hinten", 60.0, 180.0, 5.0, "%.0f %%", note)
	_ws["arb_f"] = _pause_slider(ws_page, "Stabilisator vorn", 0.0, 200.0, 10.0, "%.0f %%", note)
	_ws["arb_r"] = _pause_slider(ws_page, "Stabilisator hinten", 0.0, 200.0, 10.0, "%.0f %%", note)
	_ws["ride_height"] = _pause_slider(ws_page, "Fahrzeughöhe", -40.0, 60.0, 5.0, "%+.0f mm", note)
	ws_page.add_child(UITheme.section("Räder, Bremsen, Gewicht"))
	_ws["compound"] = _pause_choices(ws_page, "Reifen", Workshop.COMPOUNDS.map(func(c): return c[0]))
	_ws["wheels"] = _pause_choices(ws_page, "Räder", Workshop.WHEELS.map(func(w): return w[0]))
	_ws["tire_width"] = _pause_slider(ws_page, "Reifenbreite", 85.0, 125.0, 5.0, "%.0f %%", note)
	_ws["wing"] = _pause_choices(ws_page, "Heckflügel", Workshop.WINGS.map(func(w): return w[0]))
	_ws["bullbar"] = _pause_choices(ws_page, "Rammschutz", ["Ohne", "Stahl-Rammschutz (30 kg)"])
	_ws["brakes"] = _pause_slider(ws_page, "Bremsanlage", 70.0, 150.0, 5.0, "%.0f %%", note)
	_ws["ballast"] = _pause_slider(ws_page, "Gewicht", -150.0, 300.0, 10.0, "%+.0f kg", note)
	for key in ["engine", "gearbox", "layout", "lsd", "compound", "wing", "wheels", "bullbar"]:
		(_ws[key] as OptionButton).item_selected.connect(func(_i: int): _workshop_preview())
	_ws_info = UITheme.label("", 14, UITheme.MUTED)
	_ws_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ws_page.add_child(_ws_info)
	var apply := Button.new()
	apply.text = "Übernehmen – Auto in der Werkstatt neu aufbauen"
	apply.alignment = HORIZONTAL_ALIGNMENT_LEFT
	apply.pressed.connect(func():
		hud.toast(rebuild_player(_workshop_read()))
		_toggle_pause())
	ws_page.add_child(apply)
	var factory := Button.new()
	factory.text = "Werkszustand wiederherstellen"
	factory.alignment = HORIZONTAL_ALIGNMENT_LEFT
	factory.pressed.connect(func():
		hud.toast(rebuild_player({}))
		_toggle_pause())
	ws_page.add_child(factory)


## Fills the Werkstatt controls from the player's car's stored configuration.
func _workshop_load() -> void:
	if _ws.is_empty() or not is_instance_valid(player):
		return
	var cfg := Workshop.normalized(Game.progress.get_config(str(player.get_info().get("id", ""))))
	(_ws["engine"] as OptionButton).select(maxi(0, _ws_engine_ids.find(cfg["engine"])))
	(_ws["gearbox"] as OptionButton).select(1 if cfg["gearbox"] == "donor" else 0)
	(_ws["layout"] as OptionButton).select(maxi(0, Workshop.LAYOUTS.map(func(l): return l[1]).find(cfg["layout"])))
	(_ws["lsd"] as OptionButton).select(maxi(0, LSD_CHOICES.map(func(l): return l[1]).find(float(cfg["lsd"]))))
	(_ws["compound"] as OptionButton).select(int(cfg["compound"]))
	(_ws["wing"] as OptionButton).select(int(cfg["wing"]))
	(_ws["wheels"] as OptionButton).select(int(cfg["wheels"]))
	(_ws["bullbar"] as OptionButton).select(1 if cfg["bullbar"] else 0)
	# Only as many gear sliders as the car's gearbox (or the donor's, if chosen) has gears.
	var gear_count := int(player.get_info().get("gears", 6))
	for g in 8:
		(_ws["g%d" % (g + 1)] as HSlider).get_parent().visible = g < gear_count
	# Wings only on the generated bodies (an imported model hides it).
	var imported := not (Game.car_info(Game.car_path_for_id(str(player.get_info().get("id", "")))).get("visual_model", {}) as Dictionary).is_empty()
	var electric := bool(player.get_info().get("electric", false))
	for part in ["engine", "gearbox"]:
		(_ws[part] as OptionButton).disabled = electric
		(_ws[part] as OptionButton).tooltip_text = "Elektroauto: Motor und Akku bleiben" if electric else ""
	for part in ["wing", "bullbar"]:
		(_ws[part] as OptionButton).disabled = imported
		(_ws[part] as OptionButton).tooltip_text = "Nur für Fahrzeuge ohne importiertes Modell" if imported else ""
	for key in ["power", "final_drive", "spring_f", "spring_r", "damp_f", "damp_r", "arb_f", "arb_r", "brakes", "tire_width", "boost", "gear_spread", "g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8"]:
		(_ws[key] as HSlider).value = float(cfg[key]) * 100.0
	(_ws["ride_height"] as HSlider).value = float(cfg["ride_height"]) * 1000.0
	(_ws["limiter"] as HSlider).value = float(cfg["limiter"])
	(_ws["ballast"] as HSlider).value = float(cfg["ballast"])
	for key in _ws.keys():
		if _ws[key] is HSlider:   # the value label also when the value did not change
			var sl: HSlider = _ws[key]
			(sl.get_meta("label") as Label).text = String(sl.get_meta("format")) % sl.value
	_workshop_preview()


func _workshop_read() -> Dictionary:
	var cfg := {}
	cfg["engine"] = _ws_engine_ids[(_ws["engine"] as OptionButton).selected]
	if cfg["engine"] == str(player.get_info().get("id", "")):
		cfg["engine"] = ""
	cfg["gearbox"] = "donor" if (_ws["gearbox"] as OptionButton).selected == 1 else "own"
	cfg["layout"] = Workshop.LAYOUTS[(_ws["layout"] as OptionButton).selected][1]
	cfg["lsd"] = LSD_CHOICES[(_ws["lsd"] as OptionButton).selected][1]
	cfg["compound"] = (_ws["compound"] as OptionButton).selected
	cfg["wing"] = (_ws["wing"] as OptionButton).selected
	cfg["wheels"] = (_ws["wheels"] as OptionButton).selected
	cfg["bullbar"] = (_ws["bullbar"] as OptionButton).selected == 1
	for key in ["power", "final_drive", "spring_f", "spring_r", "damp_f", "damp_r", "arb_f", "arb_r", "brakes", "tire_width", "boost", "gear_spread", "g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8"]:
		cfg[key] = (_ws[key] as HSlider).value / 100.0
	cfg["ride_height"] = (_ws["ride_height"] as HSlider).value / 1000.0
	cfg["limiter"] = (_ws["limiter"] as HSlider).value
	cfg["ballast"] = (_ws["ballast"] as HSlider).value
	return Workshop.normalized(cfg)


## Resulting key figures of the configuration shown under the controls.
func _workshop_preview() -> void:
	if _ws_info == null or not is_instance_valid(player):
		return
	var path := Game.car_path_for_id(str(player.get_info().get("id", "")))
	var d := Workshop.apply(Workshop.read_definition(path), _workshop_read(), Game.engine_catalogue())
	var e: Dictionary = d.get("engine", {})
	var peak_t := 0.0
	var peak_p := 0.0
	for pt in e.get("torqueCurve", []):
		peak_t = maxf(peak_t, float(pt[1]))
		peak_p = maxf(peak_p, float(pt[1]) * float(pt[0]) * TAU / 60.0 / 1000.0)
	var mass := float(d.get("chassis", {}).get("curbMass", 0.0))
	# Tyre size as written on the sidewall: width / profile R rim diameter.
	var t: Dictionary = d.get("tires", {})
	var tw := float(t.get("width", 0.205))
	var tr := float(t.get("radius", 0.316))
	var rr := float(t.get("rimRadius", 0.203))
	_ws_info.text = "Ergebnis: %s, %d kW (%d PS), %d Nm, Drehzahlgrenze %d U/min, %s, %d kg, %.1f kg/kW, Reifen %d/%d R%d %s" % [
		e.get("name", "?"), int(round(peak_p)), int(round(peak_p * 1.36)), int(round(peak_t)), int(e.get("redlineRpm", 0)),
		e.get("layout", "?"), int(round(mass)), mass / maxf(peak_p, 1.0),
		int(round(tw * 1000.0 / 5.0) * 5.0), int(round((tr - rr) / tw * 20.0) * 5.0), int(round(rr * 2.0 / 0.0254)),
		"Geländeprofil" if t.get("tread", "road") == "offroad" else "Straßenprofil"]


## Rebuilds the player's car with configuration `cfg` where it stands (upright, at rest): stores the
## configuration for this car, spawns the new build and replaces the old one, like applying parts
## in a garage. Returns the message for the toast.
func rebuild_player(cfg: Dictionary) -> String:
	if absf(player.get_speed_kmh()) > 5.0:
		return "Für die Werkstatt anhalten"
	var id := str(player.get_info().get("id", ""))
	var path := Game.car_path_for_id(id)
	if path.is_empty():
		return "Fahrzeug nicht gefunden"
	Game.progress.set_config(id, {} if Workshop.is_default(cfg) else cfg)
	uncouple_trailer()
	var old := player
	var f := old.get_forward()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.1 else Vector3.RIGHT
	var xf := MapBuilder.car_xform(old.get_position_ws() + Vector3.UP * 0.25, f)
	# The old car goes first: two bodies built into each other would be blown apart.
	var i := vehicles.find(old)
	vehicles.erase(old)
	world.remove_vehicle(old)
	var message := "Werkstatt: %s" % Workshop.summary(cfg, Game.engine_catalogue())
	var v := Game.spawn_vehicle(world, path, xf, true)
	if v == null:
		Game.progress.set_config(id, {})
		v = Game.spawn_vehicle(world, path, xf, false)
		message = "Diese Konfiguration ließ sich nicht aufbauen – Serienstand"
	Game.apply_chosen_paint(v)
	vehicles.insert(maxi(0, i), v)
	_apply_settings(v)
	_configure_effects(v)
	_set_player(v)
	for driver in ai.values():
		driver.player = v
	cam.snap()
	return message


## In-game vehicle selection (pause menu "Fahrzeug", as BeamNG's vehicle selector): the player's
## car is exchanged for another model where it stands, or another car is parked in front of it
## (to crash into, or to switch to with the vehicle-switch key). In the career only owned cars.
var _pick_car: OptionButton
var _pick_paths: Array = []
var _parked: Array[SBVehicle] = []


func _build_vehicle_picker(page_box: VBoxContainer) -> void:
	page_box.add_child(UITheme.section("Fahrzeugauswahl"))
	_pick_paths = []
	var names: Array = []
	for c: Dictionary in Game.cars:
		_pick_paths.append(c["path"])
		names.append("%s · %s · %.0f kW" % [c["name"], c["layout"], float(c["power"])])
	_pick_car = _pause_choices(page_box, "Fahrzeug", names)
	for entry in [["Mein Fahrzeug gegen dieses tauschen", func():
				hud.toast(swap_player_car(_pick_paths[_pick_car.selected]))
				_toggle_pause()],
			["Dieses Fahrzeug vor mir abstellen", func():
				hud.toast(park_car_ahead(_pick_paths[_pick_car.selected]))
				_toggle_pause()],
			["Abgestellte Fahrzeuge entfernen", func():
				hud.toast(remove_parked_cars())
				_toggle_pause()]]:
		var b := Button.new()
		b.text = entry[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		page_box.add_child(b)


func swap_player_car(path: String) -> String:
	if absf(player.get_speed_kmh()) > 5.0:
		return "Zum Fahrzeugwechsel anhalten"
	var info := Game.car_info(path)
	if info.is_empty():
		return "Fahrzeug nicht gefunden"
	if Game.settings.get("career", false) and not Career.owns(Game.progress, str(info["id"])):
		return "In der Karriere nur mit eigenen Fahrzeugen"
	if str(info["id"]) == str(player.get_info().get("id", "")):
		return "Dieses Fahrzeug fährst du schon"
	uncouple_trailer()
	var old := player
	var xf := _here(old)
	var i := vehicles.find(old)
	vehicles.erase(old)
	world.remove_vehicle(old)
	var v := Game.spawn_vehicle(world, path, xf, true)
	if v == null:
		return "Fahrzeug ließ sich nicht aufbauen"
	Game.selected_car = path   # "Neu starten" keeps the new choice
	Game.apply_chosen_paint(v)
	vehicles.insert(maxi(0, i), v)
	_apply_settings(v)
	_configure_effects(v)
	_set_player(v)
	for driver in ai.values():
		driver.player = v
	cam.snap()
	return "Fahrzeug: %s" % info["name"]


func park_car_ahead(path: String) -> String:
	if _parked.size() >= 6:
		return "Höchstens sechs abgestellte Fahrzeuge"
	var f := player.get_forward()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.1 else Vector3.RIGHT
	var pos := player.get_position_ws() + f * 9.0 + Vector3.UP * 0.3
	var v := Game.spawn_vehicle(world, path, MapBuilder.car_xform(pos, f))
	if v == null:
		return "Fahrzeug ließ sich nicht aufbauen"
	v.set_input(0, 1, 0, 1)   # parked: handbrake on
	vehicles.append(v)
	_parked.append(v)
	_configure_effects(v)
	return "%s abgestellt · Fahrzeugwechsel mit der Wechseltaste" % Game.car_info(path).get("name", "Fahrzeug")


func remove_parked_cars() -> String:
	var n := 0
	for v in _parked:
		if is_instance_valid(v) and v != player:
			vehicles.erase(v)
			ai.erase(v)
			world.remove_vehicle(v)
			n += 1
	_parked = _parked.filter(func(v): return is_instance_valid(v) and v == player)
	if n == 0: return "Keine abgestellten Fahrzeuge"
	return "1 abgestelltes Fahrzeug entfernt" if n == 1 else "%d abgestellte Fahrzeuge entfernt" % n


## Where `car` stands, upright and facing its way, a little above the ground for the new build.
func _here(car: SBVehicle) -> Transform3D:
	var f := car.get_forward()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.1 else Vector3.RIGHT
	return MapBuilder.car_xform(car.get_position_ws() + Vector3.UP * 0.25, f)


func _pause_slider(parent: VBoxContainer, caption: String, low: float, high: float, step: float, fmt: String,
		changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 170
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size.x = 72
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(shown)
	slider.set_meta("label", shown)
	slider.set_meta("format", fmt)
	slider.value_changed.connect(func(v: float):
		shown.text = fmt % v
		changed.call(v))
	parent.add_child(row)
	return slider


## Tuning from the pause menu: tyre pressures per axle and the front brake share.
func _apply_tuning() -> void:
	if not is_instance_valid(player) or _tune_front == null:
		return
	player.set_tire_pressure(_tune_front.value, _tune_rear.value)
	player.set_brake_bias(_tune_bias.value / 100.0)


func _sync_tuning() -> void:
	if not is_instance_valid(player) or _tune_front == null:
		return
	var t: Dictionary = player.get_tuning()
	for pair in [[_tune_front, t["front_psi"]], [_tune_rear, t["rear_psi"]], [_tune_bias, float(t["brake_bias"]) * 100.0]]:
		var slider: HSlider = pair[0]
		slider.set_value_no_signal(pair[1])
		(slider.get_meta("label") as Label).text = String(slider.get_meta("format")) % slider.value


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
		_pause_activity.select(maxi(0, activity.available_modes().find(activity.mode)))
		_sync_tuning()
		_workshop_load()
		if _pick_car:
			_pick_car.select(maxi(0, _pick_paths.find(Game.car_path_for_id(str(player.get_info().get("id", ""))))))
		_pause_weather.select(weather.weather_index)
		_pause_time.select(weather.time_index)
		_pause_clock.set_pressed_no_signal(weather.automatic_time)
		player.set_input(0, 0, 0, 0)
		_pause_first_button.grab_focus()
