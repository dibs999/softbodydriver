extends SceneTree
const Map := preload("res://scripts/map_builder.gd")
const Surface := preload("res://scripts/road_surface.gd")
var failed := false
var world: SBWorld
class SceneFixture extends Node3D:
	var weather: Node
class ClockFixture extends Node:
	var hour := 13.0
var host: SceneFixture
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func spawn_at(point: Vector3, heading: Vector3) -> SBVehicle:
	var car := world.spawn_car("res://cars/kestrel_hatch.car.json", Map.car_xform(point, heading))
	if car == null:
		check(false, "Vehicle spawn available")
		quit(1)
		return null
	car.set_input(0, 0, 0, 0)
	world.step_blocking(1)
	world.sync_visuals()
	return car
func step(car: SBVehicle, throttle: float, brake := 0.0) -> void:
	car.set_input(throttle, brake, 0, 0)
	world.step_blocking(0.05)
	world.sync_visuals()
func run() -> void:
	host = SceneFixture.new()
	host.weather = ClockFixture.new()
	host.add_child(host.weather)
	root.add_child(host)
	current_scene = host
	world = SBWorld.new()
	world.paused = true
	host.add_child(world)
	var maproot := Node3D.new()
	host.add_child(maproot)
	var data := Map.build_proving_grounds(world, maproot)
	var lighting = maproot.get_node("WayfindingAndService/FacilityLighting")
	lighting._process(0)
	check(not lighting.lamps[0].visible, "Facility lamps switch off in daylight")
	host.weather.hour = 0
	lighting._timer = 0
	lighting._process(0)
	check(lighting.lamps[0].visible and lighting.lamps[0].light_energy > 0, "Facility lamps follow night clock")
	var start: Transform3D = data["spawns"][0]
	var car := spawn_at(start.origin, start.basis.x)
	if car == null: return
	var initial := car.get_position_ws()
	for i in 160:
		step(car, 1)
		if car.get_speed_kmh() >= 55: break
	check(car.get_speed_kmh() >= 50, "Primary spawn reaches braking speed without entering jump lane")
	for i in 200:
		step(car, 0, 1)
		if absf(car.get_speed_kmh()) < 1: break
	var finish := car.get_position_ws()
	check(absf(car.get_speed_kmh()) < 1 and finish.x < 20 and finish.x > initial.x + 30, "First drive stops safely before bump strip")
	check(int(car.get_telemetry()["broken_beams"]) == 0 and absf(finish.z + 5) < 2, "Straight acceleration/braking avoids map obstacles")
	world.remove_vehicle(car)
	car = spawn_at(Vector3(203, 0, -74), Vector3.LEFT)
	if car == null: return
	for i in 240:
		var speed := absf(car.get_speed_kmh())
		step(car, 0.3 if speed < 10 else 0, 0.15 if speed > 12 else 0)
		if car.get_position_ws().x < 186: break
	for i in 80:
		step(car, 0, 1)
		if absf(car.get_speed_kmh()) < 1: break
	check(car.get_position_ws().x < 187 and car.get_position_ws().x > 178 and int(car.get_telemetry()["broken_beams"]) == 0, "Workshop entrance admits a car beneath solid roof")
	world.remove_vehicle(car)
	car = spawn_at(Vector3(182, 5.7, -74), Vector3.RIGHT)
	if car == null: return
	world.step_blocking(1)
	world.sync_visuals()
	check(car.get_position_ws().y > 5.2, "Visible workshop roof supports vehicle collision")
	world.remove_vehicle(car)
	car = spawn_at(start.origin, Vector3.BACK)
	if car == null: return
	var reached_service := false
	var bay := start.origin + start.basis.z * 8
	for i in 140:
		var speed := absf(car.get_speed_kmh())
		step(car, 0.25 if speed < 10 else 0, 0.2 if speed > 12 else 0)
		if car.get_position_ws().distance_to(bay) < 2:
			reached_service = true
			break
	check(reached_service and int(car.get_telemetry()["broken_beams"]) == 0, "Service apron accessible from primary spawn")
	check(data["rain_shelters"].size() == 7, "Roof shelter metadata covers all open workshop canopies")
	world.remove_vehicle(car)
	var surfaces := Surface.new()
	surfaces.configure("proving_grounds", data)
	check(surfaces.at(Vector3(-125, 0, 90)) == "grass" and surfaces.at(start.origin) == "asphalt", "Planted infield uses grass grip without changing starter lane")
	car = spawn_at(Vector3(-183, 0, 67), Vector3.RIGHT)
	if car == null: return
	var tree_impact := 0.0
	car.take_impact()
	for i in 200:
		step(car, 0.35)
		tree_impact = maxf(tree_impact, car.take_impact())
	print("TREE CONTACT ", car.get_position_ws(), " impact ", tree_impact)
	check(car.get_position_ws().x < -170 and tree_impact > 2, "Reachable infield trunk causes a real vehicle collision")
	world.remove_vehicle(car)
	car = spawn_at(Vector3(362, 0, 140), Vector3.RIGHT)
	if car == null: return
	for i in 100: step(car, 0.3)
	print("RAIL CONTACT ", car.get_position_ws(), " broken ", car.get_telemetry()["broken_beams"])
	check(car.get_position_ws().x < 370 and car.get_position_ws().x > 363, "Perimeter rail blocks a low-speed approach")
	world.remove_vehicle(car)
	host.queue_free()
	await process_frame
	quit(1 if failed else 0)
