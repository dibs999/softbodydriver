extends SceneTree
## Hill roads network: the district road across the valley joins the loop at two T-junctions and
## can be driven end to end, from the loop at one junction to the loop at the other, without a
## step at the junctions, a roll-over or getting stuck; it shows on the map. Traffic gets a route
## over it: a car turns off the loop, crosses the valley, turns back onto the loop and comes round.
## godot --headless -s res://tests/district_road_test.gd
const AIDriver := preload("res://scripts/ai_driver.gd")
const STEP := 0.05
var frame := 0
var failed := false

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _initialize() -> void:
	var game := root.get_node("Game")
	game.selected_map = "hill_roads"
	game.selected_car = "res://cars/kestrel_hatch.car.json"
	game.settings["traffic"] = false
	game.settings["show_help"] = false
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
	var paths: Array = scene.map_data["map_paths"]
	check(paths.size() >= 3, "The map lists the district road among its roads")
	var chord: PackedVector3Array = paths[1]
	var loop: PackedVector3Array = scene.map_data["waypoints"]
	# Both ends meet the loop.
	var ends_on_loop := true
	for e: Vector3 in [chord[0], chord[chord.size() - 1]]:
		var best := INF
		for q in loop: best = minf(best, Vector2(q.x - e.x, q.z - e.z).length())
		ends_on_loop = ends_on_loop and best < 5.0
	check(ends_on_loop, "Both ends of the district road join the loop")
	var length := 0.0
	var steepest := 0.0
	for i in range(1, chord.size()):
		var d := chord[i] - chord[i - 1]
		length += d.length()
		steepest = maxf(steepest, absf(d.y) / maxf(0.1, Vector2(d.x, d.z).length()))
	print("  district road %.0f m long, steepest %.1f %%" % [length, steepest * 100.0])
	check(length > 500.0 and steepest < 0.10, "The district road is long and gently graded (< 10 %)")
	# Drive it: start on the loop at the first junction, out to the loop at the far end.
	var route := PackedVector3Array()
	route.append_array(chord)
	var back := chord.duplicate()
	back.reverse()
	route.append_array(back)
	var speeds := PackedFloat32Array()
	speeds.resize(route.size())
	speeds.fill(16.0)
	var player: SBVehicle = scene.player
	player.reset_to(MapBuilder_xform(chord[0], chord[2] - chord[0]))
	world.step_blocking(1.0)
	var driver := AIDriver.new(player, route, speeds, 1.0)
	driver.idx = 0   # the reset is published after the driver is made; start at the junction
	var t := 0.0
	var min_up := 1.0
	var far_end := chord[chord.size() - 1]
	var closest := INF
	while t < 120.0:
		driver.update(STEP)
		world.step_blocking(STEP)
		t += STEP
		min_up = minf(min_up, player.get_up().y)
		closest = minf(closest, player.get_position_ws().distance_to(far_end))
		if closest < 8.0:
			break
	print("  reached %.1f m from the far junction after %.0f s, lowest up %.2f" % [closest, t, min_up])
	check(closest < 8.0, "The car drives the district road to the far junction")
	check(min_up > 0.85, "It stays on its wheels all the way")
	check(int(player.get_telemetry().get("broken_beams", 0)) == 0, "No damage from steps at the junctions")
	# The traffic route over the network: one full lap with both turns.
	var routes: Array = scene.map_data.get("ai_routes", [])
	check(routes.size() == 3, "Traffic has a route over the district road")
	if routes.size() < 3:
		return
	var net: PackedVector3Array = routes[2]["waypoints"]
	var lap := 0.0
	for i in net.size(): lap += net[i].distance_to(net[(i + 1) % net.size()])
	player.reset_to(MapBuilder_xform(net[2], net[4] - net[2]))
	world.step_blocking(1.0)
	var taxi := AIDriver.new(player, net, routes[2]["speeds"], 0.9)
	taxi.idx = 2
	var progress := 0
	var prev_idx := taxi.idx
	t = 0.0
	min_up = 1.0
	var passed_far_mouth := false
	while t < 300.0 and progress < net.size() - 4:
		taxi.update(STEP)
		world.step_blocking(STEP)
		t += STEP
		var step_idx := posmod(taxi.idx - prev_idx, net.size())
		if step_idx < net.size() / 2: progress += step_idx   # forward along the route only
		prev_idx = taxi.idx
		min_up = minf(min_up, player.get_up().y)
		if player.get_position_ws().distance_to(far_end) < 10.0: passed_far_mouth = true
	print("  network lap (%.0f m): %d of %d route points in %.0f s, lowest up %.2f" % [lap, progress, net.size(), t, min_up])
	check(passed_far_mouth and progress >= net.size() - 4, "A traffic car turns off, crosses the valley, turns back onto the loop and completes the lap")
	check(min_up > 0.85 and int(player.get_telemetry().get("broken_beams", 0)) == 0, "It turns at both junctions without leaving the road")

func MapBuilder_xform(p: Vector3, heading: Vector3) -> Transform3D:
	return preload("res://scripts/map_builder.gd").car_xform(p + Vector3.UP * 0.4, heading)
