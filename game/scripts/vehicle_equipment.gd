extends Node3D
## Per-vehicle lighting and a marked service bay. Fuel goes into the actual C++ tank.
const DriverPrompts := preload("res://scripts/driver_prompts.gd")
var _service_sign: Label3D

signal service_completed(kind: String)
signal fuel_delivered(litres: float, session_litres: float)

const REPAIR_SECONDS := 4.0
const FUEL_RATE_LPS := 0.8
var service_progress := 0.0
var refuel_delivered_litres := 0.0
var _service_vehicle: SBVehicle
var _repair_latched := false
var _fuel_session := false
var _fuel_completed := false
var _last_sim_time := -1.0
var _bay_transform := Transform3D.IDENTITY
var game: Node3D
var states: Dictionary = {}
var bay := Vector3.ZERO
var refueling := false
var _fuel_unpaid := 0.0   # litres delivered but not yet billed (career)
var clock := 0.0

func configure(scene: Node3D, spawn: Transform3D) -> void:
	game = scene
	bay = spawn.origin + spawn.basis.z.normalized() * 8.0
	_bay_transform = Transform3D(spawn.basis, bay)
	_last_sim_time = float(game.world.get_stats()["sim_time"])
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 3.3
	ring.outer_radius = 3.5
	marker.mesh = ring
	marker.position = bay + Vector3(0, 0.025, 0)
	marker.scale.y = 0.04
	marker.material_override = material(Color(0.16, 0.76, 0.62), true)
	add_child(marker)
	var pump := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 1.5, 0.5)
	pump.mesh = box
	pump.position = bay + spawn.basis.z.normalized() * 4.0 + Vector3(0, 0.75, 0)
	pump.material_override = material(Color(0.16, 0.55, 0.48), false)
	add_child(pump)
	game.world.add_box(pump.position, box.size * 0.5, Vector3.ZERO, 0.8)
	var sign := Label3D.new()
	_service_sign = sign
	_refresh_service_sign()
	var prompts := get_node_or_null("/root/Game/DriverPrompts")
	if prompts: prompts.device_changed.connect(_refresh_service_sign)
	sign.position = pump.position + Vector3(0, 1.4, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 28
	sign.pixel_size = 0.008
	sign.visibility_range_end = 55.0
	add_child(sign)

func _refresh_service_sign() -> void:
	if not is_instance_valid(_service_sign): return
	_service_sign.text = "SERVICE\n%s Tanken · %s Reparatur (halten)\nAnhalten · %s Motor aus" % [DriverPrompts.hint("refuel"), DriverPrompts.hint("service_repair"), DriverPrompts.hint("ignition")]

func material(color: Color, lit: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = lit
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	return mat

func state_for(v: SBVehicle) -> Dictionary:
	if states.has(v):
		return states[v]
	var rig := Node3D.new()
	add_child(rig)
	var info := v.get_info()
	var length := float(info["length"])
	var width := float(info["width"])
	# Axle midpoint differs from body midpoint; use authored overhangs to put
	# the light just outside the bumper instead of inside its opaque mesh.
	var body: Dictionary = {}
	for entry in Game.cars:
		if str(entry.get("id", "")) == str(info.get("id", "")):
			var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(entry["path"]))
			if definition is Dictionary: body = definition.get("body", {})
			break
	var lamp_x := float(body.get("wheelbase", length * 0.62)) * 0.5 + float(body.get("frontOverhang", length * 0.21)) + 0.045
	var ground_clearance := float(body.get("groundClearance", 0.14))
	var lamp_y := float(body.get("noseHeight", 0.72)) - 0.075 - ground_clearance
	var rear_x := -(length - (lamp_x - 0.045)) - 0.025
	var rear_y := float(body.get("tailHeight", 1.0)) - 0.16 - ground_clearance
	var authored_signals: Array[ShaderMaterial] = []
	var lamp_materials: Array = []
	var tail_materials: Array = []
	var lamp_entries: Array = []
	for child in v.get_children():
		var lamp_name := String(child.name).to_lower()
		if child is MeshInstance3D and "turnsignalsrear" in lamp_name:
			var signal_material := _authored_signal_material()
			child.material_override = signal_material
			authored_signals.append(signal_material)
		var is_head := "headlight" in lamp_name
		var is_tail := lamp_name.ends_with("taillight") or lamp_name.ends_with("taillights") \
			or lamp_name.ends_with("taillight_left") or lamp_name.ends_with("taillight_right")
		if child is MeshInstance3D and (is_head or is_tail):
			var original: Material = child.get_active_material(0)
			if original is StandardMaterial3D:
				var own: StandardMaterial3D = original.duplicate()
				child.material_override = own
				own.emission = Color(1.0, 0.94, 0.8) if is_head else Color(0.95, 0.025, 0.015)
				own.emission_energy_multiplier = 1.2
				if is_head: lamp_materials.append(own)
				else: tail_materials.append(own)
				# Generated lamps are split per side; an imported lamp mesh may cover both sides (0).
				var lamp_side := -1 if lamp_name.ends_with("_left") else (1 if lamp_name.ends_with("_right") else 0)
				lamp_entries.append({"material": own, "front": is_head, "side": lamp_side, "albedo": own.albedo_color})
	var headlights: Array = []
	var left: Array = []
	var right: Array = []
	for side in [-1, 1]:
		var light := SpotLight3D.new()
		light.position = Vector3(lamp_x, maxf(0.25, lamp_y), side * width * 0.36)
		light.rotation_degrees = Vector3(-2.0, -90, 0)
		light.spot_range = 70
		light.spot_angle = 44
		light.light_energy = 16
		light.spot_attenuation = 0.65
		light.shadow_enabled = true
		light.light_color = Color(1.0, 0.95, 0.82)
		rig.add_child(light)
		headlights.append(light)
		for end in [-1, 1]:
			# The Concept already has skinned rear signal lenses. Reuse those rather
			# than stacking generated boxes over its authored lamp geometry.
			if end < 0 and not authored_signals.is_empty(): continue
			var lamp := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.018, 0.045, 0.13)
			lamp.mesh = mesh
			# Rig origin is at the chassis floor, not ground level. Use the
			# authored fascia heights, subtracting clearance just as for headlights.
			lamp.position = Vector3(lamp_x - 0.015 if end > 0 else rear_x,
				maxf(0.18, lamp_y - 0.035) if end > 0 else maxf(0.22, rear_y), side * width * 0.40)
			lamp.material_override = material(Color(1.0, 0.42, 0.04), true)
			lamp.set_meta("corner", ("head_" if end > 0 else "tail_") + ("left" if side < 0 else "right"))
			rig.add_child(lamp)
			if side < 0: left.append(lamp)
			else: right.append(lamp)
	var paint_rgb: Array = body.get("paint", [0.5, 0.1, 0.1])
	var s := {"paint": Color(float(paint_rgb[0]), float(paint_rgb[1]), float(paint_rgb[2])), "rig": rig, "lamp_materials": lamp_materials, "tail_materials": tail_materials, "lamp_entries": lamp_entries, "broken": {}, "lamp_check": 0.0, "authored_signals": authored_signals, "headlights": headlights, "left": left, "right": right, "lights": false, "light_mode": 0, "signal": 0, "hazards": false}
	states[v] = s
	return s

func _authored_signal_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform vec3 vehicle_origin;
uniform vec3 vehicle_right = vec3(0.0, 0.0, 1.0);
uniform bool left_on = false;
uniform bool right_on = false;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    bool right_side = dot(world_position - vehicle_origin, vehicle_right) > 0.0;
    ALBEDO = vec3(0.015, 0.012, 0.008);
    ROUGHNESS = 0.5;
    EMISSION = (right_side ? right_on : left_on) ? vec3(1.6, 0.7, 0.0) : vec3(0.0);
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result

func handle_action(event: InputEvent) -> bool:
	var s := state_for(game.player)
	if event.is_echo(): return false
	# Exact modifiers prevent Shift+U from also triggering the unmodified U action.
	if event.is_action_pressed("passenger_door", false, true):
		toggle_door(1)
		return true
	if event.is_action_pressed("driver_door", false, true):
		toggle_door(0)
		return true
	if event.is_action_pressed("tailgate_release", false, true):
		release_tailgate()
		return true
	if event.is_action_pressed("bonnet_release", false, true):
		release_bonnet()
		return true
	if event.is_action_pressed("headlights"):
		s["light_mode"] = (int(s["light_mode"]) + 1) % 3
		s["lights"] = s["light_mode"] > 0
		s["manual_lights"] = true   # the driver took over from the light sensor
	elif event.is_action_pressed("indicator_left"):
		s["hazards"] = false
		s["signal"] = 0 if s["signal"] == -1 else -1
	elif event.is_action_pressed("indicator_right"):
		s["hazards"] = false
		s["signal"] = 0 if s["signal"] == 1 else 1
	elif event.is_action_pressed("hazards"):
		s["hazards"] = not s["hazards"]
	else:
		return false
	game.hud.toast(status_text())
	return true

## Tailgate of an estate / SUV, boot lid of a saloon.
func lid_name(index: int) -> String:
	if index == 0: return "Motorhaube"
	var style := String(game.player.get_info().get("style", "")) if game and is_instance_valid(game.player) else ""
	return "Kofferraumdeckel" if style in ["sedan", "coupe"] else "Heckklappe"


## Opens a shut bonnet (0) / rear lid (1) at standstill, or lowers an open one until it latches.
func toggle_lid(index: int) -> bool:
	if not game or not is_instance_valid(game.player): return false
	var v: SBVehicle = game.player
	var lid := lid_name(index)
	var states: Array = v.get_lid_states() if v.has_method("get_lid_states") else []
	var state: Dictionary = states[index] if index < states.size() else {}
	if state.is_empty() or not state.get("available", false):
		game.hud.toast("%s für dieses Modell nicht verfügbar" % lid)
		return false
	if state.get("damaged", false):
		game.hud.toast("%s beschädigt · Reparatur nötig" % lid)
		return false
	if state.get("open_requested", false):
		var closing: bool = v.close_bonnet() if index == 0 else v.close_tailgate()
		if closing: game.hud.toast("%s wird geschlossen" % lid)
		return closing
	if absf(v.get_speed_kmh()) > 2.0:
		game.hud.toast("%s: zum Öffnen zuerst anhalten" % lid)
		return false
	var opened: bool = v.release_bonnet() if index == 0 else v.release_tailgate()
	game.hud.toast("%s entriegelt" % lid if opened else "%s klemmt" % lid)
	return opened


func release_bonnet() -> bool: return toggle_lid(0)
func release_tailgate() -> bool: return toggle_lid(1)


func toggle_door(index: int) -> bool:
	if not game or not is_instance_valid(game.player): return false
	var doors: Array = game.player.get_door_states()
	var name: String = ["Fahrertür", "Beifahrertür", "Tür hinten links", "Tür hinten rechts"][clampi(index, 0, 3)]
	if index < 0 or index >= doors.size():
		game.hud.toast("Bewegliche Türen für dieses Modell nicht verfügbar")
		return false
	if game.player.get_speed_kmh() > 2.0:
		game.hud.toast("Zum Öffnen oder Schließen der Tür anhalten")
		return false
	if not game.player.toggle_door(index):
		game.hud.toast(name + ": beschädigt oder abgerissen · Service nötig")
		return false
	var updated: Array = game.player.get_door_states()
	game.hud.toast(name + (" wird geöffnet" if updated[index]["requested_open"] else " wird geschlossen"))
	return true

func can_refuel() -> bool:
	if not game or not is_instance_valid(game.player): return false
	var v: SBVehicle = game.player
	return v.get_position_ws().distance_to(bay) < 3.5 and v.get_velocity().length() < 0.25 and not v.get_telemetry()["running"]

func status_text() -> String:
	if not game or not is_instance_valid(game.player): return ""
	var s := state_for(game.player)
	var signal_text := "Warnblinker" if s["hazards"] else ("Blinker links" if s["signal"] == -1 else ("Blinker rechts" if s["signal"] == 1 else ""))
	var light_caption := "Fernlicht" if s["light_mode"] == 2 else ("Abblendlicht" if s["lights"] else "Licht aus")
	var result := "%s  %s" % [light_caption, signal_text]
	for door in game.player.get_door_states():
		if door["missing"]:
			result += " · Tür abgerissen"
			break
		if door["open"]:
			result += " · Tür offen"
			break
	if game.player.get_position_ws().distance_to(bay) < 3.5:
		if service_progress > 0.0:
			result += "  |  Reparatur %d %% · %s halten" % [roundi(service_progress * 100.0), DriverPrompts.hint("service_repair")]
		elif refueling:
			result += "  |  Getankt %.1f l · %s halten" % [refuel_delivered_litres, DriverPrompts.hint("refuel")]
		else:
			result += "  |  " + ("%s tanken · %s reparieren (halten)" % [DriverPrompts.hint("refuel"), DriverPrompts.hint("service_repair")] if can_refuel() else "Service: anhalten · %s Motor aus" % DriverPrompts.hint("ignition"))
	return result

## Structured state for the HUD telltales and context prompt.
func hud_state() -> Dictionary:
	if not game or not is_instance_valid(game.player): return {}
	var s := state_for(game.player)
	var door := ""
	for d in game.player.get_door_states():
		if d["missing"]:
			door = "missing"
			break
		if d["open"]:
			door = "open"
	var prompt := ""
	if game.player.get_position_ws().distance_to(bay) < 3.5:
		if service_progress > 0.0:
			prompt = "Reparatur %d %% · %s halten" % [roundi(service_progress * 100.0), DriverPrompts.hint("service_repair")]
		elif refueling:
			prompt = "Getankt %.1f l · %s halten" % [refuel_delivered_litres, DriverPrompts.hint("refuel")]
		else:
			prompt = "%s tanken · %s reparieren (halten)" % [DriverPrompts.hint("refuel"), DriverPrompts.hint("service_repair")] if can_refuel() else "Service: anhalten · %s Motor aus" % DriverPrompts.hint("ignition")
	return {"light_mode": int(s["light_mode"]), "signal": int(s["signal"]), "hazards": bool(s["hazards"]),
		"blink": fmod(clock, 0.8) < 0.4, "door": door, "prompt": prompt}

func _process(delta: float) -> void:
	if not game: return
	for old_vehicle in states.keys():
		if not is_instance_valid(old_vehicle) or old_vehicle not in game.vehicles:
			states[old_vehicle]["rig"].queue_free()
			states.erase(old_vehicle)
	if not game.world.paused: clock += delta * game.world.time_scale
	var blink := fmod(clock, 0.8) < 0.4
	for v in game.vehicles:
		if not is_instance_valid(v): continue
		var s := state_for(v)
		var forward: Vector3 = v.get_forward().normalized()
		var up: Vector3 = v.get_up().normalized()
		var right: Vector3 = forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		s["rig"].global_transform = Transform3D(Basis(forward, up, right), v.get_position_ws())
		_update_lamp_damage(v, s, delta)
		_auto_lights(s)
		var broken: Dictionary = s["broken"]
		var braking := float(v.get_telemetry().get("brake", 0.0)) > 0.05
		for entry in s["lamp_entries"]:
			var mat: StandardMaterial3D = entry["material"]
			var dead := _lamp_dead(broken, bool(entry["front"]), int(entry["side"]))
			mat.emission_enabled = not dead and (s["lights"] or (braking and not entry["front"]))
			if not entry["front"]: mat.emission_energy_multiplier = 3.5 if braking else 0.8
			# A smashed lens shows the dark reflector behind it.
			mat.albedo_color = (entry["albedo"] as Color).darkened(0.75) if dead else entry["albedo"]
		for i in s["headlights"].size():
			var light: SpotLight3D = s["headlights"][i]
			light.visible = s["lights"] and not broken.get("head_left" if i == 0 else "head_right", false)
			var high: bool = s["light_mode"] == 2
			light.spot_range = 140.0 if high else 70.0
			light.spot_angle = 32.0 if high else 44.0
			light.light_energy = 30.0 if high else 16.0
			light.rotation_degrees.x = -0.5 if high else -2.0
		for lamp in s["left"]: lamp.visible = blink and (s["hazards"] or s["signal"] == -1) and not broken.get(lamp.get_meta("corner"), false)
		for lamp in s["right"]: lamp.visible = blink and (s["hazards"] or s["signal"] == 1) and not broken.get(lamp.get_meta("corner"), false)
		for signal_material in s["authored_signals"]:
			signal_material.set_shader_parameter("vehicle_origin", v.get_position_ws())
			signal_material.set_shader_parameter("vehicle_right", right)
			signal_material.set_shader_parameter("left_on", blink and (s["hazards"] or s["signal"] == -1))
			signal_material.set_shader_parameter("right_on", blink and (s["hazards"] or s["signal"] == 1))
	_update_cabin_light()
	var sim_time := float(game.world.get_stats()["sim_time"])
	var elapsed := maxf(0.0, sim_time - _last_sim_time) if _last_sim_time >= 0.0 else 0.0
	_last_sim_time = sim_time
	update_service(elapsed, Input.is_action_pressed("service_repair"), Input.is_action_pressed("refuel"))

## Daylight scattered in through the windows. Without global illumination the cabin only gets
## sky ambient, which leaves the headliner and the seat fronts nearly black in daylight. One weak,
## shadowless light in the player's cabin stands in for that bounce light and fades out at night.
var _cabin_light: OmniLight3D
## Light sensor: until the driver switches the lights by hand, dipped beams follow the daylight
## (dusk, night, heavy cloud and rain), with a little hysteresis so they do not flicker.
func _auto_lights(s: Dictionary) -> void:
	if s.get("manual_lights", false) or not game.get("weather"):
		return
	var daylight := float(game.weather.daylight)
	var on: bool = s["lights"]
	if on and daylight > 0.62:
		on = false
	elif not on and daylight < 0.5:
		on = true
	if on != s["lights"]:
		s["lights"] = on
		s["light_mode"] = 1 if on else 0

func _update_cabin_light() -> void:
	var car: SBVehicle = game.player if is_instance_valid(game.player) else null
	if car == null:
		if _cabin_light: _cabin_light.visible = false
		return
	if _cabin_light == null:
		_cabin_light = OmniLight3D.new()
		_cabin_light.name = "CabinFill"
		_cabin_light.shadow_enabled = false
		_cabin_light.omni_range = 1.7
		_cabin_light.omni_attenuation = 1.2
		_cabin_light.light_color = Color(1.0, 0.97, 0.92)
		_cabin_light.light_specular = 0.05
		add_child(_cabin_light)
	var weather: Node = game.get("weather")
	var day := float(weather.get("daylight")) if weather and weather.get("daylight") != null else 1.0
	_cabin_light.visible = day > 0.05
	_cabin_light.light_energy = 0.55 * day
	var eye := car.get_driver_eye()
	_cabin_light.global_position = eye + car.get_right() * 0.36 - car.get_up() * 0.28 - car.get_forward() * 0.25

const LAMP_CAPTIONS := {"head_left": "Scheinwerfer links", "head_right": "Scheinwerfer rechts",
	"tail_left": "Rückleuchte links", "tail_right": "Rückleuchte rechts"}

## Lamps break with the body structure around them and stay dark until the car is repaired.
func _update_lamp_damage(v: SBVehicle, s: Dictionary, delta: float) -> void:
	s["lamp_check"] = float(s["lamp_check"]) - delta
	if float(s["lamp_check"]) > 0.0 or not v.has_method("get_lamp_states"): return
	s["lamp_check"] = 0.2
	_update_glass(v, s)
	_update_debris(v, s)
	var broken: Dictionary = s["broken"]
	for lamp in v.get_lamp_states():
		var corner: String = lamp["name"]
		var now := bool(lamp["broken"])
		if now and not broken.get(corner, false):
			# Lens fragments: clear for headlights, red for tail lights.
			_spawn_shards(lamp.get("center", v.get_position_ws()), v.get_velocity(), 30,
				Color(0.85, 0.88, 0.9, 0.7) if lamp["front"] else Color(0.75, 0.05, 0.04, 0.8))
			if v == game.player and game.get("hud"):
				game.hud.toast("%s zerstört" % LAMP_CAPTIONS.get(corner, corner))
		broken[corner] = now

## Clips and plastic chips when a bumper clip tears out, a burst of trim and paint flakes when a
## door comes off. Counts reset with a repair.
func _update_debris(v: SBVehicle, s: Dictionary) -> void:
	if v.has_method("get_bumper_states"):
		if not s.has("clips"): s["clips"] = {}
		var clips: Dictionary = s["clips"]
		for b in v.get_bumper_states():
			var name := String(b["name"])
			var now := int(b["clips"])
			var before := int(clips.get(name, 4))
			if now < before:
				_spawn_shards(b["center"], v.get_velocity(), 14 * (before - now), Color(0.05, 0.05, 0.055, 1.0))
				_spawn_shards(b["center"], v.get_velocity(), 6 * (before - now), s.get("paint", Color(0.5, 0.1, 0.1)))
			clips[name] = now
	if not s.has("doors_missing"): s["doors_missing"] = {}
	var missing: Dictionary = s["doors_missing"]
	for door in v.get_door_states():
		var idx := int(door["index"])
		var now := bool(door["missing"])
		if now and not missing.get(idx, false):
			var at := v.get_position_ws() + v.get_right() * (0.9 if idx % 2 == 1 else -0.9) + v.get_forward() * (-0.6 if idx >= 2 else 0.4) + v.get_up() * 0.6
			_spawn_shards(at, v.get_velocity(), 40, Color(0.06, 0.06, 0.06, 1.0))
		missing[idx] = now

const CRACKED_GLASS := preload("res://materials/cracked_glass.gdshader")
const GLASS_CRACK := 0.3      # pane damage at which the first cracks show
const GLASS_SHATTER := 1.0    # tempered side and rear glass falls out

## Glass follows the frame it is bonded to: it cracks as the aperture distorts and side and rear
## panes shatter out of a badly crushed frame. The laminated windscreen stays in, crazed. A repair
## (damage back to zero) restores the glass.
func _update_glass(v: SBVehicle, s: Dictionary) -> void:
	if not v.has_method("get_glass_states"): return
	if not s.has("panes"): s["panes"] = {}
	var panes: Dictionary = s["panes"]
	for g in v.get_glass_states():
		var inst: MeshInstance3D = g["instance"]
		if not is_instance_valid(inst): continue
		var key := String(g["name"])
		var damage := float(g["damage"])
		if not panes.has(key): panes[key] = {"material": null, "shattered": false}
		var pane: Dictionary = panes[key]
		if damage < GLASS_CRACK:
			if pane["material"] != null:
				inst.material_override = null
				pane["material"] = null
			if pane["shattered"]:
				inst.visible = true
				pane["shattered"] = false
			continue
		if damage >= GLASS_SHATTER and key != "windscreen":
			if not pane["shattered"]:
				inst.visible = false
				pane["shattered"] = true
				_spawn_shards(g["center"], v.get_velocity())
			continue
		if pane["material"] == null:
			var m := ShaderMaterial.new()
			m.shader = CRACKED_GLASS
			m.set_shader_parameter("seed", float(hash(key) % 997))
			# Laminated windscreen: a web of long cracks; tempered side and rear glass: small cubes.
			m.set_shader_parameter("cell_scale", 4.0 if key == "windscreen" else 9.0)
			m.set_shader_parameter("fine_scale", 26.0 if key == "windscreen" else 38.0)
			inst.material_override = m
			pane["material"] = m
		var mat: ShaderMaterial = pane["material"]
		mat.set_shader_parameter("origin", g["origin_uv"])
		mat.set_shader_parameter("crack", clampf((damage - GLASS_CRACK) / (GLASS_SHATTER - GLASS_CRACK), 0.05, 1.0))

static var _shard_meshes := {}
func _spawn_shards(at: Vector3, velocity: Vector3, amount := 90, colour := Color(0.75, 0.82, 0.85, 0.7)) -> void:
	if not _shard_meshes.has(colour):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.018, 0.003, 0.014)
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.4
		m.roughness = 0.1
		mesh.material = m
		_shard_meshes[colour] = mesh
	var p := CPUParticles3D.new()
	p.mesh = _shard_meshes[colour]
	p.amount = amount if Game.graphics.get("effects", 1) > 0 else maxi(8, amount / 3)
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	add_child(p)
	p.global_position = at + velocity * 0.05
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)

## A lamp mesh covering both sides (imported models) goes dark only once both corners are smashed.
static func _lamp_dead(broken: Dictionary, front: bool, side: int) -> bool:
	var prefix := "head_" if front else "tail_"
	if side < 0: return broken.get(prefix + "left", false)
	if side > 0: return broken.get(prefix + "right", false)
	return broken.get(prefix + "left", false) and broken.get(prefix + "right", false)

## Called once per frame with elapsed PHYSICS time, so slow-motion and overloaded
## frames cannot accelerate work. Releasing a key loses repair progress.
func update_service(sim_delta: float, repair_held: bool, fuel_held: bool) -> void:
	refueling = false
	if not game or not is_instance_valid(game.player):
		cancel_service()
		return
	if _service_vehicle != game.player:
		var switched := is_instance_valid(_service_vehicle)
		cancel_service()
		_service_vehicle = game.player
		if switched: return
	if game.world.paused or not can_refuel():
		cancel_service()
		return
	if not repair_held:
		service_progress = 0.0
		_repair_latched = false
	if not fuel_held:
		if _fuel_session: _settle_fuel()
		_fuel_session = false
		_fuel_completed = false
	# Repair and fueling are mutually exclusive; repair takes priority.
	if repair_held:
		_fuel_session = false
		if _repair_latched: return
		service_progress = minf(1.0, service_progress + maxf(0.0, sim_delta) / REPAIR_SECONDS)
		if service_progress >= 1.0:
			# Career: the workshop bill is due before the car is handed back.
			var bill: float = preload("res://scripts/career.gd").repair_cost(game.player.get_telemetry())
			var paid: bool = not game.has_method("career_charge") or game.career_charge(bill, "Werkstatt")
			if paid and game.player.service_repair():
				service_completed.emit("repair")
			_repair_latched = true
			service_progress = 0.0
	elif fuel_held:
		if not _fuel_session:
			refuel_delivered_litres = 0.0
			_fuel_completed = false
			_fuel_session = true
		# Career: pay per litre as it flows (in half-litre steps); an empty account stops the pump.
		var Career := preload("res://scripts/career.gd")
		if Game.settings.get("career", false) and _fuel_unpaid >= 0.5:
			if not Game.progress.change_money(-_fuel_unpaid * Career.FUEL_PRICE):
				if game.has_method("career_charge"): game.career_charge(_fuel_unpaid * Career.FUEL_PRICE, "Tanken")
				return
			_fuel_unpaid = 0.0
		var added: float = game.player.refuel(maxf(0.0, sim_delta) * FUEL_RATE_LPS)
		_fuel_unpaid += added
		refueling = added > 0.0
		if added > 0.0:
			refuel_delivered_litres += added
			fuel_delivered.emit(added, refuel_delivered_litres)
			var full: bool = float(game.player.get_telemetry()["fuel_l"]) >= float(game.player.get_info()["fuel_capacity"]) - 0.001
			if not _fuel_completed and (refuel_delivered_litres >= 1.0 or full):
				_fuel_completed = true
				service_completed.emit("refuel")

func cancel_service() -> void:
	_settle_fuel()
	service_progress = 0.0
	refueling = false
	_repair_latched = false
	_fuel_session = false
	_fuel_completed = false
	_service_vehicle = null

## Career: bill the fuel delivered since the last half-litre step when the nozzle is put back.
func _settle_fuel() -> void:
	if _fuel_unpaid > 0.0 and Game.settings.get("career", false):
		var amount := _fuel_unpaid * preload("res://scripts/career.gd").FUEL_PRICE
		Game.progress.change_money(-minf(amount, Game.progress.get_money()))
		if game and game.get("hud"): game.hud.toast("Getankt %.1f l · Konto %s" % [refuel_delivered_litres, preload("res://scripts/career.gd").money_text(Game.progress.get_money())])
	_fuel_unpaid = 0.0


## Towing only relocates the existing damaged car. It does not repair/refill it.
func recover_to_service() -> bool:
	if not game or not is_instance_valid(game.player): return false
	cancel_service()
	if not game.player.relocate_to(_bay_transform): return false
	game.player.set_input(0, 1, 0, 1)
	game.player.set_ignition(false)
	_last_sim_time = float(game.world.get_stats()["sim_time"])
	service_completed.emit("recovery")
	return true
