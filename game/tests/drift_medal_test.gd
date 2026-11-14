extends SceneTree
## Drift medals against a driver: a scripted drifter (counter-steer holding the drift angle, throttle
## holding the speed) circles on the proving ground's concrete pad for 60 s, scored with the drift
## challenge's own formula and combo. A steady, unbroken drift at 55 km/h and ~30 deg earns silver;
## a fast, steep one at ~70 km/h and ~38 deg earns gold. This also checks that a rear-drive car can
## hold a long drift at all. The circles are ones sliding tyres can hold (~0.9 g: 26 m at 55 km/h,
## 44 m at 70 km/h; the 28 m once asked of the fast drift needed 1.4 g), and the drifter kicks the
## tail out at moderate speed, holds the angle with steering and throttle and lifts when it runs
## away, as a driver does. The fast circle runs on the open west part of the pad.
## godot --headless -s res://tests/drift_medal_test.gd
const Activity := preload("res://scripts/driving_activity.gd")
const STEP := 0.02
var frame := 0

var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/fastback_69.car.json"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
	game.settings["automatic"] = true
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")

func _process(_d: float) -> bool:
	frame += 1
	var scene := current_scene
	if scene == null or not scene.get("player"):
		return frame > 600
	if frame < 5:
		return false
	_run(scene)
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true

func _run(scene: Node) -> void:
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)
	scene.activity.set_process(false)
	var steady: Array = _drift(scene, 55.0, 34.0, 26.0, Vector3(-110, 0.5, -130))
	print("  steady drift 55 km/h: %.0f points, longest chain %.0f s" % steady)
	check(steady[1] > 40.0, "A rear-drive car holds a drift for most of the minute")
	check(steady[0] >= Activity.DRIFT_MEDAL_POINTS[1] and steady[0] < Activity.DRIFT_MEDAL_POINTS[2], "A steady medium-speed drift earns silver")
	# The fast circle (88 m across) on the open west part of the pad: from the steady drift's start
	# it reached z = -218, at the pad's edge (-221), and every lap the tail ran off the concrete
	# at the same spot and the drift collapsed.
	var fast: Array = _drift(scene, 70.0, 40.0, 44.0, Vector3(-255, 0.5, -78))
	print("  fast drift 70 km/h: %.0f points, longest chain %.0f s" % fast)
	check(fast[0] >= Activity.DRIFT_MEDAL_POINTS[2], "A fast, steep drift held for the minute earns gold")


func _drift(scene: Node, speed_t: float, beta_deg: float, radius_t: float, start: Vector3) -> Array:
	var world: SBWorld = scene.world
	var car: SBVehicle = scene.player
	var beta_t := deg_to_rad(beta_deg)
	var lock := 0.6
	car.reset_to(Transform3D(Basis.IDENTITY, start))   # facing +x along the pad
	world.step_blocking(1.0)
	var centre := Vector3.INF
	var t := 0.0
	var phase := 0
	var score := 0.0
	var chain := 0.0
	var hold := 0.0
	var drift_time := 0.0
	var log_t := 0.0
	var best_chain := 0.0
	var integ := 0.0
	var prev_heading := 0.0
	var yaw_f := 0.0
	while t < 75.0:
		var p := car.get_position_ws()
		var v := car.get_velocity()
		v.y = 0
		var f := car.get_forward()
		f.y = 0
		f = f.normalized()
		var speed := v.length() * 3.6
		var beta := 0.0
		if v.length() > 1.0:
			beta = atan2(f.cross(v.normalized()).y * -1.0, f.dot(v.normalized()))   # + : nose left of travel
		var heading := atan2(f.z, f.x)
		var throttle := 0.0
		var steer := 0.0
		var hb := 0.0
		if phase == 0:
			throttle = 1.0
			steer = 0.0
			# Kick the tail out at a moderate speed and build the speed up in the drift (initiated at
			# ~60 km/h the sliding rear swung past the angle into a spin).
			if speed > minf(speed_t * 0.85, 48.0):
				phase = 1
				centre = p + f.cross(Vector3.UP) * -radius_t   # circle centre to the left
		elif phase == 1:
			steer = 1.0
			throttle = 1.0
			# Hand over to the angle control early: waiting for 60 % of the angle let the swinging
			# tail overshoot to ~60 deg, and the lift that caught it straightened the car.
			if beta > beta_t * 0.45:
				phase = 2
		else:
			# Steering holds the drift angle: wheels along the travel direction, more counter-steer
			# when the angle grows, damped by the yaw rate error; a weak pull back onto the circle.
			var r := Vector2(p.x - centre.x, p.z - centre.z).length()
			# Yaw rate from one 20 ms step is noisy (the body rocks on its tyres): lightly filtered
			# (a ~0.1 s filter lagged enough to destabilise the counter-steer).
			var yaw_raw := -wrapf(heading - prev_heading, -PI, PI) / STEP   # + : turning left
			yaw_f += (yaw_raw - yaw_f) * 0.5
			var yaw_rate := yaw_f
			var want_rate := v.length() / radius_t
			var kb := 1.2
			var kr := 0.25
			var delta := -beta - kb * (beta - beta_t) - kr * (yaw_rate - want_rate) + clampf((r - radius_t) * 0.01, -0.12, 0.12)
			steer = clampf(delta / lock, -1.0, 1.0)
			# Throttle holds the speed (and with it the rear slip that keeps the car sideways).
			integ = clampf(integ + (speed_t - speed) * STEP * 0.02, -0.4, 0.4)
			throttle = clampf(0.45 + 0.04 * (speed_t - speed) + integ, 0.0, 1.0)
			# The angle is held with the throttle as well: more power when the tail starts to grip
			# again (the angle falls off and the drift would straighten), a lift when it runs away
			# (full throttle on a sliding rear spins the car).
			if beta < beta_t * 0.85:
				throttle = maxf(throttle, clampf(0.55 + 2.0 * (beta_t * 0.85 - beta) / beta_t, 0.0, 1.0))
			throttle = minf(throttle, clampf(1.0 - 2.0 * (beta - beta_t) / beta_t, 0.15, 1.0))
		prev_heading = heading
		car.set_input(throttle, 0.0, steer, hb)
		world.step_blocking(STEP)
		t += STEP
		# Score exactly like the drift challenge (60 s from the moment the drift is established).
		if phase == 2 and drift_time < 60.0:
			drift_time += STEP
			var loads := car.get_wheel_load()
			var slips := car.get_wheel_slip()
			var slip := 0.0
			var contact := 0.0
			for i in mini(loads.size(), slips.size()):
				contact += loads[i] * 0.25
				slip += slips[i] * 0.25
			var rate := Activity.drift_rate(speed, rad_to_deg(absf(beta)), slip, contact)
			if OS.has_environment("DRIFT_DEBUG") and int(round(drift_time / STEP)) % 25 == 0:
				print("    t=%.1f v=%.0f beta=%.0f slip=%.2f rate=%.0f thr=%.2f steer=%.2f" % [drift_time, speed, rad_to_deg(beta), slip, rate, throttle, steer])
			if rate > 0:
				chain += STEP
				hold = 1.2
			else:
				hold -= STEP
				if hold <= 0: chain = 0
			best_chain = maxf(best_chain, chain)
			var combo := minf(4, 1 + chain / 4.0)
			score += rate * combo * STEP
		if drift_time >= 60.0:
			break
	car.set_input(0, 1, 0, 1)
	world.step_blocking(2.0)
	return [score, best_chain]
