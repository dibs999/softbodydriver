extends SceneTree
## Vehicle fire through the GDExtension and the effects: it grows, kills the engine, shows flames,
## and a repair puts it out.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := root.get_node("Game")
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	var car: SBVehicle = game.spawn_vehicle(world, "res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	car.set_input(0, 1, 0, 1)
	world.step_blocking(1.0)
	world.sync_visuals()
	check(float(car.get_telemetry()["fire"]) == 0.0 and bool(car.get_telemetry()["running"]), "Healthy car is not burning")
	car.ignite(0)
	world.step_blocking(20.0)
	world.sync_visuals()
	await process_frame
	var t := car.get_telemetry()
	check(float(t["fire"]) > 0.5, "Fire grows (%.2f)" % float(t["fire"]))
	check(not bool(t["running"]), "The fire killed the engine")
	check(str(t["status"]) == "ENGINE FIRE", "Status reports the engine fire")
	var effects := car.get_node("VehicleEffects")
	world.paused = false   # effects stand still while the world is paused
	await process_frame
	await process_frame
	world.paused = true
	check(effects.flames.emitting and effects.fire_light.light_energy > 0.5, "Flames and fire light are on")
	car.repair_in_place()
	world.step_blocking(0.2)
	world.sync_visuals()
	world.paused = false
	await process_frame
	await process_frame
	world.paused = true
	check(float(car.get_telemetry()["fire"]) == 0.0 and not effects.flames.emitting, "Repair puts the fire out")
	world.remove_vehicle(car)
	world.free()
	print("FIRE TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
