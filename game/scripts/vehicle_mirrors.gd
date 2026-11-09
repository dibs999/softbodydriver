extends Node
## Two actual planar reflections. The native optical planes follow the deformed
## vehicle/panel skin; projective sampling needs no authored UVs or fake rear image.
const MIRROR_LAYER := 1 << 19
const MirrorShader := preload("res://shaders/vehicle_mirror.gdshader")
var _vehicle: SBVehicle
var _mirrors: Array[Dictionary] = []
var _elapsed := 0.0
var update_count := 0
var _active := false

func _exit_tree() -> void:
	_release()

func _release() -> void:
	for mirror in _mirrors:
		var mesh: MeshInstance3D = mirror.mesh
		if is_instance_valid(mesh):
			mesh.material_override = mirror.original_material
			mesh.layers = mirror.original_layers
		if is_instance_valid(mirror.viewport): mirror.viewport.queue_free()
	_mirrors.clear()
	_vehicle = null
	_active = false

func _configure(view: Camera3D, vehicle: SBVehicle) -> void:
	_release()
	_vehicle = vehicle
	if not is_instance_valid(vehicle): return
	for optical: Dictionary in vehicle.get_mirror_surfaces():
		var mesh: MeshInstance3D = optical.mesh
		var viewport := SubViewport.new()
		viewport.name = "MirrorViewportLeft" if optical.side == 0 else "MirrorViewportRight"
		viewport.size = Vector2i(384, 192)
		viewport.world_3d = view.get_world_3d()
		viewport.gui_disable_input = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.positional_shadow_atlas_size = 0
		add_child(viewport)
		var camera := Camera3D.new()
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.cull_mask = view.cull_mask & ~MIRROR_LAYER
		viewport.add_child(camera)
		camera.current = true
		var material := ShaderMaterial.new()
		material.shader = MirrorShader
		material.set_shader_parameter("reflection_texture", viewport.get_texture())
		_mirrors.append({"mesh": mesh, "viewport": viewport, "camera": camera, "material": material,
			"original_material": mesh.material_override, "original_layers": mesh.layers, "side": optical.side,
			"updates": 0, "plane": optical, "visible": false})
	_elapsed = 1.0

func _set_active(enabled: bool) -> void:
	if _active == enabled: return
	_active = enabled
	for mirror in _mirrors:
		if is_instance_valid(mirror.mesh):
			mirror.mesh.material_override = mirror.material if enabled else mirror.original_material
			mirror.mesh.layers = MIRROR_LAYER if enabled else mirror.original_layers
		mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mirror.material.set_shader_parameter("reflection_valid", false)
		mirror.visible = false
	_elapsed = 1.0

static func reflected_eye(eye: Vector3, center: Vector3, normal: Vector3) -> Vector3:
	return eye - 2.0 * normal * (eye - center).dot(normal)

static func aperture_in_view(view: Camera3D, center: Vector3, normal: Vector3, up: Vector3, extents: Vector2) -> bool:
	if view.is_position_in_frustum(center): return true
	var right := up.cross(normal)
	for x in [-1, 1]:
		for y in [-1, 1]:
			if view.is_position_in_frustum(center + right * extents.x * x + up * extents.y * y): return true
	return false

func update_views(delta: float, view: Camera3D, vehicle: SBVehicle, enabled: bool) -> void:
	if _vehicle != vehicle or (is_instance_valid(vehicle) and _mirrors.is_empty()):
		_configure(view, vehicle)
	var game := get_node_or_null("/root/Game")
	var preset := int(game.get("graphics").get("mirrors", 1)) - 1 if game else 1
	_set_active(enabled and is_instance_valid(vehicle) and preset >= 0)
	if not _active: return
	_elapsed += delta
	var interval := 1.0 / (12.0 if preset == 0 else 20.0)
	var capture_due := _elapsed >= interval
	if capture_due: _elapsed = 0.0
	# The reflective mesh moves every rendered frame. Keeping a stale world-view
	# matrix until the next texture capture makes its UVs slide out of the image
	# at road speed. Update optical transforms continuously; budget only rendering.
	var frames: Array = vehicle.get_mirror_surfaces()
	for mirror in _mirrors:
		mirror.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var found := false
		for optical: Dictionary in frames:
			if optical.mesh != mirror.mesh: continue
			found = true
			mirror.plane = optical
			var center: Vector3 = optical.center
			var normal: Vector3 = optical.normal
			var up: Vector3 = optical.up
			var extents: Vector2 = optical.half_extents
			var distance := (view.global_position - center).dot(normal)
			# Render only optical faces actually in the driver's view, facing the
			# eye and within reach. Detached mirrors far away consume no viewport.
			var visible := distance > 0.025 and extents.x > 0.001 and extents.y > 0.001 and view.global_position.distance_to(center) < 5.0 and aperture_in_view(view, center, normal, up, extents)
			var newly_visible := visible and not bool(mirror.visible)
			mirror.visible = visible
			mirror.material.set_shader_parameter("reflection_valid", visible)
			if not visible: break
			var viewport: SubViewport = mirror.viewport
			var resolution := Vector2i(256, 128) if preset <= 0 else Vector2i(384, 192)
			var resized := viewport.size != resolution
			if resized: viewport.size = resolution
			var camera: Camera3D = mirror.camera
			camera.global_transform = Transform3D(Basis.looking_at(normal, up), reflected_eye(view.global_position, center, normal))
			var local_center := camera.global_transform.affine_inverse() * center
			var near_clip := distance + 0.002
			var aspect := float(viewport.size.x) / viewport.size.y
			var height := 2.1 * maxf(extents.y, extents.x / aspect)
			var ratio := near_clip / distance
			camera.set_frustum(height * ratio, Vector2(local_center.x, local_center.y) * ratio, near_clip, 350.0)
			mirror.material.set_shader_parameter("mirror_projection", camera.get_camera_projection())
			mirror.material.set_shader_parameter("mirror_view", camera.global_transform.affine_inverse())
			if capture_due or newly_visible or resized:
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				mirror.updates += 1
				update_count += 1
			break
		if not found:
			mirror.visible = false
			mirror.material.set_shader_parameter("reflection_valid", false)
