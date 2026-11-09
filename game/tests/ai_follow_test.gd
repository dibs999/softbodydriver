extends SceneTree
## AI traffic keeps its distance: an AI car approaching a stopped car on the proving-ground
## straight stops behind it without contact, and moves off again once the road ahead is clear.
const AIDriver := preload("res://scripts/ai_driver.gd")
var failed := false
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var world := SBWorld.new()
	host.add_child(world)
	world.add_ground_plane(1.0)
	world.time_scale = 0.0
	var game := root.get_node("Game")
	world.material_library = game.make_material_library()
	var route := PackedVector3Array()
	var speeds := PackedFloat32Array()
	for i in 80:
		route.append(Vector3(-200.0 + i * 8.0, 0, 0))
		speeds.append(16.0)
	var xf := func(x: float) -> Transform3D: return preload("res://scripts/map_builder.gd").car_xform(Vector3(x, 0, 0), Vector3(1, 0, 0))
	var blocker: SBVehicle = game.spawn_vehicle(world, "res://cars/kestrel_hatch.car.json", xf.call(60.0))
	var follower: SBVehicle = game.spawn_vehicle(world, "res://cars/aurora_sedan.car.json", xf.call(-180.0))
	world.step_blocking(1.0)
	blocker.set_input(0, 1, 0, 1)
	var ai := AIDriver.new(follower, route, speeds, 1.0)
	ai.others = [blocker, follower]
	var top := 0.0
	var closest := 1e9
	for i in 800:   # 40 s
		ai.update(0.05)
		world.step_blocking(0.05)
		top = maxf(top, follower.get_speed_kmh())
		closest = minf(closest, blocker.get_position_ws().distance_to(follower.get_position_ws()))
	var gap := blocker.get_position_ws().distance_to(follower.get_position_ws())
	print("top %.0f km/h, closest %.1f m, final gap %.1f m, final speed %.1f km/h" % [top, closest, gap, follower.get_speed_kmh()])
	check(top > 45.0, "AI reaches road speed on the straight")
	check(closest > 5.5 and blocker.take_impact() < 5.0, "AI stops behind the standing car without contact")
	check(follower.get_speed_kmh() < 2.0 and gap < 16.0, "AI waits in a short queue gap")
	blocker.relocate_to(xf.call(400.0))
	for i in 200:
		ai.update(0.05)
		world.step_blocking(0.05)
	check(follower.get_speed_kmh() > 20.0, "AI moves off once the road is clear")
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
