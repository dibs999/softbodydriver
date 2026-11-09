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
	for child in v.get_children():
		var lamp_name := String(child.name).to_lower()
		if child is MeshInstance3D and "turnsignalsrear" in lamp_name:
			var signal_material := _authored_signal_material()
			child.material_override = signal_material
			authored_signals.append(signal_material)
		var is_head := "headlight" in lamp_name
		var is_tail := lamp_name == "taillight" or lamp_name.ends_with("taillights")
		if child is MeshInstance3D and (is_head or is_tail):
			var original: Material = child.get_active_material(0)
			if original is StandardMaterial3D:
				var own: StandardMaterial3D = original.duplicate()
				child.material_override = own
				own.emission = Color(1.0, 0.94, 0.8) if is_head else Color(0.95, 0.025, 0.015)
				own.emission_energy_multiplier = 1.2
				if is_head: lamp_materials.append(own)
				else: tail_materials.append(own)
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
			rig.add_child(lamp)
			if side < 0: left.append(lamp)
			else: right.append(lamp)
	var s := {"rig": rig, "lamp_materials": lamp_materials, "tail_materials": tail_materials, "authored_signals": authored_signals, "headlights": headlights, "left": left, "right": right, "lights": false, "light_mode": 0, "signal": 0, "hazards": false}
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
	if event.is_action_pressed("bonnet_release"):
		if not game.player.get_info().get("bonnet_supported", true):
			game.hud.toast("Motorhaube für dieses Modell nicht verfügbar")
			return true
		if absf(game.player.get_speed_kmh()) > 2.0:
			game.hud.toast("Zum Öffnen der Motorhaube zuerst anhalten")
			return true
		var opened: bool = game.player.release_bonnet()
		game.hud.toast("Motorhaube entriegelt · Reparatur schließt sie" if opened else "Motorhaube bereits entriegelt")
		return true
	if event.is_action_pressed("headlights"):
		s["light_mode"] = (int(s["light_mode"]) + 1) % 3
		s["lights"] = s["light_mode"] > 0
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

func toggle_door(index: int) -> bool:
	if not game or not is_instance_valid(game.player): return false
	var doors: Array = game.player.get_door_states()
	var name := "Fahrertür" if index == 0 else "Beifahrertür"
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
		for mat in s["lamp_materials"]: mat.emission_enabled = s["lights"]
		var braking := float(v.get_telemetry().get("brake", 0.0)) > 0.05
		for mat in s["tail_materials"]:
			mat.emission_enabled = s["lights"] or braking
			mat.emission_energy_multiplier = 3.5 if braking else 0.8
		for light in s["headlights"]:
			light.visible = s["lights"]
			var high: bool = s["light_mode"] == 2
			light.spot_range = 140.0 if high else 70.0
			light.spot_angle = 32.0 if high else 44.0
			light.light_energy = 30.0 if high else 16.0
			light.rotation_degrees.x = -0.5 if high else -2.0
		for lamp in s["left"]: lamp.visible = blink and (s["hazards"] or s["signal"] == -1)
		for lamp in s["right"]: lamp.visible = blink and (s["hazards"] or s["signal"] == 1)
		for signal_material in s["authored_signals"]:
			signal_material.set_shader_parameter("vehicle_origin", v.get_position_ws())
			signal_material.set_shader_parameter("vehicle_right", right)
			signal_material.set_shader_parameter("left_on", blink and (s["hazards"] or s["signal"] == -1))
			signal_material.set_shader_parameter("right_on", blink and (s["hazards"] or s["signal"] == 1))
	var sim_time := float(game.world.get_stats()["sim_time"])
	var elapsed := maxf(0.0, sim_time - _last_sim_time) if _last_sim_time >= 0.0 else 0.0
	_last_sim_time = sim_time
	update_service(elapsed, Input.is_action_pressed("service_repair"), Input.is_action_pressed("refuel"))

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
		_fuel_session = false
		_fuel_completed = false
	# Repair and fueling are mutually exclusive; repair takes priority.
	if repair_held:
		_fuel_session = false
		if _repair_latched: return
		service_progress = minf(1.0, service_progress + maxf(0.0, sim_delta) / REPAIR_SECONDS)
		if service_progress >= 1.0:
			if game.player.service_repair():
				service_completed.emit("repair")
			_repair_latched = true
			service_progress = 0.0
	elif fuel_held:
		if not _fuel_session:
			refuel_delivered_litres = 0.0
			_fuel_completed = false
			_fuel_session = true
		var added: float = game.player.refuel(maxf(0.0, sim_delta) * FUEL_RATE_LPS)
		refueling = added > 0.0
		if added > 0.0:
			refuel_delivered_litres += added
			fuel_delivered.emit(added, refuel_delivered_litres)
			var full: bool = float(game.player.get_telemetry()["fuel_l"]) >= float(game.player.get_info()["fuel_capacity"]) - 0.001
			if not _fuel_completed and (refuel_delivered_litres >= 1.0 or full):
				_fuel_completed = true
				service_completed.emit("refuel")

func cancel_service() -> void:
	service_progress = 0.0
	refueling = false
	_repair_latched = false
	_fuel_session = false
	_fuel_completed = false
	_service_vehicle = null

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
