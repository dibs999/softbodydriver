extends SceneTree
## Loose props through the GDExtension: spawn, rest, get knocked over by a car, reset, remove.
var failures := 0

func check(value: bool, label: String) -> void:
	print(label, ": ", value)
	if not value:
		failures += 1

func _initialize() -> void:
	var game := root.get_node("Game")
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	check(world.spawn_prop("pyramid", Transform3D.IDENTITY) == null, "Unknown prop kind is rejected")
	var barrier: SBProp = game.spawn_prop(world, "barrier", Transform3D(Basis.IDENTITY, Vector3(-8.0, 0, 3.0)))
	check(barrier != null and barrier.get_child_count() >= 6, "Water-filled barrier spawns with its meshes")
	var cone: SBProp = game.spawn_prop(world, "cone", Transform3D(Basis.IDENTITY, Vector3(10.0, 0, 0.3)))
	var drum: SBProp = game.spawn_prop(world, "barrel", Transform3D(Basis.IDENTITY, Vector3(16.0, 0, -0.4)))
	var trunk: SBProp = game.spawn_prop(world, "log", Transform3D(Basis.IDENTITY, Vector3(4.0, 0, 8.0)))
	check(trunk != null and trunk.get_child_count() >= 6, "Felled log spawns with bark, end faces and branch stub")
	check(cone != null and drum != null and world.get_props().size() == 4, "Cone and drum spawn")
	check(cone.get_child_count() >= 3 and drum.get_child_count() >= 5, "Props carry their meshes")
	world.step_blocking(1.0)
	world.sync_visuals()
	check(cone.get_displacement() < 0.05 and drum.get_displacement() < 0.05 and trunk.get_displacement() < 0.05, "Props stand still on the ground")
	check(cone.transform.basis.y.dot(Vector3.UP) > 0.98, "Cone stays upright at rest")
	var car := world.spawn_car("res://cars/kestrel_hatch.car.json", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	world.step_blocking(0.5)
	car.set_input(0.6, 0, 0, 0)
	world.step_blocking(5.0)
	world.sync_visuals()
	check(cone.get_displacement() > 2.0, "The car knocks the cone away (%.1f m)" % cone.get_displacement())
	check(drum.get_displacement() > 1.0, "The car knocks the drum away (%.1f m)" % drum.get_displacement())
	check(cone.transform.origin.is_finite() and drum.transform.origin.is_finite(), "Props stay finite")
	cone.reset()
	drum.reset()
	world.step_blocking(0.1)
	world.sync_visuals()
	check(cone.get_displacement() < 0.05 and drum.get_displacement() < 0.05 and drum.get_damage() == 0.0, "Reset puts both back, undamaged")
	world.remove_prop(cone)
	check(world.get_props().size() == 3, "A prop can be removed")
	world.step_blocking(0.5)
	world.sync_visuals()
	check(car.get_position_ws().is_finite(), "Car keeps simulating after a prop was removed")
	world.remove_vehicle(car)
	world.step_blocking(0.2)
	world.sync_visuals()
	check(drum.transform.origin.is_finite(), "Prop keeps simulating after a vehicle was removed")
	world.free()
	print("PROP TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
