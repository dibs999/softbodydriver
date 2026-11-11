extends SceneTree
## Drift medals against a driver: a scripted drifter (counter-steer holding the drift angle, throttle
## holding the speed) circles on the proving ground's concrete pad for 60 s, scored with the drift
## challenge's own formula and combo. A steady, unbroken drift at 55 km/h and ~30 deg earns silver;
## a fast, steep one at ~70 km/h and ~38 deg earns gold. This also checks that a rear-drive car can
## hold a long drift at all.
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
	var steady: Array = _drift(scene, 55.0, 34.0, 22.0)
	print("  steady drift 55 km/h: %.0f points, longest chain %.0f s" % steady)
	check(steady[1] > 40.0, "A rear-drive car holds a drift for most of the minute")
	check(steady[0] >= Activity.DRIFT_MEDAL_POINTS[1] and steady[0] < Activity.DRIFT_MEDAL_POINTS[2], "A steady medium-speed drift earns silver")
	var fast: Array = _drift(scene, 70.0, 40.0, 28.0)
	print("  fast drift 70 km/h: %.0f points, longest chain %.0f s" % fast)
	check(fast[0] >= Activity.DRIFT_MEDAL_POINTS[2], "A fast, steep drift held for the minute earns gold")


func _drift(scene: Node, speed_t: float, beta_deg: float, radius_t: float) -> Array:
	var world: SBWorld = scene.world
	var car: SBVehicle = scene.player
	var beta_t := deg_to_rad(beta_deg)
	var lock := 0.6
	var start := Vector3(-110, 0.5, -130)
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
			if speed > speed_t * 0.85:
				phase = 1
				centre = p + f.cross(Vector3.UP) * -radius_t   # circle centre to the left
		elif phase == 1:
			steer = 1.0
			throttle = 1.0
			if beta > beta_t * 0.6:
				phase = 2
		else:
			# Steering holds the drift angle: wheels along the travel direction, more counter-steer
			# when the angle grows, damped by the yaw rate error; a weak pull back onto the circle.
			var r := Vector2(p.x - centre.x, p.z - centre.z).length()
			var yaw_rate := -wrapf(heading - prev_heading, -PI, PI) / STEP   # + : turning left
			var want_rate := v.length() / radius_t
			var kb := 1.2
			var kr := 0.25
			var delta := -beta - kb * (beta - beta_t) - kr * (yaw_rate - want_rate) + clampf((r - radius_t) * 0.01, -0.12, 0.12)
			steer = clampf(delta / lock, -1.0, 1.0)
			# Throttle holds the speed (and with it the rear slip that keeps the car sideways).
			integ = clampf(integ + (speed_t - speed) * STEP * 0.02, -0.4, 0.4)
			throttle = clampf(0.45 + 0.04 * (speed_t - speed) + integ, 0.0, 1.0)
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
