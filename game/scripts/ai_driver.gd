extends RefCounted
## Simple waypoint-following AI driver (traffic / opponents).

var vehicle: SBVehicle
var waypoints: PackedVector3Array
var speeds: PackedFloat32Array
var idx := 0
var speed_scale := 1.0
var _stuck := 0.0
var _reverse_t := 0.0
## Other vehicles to keep a distance to (set by the game scene).
var others: Array = []


func _init(v: SBVehicle, wp: PackedVector3Array, sp: PackedFloat32Array, scale := 1.0) -> void:
	vehicle = v
	waypoints = wp
	speeds = sp
	speed_scale = scale
	idx = _nearest()


func _nearest() -> int:
	var p := vehicle.get_position_ws()
	var best := 0
	var bd := 1e18
	for i in waypoints.size():
		var d := p.distance_squared_to(waypoints[i])
		if d < bd:
			bd = d
			best = i
	return best


func update(delta: float) -> void:
	if waypoints.is_empty() or not is_instance_valid(vehicle):
		return
	var p := vehicle.get_position_ws()
	var n := waypoints.size()
	# Advance along the path.
	for _k in 8:
		var a := waypoints[idx]
		var b := waypoints[(idx + 1) % n]
		var seg := b - a
		if (p - a).dot(seg) > seg.length_squared() * 0.5 or p.distance_to(b) < 6.0:
			idx = (idx + 1) % n
		else:
			break
	var v := vehicle.get_speed_kmh() / 3.6
	var look := clampi(int(2 + v * 0.18), 2, 10)
	var target := waypoints[(idx + look) % n]
	var fwd := vehicle.get_forward()
	var right := vehicle.get_right()
	var to := target - p
	to.y = 0
	var ang := atan2(to.dot(-right), to.dot(fwd))
	var steer := clampf(ang * 1.6, -1.0, 1.0)
	var target_v := speeds[(idx + look / 2) % n] * speed_scale
	# Keep a 1.5 s gap plus 7 m to the vehicle ahead in the own lane and stop behind it.
	var gap_limit := INF
	for other in others:
		if not is_instance_valid(other) or other == vehicle:
			continue
		var rel: Vector3 = other.get_position_ws() - p
		var along := rel.dot(fwd)
		if along <= 0.0 or along > 60.0 or absf(rel.dot(right)) > 2.6:
			continue
		var other_v: float = maxf(0.0, other.get_velocity().dot(fwd))
		var free := along - 7.0
		gap_limit = minf(gap_limit, maxf(0.0, other_v + (free - v * 1.5) * 0.35))
		if free < 1.0:
			gap_limit = 0.0
	target_v = minf(target_v, gap_limit)
	var throttle := clampf((target_v - v) * 0.3, 0.0, 1.0)
	var brake := clampf((v - target_v - (1.5 if is_inf(gap_limit) else 0.3)) * 0.25, 0.0, 1.0)
	if gap_limit < 0.5 and v < 2.0:
		brake = maxf(brake, 0.5)   # hold the car while waiting behind another
	# Stuck recovery: reverse briefly, then reset onto the road.
	if throttle > 0.3 and v < 1.0 and gap_limit > 1.0:
		_stuck += delta
	else:
		_stuck = maxf(0.0, _stuck - delta)
	if _stuck > 3.0 and _reverse_t <= 0.0:
		_reverse_t = 1.8
		vehicle.set_gear(-1)
	if _reverse_t > 0.0:
		_reverse_t -= delta
		vehicle.set_input(0.6, 0.0, -steer, 0.0)
		if _reverse_t <= 0.0:
			vehicle.set_gear(1)
			_stuck = 0.0
		return
	if _stuck > 2.0 and vehicle.get_up().y < 0.3:
		reset_on_path()
		return
	vehicle.set_input(throttle, brake, steer, 0.0)


func reset_on_path() -> void:
	idx = _nearest()
	var a := waypoints[idx]
	var b := waypoints[(idx + 1) % waypoints.size()]
	vehicle.reset_to(preload("res://scripts/map_builder.gd").car_xform(a, b - a))
	_stuck = 0.0
