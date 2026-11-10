extends Node3D
## Small driving challenges using simulation time, ordered gates and persistent records.
signal completed(result: Dictionary)

const C := preload("res://scripts/maps/common.gd")
const RaceField := preload("res://scripts/race_field.gd")
const MODES := ["Freie Fahrt", "Zeitfahren", "Drift-Challenge", "Lieferfahrt", "Rennen"]
## Race opponents are created and removed by the game scene, which owns the vehicles:
## spawn_opponents(grid: Array[Transform3D]) -> Array (AIDriver) and release_opponents(drivers).
var spawn_opponents: Callable
var release_opponents: Callable
var race_size := 2
var place := 0
var records_path := "user://driving_records.cfg":
	set(value):
		records_path = value
		_records = ConfigFile.new()
		_records.load(value)
var last_result: Dictionary = {}
var world: SBWorld
var vehicle: SBVehicle
var map_id := ""
var mode := 0
var active := false
var route := PackedVector3Array()
var gate := 0
var elapsed := 0.0
var countdown := 0.0
var score := 0.0
var combo := 1.0
var best := 0.0
var message := "F3 Aktivität wählen · F4 starten"
var _clock := 0.0
var _previous := Vector3.ZERO
var _hold := 0.0
var _drift_chain := 0.0
var _broken := 0
var _start := Transform3D.IDENTITY
var _race_route := PackedVector3Array()
var _marker: Node3D
var _records := ConfigFile.new()
var _car_id := ""
var _arming := false
var _spawn_position := Vector3.ZERO
var _reset_wait := 0.0
var _race_gates := PackedVector3Array()
var _field := RaceField.new()

func configure(id: String, data: Dictionary) -> void:
	_race_route.clear()
	_race_gates.clear()
	map_id = id
	_start = data["spawns"][0]
	var path: PackedVector3Array = data.get("activity_route", data.get("waypoints", PackedVector3Array()))
	# Retain the road's shape, with a gate roughly every 45 metres.
	var distance := 100.0
	for i in path.size():
		if i > 0: distance += path[i].distance_to(path[i - 1])
		if distance >= 45.0:
			_race_route.append(path[i])
			distance = 0.0
	if _race_route.size() > 2:
		_race_route.append(_race_route[0])
	# Races follow the AI route itself, so opponents and player pass the same gates.
	var ai_path: PackedVector3Array = data.get("waypoints", PackedVector3Array())
	if ai_path.size() > 3 and data.get("speeds", PackedFloat32Array()).size() == ai_path.size():
		distance = 100.0
		for i in ai_path.size():
			if i > 0: distance += ai_path[i].distance_to(ai_path[i - 1])
			if distance >= 45.0:
				_race_gates.append(ai_path[i])
				distance = 0.0
		if _race_gates.size() > 2:
			_race_gates.append(_race_gates[0])
	_records.load(records_path)
	_marker = Node3D.new()
	add_child(_marker)
	var material := C.mat(Color("71e0cb"))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x: float in [-5.0, 5.0]:
		C.box(_marker, null, Vector3(x, 2, 0), Vector3(0.09, 2, 0.09), Vector3.ZERO, material, 0.8, false, false)
	C.box(_marker, null, Vector3(0, 4.0, 0), Vector3(5.1, 0.09, 0.09), Vector3.ZERO, material, 0.8, false, false)
	_marker.hide()

## Modes offered on this map: deliveries need the city streets, races an AI route.
func available_modes() -> Array[int]:
	var out: Array[int] = [0, 1, 2]
	if map_id == "city": out.append(3)
	if _race_gates.size() > 3: out.append(4)
	return out

func choose() -> void:
	last_result = {}
	cancel("")
	var modes := available_modes()
	mode = modes[(modes.find(mode) + 1) % modes.size()]
	message = "F3 Wechseln · F4 am Start aufstellen" if mode else "F3 Aktivität wählen"
	_read_best()

func _read_best() -> void:
	_car_id = str(vehicle.get_info().get("id", "car")) if is_instance_valid(vehicle) else "car"
	best = float(_records.get_value(map_id + ":" + _car_id, str(mode), 0.0))

func start() -> void:
	if active:
		cancel("Lauf abgebrochen · F4 erneut starten")
		return
	if mode == 0 or not is_instance_valid(vehicle): return
	last_result = {}
	_read_best()
	route = _race_route.duplicate()
	var spawn := _start
	if mode == 1 and route.size() > 2:
		spawn = C.car_xform(route[0], route[1] - route[0])
	elif mode == 4:
		if _race_gates.size() < 4 or not spawn_opponents.is_valid():
			return
		route = _race_gates.duplicate()
		spawn = C.car_xform(route[0], route[1] - route[0])
	elif mode == 3:
		# Curbside stops along existing streets, not inside the buildings.
		route = PackedVector3Array([Vector3(4, 0, 44), Vector3(92, 0, -132), Vector3(260, 0, 220), Vector3(-4, 0, 132)])
		spawn = C.car_xform(route[0], Vector3.FORWARD)
	gate = 1
	elapsed = 0
	score = 0
	combo = 1
	_hold = 0
	_drift_chain = 0
	countdown = 3.0
	active = true
	_arming = true
	_reset_wait = 0.0
	_spawn_position = spawn.origin
	vehicle.reset_to(spawn)
	vehicle.set_input(0, 1, 0, 1)
	place = 0
	if mode == 4:
		_field.setup(route, spawn_opponents.call(RaceField.grid(spawn, race_size)))
		_field.hold(true)
	_previous = spawn.origin + Vector3.UP * 0.6
	_broken = int(vehicle.get_telemetry().get("broken_beams", 0))
	_clock = float(world.get_stats()["sim_time"])
	message = "Bereit machen"
	_update_marker()

func cancel(reason: String) -> void:
	active = false
	message = reason
	if _marker: _marker.hide()
	if not _field.drivers.is_empty():
		var drivers := _field.drivers
		_field.drivers = []
		if release_opponents.is_valid(): release_opponents.call(drivers)

## Opponent vehicles of the running race.
func opponents() -> Array:
	return _field.drivers.map(func(d): return d.vehicle)

func target() -> Vector3:
	return route[gate] if active and mode != 2 and gate < route.size() else Vector3.INF

func on_impact(strength: float) -> void:
	if active and mode == 2 and strength > 35.0:
		_drift_chain = 0
		_hold = 0
		combo = 1

static func crossed(previous: Vector3, point: Vector3, center: Vector3, forward: Vector3) -> bool:
	# Only accept the forward crossing of the next gate at road height.
	var a := (previous - center).dot(forward)
	var b := (point - center).dot(forward)
	if a >= 0 or b < 0 or point.distance_to(previous) > 22: return false
	var hit := previous.lerp(point, -a / maxf(0.00001, b - a)) - center
	return Vector2(hit.x, hit.z).length() <= 7.0 and absf(hit.y) < 3.0

static func drift_rate(speed: float, angle: float, slip: float, contact: float) -> float:
	if speed < 20 or speed > 140 or angle < 12 or angle > 70 or contact < 0.45 or slip < 2.5: return 0.0
	return minf(speed, 90) * sin(deg_to_rad(angle)) * 0.8

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(vehicle) or world.paused: return
	var now := float(world.get_stats()["sim_time"])
	var dt := maxf(0, now - _clock)
	_clock = now
	var position := vehicle.get_position_ws()
	# reset_to is queued for the physics thread. Wait for its published snapshot;
	# otherwise the previous location looks like a teleport and invalidates F4.
	if _arming:
		_reset_wait += dt
		if position.distance_to(_spawn_position) < 5.0:
			_arming = false
			_previous = position
			_broken = int(vehicle.get_telemetry().get("broken_beams", 0))
		elif _reset_wait > 2.0:
			cancel("Startposition konnte nicht erreicht werden")
		return
	if position.distance_to(_previous) > 22:
		cancel("Lauf ungültig: Fahrzeug versetzt")
		return
	if countdown > 0:
		countdown = maxf(0, countdown - dt)
		vehicle.set_input(0, 1, 0, 1)
		message = "Start in %d" % ceili(countdown) if countdown > 0 else "Los!"
		if countdown <= 0: _field.hold(false)
		_previous = position
		return
	elapsed += dt
	var t := vehicle.get_telemetry()
	if mode == 2:
		var velocity := vehicle.get_velocity()
		velocity.y = 0
		var forward := vehicle.get_forward()
		forward.y = 0
		var angle := rad_to_deg(acos(clampf(absf(velocity.normalized().dot(forward.normalized())), 0, 1)))
		var slip := 0.0
		var contact := 0.0
		var loads := vehicle.get_wheel_load()
		var slips := vehicle.get_wheel_slip()
		for i in mini(loads.size(), slips.size()):
			contact += loads[i] * 0.25
			slip += slips[i] * 0.25
		var rate := drift_rate(absf(t["speed_kmh"]), angle, slip, contact)
		if int(t.get("broken_beams", 0)) > _broken:
			_drift_chain = 0
			_broken = int(t["broken_beams"])
			_hold = 0
			rate = 0
		if rate > 0:
			_drift_chain += dt
			_hold = 1.2
		else:
			_hold -= dt
			if _hold <= 0: _drift_chain = 0
		combo = minf(4, 1 + _drift_chain / 4.0)
		score += rate * combo * dt
		message = "%d Punkte  ·  ×%.1f  ·  noch %.0f s" % [score, combo, maxf(0, 60 - elapsed)]
		if elapsed >= 60: _finish()
	elif gate < route.size():
		if mode == 3:
			var at_stop := position.distance_to(route[gate] + Vector3.UP * 0.6) < 7.0 and absf(t["speed_kmh"]) < 2.0
			_hold = _hold + dt if at_stop else 0.0
			message = "Lieferung %d / %d · am Ziel 2 s halten" % [gate, route.size() - 1]
			if _hold >= 2.0:
				_hold = 0
				gate += 1
		else:
			var forward := (route[gate] - route[gate - 1]).normalized()
			forward.y = 0
			if crossed(_previous, position, route[gate], forward.normalized()): gate += 1
			message = "Checkpoint %d / %d · %.2f s" % [mini(gate, route.size() - 1), route.size() - 1, elapsed]
			if mode == 4:
				_field.update(elapsed, crossed)
				place = 1 + _field.finished_count() if gate >= route.size() else _field.place(position, gate, false)
				message = "Platz %d / %d · " % [place, race_size + 1] + message
		if gate >= route.size(): _finish()
		else: _update_marker()
	_previous = position

func navigation_hint() -> String:
	if not active or mode == 2 or gate >= route.size() or not is_instance_valid(vehicle): return ""
	var distance := Vector2(vehicle.get_position_ws().x - route[gate].x, vehicle.get_position_ws().z - route[gate].z).length()
	var instruction := "Ziel" if gate == route.size() - 1 else "Geradeaus"
	if gate + 1 < route.size():
		var incoming := route[gate] - route[gate - 1]
		var outgoing := route[gate + 1] - route[gate]
		var angle := atan2(incoming.x * outgoing.z - incoming.z * outgoing.x, incoming.dot(outgoing))
		if absf(angle) > deg_to_rad(12):
			instruction = "Rechtskurve" if angle > 0 else "Linkskurve"
	return "%s in %.0f m" % [instruction, distance]

func _finish() -> void:
	if not active: return
	var value := score if mode == 2 else elapsed
	var previous_best := best
	var improved := best == 0 or (value > best if mode == 2 else value < best)
	var save_error := OK
	if improved:
		_records.set_value(map_id + ":" + _car_id, str(mode), value)
		save_error = _records.save(records_path)
		if save_error == OK:
			best = value
		else:
			# Failed writes must not masquerade as a persistent personal best.
			_records.set_value(map_id + ":" + _car_id, str(mode), previous_best)
	last_result = {
		"mode": mode, "map_id": map_id, "car_id": _car_id, "result": value,
		"elapsed": elapsed, "score": score, "checkpoints": maxi(0, gate - 1),
		"previous_best": previous_best, "improved": improved,
		"record_saved": save_error == OK, "record_save_error": save_error,
	}
	var summary := ("Neue Bestleistung! " if improved else "Ziel! ") + ("%d Punkte" % score if mode == 2 else "%.2f s" % elapsed)
	if mode == 4:
		last_result["place"] = place
		last_result["field"] = race_size + 1
		summary = "Platz %d von %d · %.2f s" % [place, race_size + 1, elapsed] + (" · Bestzeit!" if improved else "")
	if save_error != OK: summary += " · Speichern fehlgeschlagen"
	cancel(summary)
	completed.emit(last_result.duplicate(true))

func _update_marker() -> void:
	var next := target()
	_marker.visible = next.is_finite()
	if not _marker.visible: return
	_marker.global_position = next
	var heading := route[gate] - route[maxi(0, gate - 1)]
	_marker.rotation.y = atan2(heading.x, heading.z)
