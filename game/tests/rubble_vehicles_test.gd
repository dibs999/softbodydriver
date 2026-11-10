extends SceneTree
## Imported Rubble vehicles (CC-BY 4.0): multi-part wheels, per-car paint, body attached, drivable.
var failed := false
func check(condition: bool, label: String) -> void:
	print(label, ": ", condition)
	if not condition:
		failed = true
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = root.get_node("Game")
	for id in ["meridian_sedan", "meridian_wagon", "meridian_interceptor", "trailhead_4x4", "fastback_69"]:
		var path := "res://cars/%s.car.json" % id
		var world := SBWorld.new()
		root.add_child(world)
		world.add_ground_plane(1)
		var car: SBVehicle = game.spawn_vehicle(world, path, Transform3D.IDENTITY)
		check(car != null, "%s spawns" % id)
		if car == null:
			continue
		check(car.has_node("hood") and car.has_node("door_FL"), "%s detailed body is attached" % id)
		var info: Dictionary = game.car_info(path)
		var radius: float = float(JSON.parse_string(FileAccess.get_file_as_string(path))["tires"]["radius"])
		for name in ["FL", "FR", "RL", "RR"]:
			var wheel := car.get_node(name)
			var bounds := AABB()
			var rubber := 0
			var rim := 0
			for part in wheel.get_children():
				if part is MeshInstance3D:
					var mat_name: String = part.mesh.surface_get_material(0).resource_name
					if mat_name.begins_with("rubber"):
						bounds = part.mesh.get_aabb() if rubber == 0 else bounds.merge(part.mesh.get_aabb())
						rubber += 1
					elif mat_name in ["chrome", "metal_bare"]:
						rim += 1
			check(rubber > 0 and rim > 0 and absf(bounds.size.y * 0.5 - radius) < 0.01,
				"%s wheel %s uses its own rim and tyre at the physics radius" % [id, name])
		var paint: Color
		var found := false
		for child in car.get_children():
			if child is MeshInstance3D and child.name == "hood":
				var m = child.get_active_material(0)
				if m is StandardMaterial3D:
					paint = (m as StandardMaterial3D).albedo_color
					found = true
				elif m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("paint") is Color:
					paint = (m as ShaderMaterial).get_shader_parameter("paint")   # crash-wear paint
					found = true
		var rgb: Array = info["paint"]
		check(found and absf(paint.r - float(rgb[0])) < 0.01 and absf(paint.b - float(rgb[2])) < 0.01, "%s keeps its own paint colour" % id)
		var start := car.get_position_ws()
		for i in 40:
			car.set_input(0.6, 0, 0, 0)
			world.step_blocking(0.1)
		world.sync_visuals()
		check(car.get_position_ws().distance_to(start) > 5.0 and int(car.get_telemetry()["broken_beams"]) == 0, "%s drives off undamaged" % id)
		world.queue_free()
		await process_frame
	print("RUBBLE VEHICLES TEST ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
