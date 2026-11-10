extends SceneTree
## Track acceptance: the AI driver takes the player's car once around each map's whole route.
## A map passes when the lap completes without getting stuck, needing a reset, leaving the route
## by more than 15 m or crashing hard. godot --headless -s res://tests/track_acceptance_test.gd [-- <map>...]
## TRACE=1 logs progress, status changes and sump damage; WINDOW=<s> logs motion around a moment.
const AIDriver := preload("res://scripts/ai_driver.gd")
const STEP := 0.05

var maps: Array = []
var current := ""
var wait := -1
var failed := false
var results: Array[String] = []

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	call_deferred("_next")

func _next() -> void:
	if maps.is_empty() and current == "":
		var args := OS.get_cmdline_user_args()
		for m in root.get_node("Game").MAPS:
			if args.is_empty() or m["id"] in args:
				maps.append(m["id"])
	if maps.is_empty():
		for r in results: print(r)
		print("TEST OK" if not failed else "TEST FAILED")
		quit(1 if failed else 0)
		return
	current = maps.pop_front()
	var game := root.get_node("Game")
	game.selected_map = current
	# The map descriptions recommend an SUV or rally car off the tarmac.
	game.selected_car = {"offroad": "res://cars/trailhead_4x4.car.json", "desert": "res://cars/kestrel_rally.car.json"}.get(current, "res://cars/meridian_sedan.car.json")
	game.settings["traffic"] = false
	game.settings["show_help"] = false
	game.start_lesson = false
	change_scene_to_file("res://scenes/game.tscn")
	wait = 0

static func _route_distance(p: Vector3, route: PackedVector3Array) -> float:
	var best := 1e9
	for i in route.size():
		var a := route[i]
		var b := route[(i + 1) % route.size()]
		var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
		best = minf(best, q.distance_to(Vector3(p.x, 0, p.z)))
	return best

func _process(_d: float) -> bool:
	var scene := current_scene
	if wait < 0 or scene == null or not scene.get("player"):
		return false
	wait += 1
	if wait < 3:
		return false
	wait = -1
	_drive(scene)
	call_deferred("_next")
	return false

func _drive(scene: Node) -> void:
	var data: Dictionary = scene.map_data
	var route: PackedVector3Array = data.get("waypoints", PackedVector3Array())
	var speeds: PackedFloat32Array = data.get("speeds", PackedFloat32Array())
	if route.size() < 3 or speeds.size() != route.size():
		results.append("%-16s no closed route, skipped" % current)
		return
	var length := 0.0
	for i in route.size():
		length += route[i].distance_to(route[(i + 1) % route.size()])
	var world: SBWorld = scene.world
	world.time_scale = 0.0
	scene.set_process(false)   # the test drives; no player input handling
	var car: SBVehicle = scene.player
	car.reset_to(preload("res://scripts/map_builder.gd").car_xform(route[0], route[1] - route[0]))
	world.step_blocking(1.0)
	var ai := AIDriver.new(car, route, speeds, 0.85)
	var travelled := 0.0
	var last := car.get_position_ws()
	var worst_offset := 0.0
	var slow := 0.0
	var worst_slow := 0.0
	var hard_hits := 0
	var t := 0.0
	var avg := 0.0
	for s in speeds: avg += s / speeds.size()
	var limit := length / maxf(4.0, avg * 0.85 * 0.45) + 30.0
	while travelled < length * 0.98 and t < limit:
		ai.update(STEP)
		world.step_blocking(STEP)
		t += STEP
		var p := car.get_position_ws()
		travelled += Vector2(p.x - last.x, p.z - last.z).length()
		last = p
		worst_offset = maxf(worst_offset, _route_distance(p, route))
		if car.get_speed_kmh() < 3.0: slow += STEP
		else: slow = 0.0
		if OS.has_environment("TRACE") and (is_equal_approx(slow, 3.0) or int(t / STEP) % 400 == 0):
			var tel := car.get_telemetry()
			print("  t=%6.1f wp %3d/%d pos %s v %5.1f gear %d rpm %4.0f up %.2f slope %+.1f%% status '%s' slow %.1f tyres %s rims %s" % [t, ai.idx, route.size(), p.round(), car.get_speed_kmh(), tel["gear"], tel["rpm"],
				car.get_up().y, 100.0 * car.get_forward().y, tel["status"], slow, str(tel["tire_pressure"].map(func(x): return snappedf(x, 1))), str(tel.get("rim_damage", []).map(func(x): return snappedf(x, 0.01)))])
		worst_slow = maxf(worst_slow, slow)
		if OS.has_environment("TRACE"):
			var tel2 := car.get_telemetry()
			if str(tel2["status"]) != str(car.get_meta("last_status", "")):
				car.set_meta("last_status", str(tel2["status"]))
				print("  STATUS '%s' t=%.1f pos %s v %.1f coolant %.0f°C level %.2f oil %.0f°C level %.2f radiator %.2f clutch %.0f°C" % [tel2["status"], t, p.round(), car.get_speed_kmh(),
					tel2["coolant_temp"], tel2["coolant_level"], tel2["oil_temp"], tel2["oil_level"], tel2["radiator_damage"], tel2["clutch_temp"]])
			if OS.has_environment("WINDOW") and absf(t - float(OS.get_environment("WINDOW"))) < 1.5:
				var vel := car.get_velocity()
				print("    t=%.2f pos %s v %.1f vy %+.2f pitch %+.1f roll %+.1f radiator %.3f" % [t, p, car.get_speed_kmh(), vel.y,
					rad_to_deg(asin(clampf(car.get_forward().y, -1, 1))), rad_to_deg(asin(clampf(car.get_right().y, -1, 1))), float(tel2["radiator_damage"])])
			var pan := float(car.get_telemetry().get("oilpan_damage", 0.0))
			if pan > 0.0 and not car.has_meta("pan_logged"):
				car.set_meta("pan_logged", true)
				print("  SUMP damage %.3f at t=%.2f pos %s v %.1f km/h wp %d" % [pan, t, p, car.get_speed_kmh(), ai.idx])
		var impact := car.take_impact()
		if impact > 60.0 and t > 2.0:   # ignore the drop onto the start line
			hard_hits += 1
			if OS.has_environment("TRACE"):
				print("  IMPACT %.0f at t=%.1f pos %s v %.1f km/h wp %d" % [impact, t, p, car.get_speed_kmh(), ai.idx])
	var zones: Array = car.get_telemetry().get("zones", [])
	var damage := 0.0
	for z in zones: damage = maxf(damage, float(z))
	var lap := travelled >= length * 0.98
	results.append("%-16s %-22s route %5.0f m  lap %s in %5.1f s (%3.0f km/h avg)  max offset %4.1f m  longest stop %4.1f s  hard hits %d  body damage %.2f  status '%s'" % [
		current, car.get_info()["name"], length, "yes" if lap else "NO", t, travelled / maxf(t, 0.1) * 3.6, worst_offset, worst_slow, hard_hits, damage, car.get_telemetry()["status"]])
	check(lap, "%s: complete lap" % current)
	check(worst_offset < 15.0, "%s: stays on the route" % current)
	check(worst_slow < 6.0, "%s: never stuck" % current)
	check(hard_hits == 0 and damage < 0.2, "%s: no crash" % current)
