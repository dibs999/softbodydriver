extends SceneTree
## Traffic signals: the X/Z phases alternate with amber and all-red, and AI traffic stops at the
## line on red and drives on when the light turns green.
const AIDriver := preload("res://scripts/ai_driver.gd")
const Signals := preload("res://scripts/maps/traffic_signals.gd")
var failed := false
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var signals: Node3D = Signals.new()
	check(signals.state("x", 1.0) == 0 and signals.state("z", 1.0) == 2, "X green while Z red")
	check(signals.state("x", 13.0) == 1 and signals.state("z", 13.0) == 2, "X amber, Z still red")
	check(signals.state("x", 15.5) == 2 and signals.state("z", 15.5) == 2, "Short all-red phase")
	check(signals.state("x", 20.0) == 2 and signals.state("z", 20.0) == 0, "Z green while X red")
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(signals)
	signals.set_process(false)
	signals.centers = PackedVector2Array([Vector2(0, 0)])
	signals.stop_offset = 9.5
	signals.clock = 16.0   # X red for the next 16 s
	var world := SBWorld.new()
	host.add_child(world)
	world.add_ground_plane(1.0)
	world.time_scale = 0.0
	var game := root.get_node("Game")
	world.material_library = game.make_material_library()
	var route := PackedVector3Array()
	var speeds := PackedFloat32Array()
	for i in 60:
		route.append(Vector3(-200.0 + i * 8.0, 0, 0))
		speeds.append(15.0)
	var car: SBVehicle = game.spawn_vehicle(world, "res://cars/aurora_sedan.car.json",
		preload("res://scripts/map_builder.gd").car_xform(Vector3(-150, 0, 0), Vector3(1, 0, 0)))
	world.step_blocking(1.0)
	var ai := AIDriver.new(car, route, speeds, 1.0)
	ai.signals = signals
	for i in 300:   # 15 s, light stays red
		ai.update(0.05)
		world.step_blocking(0.05)
	var x := car.get_position_ws().x
	print("stopped at x %.1f, %.1f km/h" % [x, car.get_speed_kmh()])
	check(car.get_speed_kmh() < 2.0 and x < -9.5 and x > -22.0, "AI stops at the red light before the line")
	signals.clock = 0.0    # green for X
	for i in 120:
		ai.update(0.05)
		world.step_blocking(0.05)
	check(car.get_position_ws().x > 5.0, "AI drives on when the light turns green")
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
