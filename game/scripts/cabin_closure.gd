extends Node3D
## Firewall and footwell for imported vehicle models. Low-poly models often model the dashboard as
## a floating slab: from the driver's seat one looked under it straight through to the front tyres
## and the road. The closure is a dark, matte tub between dashboard, floor and door sills, placed
## from the body profile in the same vehicle frame as the weather's cabin shelter.

var _vehicle: SBVehicle


func attach(vehicle: SBVehicle, body: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	_vehicle = vehicle if is_instance_valid(vehicle) and not body.is_empty() else null
	visible = _vehicle != null
	if _vehicle == null:
		return
	top_level = true
	var length := float(body.get("length", 4.26))
	var origin_x := length - float(body.get("frontOverhang", 0.89)) - float(body.get("wheelbase", 2.62)) * 0.5
	var origin_y := float(body.get("groundClearance", 0.14)) + 0.04
	var cowl := length - float(body.get("hoodLength", 1.15)) - origin_x
	var floor_y := float(body.get("groundClearance", 0.14)) + 0.13 - origin_y
	var dash_y := float(body.get("hoodHeight", 0.98)) - 0.12 - origin_y
	var half := float(body.get("width", 1.79)) * 0.5 - 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.07, 0.075)
	material.roughness = 0.95
	var parts := [
		# Firewall slightly behind the cowl, floor to under the dashboard.
		[Vector3(cowl - 0.06, (floor_y + dash_y) * 0.5, 0.0), Vector3(0.03, dash_y - floor_y, half * 2.0)],
		# Footwell floor towards the seats.
		[Vector3(cowl - 0.55, floor_y, 0.0), Vector3(1.0, 0.03, half * 2.0)],
		# Sloped toe board between firewall and floor.
		[Vector3(cowl - 0.2, floor_y + 0.12, 0.0), Vector3(0.03, 0.32, half * 2.0)],
	]
	for i in parts.size():
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = parts[i][1]
		mi.mesh = box
		mi.material_override = material
		mi.position = parts[i][0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 2:
			mi.rotation.z = deg_to_rad(-40.0)
		add_child(mi)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if not is_instance_valid(_vehicle):
		visible = false
		return
	var b := _vehicle.get_visual_basis()
	global_transform = Transform3D(Basis(-b.z, b.y, b.x), _vehicle.get_position_ws())
