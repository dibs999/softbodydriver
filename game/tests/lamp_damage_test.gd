extends SceneTree
## Lamps and glass break with the structure around them: a parking bump leaves them intact, a
## 50 km/h frontal impact smashes both headlights and cracks the windscreen but leaves the tail
## lights and the rear window whole, and a repair restores everything.
## godot --headless -s res://tests/lamp_damage_test.gd
var Equipment: GDScript

var failed := false
var frame := 0

func check(value: bool, caption: String) -> void:
	print(caption, ": ", value)
	failed = failed or not value

func _glass(car: SBVehicle) -> Dictionary:
	var out := {}
	for g in car.get_glass_states(): out[g["name"]] = float(g["damage"])
	return out

func _states(car: SBVehicle) -> Dictionary:
	var out := {}
	for s in car.get_lamp_states(): out[s["name"]] = s
	return out

## Accelerates to `kmh`, then coasts into the wall at x = 40 and settles.
func _run_into_wall(world: SBWorld, car: SBVehicle, kmh: float) -> float:
	var impact := 0.0
	var moving := false
	for i in 1500:
		var p := car.get_position_ws()
		var v := car.get_speed_kmh()
		car.set_input(0.6 if v < kmh and p.x < 33.0 else 0.0, 0.0, 0.0, 0.0)
		world.step_blocking(0.02)
		moving = moving or v > 2.0
		if p.x > 30.0 and p.x < 37.0: impact = maxf(impact, v)
		if moving and p.x > 34.0 and v < 0.5: break
	car.set_input(0, 1, 0, 1)
	world.step_blocking(1.0)
	return impact

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2: return false
	var game := root.get_node("Game")
	Equipment = load("res://scripts/vehicle_equipment.gd")
	var scene := Node3D.new()
	root.add_child(scene)
	var world := SBWorld.new()
	world.material_library = game.make_material_library()
	scene.add_child(world)
	world.time_scale = 0.0
	world.add_ground_plane(1.0)
	world.add_box(Vector3(41, 1.5, 0.0), Vector3(1, 1.5, 4), Vector3.ZERO, 0.8)
	var start := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var car: SBVehicle = game.spawn_vehicle(world, "res://cars/kestrel_hatch.car.json", start)
	world.step_blocking(1.0)

	var names := []
	for child in car.get_children(): names.append(String(child.name))
	check("headlight_left" in names and "headlight_right" in names, "Generated headlights are split per side")
	check(names.any(func(n): return String(n).ends_with("taillight_left")), "Generated tail lights are split per side")

	var lamps := _states(car)
	check(lamps.size() == 4 and not lamps.values().any(func(s): return s["broken"]), "New car has four intact lamps")
	var glass := _glass(car)
	print("  panes ", glass.keys())
	check(glass.has("windscreen") and glass.has("rear") and glass.has("door_left_glass") and glass.values().all(func(d): return d < 0.05),
		"New car has intact windscreen, rear and door glass")

	var bump := _run_into_wall(world, car, 6.0)
	lamps = _states(car)
	print("  bump at %.1f km/h, head damage %.2f / %.2f" % [bump, lamps["head_left"]["damage"], lamps["head_right"]["damage"]])
	check(bump > 3.0 and not lamps["head_left"]["broken"] and not lamps["head_right"]["broken"], "Parking bump leaves the headlights intact")
	check(_glass(car)["windscreen"] < 0.3, "Parking bump leaves the windscreen uncracked")

	car.reset_to(start)
	world.step_blocking(1.0)
	var crash := _run_into_wall(world, car, 50.0)
	lamps = _states(car)
	print("  crash at %.1f km/h, damage head %.2f / %.2f tail %.2f / %.2f" % [crash, lamps["head_left"]["damage"], lamps["head_right"]["damage"],
		lamps["tail_left"]["damage"], lamps["tail_right"]["damage"]])
	check(crash > 40.0 and lamps["head_left"]["broken"] and lamps["head_right"]["broken"], "50 km/h frontal impact smashes both headlights")
	check(not lamps["tail_left"]["broken"] and not lamps["tail_right"]["broken"], "Tail lights survive a frontal impact")
	glass = _glass(car)
	print("  glass after crash ", glass)
	check(glass["windscreen"] >= 0.3, "50 km/h frontal impact cracks the windscreen")
	check(glass["rear"] < 1.0, "Rear window survives a frontal impact")

	var broken := {"head_left": true, "head_right": false}
	check(Equipment._lamp_dead(broken, true, -1) and not Equipment._lamp_dead(broken, true, 1), "Split lamps go dark per side")
	check(not Equipment._lamp_dead(broken, true, 0), "A lamp mesh covering both sides stays lit while one side works")

	car.reset_to(start)
	world.step_blocking(0.5)
	lamps = _states(car)
	check(not lamps.values().any(func(s): return s["broken"]), "Repair restores all lamps")
	check(_glass(car).values().all(func(d): return d < 0.05), "Repair restores all glass")
	print("TEST OK" if not failed else "TEST FAILED")
	quit(1 if failed else 0)
	return true
