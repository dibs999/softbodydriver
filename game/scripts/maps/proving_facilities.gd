extends RefCounted
const C := preload("res://scripts/maps/common.gd")
const Lighting := preload("res://scripts/maps/facility_lighting.gd")

static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	var facilities := Node3D.new()
	facilities.name = "WayfindingAndService"
	parent.add_child(facilities)
	var white := C.mat(Color(0.9, 0.9, 0.85))
	var mint := C.mat(Color(0.15, 0.65, 0.53))
	var blue := C.mat(Color(0.055, 0.15, 0.23))
	var steel := C.mat(Color(0.12, 0.16, 0.19), 0.48, 0.65)
	# The beginner apron has a level entry and a full-width exit to the brake straight.
	# Paint does not introduce artificial bumps or hidden colliders.
	for z: float in [-9.4, -0.6]:
		paint(facilities, Vector3(-69, 0.022, z), Vector2(192, 0.15), white)
	paint(facilities, Vector3(-145, 0.025, 3), Vector2(10, 7.5), C.mat(Color(0.14, 0.24, 0.25)))
	for z: float in [-0.7, 6.7]:
		paint(facilities, Vector3(-145, 0.027, z), Vector2(10, 0.18), mint)
	paint(facilities, Vector3(-150, 0.027, 3), Vector2(0.18, 7.5), mint)
	# Approach markers sit off the driving envelope, with readable faces toward +X.
	make_sign(facilities, world, Vector3(-131, 0, -12), "01  BREMSGERADE\n50 km/h  >  BREMSEN", steel, blue, white)
	make_sign(facilities, world, Vector3(-155, 0, 9), "SERVICE  /  TANKEN\nEINFAHRT  >", steel, blue, white)
	make_sign(facilities, world, Vector3(-28, 0, -17), "02  SPRUNG / CRASH\nRECHTS  >", steel, blue, white)
	make_sign(facilities, world, Vector3(202, 0, -57), "03  BOXENGASSE\nTEMPO 20", steel, blue, white)
	# A marked access aisle reaches all four open workshop bays from their east side.
	for z in range(-112, -58, 6):
		paint(facilities, Vector3(199, 0.024, z), Vector2(0.17, 3.0), white)
	for z: float in [-74, -84, -94, -104]:
		paint(facilities, Vector3(192, 0.026, z), Vector2(4, 0.18), mint)
		paint(facilities, Vector3(190.3, 0.026, z - 0.6), Vector2(0.18, 1.3), mint)
		paint(facilities, Vector3(182, 0.026, z + 3.8), Vector2(13, 0.12), white)
	# Crash runway must be conspicuous; a beginner is never spawned facing it.
	C.label3d(facilities, "CRASH TEST\nKEINE DURCHFAHRT", Vector3(223.94, 2.1, -40), -PI * 0.5, 0.65)
	var amber := C.mat(Color(0.95, 0.66, 0.08))
	for z in range(-50, -28, 2):
		C.box(facilities, null, Vector3(223.96, 0.7, z), Vector3(0.025, 0.65, 0.22), Vector3(0.4, 0, 0), amber, 1, false)
	var lighting := Lighting.new()
	lighting.name = "FacilityLighting"
	facilities.add_child(lighting)
	for p: Vector3 in [Vector3(-151, 0, 8), Vector3(-125, 0, -13), Vector3(196, 0, -64), Vector3(196, 0, -84), Vector3(196, 0, -107), Vector3(168, 0, -65)]:
		lamp(lighting, world, p, steel)
	return {"service_approach": PackedVector3Array([Vector3(-145, 0, -5), Vector3(-140, 0, -2), Vector3(-140, 0, 3), Vector3(-145, 0, 3)]),
		"pit_approach": PackedVector3Array([Vector3(211, 0, -58), Vector3(202, 0, -65), Vector3(193, 0, -74), Vector3(181, 0, -74)])}

static func paint(parent: Node3D, point: Vector3, size: Vector2, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = material
	mesh.position = point
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

static func make_sign(parent: Node3D, world: SBWorld, point: Vector3, caption: String, steel: Material, panel: Material, ink: Material) -> void:
	for side: float in [-1.8, 1.8]:
		C.box(parent, world, point + Vector3(0, 1.5, side), Vector3(0.07, 1.5, 0.07), Vector3.ZERO, steel)
	C.box(parent, world, point + Vector3(0, 2.5, 0), Vector3(0.07, 0.75, 2.1), Vector3.ZERO, panel)
	# Two faces: signs remain useful when returning to service.
	C.label3d(parent, caption, point + Vector3(-0.08, 2.5, 0), -PI * 0.5, 0.38, ink.albedo_color)
	C.label3d(parent, caption, point + Vector3(0.08, 2.5, 0), PI * 0.5, 0.38, ink.albedo_color)

static func lamp(parent: Node3D, world: SBWorld, point: Vector3, steel: Material) -> void:
	C.box(parent, world, point + Vector3(0, 3.3, 0), Vector3(0.11, 3.3, 0.11), Vector3.ZERO, steel)
	C.box(parent, null, point + Vector3(0, 6.6, 0.5), Vector3(0.45, 0.12, 0.8), Vector3.ZERO, steel, 1, false)
	var lens_material := C.mat(Color(1.0, 0.84, 0.59))
	lens_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lens := C.box(parent, null, point + Vector3(0, 6.46, 0.5), Vector3(0.36, 0.025, 0.7), Vector3.ZERO, lens_material, 1, false)
	parent.luminous.append(lens)
	var light := OmniLight3D.new()
	light.position = point + Vector3(0, 6.1, 0.5)
	light.light_color = Color(1.0, 0.84, 0.65)
	light.light_energy = 0
	light.omni_range = 21
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 100
	light.distance_fade_length = 30
	parent.add_child(light)
	parent.lamps.append(light)
