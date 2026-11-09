extends SceneTree
## Integration regression: gameplay surface sampling -> queued native grip -> actual tyre braking.
## The world is deliberately kept outside the tree: no realtime physics worker competes
## with step_blocking. Its rendered vehicle/effects are in-tree for the normal surface path.
const Surface := preload("res://scripts/road_surface.gd")
const STEP := 0.02
const TARGET_SPEED := 60.0
var failed := false
var host: Node3D
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value
func advance(world: SBWorld, vehicle: SBVehicle, effects: Node, throttle: float, brake: float) -> void:
	vehicle.set_input(throttle, brake, 0, 0)
	effects._process(STEP)
	world.step_blocking(STEP)
	world.sync_visuals()
func measure(wetness: float) -> Dictionary:
	var state := root.get_node("Game")
	var world := SBWorld.new()
	world.paused = false
	world.material_library = state.make_material_library()
	world.add_ground_plane(1.0)
	var vehicle: SBVehicle = state.spawn_vehicle(world, "res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	if vehicle == null:
		check(false, "Reference car can be spawned")
		world.free()
		return {}
	world.remove_child(vehicle)
	host.add_child(vehicle)
	vehicle.set_abs(true)
	vehicle.set_tcs(true)
	var effects: Node = vehicle.get_node("VehicleEffects")
	effects.set_process(false)
	var surfaces := Surface.new()
	surfaces.configure("proving_grounds", {})
	surfaces.wetness = wetness
	effects.surfaces = surfaces
	world.sync_visuals()
	for i in 75:
		advance(world, vehicle, effects, 0, 0)
	for i in 1000:
		advance(world, vehicle, effects, 1, 0)
		if vehicle.get_speed_kmh() >= TARGET_SPEED: break
	var start_speed := float(vehicle.get_speed_kmh())
	var start := vehicle.get_position_ws()
	var previous := start
	var distance := 0.0
	var elapsed := 0.0
	for i in 600:
		advance(world, vehicle, effects, 0, 1)
		var position := vehicle.get_position_ws()
		distance += Vector2(position.x - previous.x, position.z - previous.z).length()
		previous = position
		elapsed += STEP
		if absf(vehicle.get_speed_kmh()) < 1: break
	var result := {"wetness": wetness, "start_speed": start_speed, "distance": distance,
		"elapsed": elapsed, "stop_speed": vehicle.get_speed_kmh(),
		"broken": int(vehicle.get_telemetry()["broken_beams"]),
		"lateral": absf(vehicle.get_position_ws().z - start.z), "surface": effects.wheel_surfaces.duplicate()}
	print("BRAKE RESULT ", result)
	world.remove_vehicle(vehicle)
	world.free()
	return result
func run() -> void:
	host = Node3D.new()
	root.add_child(host)
	var dry := measure(0)
	var wet := measure(1)
	if dry.is_empty() or wet.is_empty():
		quit(1)
		return
	check(dry.start_speed >= TARGET_SPEED and wet.start_speed >= TARGET_SPEED and absf(dry.start_speed - wet.start_speed) < 0.5, "Dry and wet runs start braking at matched actual speed")
	check(absf(dry.stop_speed) < 1 and absf(wet.stop_speed) < 1, "Both vehicles reach standstill")
	check(dry.broken == 0 and wet.broken == 0 and dry.lateral < 2 and wet.lateral < 2, "Measurements remain straight and undamaged")
	check(dry.surface == ["asphalt", "asphalt", "asphalt", "asphalt"] and wet.surface == dry.surface, "Gameplay samples asphalt at all four wheel contacts")
	check(wet.distance > dry.distance * 1.10, "Wet asphalt increases measured stopping distance by more than ten percent")
	host.queue_free()
	await process_frame
	quit(1 if failed else 0)
