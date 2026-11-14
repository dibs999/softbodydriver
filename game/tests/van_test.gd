extends SceneTree
## The Kastell Cargo panel van against a real 2.2-litre panel van: ~2 t, 0-100 km/h in about
## 14 s, stops from 100 km/h in roughly 40-50 m, and a quick lane change at 70 km/h (~0.4 g) leans
## the tall body a few degrees, as a real van's springs and anti-roll bars do.
## godot --headless -s res://tests/van_test.gd
const STEP := 0.02
var failed := false
var frame := 0

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "proving_grounds"
	game.selected_car = "res://cars/kastell_cargo.car.json"
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
	var car: SBVehicle = scene.player
	var info := car.get_info()
	print("  %s: %.0f kg, %.2f m tall" % [info["name"], float(info["mass"]), float(info["height"])])
	check(float(info["mass"]) > 1800.0 and float(info["mass"]) < 2400.0, "It weighs about two tonnes")
	car.set_automatic(true)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(-350, 0.6, -60)))   # facing +x along the pad
	world.step_blocking(1.5)
	# 0-100 km/h, full throttle (the automatic shifts).
	var t := 0.0
	var t100 := -1.0
	while t < 30.0:
		car.set_input(1.0, 0.0, 0.0, 0.0)
		world.step_blocking(STEP)
		t += STEP
		if car.get_speed_kmh() >= 100.0:
			t100 = t
			break
	print("  0-100 km/h: %.1f s" % t100)
	check(t100 > 9.0 and t100 < 19.0, "It reaches 100 km/h in a van's time (10-18 s)")
	# Full stop from 100 km/h (ABS).
	var p0 := car.get_position_ws()
	var min_up := 1.0
	t = 0.0
	while car.get_speed_kmh() > 0.5 and t < 15.0:
		car.set_input(0.0, 1.0, 0.0, 0.0)
		world.step_blocking(STEP)
		t += STEP
		min_up = minf(min_up, car.get_up().y)
	var dist := Vector2(car.get_position_ws().x - p0.x, car.get_position_ws().z - p0.z).length()
	print("  100-0 km/h: %.1f m" % dist)
	check(dist > 34.0 and dist < 56.0, "It stops from 100 km/h in 35-55 m")
	# Double lane change at 70 km/h: 3.5 m to the left and back within ~60 m.
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(-350, 0.6, -110)))
	world.step_blocking(1.5)
	t = 0.0
	while car.get_speed_kmh() < 70.0 and t < 20.0:
		car.set_input(1.0, 0.0, 0.0, 0.0)
		world.step_blocking(STEP)
		t += STEP
	var p_start := car.get_position_ws()
	var side := car.get_right()
	side.y = 0.0
	side = side.normalized()
	min_up = 1.0
	var max_dz := 0.0
	var max_roll := 0.0
	var max_ay := 0.0
	var v_prev := car.get_velocity()
	t = 0.0
	while t < 5.0:
		# Steering as a driver: a full sine left, then back (one period each way, 2.2 s).
		var steer := 0.0
		if t < 2.2:
			steer = 0.12 * sin(TAU * t / 2.2)
		elif t < 4.4:
			steer = -0.12 * sin(TAU * (t - 2.2) / 2.2)
		car.set_input(0.3, 0.0, steer, 0.0)
		world.step_blocking(STEP)
		t += STEP
		min_up = minf(min_up, car.get_up().y)
		max_dz = maxf(max_dz, absf((car.get_position_ws() - p_start).dot(side)))
		max_roll = maxf(max_roll, absf(rad_to_deg(asin(clampf(car.get_right().y, -1.0, 1.0)))))
		var v_now := car.get_velocity()
		max_ay = maxf(max_ay, absf((v_now - v_prev).dot(car.get_right())) / STEP / 9.81)
		v_prev = v_now
	print("  lane change at 70 km/h: lateral %.1f m, peak roll %.1f deg, peak lateral %.2f g" % [max_dz, max_roll, max_ay])
	check(max_dz > 2.0, "The lane change actually moves it across a lane")
	check(max_roll > 0.8 and max_roll < 6.0 and min_up > 0.8, "It leans (a real van: ~4 deg per g) and stays on its wheels")
	check(int(car.get_telemetry()["broken_beams"]) == 0, "Nothing breaks")
