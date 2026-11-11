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
## Optional traffic signal controller with stop_distance(position, forward, speed).
var signals: Node
var _half_length := 2.2
## Held on the brakes (race grid during the countdown).
var hold := false
## Race opponent: short following gap and overtaking around slower cars instead of queueing.
var racing := false
var _lane := 0.0
## Pursuit (police): chase this vehicle. Far away the car runs the route in whichever direction
## closes the distance, near it steers at the fugitive's predicted position.
var pursue: SBVehicle
var pursue_speed := 1.3
var dir := 1
var _dir_timer := 0.0
const CHASE_RANGE := 60.0


func _init(v: SBVehicle, wp: PackedVector3Array, sp: PackedFloat32Array, scale := 1.0) -> void:
	vehicle = v
	waypoints = wp
	speeds = sp
	speed_scale = scale
	idx = _nearest()
	_half_length = float(v.get_info().get("length", 4.4)) * 0.5


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
	if hold:
		vehicle.set_input(0.0, 1.0, 0.0, 1.0)
		return
	var p := vehicle.get_position_ws()
	var n := waypoints.size()
	if is_instance_valid(pursue):
		_choose_direction(delta)
	# Advance along the path.
	for _k in 8:
		var a := waypoints[idx]
		var b := waypoints[posmod(idx + dir, n)]
		var seg := b - a
		if (p - a).dot(seg) > seg.length_squared() * 0.5 or p.distance_to(b) < 6.0:
			idx = posmod(idx + dir, n)
		else:
			break
	var v := vehicle.get_speed_kmh() / 3.6
	var look := clampi(int(2 + v * 0.18), 2, 10)
	var target := waypoints[posmod(idx + dir * look, n)]
	var fwd := vehicle.get_forward()
	var right := vehicle.get_right()
	if racing:
		# Pull out beside a slower car close ahead, back onto the line once past it.
		var want := 0.0
		for other in others:
			if not is_instance_valid(other) or other == vehicle:
				continue
			var rel: Vector3 = other.get_position_ws() - p
			var along := rel.dot(fwd)
			var lateral := rel.dot(right)
			if absf(along) < 6.0 and absf(lateral) < 3.0:
				# Running side by side: keep a car's width of air instead of both taking the line.
				want = -2.6 if lateral >= 0.0 else 2.6
			elif along > -3.0 and along < 22.0 and absf(lateral) < 2.4 and other.get_velocity().dot(fwd) < v - 0.5:
				want = -3.0 if lateral >= 0.0 else 3.0
		_lane = move_toward(_lane, want, delta * 2.5)
		var path_dir := waypoints[(idx + look) % n] - waypoints[(idx + look - 1 + n) % n]
		var path_right := Vector3(-path_dir.z, 0, path_dir.x).normalized()   # = dir × up, as in car_xform
		target += path_right * _lane
	var chasing := false
	var chase_dist := INF
	var chase_speed := 0.0
	if is_instance_valid(pursue):
		var q := pursue.get_position_ws()
		chase_dist = p.distance_to(q)
		# Off its route (a start beside it, a street the route does not use) it goes straight for
		# the fugitive instead of steering through houses towards the nearest route point.
		if chase_dist < CHASE_RANGE or p.distance_to(waypoints[idx]) > 25.0:
			# Aim where the fugitive will be.
			chasing = true
			var qv := pursue.get_velocity()
			chase_speed = qv.length()
			target = q + qv * clampf(chase_dist / maxf(v, 6.0), 0.0, 1.2)
	var to := target - p
	to.y = 0
	var ang := atan2(to.dot(-right), to.dot(fwd))
	var steer := clampf(ang * 1.6, -1.0, 1.0)
	var target_v := speeds[posmod(idx + dir * (look / 2), n)] * speed_scale
	if is_instance_valid(pursue):
		target_v *= pursue_speed
		if chasing:
			# Close in at a few m/s over the fugitive's speed, slowly while still turning towards it.
			target_v = clampf(chase_speed + (chase_dist - 5.0) * 0.5, 1.5, 60.0) * clampf(1.15 - absf(ang) / 1.4, 0.3, 1.0)
	# Keep a 1.5 s gap plus 7 m to the vehicle ahead in the own lane and stop behind it.
	var gap_limit := INF
	for other in others:
		if not is_instance_valid(other) or other == vehicle:
			continue
		if chasing and other == pursue:
			continue   # the chase closes in on the fugitive instead of queueing behind it
		var rel: Vector3 = other.get_position_ws() - p
		var along := rel.dot(fwd)
		if along <= 0.0 or along > 60.0 or absf(rel.dot(right)) > (1.9 if racing else 2.6):
			continue
		var other_v: float = maxf(0.0, other.get_velocity().dot(fwd))
		var free := along - (5.0 if racing else 7.0)
		gap_limit = minf(gap_limit, maxf(0.0, other_v + (free - v * (0.5 if racing else 1.5)) * 0.35))
		if free < 1.0:
			gap_limit = 0.0
	target_v = minf(target_v, gap_limit)
	# Stop at the line on red (and on amber when there is room to stop).
	if is_instance_valid(signals):
		var line := float(signals.stop_distance(p, fwd, v))
		if not is_inf(line):
			# Distance from the front bumper, with a metre to spare.
			line -= _half_length + 1.0
			gap_limit = minf(gap_limit, sqrt(maxf(0.0, 2.0 * 3.0 * line)))
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


## Route direction towards the fugitive: the shorter way round the loop, re-chosen every 2 s.
func _choose_direction(delta: float) -> void:
	_dir_timer -= delta
	if _dir_timer > 0.0:
		return
	_dir_timer = 2.0
	var n := waypoints.size()
	var q := pursue.get_position_ws()
	var best := 0
	var bd := 1e18
	for i in n:
		var d := q.distance_squared_to(waypoints[i])
		if d < bd:
			bd = d
			best = i
	var ahead := posmod(best - idx, n)
	dir = 1 if ahead <= n / 2 else -1


func reset_on_path() -> void:
	idx = _nearest()
	var a := waypoints[idx]
	var b := waypoints[posmod(idx + dir, waypoints.size())]
	vehicle.reset_to(preload("res://scripts/map_builder.gd").car_xform(a, b - a))
	_stuck = 0.0
