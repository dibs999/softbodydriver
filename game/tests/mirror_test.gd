extends SceneTree
## Native optical surfaces, projective mapping and bounded viewport lifecycle.
## Rendered left/right/top/bottom pixel acceptance is a separate GPU check.
const Mirrors := preload("res://scripts/vehicle_mirrors.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, caption: String) -> void:
	print(caption, ": ", condition)
	if not condition: failures += 1

func optical_for(vehicle: SBVehicle, side: int) -> Dictionary:
	for optical: Dictionary in vehicle.get_mirror_surfaces():
		if optical.side == side: return optical
	return {}

func check_rearward_aim(vehicle: SBVehicle, optical: Dictionary) -> void:
	# Test the actual deformed optical plane from the authored driving position.
	# A mathematically correct reflection can still show only asphalt if the
	# physical glass is aimed incorrectly; imported optics allow a slight dip.
	var toward_eye: Vector3 = (vehicle.get_driver_eye() - optical.center).normalized()
	var reflected: Vector3 = -toward_eye + 2 * optical.normal * toward_eye.dot(optical.normal)
	var rear: Vector3 = -vehicle.get_forward()
	var up: Vector3 = vehicle.get_visual_basis().y
	check(reflected.dot(rear) > 0.95 and absf(reflected.dot(up)) < 0.12,
		"Physical mirror shows rear horizon from driver eye " + str(optical.side))

func view_surface(camera: Camera3D, optical: Dictionary) -> void:
	camera.global_position = optical.center + optical.normal * 0.8 + optical.up * 0.15
	camera.look_at(optical.center, optical.up)

func project(material: ShaderMaterial, point: Vector3) -> Vector2:
	var projection: Projection = material.get_shader_parameter("mirror_projection")
	var view: Transform3D = material.get_shader_parameter("mirror_view")
	var clip: Vector4 = projection * Projection(view) * Vector4(point.x, point.y, point.z, 1)
	return Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5)

func run() -> void:
	var game := root.get_node("Game")
	var host := Node3D.new()
	root.add_child(host)
	var world := SBWorld.new()
	world.paused = true
	host.add_child(world)
	world.add_ground_plane(1)
	var kestrel: SBVehicle = game.spawn_vehicle(world, "res://cars/kestrel_hatch.car.json", Transform3D.IDENTITY)
	check(is_instance_valid(kestrel), "Current Kestrel definition loads")
	if not is_instance_valid(kestrel):
		quit(1)
		return
	world.sync_visuals()
	var surfaces := kestrel.get_mirror_surfaces()
	check(surfaces.size() == 2, "Procedural car exposes two independent optical inserts")
	if surfaces.size() != 2:
		quit(1)
		return
	for optical: Dictionary in surfaces:
		check_rearward_aim(kestrel, optical)
		check(optical.mesh.visible and optical.center.is_finite() and absf(optical.normal.length() - 1) < 0.001 and absf(optical.up.dot(optical.normal)) < 0.001, "Native optical plane is finite and orthonormal " + str(optical.side))
		check(optical.half_extents.x > 0.01 and optical.half_extents.y > 0.01, "Optical bounds derive from insert vertices " + str(optical.side))
	var camera := Camera3D.new()
	camera.fov = 70
	host.add_child(camera)
	camera.current = true
	var manager := Mirrors.new()
	host.add_child(manager)
	var left := optical_for(kestrel, 0)
	view_surface(camera, left)
	manager.update_views(1, camera, kestrel, true)
	var mirror: Dictionary
	for entry: Dictionary in manager._mirrors:
		if entry.side == 0: mirror = entry
	check(not mirror.is_empty(), "Native left surface has a viewport")
	if mirror.is_empty():
		quit(1)
		return
	check(mirror.viewport.world_3d == camera.get_world_3d(), "Mirror shares the actual scene world")
	check(mirror.mesh.layers == Mirrors.MIRROR_LAYER and (mirror.camera.cull_mask & Mirrors.MIRROR_LAYER) == 0, "Optical surface is excluded from all reflection cameras")
	check(bool(mirror.material.get_shader_parameter("reflection_valid")) and mirror.updates > 0, "Visible mirror captures immediately")
	var virtual_eye: Vector3 = mirror.camera.global_position
	check(absf((virtual_eye - left.center).dot(left.normal) + (camera.global_position - left.center).dot(left.normal)) < 0.001, "Reflected eye is equally far behind the optical plane")
	var center_uv := project(mirror.material, left.center)
	check(center_uv.distance_to(Vector2(0.5, 0.5)) < 0.001, "Off-axis frustum centers the physical aperture")
	var right: Vector3 = left.up.cross(left.normal)
	check(project(mirror.material, left.center + right * left.half_extents.x * 0.5).x < center_uv.x, "Projective mapping preserves physical horizontal mirror reversal")
	check(project(mirror.material, left.center + left.up * left.half_extents.y * 0.5).y < center_uv.y, "Viewport texture Y convention keeps up above center")
	for x in [-1, 1]:
		for y in [-1, 1]:
			var uv := project(mirror.material, left.center + right * left.half_extents.x * x + left.up * left.half_extents.y * y)
			check(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1, "Actual aperture fits fixed viewport aspect %d/%d" % [x, y])
	var before_uv := project(mirror.material, left.center + left.up * left.half_extents.y * 0.5)
	var before_view: Transform3D = mirror.material.get_shader_parameter("mirror_view")
	var captures: int = mirror.updates
	manager._elapsed = 0
	check(kestrel.relocate_to(Transform3D(Basis.IDENTITY, Vector3(4, 0, 3))), "Vehicle can translate between mirror captures")
	left = optical_for(kestrel, 0)
	view_surface(camera, left)
	manager.update_views(0.001, camera, kestrel, true)
	var after_view: Transform3D = mirror.material.get_shader_parameter("mirror_view")
	check(mirror.updates == captures and mirror.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Texture rendering remains throttled between captures")
	check(after_view.origin.distance_to(before_view.origin) > 1, "World-view shader matrix follows motion even without a capture")
	check(project(mirror.material, left.center + left.up * left.half_extents.y * 0.5).distance_to(before_uv) < 0.003, "Mirror-relative UVs remain stable during fast translation")
	manager.update_views(0.1, camera, kestrel, true)
	check(mirror.updates == captures + 1, "Capture resumes when its budget interval elapses")
	# A mirror must not turn black as its center crosses the screen edge while
	# part of its glass remains visible. Find that boundary for the actual viewport.
	var viewing_direction: Vector3 = (left.center - camera.global_position).normalized()
	var partial := false
	for degrees in range(1, 90):
		camera.look_at(camera.global_position + viewing_direction.rotated(left.up, deg_to_rad(degrees)), left.up)
		if camera.is_position_in_frustum(left.center): continue
		for x in [-1, 1]:
			if camera.is_position_in_frustum(left.center + left.up.cross(left.normal) * left.half_extents.x * x): partial = true
		if partial: break
	check(partial, "Screen-edge fixture retains part of the optical aperture")
	manager.update_views(0.001, camera, kestrel, true)
	check(bool(mirror.material.get_shader_parameter("reflection_valid")), "Partially visible mirror stays reflective when its center leaves the screen")
	camera.global_position = left.center - left.normal * 0.8
	camera.look_at(left.center, left.up)
	manager.update_views(0.001, camera, kestrel, true)
	check(not bool(mirror.material.get_shader_parameter("reflection_valid")), "Optical backside is disabled immediately between captures")
	# Optical placement must follow the articulated panel, independently of
	# suspension/chassis motion while the native mechanism opens the door.
	var closed_basis := kestrel.get_visual_basis()
	var closed_position := kestrel.get_position_ws()
	var closed_optical := optical_for(kestrel, 0)
	check(kestrel.set_door_open(0, true), "Stationary physical door accepts opening")
	world.step_blocking(1.8)
	world.sync_visuals()
	var open_optical := optical_for(kestrel, 0)
	var open_basis := kestrel.get_visual_basis()
	check((closed_basis.inverse() * closed_optical.normal).distance_to(open_basis.inverse() * open_optical.normal) > 0.5,
		"Optical normal follows door rotation independently of chassis")
	check((closed_basis.inverse() * (closed_optical.center - closed_position)).distance_to(open_basis.inverse() * (open_optical.center - kestrel.get_position_ws())) > 0.1,
		"Optical center follows door motion independently of chassis")
	var saved_mesh: MeshInstance3D = mirror.mesh
	var original_material: Material = mirror.original_material
	var original_layers: int = mirror.original_layers
	var old_viewport: SubViewport = mirror.viewport
	var concept: SBVehicle = game.spawn_vehicle(world, "res://cars/concept_gt.car.json", Transform3D.IDENTITY)
	world.sync_visuals()
	check(is_instance_valid(concept), "Imported Concept loads")
	if not is_instance_valid(concept):
		quit(1)
		return
	var imported := concept.get_mirror_surfaces()
	check(imported.size() == 2, "Concept excludes hidden procedural mirrors")
	for optical: Dictionary in imported:
		check_rearward_aim(concept, optical)
		check(str(optical.mesh.name) in ["BodyDoorLMirror", "BodyDoorRMirror"], "Imported optical plane comes from glass, not housing")
	view_surface(camera, optical_for(concept, 0))
	manager.update_views(1, camera, concept, true)
	check(saved_mesh.material_override == original_material and saved_mesh.layers == original_layers, "Changing vehicle restores previous material and layers")
	check(old_viewport.is_queued_for_deletion(), "Old vehicle reflection viewports are released")
	manager.update_views(1, camera, concept, false)
	for entry: Dictionary in manager._mirrors:
		check(entry.mesh.material_override == entry.original_material and entry.mesh.layers == entry.original_layers and entry.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Leaving cockpit restores optics and stops reflection rendering")
	manager.queue_free()
	await process_frame
	check(not is_instance_valid(old_viewport), "Released viewport does not survive another frame")
	world.remove_vehicle(kestrel)
	world.remove_vehicle(concept)
	host.queue_free()
	await process_frame
	print("MIRROR TEST ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
