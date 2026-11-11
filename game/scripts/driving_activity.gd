extends Node3D
## Small driving challenges using simulation time, ordered gates and persistent records.
signal completed(result: Dictionary)

const C := preload("res://scripts/maps/common.gd")
const RaceField := preload("res://scripts/race_field.gd")
const MODES := ["Freie Fahrt", "Zeitfahren", "Drift-Challenge", "Lieferfahrt", "Rennen", "Crashtest", "Verfolgungsjagd"]
## Pursuit: escape by opening a gap of ESCAPE_GAP metres and holding it ESCAPE_HOLD seconds, or by
## staying free until PURSUIT_TIME; caught after CAUGHT_HOLD s at walking pace next to the police.
const ESCAPE_GAP := 300.0
const ESCAPE_HOLD := 8.0
const CAUGHT_GAP := 8.0
const CAUGHT_HOLD := 3.0
const PURSUIT_TIME := 180.0
## Crash test (proving ground): run-up on the crash lane into the concrete wall at >= 50 km/h.
const CRASH_START := Vector3(60.0, 0.0, -34.0)
const CRASH_WALL_X := 224.0
const CRASH_MIN_KMH := 50.0
## Race opponents are created and removed by the game scene, which owns the vehicles:
## spawn_opponents(grid: Array[Transform3D]) -> Array (AIDriver) and release_opponents(drivers).
var spawn_opponents: Callable
var release_opponents: Callable
## spawn_police(xform: Transform3D, fugitive: SBVehicle) -> AIDriver for the pursuit.
var spawn_police: Callable
var police = null             # AIDriver of the pursuing car
var escaped := false
var _escape_t := 0.0
var _ai_path := PackedVector3Array()
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
var _crash_speed := 0.0         # km/h just before the impact
var _crash_peak_g := 0.0
var _crash_settle := -1.0       # s since the impact (-1 = not yet)
var _last_velocity := Vector3.ZERO
var report := {}                # crash test result for the HUD
var _ref_speed := 15.0          # m/s, mean of the map's AI target speeds (medal reference pace)
const MEDALS := ["", "Bronze", "Silber", "Gold"]

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
	_ai_path = ai_path
	if ai_path.size() > 3 and data.get("speeds", PackedFloat32Array()).size() == ai_path.size():
		distance = 100.0
		for i in ai_path.size():
			if i > 0: distance += ai_path[i].distance_to(ai_path[i - 1])
			if distance >= 45.0:
				_race_gates.append(ai_path[i])
				distance = 0.0
		if _race_gates.size() > 2:
			_race_gates.append(_race_gates[0])
	var speeds: PackedFloat32Array = data.get("speeds", PackedFloat32Array())
	if speeds.size() > 0:
		var total := 0.0
		for v in speeds: total += v
		_ref_speed = clampf(total / speeds.size(), 6.0, 45.0)
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
	if map_id == "proving_grounds": out.append(5)
	if _ai_path.size() > 10 and spawn_police.is_valid(): out.append(6)
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
	elif mode == 5:
		route = PackedVector3Array([CRASH_START, Vector3(CRASH_WALL_X, 0, CRASH_START.z)])
		spawn = C.car_xform(CRASH_START, Vector3.RIGHT)
		_crash_speed = 0.0
		_crash_peak_g = 0.0
		_crash_settle = -1.0
		_last_velocity = Vector3.ZERO
		report = {}
	elif mode == 6:
		if not spawn_police.is_valid() or _ai_path.size() < 10:
			return
		route = PackedVector3Array([spawn.origin])
		escaped = false
		_escape_t = 0.0
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
	if mode == 6:
		police = spawn_police.call(police_start(spawn.origin, spawn), vehicle)
		if police: police.hold = true
	_previous = spawn.origin + Vector3.UP * 0.6
	_broken = int(vehicle.get_telemetry().get("broken_beams", 0))
	_clock = float(world.get_stats()["sim_time"])
	message = "Bereit machen"
	_update_marker()

func cancel(reason: String) -> void:
	active = false
	message = reason
	if _marker: _marker.hide()
	if police != null:
		var p = police
		police = null
		if release_opponents.is_valid(): release_opponents.call([p])
	if not _field.drivers.is_empty():
		var drivers := _field.drivers
		_field.drivers = []
		if release_opponents.is_valid(): release_opponents.call(drivers)

## Opponent vehicles of the running race.
func opponents() -> Array:
	return _field.drivers.map(func(d): return d.vehicle)

func target() -> Vector3:
	return route[gate] if active and mode != 2 and mode != 5 and mode != 6 and gate < route.size() else Vector3.INF

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
		if countdown <= 0:
			_field.hold(false)
			if police != null: police.hold = false
		_previous = position
		return
	elapsed += dt
	var t := vehicle.get_telemetry()
	if mode == 5:
		_crash_test(dt, t)
		_previous = position
		return
	if mode == 6:
		_pursuit(dt, t, position)
		_previous = position
		return
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

## Police 50 m behind the start along the AI route, facing the start. Where the start is off the
## route (city), 45 m behind it on the same street instead.
func police_start(at: Vector3, start := Transform3D.IDENTITY) -> Transform3D:
	var n := _ai_path.size()
	var near := 0
	for i in n:
		if _ai_path[i].distance_squared_to(at) < _ai_path[near].distance_squared_to(at): near = i
	if _ai_path[near].distance_to(at) > 30.0 and start != Transform3D.IDENTITY:
		var forward := start.basis.x   # car_xform: x is the heading
		return C.car_xform(at - forward * 45.0, forward)
	var k := near
	var back := 0.0
	while back < 50.0:
		var j := posmod(k - 1, n)
		back += _ai_path[j].distance_to(_ai_path[k])
		k = j
	return C.car_xform(_ai_path[k], _ai_path[posmod(k + 1, n)] - _ai_path[k])


func _pursuit(dt: float, t: Dictionary, position: Vector3) -> void:
	if police == null or not is_instance_valid(police.vehicle):
		cancel("Verfolgung abgebrochen")
		return
	var gap := position.distance_to(police.vehicle.get_position_ws())
	var slow := absf(float(t["speed_kmh"])) < 10.0
	_hold = _hold + dt if gap < CAUGHT_GAP and slow else 0.0
	_escape_t = _escape_t + dt if gap > ESCAPE_GAP else 0.0
	if _hold >= CAUGHT_HOLD:
		escaped = false
		_finish()
		return
	if _escape_t >= ESCAPE_HOLD or elapsed >= PURSUIT_TIME:
		escaped = true
		_finish()
		return
	if _hold > 0.0:
		message = "Angehalten! Festnahme in %.1f s" % (CAUGHT_HOLD - _hold)
	elif _escape_t > 0.0:
		message = "Abstand %d m · abgehängt in %.0f s" % [gap, ESCAPE_HOLD - _escape_t]
	else:
		message = "Polizei %d m hinter dir · noch %.0f s" % [gap, maxf(0.0, PURSUIT_TIME - elapsed)]


func _crash_test(dt: float, t: Dictionary) -> void:
	var velocity := vehicle.get_velocity()
	var speed := absf(float(t["speed_kmh"]))
	if _crash_settle < 0.0:
		var to_wall := CRASH_WALL_X - 1.0 - vehicle.get_position_ws().x
		message = "Crashtest · Wand in %.0f m · %.0f km/h (mind. %.0f)" % [maxf(0.0, to_wall), speed, CRASH_MIN_KMH]
		if dt > 0.0 and _last_velocity != Vector3.ZERO:
			var decel := (_last_velocity - velocity).length() / dt / 9.81
			if decel > 6.0 and to_wall < 6.0:
				_crash_settle = 0.0
				_crash_speed = _last_velocity.length() * 3.6
				_crash_peak_g = decel
		_last_velocity = velocity
		if elapsed > 60.0: cancel("Crashtest abgebrochen: Wand nicht erreicht")
		return
	if dt > 0.0:
		_crash_peak_g = maxf(_crash_peak_g, (_last_velocity - velocity).length() / dt / 9.81)
	_last_velocity = velocity
	_crash_settle += dt
	message = "Aufprall mit %.0f km/h …" % _crash_speed
	if _crash_settle >= 2.5 and speed < 3.0:
		_crash_report(t)

## Rates the crash: occupant load from the deceleration, how much of the impact the crumple zone
## took (front damage) and whether the passenger cell stayed intact (roof / side zones).
static func crash_stars(speed: float, peak_g: float, front: float, cabin: float) -> int:
	if speed < CRASH_MIN_KMH: return 0
	var stars := 5
	if peak_g > 45.0: stars -= 1
	if peak_g > 65.0: stars -= 1
	if peak_g > 90.0: stars -= 1
	if cabin > 0.15: stars -= 1
	if cabin > 0.35: stars -= 1
	if front < 0.15: stars -= 1   # a rigid front passes the crash pulse straight to the occupants
	return clampi(stars, 1, 5)

func _crash_report(t: Dictionary) -> void:
	var zones: Array = t.get("zones", [])
	var front := float(zones[0]) if zones.size() > 0 else 0.0
	var cabin := 0.0
	for z in [2, 3, 4]:
		if zones.size() > z: cabin = maxf(cabin, float(zones[z]))
	var stars := crash_stars(_crash_speed, _crash_peak_g, front, cabin)
	var doors_off := 0
	for state: Dictionary in vehicle.get_door_states():
		if bool(state.get("missing", false)): doors_off += 1
	var engine := "Motor läuft" if bool(t["running"]) else ("Motor fest" if bool(t["seized"]) else "Motor aus")
	if doors_off > 0: engine += " · %d Tür%s abgerissen" % [doors_off, "en" if doors_off > 1 else ""]
	if float(t.get("radiator_damage", 0.0)) > 0.04: engine += " · Kühler leck"
	if float(t.get("fire", 0.0)) > 0.0: engine += " · BRAND"
	report = {"speed": _crash_speed, "peak_g": _crash_peak_g, "front": front, "cabin": cabin, "stars": stars, "engine": engine}
	score = stars
	if _crash_speed < CRASH_MIN_KMH:
		cancel("Zu langsam: %.0f km/h (mindestens %.0f) · F4 neuer Versuch" % [_crash_speed, CRASH_MIN_KMH])
		return
	_finish()

func navigation_hint() -> String:
	if not active or mode == 2 or mode == 5 or mode == 6 or gate >= route.size() or not is_instance_valid(vehicle): return ""
	var distance := Vector2(vehicle.get_position_ws().x - route[gate].x, vehicle.get_position_ws().z - route[gate].z).length()
	var instruction := "Ziel" if gate == route.size() - 1 else "Geradeaus"
	if gate + 1 < route.size():
		var incoming := route[gate] - route[gate - 1]
		var outgoing := route[gate + 1] - route[gate]
		var angle := atan2(incoming.x * outgoing.z - incoming.z * outgoing.x, incoming.dot(outgoing))
		if absf(angle) > deg_to_rad(12):
			instruction = "Rechtskurve" if angle > 0 else "Linkskurve"
	return "%s in %.0f m" % [instruction, distance]

## Reference time (s) for a timed run over `points`: the AI's mean target pace on this map.
## Deliveries run on streets, ~35 % longer than the straight lines between the stops.
func reference_time(points: PackedVector3Array, run_mode: int) -> float:
	var length := 0.0
	for i in range(1, points.size()): length += points[i].distance_to(points[i - 1])
	if run_mode == 3: length *= 1.35
	return length / _ref_speed

## Medal for a result: 0 none, 1 bronze, 2 silver, 3 gold. Timed runs against the reference
## pace (gold at it, silver within 20 %, bronze within 50 %), races by place, the crash test by
## stars, the 60 s drift challenge by points. Drift thresholds follow the scoring and are checked
## against a scripted drifter (drift_medal_test): an unbroken minute at 55 km/h and ~30 deg makes
## ~3,600 points (silver), one at ~70 km/h and ~38 deg ~6,300 (gold); bronze is some 20 s of clean
## drifting. Not yet played with a gamepad by a person.
const DRIFT_MEDAL_POINTS := [1000.0, 2500.0, 5000.0]
func medal_for(run_mode: int, result: Dictionary) -> int:
	match run_mode:
		2:
			var points := float(result.get("score", 0.0))
			return 3 if points >= DRIFT_MEDAL_POINTS[2] else (2 if points >= DRIFT_MEDAL_POINTS[1] else (1 if points >= DRIFT_MEDAL_POINTS[0] else 0))
		1, 3:
			var ref := reference_time(route, run_mode)
			var t := float(result.get("elapsed", INF))
			if ref <= 0.0: return 0
			return 3 if t <= ref else (2 if t <= ref * 1.2 else (1 if t <= ref * 1.5 else 0))
		4:
			var p := int(result.get("place", 0))
			return 3 if p == 1 else (2 if p == 2 else (1 if p == 3 and int(result.get("field", 3)) > 3 else 0))
		5:
			var stars := int(result.get("crash", {}).get("stars", 0))
			return 3 if stars >= 5 else (2 if stars == 4 else (1 if stars == 3 else 0))
		6:
			if not bool(result.get("escaped", false)): return 0
			var t := float(result.get("elapsed", INF))
			return 3 if t <= 60.0 else (2 if t <= 100.0 else 1)
	return 0

## Best medal won so far on this map in a mode (any car).
func best_medal(for_map: String, run_mode: int) -> int:
	return int(_records.get_value("medals", for_map + ":" + str(run_mode), 0))

## Medal tally over all maps and modes: [bronze, silver, gold].
static func medal_tally(path := "user://driving_records.cfg") -> Array[int]:
	var cfg := ConfigFile.new()
	var out: Array[int] = [0, 0, 0]
	if cfg.load(path) != OK or not cfg.has_section("medals"): return out
	for key in cfg.get_section_keys("medals"):
		var m := int(cfg.get_value("medals", key, 0))
		if m >= 1 and m <= 3: out[m - 1] += 1
	return out

func _finish() -> void:
	if not active: return
	var higher_is_better := mode == 2 or mode == 5
	var value := score if higher_is_better else elapsed
	var previous_best := best
	var improved := best == 0 or (value > best if higher_is_better else value < best)
	if mode == 6 and not escaped:
		improved = false   # an arrest is no record
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
	if mode == 5:
		last_result["crash"] = report.duplicate()
		summary = "Crashtest: %d von 5 Sternen · %.0f km/h · %.0f g · Front %d %% · Fahrgastzelle %d %% · %s" % [
			int(report["stars"]), report["speed"], report["peak_g"], roundi(100 * float(report["front"])), roundi(100 * float(report["cabin"])), report["engine"]]
		if improved: summary += " · Bestwert!"
	if mode == 6:
		last_result["escaped"] = escaped
		summary = ("Entkommen nach %.1f s" % elapsed if escaped else "Festgenommen nach %.1f s" % elapsed) + (" · Bestzeit!" if improved else "")
	if mode == 4:
		last_result["place"] = place
		last_result["field"] = race_size + 1
		summary = "Platz %d von %d · %.2f s" % [place, race_size + 1, elapsed] + (" · Bestzeit!" if improved else "")
	var medal := medal_for(mode, last_result)
	last_result["medal"] = medal
	if medal > 0:
		var previous_medal := best_medal(map_id, mode)
		summary += " · %s" % MEDALS[medal]
		if medal > previous_medal:
			_records.set_value("medals", map_id + ":" + str(mode), medal)
			if _records.save(records_path) != OK:
				_records.set_value("medals", map_id + ":" + str(mode), previous_medal)
				save_error = FAILED
			else:
				summary += " (neu)"
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
