extends SceneTree

func _initialize() -> void:
	var world := SBWorld.new()
	world.paused = true
	root.add_child(world)
	world.add_ground_plane(1.0)
	for i in 3:
		var v: SBVehicle = world.spawn_car("res://cars/aurora_sedan.car.json", Transform3D(Basis.IDENTITY, Vector3(0, 0, i * 4)))
	world.step_blocking(0.5)
	var t0 := Time.get_ticks_usec()
	for k in 30:
		world.sync_visuals()
	var dt := (Time.get_ticks_usec() - t0) / 30.0
	print("sync_visuals for 3 cars: %.2f ms per frame" % (dt / 1000.0))
	t0 = Time.get_ticks_usec()
	world.step_blocking(1.0)
	print("1 s of physics for 3 cars: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	quit()
