extends Node3D
## Small driving challenges using simulation time, ordered gates and persistent records.
const C := preload("res://scripts/maps/common.gd")
const MODES := ["Freie Fahrt", "Zeitfahren", "Drift-Challenge", "Lieferfahrt"]
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

func configure(id: String, data: Dictionary) -> void:
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
	_records.load("user://driving_records.cfg")
	_marker = Node3D.new()
	add_child(_marker)
	var material := C.mat(Color("71e0cb"))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x: float in [-5.0, 5.0]:
		C.box(_marker, null, Vector3(x, 2, 0), Vector3(0.09, 2, 0.09), Vector3.ZERO, material, 0.8, false, false)
	C.box(_marker, null, Vector3(0, 4.0, 0), Vector3(5.1, 0.09, 0.09), Vector3.ZERO, material, 0.8, false, false)
	_marker.hide()

func choose() -> void:
	cancel("")
	mode = (mode + 1) % (4 if map_id == "city" else 3)
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
	_read_best()
	route = _race_route.duplicate()
	var spawn := _start
	if mode == 1 and route.size() > 2:
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
	_previous = spawn.origin + Vector3.UP * 0.6
	_broken = int(vehicle.get_telemetry().get("broken_beams", 0))
	_clock = float(world.get_stats()["sim_time"])
	message = "Bereit machen"
	_update_marker()

func cancel(reason: String) -> void:
	active = false
	message = reason
	if _marker: _marker.hide()

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
		if gate >= route.size(): _finish()
		else: _update_marker()
	_previous = position

func _finish() -> void:
	var result := score if mode == 2 else elapsed
	var improved := best == 0 or (result > best if mode == 2 else result < best)
	if improved:
		best = result
		_records.set_value(map_id + ":" + _car_id, str(mode), best)
		_records.save("user://driving_records.cfg")
	cancel(("Neue Bestleistung! " if improved else "Ziel! ") + ("%d Punkte" % score if mode == 2 else "%.2f s" % elapsed))

func _update_marker() -> void:
	var next := target()
	_marker.visible = next.is_finite()
	if not _marker.visible: return
	_marker.global_position = next
	var heading := route[gate] - route[maxi(0, gate - 1)]
	_marker.rotation.y = atan2(heading.x, heading.z)
