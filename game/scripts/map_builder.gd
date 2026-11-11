extends RefCounted
## Builds the maps: visual geometry (Godot meshes) + matching static colliders in the SBWorld.
## Returns {"spawns": Array[Transform3D], "waypoints": PackedVector3Array, "speeds": PackedFloat32Array}.

const FACE_POS_X := 0.0           # yaw that makes a car (local +X forward) face world +X
const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")


static func car_xform(pos: Vector3, heading: Vector3) -> Transform3D:
	## Transform for spawning a car at `pos` (ground) facing `heading`.
	var f := Vector3(heading.x, 0, heading.z).normalized()
	var up := Vector3.UP
	var r := f.cross(up)
	return Transform3D(Basis(f, up, r), pos)


static func _mat(color: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


static func _box(parent: Node3D, world: SBWorld, center: Vector3, half: Vector3, euler: Vector3, mat: Material, friction := 1.0, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(euler, EULER_ORDER_XYZ), center)
	parent.add_child(mi)
	if collide:
		world.add_box(center, half, euler, friction)


static func _ramp(parent: Node3D, world: SBWorld, x_start: float, z: float, half_len: float, angle: float, mat: Material) -> void:
	## Ramp rising along +X from (x_start, 0, z).
	var h := 0.4
	var cx := x_start + half_len * cos(angle) + h * sin(angle)
	var cy := half_len * sin(angle) - h * cos(angle)
	_box(parent, world, Vector3(cx, cy, z), Vector3(half_len, h, 2.8), Vector3(0, 0, angle), mat)


static func _flat_quad(parent: Node3D, center: Vector3, size: Vector2, mat: Material, yaw := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Loose props of the map being built; the game spawns them as soft bodies ("props" in the map data).
static var props: Array = []

static func _cone(_parent: Node3D, pos: Vector3, yaw := 0.0) -> void:
	props.append({"kind": "cone", "position": Vector3(pos.x, 0.0, pos.z), "yaw": yaw})


static func _drum(pos: Vector3, yaw := 0.0) -> void:
	props.append({"kind": "barrel", "position": pos, "yaw": yaw})


# =========================================================================== proving grounds
static func build_proving_grounds(world: SBWorld, parent: Node3D) -> Dictionary:
	props.clear()
	world.add_ground_plane(1.0)
	var grass := C.surface_material("grass", 3.1, Color(0.50, 0.66, 0.50))
	var asphalt := C.surface_material("asphalt", 2.0, Color.WHITE, 0.30)
	var concrete := C.surface_material("pavement", 2.1, Color(0.86, 0.86, 0.85), 0.25)
	var line := _mat(Color(0.92, 0.92, 0.88), 0.6)
	var red := _mat(Color(0.75, 0.1, 0.08), 0.6)

	_flat_quad(parent, Vector3(0, -0.01, 0), Vector2(3000, 3000), grass)
	_flat_quad(parent, Vector3(0, 0.0, 0), Vector2(750, 440), asphalt)

	var landscape_regions: Array = preload("res://scripts/maps/proving_surroundings.gd").build(world, parent)

	# Oval track painted on the pad (straights along X).
	var waypoints := PackedVector3Array()
	var speeds := PackedFloat32Array()
	var straight := 340.0
	var radius := 76.0
	var cz := 94.0
	var steps := 128
	for i in steps:
		var t := float(i) / steps
		var p := Vector3.ZERO
		var perim := 2.0 * straight + 2.0 * PI * radius
		var s := t * perim
		var spd := 30.0
		if s < straight:
			p = Vector3(-straight / 2 + s, 0, cz - radius)
		elif s < straight + PI * radius:
			var a := (s - straight) / radius
			p = Vector3(straight / 2 + sin(a) * radius, 0, cz - cos(a) * radius)
			spd = 19.0
		elif s < 2 * straight + PI * radius:
			p = Vector3(straight / 2 - (s - straight - PI * radius), 0, cz + radius)
		else:
			var a := (s - 2 * straight - PI * radius) / radius
			p = Vector3(-straight / 2 - sin(a) * radius, 0, cz + cos(a) * radius)
			spd = 19.0
		waypoints.append(p)
		speeds.append(spd)
	var paint := PlaneMesh.new()
	paint.size = Vector2.ONE
	var white_marks: Array[Transform3D] = []
	for i in waypoints.size():
		var a := waypoints[i]
		var b := waypoints[(i + 1) % waypoints.size()]
		var mid := (a + b) * 0.5
		var d := b - a
		var yaw := atan2(-d.z, d.x)
		for side: float in [-6.5, 6.5]:
			var n := Vector3(-d.z, 0, d.x).normalized() * side
			var basis := Basis(Vector3.UP, yaw).scaled_local(Vector3(d.length(), 1.0, 0.2))
			white_marks.append(Transform3D(basis, mid + n + Vector3(0, 0.012, 0)))

	_oval_furniture(parent, world, straight, radius, cz)
	_grandstand(parent, world, Vector3(0, 0, cz + radius + 26.0), 96.0)
	# Start grid lines.
	for i in 6:
		white_marks.append(Transform3D(Basis.from_scale(Vector3(0.3, 1, 4)), Vector3(-20 + i * 9, 0.012, -40)))
	for row in 2:
		for col in 10:
			if (row + col) % 2 == 0:
				white_marks.append(Transform3D(Basis.from_scale(Vector3(0.65, 1, 0.65)),
					Vector3(8.0 + row * 0.65, 0.012, -43.0 + col * 0.65)))
	C.scatter_multimesh(parent, paint, line, white_marks, false)
	var amber_marks: Array[Transform3D] = []
	for x in range(-30, 223, 7):
		for z: float in [-44.2, -35.8]:
			amber_marks.append(Transform3D(Basis.from_scale(Vector3(4.6, 1, 0.19)), Vector3(x, 0.013, z)))
	C.scatter_multimesh(parent, paint, _mat(Color(0.95, 0.68, 0.11)), amber_marks, false)
	_proving_wear(parent, world, waypoints, straight, radius, cz)
	var steel := _mat(Color(0.32, 0.36, 0.39), 0.55, 0.6)
	var blue := _mat(Color(0.10, 0.24, 0.41), 0.65)
	_flat_quad(parent, Vector3(20, 0.005, -130), Vector2(330, 98), concrete)
	var training := PackedVector3Array()
	for i in 96:
		var a := TAU * i / 96
		training.append(Vector3(20.0 + cos(a) * 142.0, 0, -130.0 + sin(a) * 37.0))
	parent.add_child(C.road_mesh(training, 4.5, C.road_material(2, 9.0, 12.0, "rural"), true, 0.015))
	var handling := _handling_course(world, parent, line, blue)
	# A separate, smooth braking lane with metre marks and a mild 5 cm bump strip.
	for metres in range(0, 101, 10):
		var x := -95.0 + metres
		_flat_quad(parent, Vector3(x, 0.019, -5), Vector2(0.16, 7.0), line)
		C.label3d(parent, "%d m" % metres, Vector3(x, 0.6, -10), 0, 0.26)
	for i in 3:
		_box(parent, world, Vector3(30 + i * 8, 0, -5), Vector3(0.5, 0.05, 3.4), Vector3.ZERO, concrete)
	C.label3d(parent, "BREMSWEG  /  100 m", Vector3(-103, 1.5, -10), 0, 0.42)
	_service_campus(world, parent)
	var facilities := preload("res://scripts/maps/proving_facilities.gd").build(world, parent)
	var workshop := Vector3(182, 0, -74)
	for i in 4:
		var p := workshop + Vector3(0, 0, -i * 10.0)
		_box(parent, world, p + Vector3(-7.0, 2.7, 0), Vector3(0.24, 2.7, 4.9), Vector3.ZERO, steel)
		_box(parent, world, p + Vector3(0, 5.4, 0), Vector3(7.4, 0.18, 4.9), Vector3.ZERO, blue, 0.8, true)
		_box(parent, world, p + Vector3(0, 2.7, -4.8), Vector3(7.0, 2.7, 0.13), Vector3.ZERO, concrete)
	C.label3d(parent, "FAHRDYNAMIK   /   BOXEN", workshop + Vector3(7.45, 5.27, -15), PI * 0.5, 0.56)
	# Back of the box row (towards the office walkway): per box a steel staff door with frame,
	# canopy and box number, a band of high windows, a wall lamp, and downpipes at the joints
	# (before, a 40 m blank wall).
	var back_x := workshop.x - 7.24
	var door_mat := _mat(Color(0.30, 0.36, 0.40), 0.5, 0.5)
	var frame_mat := _mat(Color(0.72, 0.73, 0.74), 0.4, 0.6)
	var band_glass := _mat(Color(0.12, 0.19, 0.23), 0.12, 0.6)
	var lamp_lens := _mat(Color(0.95, 0.95, 0.9), 0.3)
	for i in 4:
		var z := workshop.z - i * 10.0
		_box(parent, null, Vector3(back_x - 0.03, 1.05, z + 2.4), Vector3(0.03, 1.05, 0.5), Vector3.ZERO, door_mat, 1, false)
		_box(parent, null, Vector3(back_x - 0.05, 1.1, z + 2.4), Vector3(0.025, 1.12, 0.56), Vector3.ZERO, frame_mat, 1, false)
		_box(parent, null, Vector3(back_x - 0.07, 1.05, z + 2.4), Vector3(0.02, 1.0, 0.46), Vector3.ZERO, door_mat, 1, false)
		_box(parent, null, Vector3(back_x - 0.1, 1.0, z + 2.05), Vector3(0.05, 0.02, 0.1), Vector3.ZERO, frame_mat, 1, false)   # handle
		_box(parent, null, Vector3(back_x - 0.45, 2.45, z + 2.4), Vector3(0.45, 0.05, 0.8), Vector3.ZERO, blue, 1, false)          # canopy
		C.label3d(parent, "BOX  %d" % (i + 1), Vector3(back_x - 0.03, 2.8, z + 2.4), -PI * 0.5, 0.3)
		_box(parent, null, Vector3(back_x - 0.06, 2.75, z + 3.6), Vector3(0.06, 0.08, 0.14), Vector3.ZERO, lamp_lens, 1, false)
		_box(parent, null, Vector3(back_x - 0.02, 4.1, z - 1.2), Vector3(0.02, 0.42, 2.9), Vector3.ZERO, band_glass, 1, false)
		_box(parent, null, Vector3(back_x - 0.04, 4.1, z - 1.2), Vector3(0.02, 0.46, 2.95), Vector3.ZERO, frame_mat, 1, false)
		_box(parent, null, Vector3(back_x - 0.05, 4.1, z - 1.2), Vector3(0.02, 0.42, 2.9), Vector3.ZERO, band_glass, 1, false)
		for k in 5:
			_box(parent, null, Vector3(back_x - 0.06, 4.1, z - 4.1 + k * 1.45), Vector3(0.02, 0.44, 0.03), Vector3.ZERO, frame_mat, 1, false)
		_box(parent, null, Vector3(back_x - 0.08, 2.7, z - 4.9), Vector3(0.05, 2.7, 0.05), Vector3.ZERO, frame_mat, 1, false)          # downpipe
	for z: float in [-57.2, -50.8]:
		_box(parent, world, Vector3(24, 1.0, z), Vector3(0.12, 1.0, 0.12), Vector3.ZERO, steel)
	_box(parent, world, Vector3(24, 2.05, -54), Vector3(0.10, 0.48, 3.7), Vector3.ZERO, blue, 0.8, false)
	C.label3d(parent, "TESTGELÄNDE  /  01", Vector3(23.89, 2.05, -54), -PI * 0.5, 0.58)
	for x: float in [32.0, 47.0, 62.0]:
		for offset: float in [-5.3, 5.3]:
			_box(parent, world, Vector3(x + offset, 1.5, -65), Vector3(0.16, 1.5, 0.18), Vector3.ZERO, steel)
		_box(parent, world, Vector3(x, 3.03, -65), Vector3(5.8, 0.12, 3.3), Vector3.ZERO, blue, 0.8, true)

	# Dedicated jump/crash lane along +X (z = -40), separate from beginner spawn.
	# Ramps: rotated slabs whose leading top edge sits exactly on the ground.
	_ramp(parent, world, 38.0, -40.0, 5.0, deg_to_rad(9.0), concrete)
	_ramp(parent, world, 120.0, -28.0, 3.5, deg_to_rad(14.0), concrete)
	# Speed bumps.
	for i in 5:
		_box(parent, world, Vector3(95 + i * 9, 0.0, -40), Vector3(0.45, 0.09, 3.0), Vector3.ZERO, red)
	# Pothole / rough strip: small blocks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 40:
		var pos := Vector3(150 + rng.randf() * 40, 0.0, -43 + rng.randf() * 6)
		_box(parent, world, pos, Vector3(0.35 + rng.randf() * 0.3, 0.05 + rng.randf() * 0.06, 0.3 + rng.randf() * 0.3),
			Vector3(0, rng.randf() * PI, 0), asphalt)
	# Crash wall at the end of the lane.
	_box(parent, world, Vector3(225, 1.5, -40), Vector3(1.0, 1.5, 12.0), Vector3.ZERO, concrete, 0.8)
	# Jersey barriers around the lane.
	for i in 18:
		_box(parent, world, Vector3(10 + i * 12, 0.4, -47), Vector3(5.8, 0.4, 0.3), Vector3.ZERO, concrete, 0.7)
	# Pole / tree for side impacts.
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.18
	pc.bottom_radius = 0.18
	pc.height = 5.0
	pole.mesh = pc
	pole.material_override = _mat(Color(0.5, 0.5, 0.52), 0.4, 0.8)
	pole.position = Vector3(-60, 2.5, -20)
	parent.add_child(pole)
	world.add_box(Vector3(-60, 2.5, -20), Vector3(0.16, 2.5, 0.16), Vector3.ZERO, 0.6)

	# Slalom cones (visual).
	for i in 10:
		_cone(parent, Vector3(-40 - i * 14, 0, -40))
	# A steep hill: heightfield bump on the pad's far side.
	# 1 m cells and a foot that sinks 6 cm under the pad: on the 2 m grid the hill's edge met the
	# asphalt at the same height and broke through it in stair steps.
	var nx := 81
	var nz := 81
	var hcell := 1.0
	var ox := -200.0
	var oz := -150.0
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var dx := (ix - 40.0) / 40.0
			var dz := (iz - 40.0) / 40.0
			var r2 := dx * dx + dz * dz
			heights[ix * nz + iz] = (7.0 * pow(1.0 - r2, 2.0) if r2 < 1.0 else 0.0) - 0.06
	world.add_heightfield(ox, oz, hcell, nx, nz, heights, 1.0)
	parent.add_child(C.terrain_mesh(ox, oz, hcell, nx, nz, heights, grass))

	var spawns: Array[Transform3D] = [
		car_xform(Vector3(-145, 0, -5), Vector3(1, 0, 0)),
		car_xform(Vector3(-15, 0, -32), Vector3(1, 0, 0)),
		car_xform(Vector3(-30, 0, -32), Vector3(1, 0, 0)),
	]
	# A drum wall at the end of the slalom lane for crash tests.
	for row in 2:
		for k in 4:
			_drum(Vector3(-196.0 - row * 0.62, 0.0, -42.0 + k * 0.64 + row * 0.32))
	return {"spawns": spawns, "waypoints": waypoints, "speeds": speeds, "props": props.duplicate(),
		"rain_shelters": proving_shelters(), "service_approach": facilities["service_approach"], "pit_approach": facilities["pit_approach"],
		"surface_regions": [{"rect": Rect2(-200, -150, 80, 80), "surface": "grass"}] + landscape_regions,
		"map_paths": [C.closed_route(waypoints), C.closed_route(training), handling, facilities["service_approach"], facilities["pit_approach"]],
		"map_places": [{"name": "Sprung- und Crashbahn", "position": Vector3(124, 0, -40)},
			{"name": "Fahrdynamik-Oval", "position": Vector3(20, 0, -130)},
			{"name": "Handling-Parcours", "position": handling[3]},
			{"name": "Werkstatt und Boxen", "position": workshop}],
		"ai_spawns": [car_xform(waypoints[0], waypoints[1] - waypoints[0]), car_xform(waypoints[64], waypoints[65] - waypoints[64])]}


## A used test facility: rubber laid down on the oval's racing line, in the braking zone and as
## doughnuts; asphalt patches of different age; distance boards along the back straight; floodlight
## masts around the pad.
## Grandstand behind the north straight: eight concrete tiers with seat rows in alternating
## colours, stairs, a cantilever roof on columns, a front fence and flags. One box collider.
static func _grandstand(parent: Node3D, world: SBWorld, front: Vector3, length: float) -> void:
	var concrete := C.noise_mat(Color(0.66, 0.66, 0.64), 0.08, 2.0, 0.9)
	var steel := C.mat(Color(0.30, 0.32, 0.35), 0.45, 0.7)
	var tiers: Array[Transform3D] = []
	var seats: Array = [[], []]
	var depth := 0.95
	var rise := 0.48
	for t in 8:
		var z := front.z + depth * (t + 0.5)
		var top := rise * (t + 1)
		tiers.append(Transform3D(Basis.from_scale(Vector3(length, top, depth)), Vector3(front.x, top * 0.5, z)))
		for block in 12:
			var x := front.x - length * 0.5 + (block + 0.5) * length / 12.0
			if block % 4 == 3:
				continue   # stairs
			var row: Array = seats[(t + block) % 2]
			row.append(Transform3D(Basis.from_scale(Vector3(length / 12.0 - 0.4, 0.42, 0.42)), Vector3(x, top + 0.21, z + 0.18)))
	var unit := BoxMesh.new()
	C.scatter_multimesh(parent, unit, concrete, tiers)
	var typed: Array[Transform3D] = []
	typed.assign(seats[0])
	C.scatter_multimesh(parent, unit, C.mat(Color(0.12, 0.30, 0.62), 0.6), typed, false)
	typed = []
	typed.assign(seats[1])
	C.scatter_multimesh(parent, unit, C.mat(Color(0.86, 0.30, 0.10), 0.6), typed, false)
	var back := front.z + depth * 8.0
	world.add_box(Vector3(front.x, rise * 4.0, front.z + depth * 4.0), Vector3(length * 0.5, rise * 4.0, depth * 4.0), Vector3.ZERO, 0.8)
	# Back wall, columns and a roof sloping towards the track.
	C.box(parent, world, Vector3(front.x, 3.2, back + 0.15), Vector3(length * 0.5, 3.2, 0.15), Vector3.ZERO, concrete, 0.8)
	for k in 9:
		var x := front.x - length * 0.5 + k * length / 8.0
		C.box(parent, world, Vector3(x, 4.6, back - 0.3), Vector3(0.18, 4.6, 0.18), Vector3.ZERO, steel, 0.6)
	C.box(parent, null, Vector3(front.x, 9.1, front.z + depth * 4.6), Vector3(length * 0.5 + 1.0, 0.14, depth * 4.6), Vector3(-0.09, 0, 0),
		C.mat(Color(0.82, 0.83, 0.85), 0.5, 0.4), 0.8, false)
	# Front fence and flags.
	C.box(parent, world, Vector3(front.x, 0.6, front.z - 0.6), Vector3(length * 0.5, 0.6, 0.04), Vector3.ZERO, steel, 0.6)
	var flag_colours := [Color(0.86, 0.30, 0.10), Color(0.12, 0.30, 0.62), Color(0.95, 0.95, 0.92)]
	for k in 7:
		var x := front.x - length * 0.5 + k * length / 6.0
		C.box(parent, null, Vector3(x, 6.5, back + 0.6), Vector3(0.05, 6.5, 0.05), Vector3.ZERO, steel, 0.6, false)
		C.box(parent, null, Vector3(x + 0.75, 12.2, back + 0.6), Vector3(0.7, 0.45, 0.02), Vector3.ZERO, C.mat(flag_colours[k % 3], 0.8), 0.6, false)
	C.label3d(parent, "TRIBÜNE  ·  START / ZIEL", Vector3(front.x, 7.6, back - 0.02), PI, 1.0)


## Race-track furniture on the oval: red and white kerbs along the inside of both bends and
## stacked tyre walls (colliding) behind the run-off on their outside.
static func _oval_furniture(parent: Node3D, world: SBWorld, straight: float, radius: float, cz: float) -> void:
	var kerb_red: Array[Transform3D] = []
	var kerb_white: Array[Transform3D] = []
	var tyres: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	for bend: float in [1.0, -1.0]:
		var centre := Vector3(bend * straight / 2, 0, cz)
		var arc := PI * radius
		var n := int(arc / 2.0)
		for k in n:
			var a := (k + 0.5) / n * PI
			var p := centre + Vector3(bend * sin(a), 0, -cos(a)) * (radius - 7.1)
			var tangent := Vector3(bend * cos(a), 0, sin(a))
			var xf := Transform3D(Basis(Vector3.UP, atan2(-tangent.z, tangent.x)).scaled_local(Vector3(arc / n, 0.06, 1.1)), p + Vector3.UP * 0.03)
			(kerb_red if k % 2 == 0 else kerb_white).append(xf)
		# Tyre wall: three tyres high, a painted belt on every other section.
		var wall_r := radius + 20.0
		var a0 := deg_to_rad(35.0)
		var a1 := deg_to_rad(145.0)
		var count := int((a1 - a0) * wall_r / 0.68)
		for k in count:
			var a := a0 + (a1 - a0) * k / (count - 1)
			var p := centre + Vector3(bend * sin(a), 0, -cos(a)) * wall_r
			for level in 3:
				tyres.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * (0.13 + level * 0.25)))
			if (k / 6) % 2 == 0:
				bands.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.63))
			if k % 5 == 0:
				var yaw := atan2(-cos(a) * bend, sin(a))
				world.add_box(p + Vector3.UP * 0.38, Vector3(0.36, 0.38, 1.75), Vector3(0, -yaw, 0), 0.5)
	var kerb := BoxMesh.new()
	C.scatter_multimesh(parent, kerb, _mat(Color(0.78, 0.10, 0.08), 0.55), kerb_red, false)
	C.scatter_multimesh(parent, kerb, _mat(Color(0.92, 0.92, 0.90), 0.55), kerb_white, false)
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.33
	tyre.bottom_radius = 0.33
	tyre.height = 0.24
	tyre.radial_segments = 12
	C.scatter_multimesh(parent, tyre, _mat(Color(0.06, 0.06, 0.06), 0.9), tyres)
	var band := CylinderMesh.new()
	band.top_radius = 0.335
	band.bottom_radius = 0.335
	band.height = 0.06
	band.radial_segments = 12
	C.scatter_multimesh(parent, band, _mat(Color(0.85, 0.85, 0.82), 0.6), bands, false)


static func _proving_wear(parent: Node3D, world: SBWorld, oval: PackedVector3Array, straight: float, radius: float, cz: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	# Patches of older and newer asphalt.
	var older := C.surface_material("asphalt", 2.0, Color(1.12, 1.10, 1.06), 0.30)
	var newer := C.surface_material("asphalt", 2.0, Color(0.72, 0.72, 0.74), 0.30)
	for i in 26:
		var c := Vector3(rng.randf_range(-360, 360), 0.004 + 0.0004 * i, rng.randf_range(-210, 210))
		var size := Vector2(rng.randf_range(12, 60), rng.randf_range(8, 40))
		C.quad(parent, c, size, older if i % 3 else newer, snappedf(rng.randf_range(-0.3, 0.3), 0.05))
	# Rubber marks: a streaky texture laid as transparent quads.
	var rubber := StandardMaterial3D.new()
	rubber.albedo_texture = _rubber_texture()
	rubber.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	rubber.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rubber.roughness = 0.75
	rubber.render_priority = 1
	var marks: Array[Transform3D] = []
	var n := oval.size()
	for i in n:
		var a := oval[i]
		var b := oval[(i + 1) % n]
		var curve := absf(a.x) > straight * 0.5 - 2.0
		if not curve and rng.randf() > 0.25: continue
		var d := b - a
		# Racing line: the outside of the oval at the curve entry, the inside at the apex.
		var inward := Vector3(-d.z, 0, d.x).normalized()
		var lateral := (2.5 if curve else -2.0) * (1.0 if rng.randf() < 0.5 else 0.6)
		var basis := Basis(Vector3.UP, atan2(-d.z, d.x)).scaled_local(Vector3(d.length() * 1.05, 1.0, 1.9))
		marks.append(Transform3D(basis, (a + b) * 0.5 + inward * lateral + Vector3.UP * 0.014))
	# Braking zone: dark straight streaks before the stop line.
	for k in 18:
		var x := rng.randf_range(60.0, 210.0)
		var l := rng.randf_range(8.0, 30.0)
		var z := -40.0 + rng.randf_range(-2.2, 2.2)
		marks.append(Transform3D(Basis.from_scale(Vector3(l, 1.0, 1.7)), Vector3(x, 0.015, z)))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	C.scatter_multimesh(parent, plane, rubber, marks, false)
	# Doughnuts on the open pad beside the start.
	var ring := StandardMaterial3D.new()
	ring.albedo_texture = _doughnut_texture()
	ring.albedo_color = Color(0.04, 0.04, 0.04, 0.8)
	ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.render_priority = 1
	var rings: Array[Transform3D] = []
	for k in 5:
		var c := Vector3(rng.randf_range(-300, -200), 0.016, rng.randf_range(-170, -90))
		rings.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(Vector3.ONE * rng.randf_range(9, 13)), c))
	C.scatter_multimesh(parent, plane, ring, rings, false)
	# Distance boards along the back straight (every 50 m).
	var board_mat := _mat(Color(0.95, 0.95, 0.93), 0.6)
	var post_mat := _mat(Color(0.35, 0.36, 0.37), 0.5, 0.6)
	for k in 7:
		var x := straight * 0.5 - 30.0 - k * 50.0
		var p := Vector3(x, 0, cz + radius + 11.0)
		_box(parent, world, p + Vector3.UP * 0.9, Vector3(0.06, 0.9, 0.06), Vector3.ZERO, post_mat)
		_box(parent, world, p + Vector3.UP * 2.0, Vector3(0.7, 0.45, 0.03), Vector3.ZERO, board_mat, 0.6, false)
		C.label3d(parent, str(50 * (k + 1)), p + Vector3(0, 2.0, -0.04), PI, 0.7, Color(0.05, 0.05, 0.05))
	# Floodlight masts around the pad.
	var mast := CylinderMesh.new()
	mast.top_radius = 0.18
	mast.bottom_radius = 0.32
	mast.height = 24.0
	var head := BoxMesh.new()
	head.size = Vector3(3.2, 1.2, 0.5)
	var masts: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for p: Vector3 in [Vector3(-390, 0, -230), Vector3(0, 0, -232), Vector3(390, 0, -230), Vector3(-390, 0, 230), Vector3(0, 0, 232), Vector3(390, 0, 230)]:
		masts.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 12.0))
		var face := Vector3(-p.x, 0, -p.z).normalized()
		heads.append(Transform3D(Basis.looking_at(face, Vector3.UP).rotated(face.cross(Vector3.UP).normalized(), -0.35), p + Vector3.UP * 24.2))
		world.add_box(p + Vector3.UP * 6.0, Vector3(0.35, 6.0, 0.35), Vector3.ZERO, 0.7)
	C.scatter_multimesh(parent, mast, post_mat, masts)
	C.scatter_multimesh(parent, head, _mat(Color(0.25, 0.26, 0.27), 0.5, 0.6), heads)


static var _rubber_tex: ImageTexture
static func _rubber_texture() -> ImageTexture:
	if _rubber_tex: return _rubber_tex
	var img := Image.create(256, 64, false, Image.FORMAT_LA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	for y in 64:
		for x in 256:
			# Two tyre-width streaks, fading in and out along the length.
			var v := float(y) / 63.0
			var streak := maxf(1.0 - absf(v - 0.25) / 0.14, 1.0 - absf(v - 0.75) / 0.14)
			var along := sin(PI * float(x) / 255.0)
			var grain := 0.6 + 0.4 * noise.get_noise_2d(x * 3.0, y * 0.4)
			img.set_pixel(x, y, Color(0, 0, 0, clampf(streak * along * grain, 0.0, 1.0)))
	img.generate_mipmaps()
	_rubber_tex = ImageTexture.create_from_image(img)
	return _rubber_tex


static var _ring_tex: ImageTexture
static func _doughnut_texture() -> ImageTexture:
	if _ring_tex: return _ring_tex
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_LA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s * 0.5, y - s * 0.5).length() / (s * 0.5)
			var a := atan2(y - s * 0.5, x - s * 0.5)
			var band := maxf(1.0 - absf(d - 0.62) / 0.07, 1.0 - absf(d - 0.84) / 0.07)
			img.set_pixel(x, y, Color(0, 0, 0, clampf(band * (0.55 + 0.45 * sin(a * 3.0 + d * 9.0)), 0.0, 1.0)))
	img.generate_mipmaps()
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex


static func _handling_course(world: SBWorld, parent: Node3D, paint: Material, sign_mat: Material) -> PackedVector3Array:
	var route := PackedVector3Array([Vector3(-25, 0, 39)])
	var yellow := _mat(Color(0.93, 0.63, 0.13))
	for i in 9:
		var p := Vector3(-13 + i * 14.0, 0, 44 + (i % 2) * 9.0)
		route.append(p)
		for sign: float in [-1.0, 1.0]:
			var cone := p + Vector3(0, 0, sign * 3.1)
			_cone(parent, cone)
			_flat_quad(parent, cone + Vector3.UP * 0.013, Vector2(0.34, 1.1), yellow)
	route.append(Vector3(110, 0, 53))
	for z: float in [45.0, 51.0]:
		_flat_quad(parent, Vector3(-24, 0.015, z), Vector2(0.15, 5.8), paint)
	var sign := Vector3(-27, 1.4, 55)
	_box(parent, world, sign, Vector3(0.12, 0.40, 2.6), Vector3.ZERO, sign_mat, 0.75, false)
	_box(parent, world, sign - Vector3.UP * 0.68, Vector3(0.07, 0.68, 0.08), Vector3.ZERO, sign_mat)
	C.label3d(parent, "HANDLING  /  09 TORE", sign - Vector3.RIGHT * 0.13, -PI * 0.5, 0.37)
	return route


# =========================================================================== hill roads
static func build_hill_roads(world: SBWorld, parent: Node3D) -> Dictionary:
	props.clear()
	var nx := 385
	var nz := 385
	var cell := 3.5
	var ox := -672.0
	var oz := -672.0
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.0036
	noise.fractal_octaves = 4
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var x := ox + ix * cell
			var z := oz + iz * cell
			var edge := smoothstep(430.0, 710.0, Vector2(x, z).length())
			var hillside := noise.get_noise_2d(x, z) * 0.5 + 0.5
			heights[ix * nz + iz] = hillside * (40.0 + edge * 44.0) + edge * 26.0

	# Closed road loop.
	var road := PackedVector3Array()
	var n_road := 576
	for i in n_road:
		var a := TAU * i / n_road
		var r := 400.0 + 64.0 * sin(3.0 * a) + 33.0 * cos(5.0 * a + 0.7)
		road.append(Vector3(cos(a) * r, 0, sin(a) * r * 0.89))
	# Road elevation = terrain sampled along the loop, heavily smoothed for drivable grades.
	var elev := PackedFloat32Array()
	elev.resize(n_road)
	for i in n_road:
		elev[i] = C.sample(heights, nx, nz, ox, oz, cell, road[i].x, road[i].z)
	for _iter in 30:
		var e2 := elev.duplicate()
		for i in n_road:
			e2[i] = (elev[(i - 2 + n_road) % n_road] + elev[(i - 1 + n_road) % n_road] + elev[i] * 2.0 + elev[(i + 1) % n_road] + elev[(i + 2) % n_road]) / 6.0
		elev = e2
	for i in n_road:
		road[i].y = elev[i]
	# District road across the valley: a T-junction past Lindenau, another between the Waldhof and
	# the lookout, so the map is a small network instead of a single loop.
	var chord := _valley_road(road, CHORD_FROM, CHORD_TO, heights, nx, nz, ox, oz, cell)
	var net := road.duplicate()
	net.append_array(chord)
	# Carve the roads into the terrain.
	var half_w := 4.5
	C.carve_path(heights, nx, nz, ox, oz, cell, road, half_w + 0.75, 13.0, 0.05)
	C.carve_path(heights, nx, nz, ox, oz, cell, chord, CHORD_HALF_W + 0.75, 11.0, 0.05, false)
	world.add_heightfield(ox, oz, cell, nx, nz, heights, 1.0)
	var grass := C.terrain_material("grass", 3.4)
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	for x in nx:
		for z in nz:
			var meadow := smoothstep(-0.24, 0.28, noise.get_noise_2d(x * 7.2, z * 7.2))
			colors[x * nz + z] = Color(0.65, 0.72, 0.49).lerp(Color(1.0, 1.0, 0.75), meadow)
	# Farmland around the farms: strips of ripe wheat and ploughed earth behind each farmhouse.
	for index: int in [12, 194, 410]:
		var tangent := road[index + 1] - road[index - 1]
		var fwd := Vector2(tangent.x, tangent.z).normalized()
		var sd := Vector2(-fwd.y, fwd.x)
		var origin := Vector2(road[index].x, road[index].z)
		for ix in nx:
			var x := ox + ix * cell
			if absf(x - origin.x) > 170.0: continue
			for iz in nz:
				var z := oz + iz * cell
				var rel := Vector2(x, z) - origin
				var along := rel.dot(fwd)
				var across := rel.dot(sd)
				if along < -120.0 or along > 6.0 or across < 30.0 or across > 150.0: continue
				var strip := int(floor((along + 120.0) / 42.0))
				var edge := minf(minf(along + 120.0, 6.0 - along), minf(across - 30.0, 150.0 - across))
				var blend := smoothstep(0.0, 6.0, edge) * (0.92 + 0.08 * sin(across * 1.9))   # furrows
				var crop: Color = [Color(1.45, 1.12, 0.52), Color(0.82, 0.62, 0.44), Color(1.25, 1.18, 0.62)][(strip + index) % 3]
				colors[ix * nz + iz] = colors[ix * nz + iz].lerp(crop, blend)
	# Woods: patches on the hillsides and closed forest on the ridges around the valley, kept off
	# the farms, the lookout and the start. A dark forest floor is painted under them.
	var woods_noise := FastNoiseLite.new()
	woods_noise.seed = 91
	woods_noise.frequency = 0.006
	var clearings := [[road[12], 175.0], [road[194], 175.0], [road[410], 175.0], [road[100], 75.0], [road[0], 60.0], [road[VILLAGE_AT], 140.0]]
	var woods := func(x: float, z: float) -> float:
		for c: Array in clearings:
			var cp: Vector3 = c[0]
			if Vector2(x - cp.x, z - cp.z).length() < c[1]:
				return 0.0
		var patch := smoothstep(0.08, 0.26, woods_noise.get_noise_2d(x, z))
		return maxf(patch, smoothstep(515.0, 575.0, Vector2(x, z).length()) * smoothstep(-0.45, -0.2, woods_noise.get_noise_2d(x, z)))
	for ix in nx:
		for iz in nz:
			var wm: float = woods.call(ox + ix * cell, oz + iz * cell)
			if wm > 0.0:
				colors[ix * nz + iz] = colors[ix * nz + iz].lerp(Color(0.36, 0.42, 0.25), wm * 0.85)
	C.terrain_tiles(parent, ox, oz, cell, nx, nz, heights, grass, colors)
	var ground_height := func(x: float, z: float) -> float:
		return C.sample(heights, nx, nz, ox, oz, cell, x, z)
	parent.add_child(C.road_mesh(road, half_w, C.road_material(2, half_w * 2.0, 12.0, "rural"), true, 0.05, 12.0, ground_height))
	parent.add_child(C.verge_mesh(road, half_w, 1.3, C.verge_material(1.3), true, 0.05, 12.0, ground_height))
	# The district road sits a few millimetres below the main road, so the main road's surface and
	# edge line run on across the junction mouth as they do on a priority road.
	parent.add_child(C.road_mesh(chord, CHORD_HALF_W, C.road_material(2, CHORD_HALF_W * 2.0, 12.0, "rural"), false, 0.044, 12.0, ground_height))
	parent.add_child(C.verge_mesh(chord, CHORD_HALF_W, 1.1, C.verge_material(1.1), false, 0.044, 12.0, ground_height))
	var markers: Array[Transform3D] = []
	for i in range(3, n_road, 8):
		var heading := (road[(i + 1) % n_road] - road[i - 1]).normalized()
		var side := Vector3(-heading.z, 0, heading.x).normalized()
		var basis := Basis(Vector3.UP, atan2(-heading.z, heading.x))
		for sign: float in [-1.0, 1.0]:
			var p := road[i] + side * sign * (half_w + 0.8)
			p.y = C.sample(heights, nx, nz, ox, oz, cell, p.x, p.z)
			markers.append(Transform3D(basis, p))
	C.roadside_markers(parent, markers)
	# Road furniture: guardrails on bends and embankments, bend chevrons and warning signs, a
	# power line along the road, and pasture fences, hay bales and boulders around the farms.
	var R := preload("res://scripts/maps/roadside.gd")
	# The loop has gentle bends (radius >= ~110 m): rails and chevrons mark its sharpest ones.
	R.guardrails(parent, world, road, half_w, ground_height, true, 0.125)
	R.bend_signs(parent, road, half_w, ground_height, true, 0.145)
	var farm_points := [road[12], road[194], road[410]]
	var keep_clear := func(p: Vector3) -> bool:
		for f: Vector3 in farm_points:
			if Vector2(p.x - f.x, p.z - f.z).length() < 34.0:
				return false
		if Vector2(p.x - road[VILLAGE_AT].x, p.z - road[VILLAGE_AT].z).length() < 110.0:
			return false
		for j in range(0, chord.size(), 2):
			if Vector2(p.x - chord[j].x, p.z - chord[j].z).length() < 9.0:
				return false
		return Vector2(p.x - road[0].x, p.z - road[0].z).length() > 30.0
	R.utility_line(parent, world, road, -(half_w + 6.0), ground_height, true, 44.0, keep_clear)
	var bale_rng := RandomNumberGenerator.new()
	bale_rng.seed = 41
	var bales: Array[Transform3D] = []
	for index: int in [12, 194, 410]:
		var tangent := road[index + 1] - road[index - 1]
		var forward := Vector3(tangent.x, 0, tangent.z).normalized()
		var side := Vector3(-forward.z, 0, forward.x)
		var c := road[index] + side * 23.0
		var pasture := PackedVector3Array([c + forward * 12.0 - side * 3.0, c + forward * 58.0 - side * 3.0,
			c + forward * 58.0 + side * 36.0, c + forward * 12.0 + side * 36.0, c + forward * 12.0 + side * 9.0])
		R.fence(parent, world, pasture, ground_height)
		for k in 5:
			var p := c + forward * bale_rng.randf_range(20.0, 50.0) + side * bale_rng.randf_range(6.0, 30.0)
			p.y = ground_height.call(p.x, p.z)
			bales.append(Transform3D(Basis(Vector3.UP, bale_rng.randf() * TAU), p))
	R.hay_bales(parent, world, bales)
	var rocks: Array[Transform3D] = []
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = 43
	while rocks.size() < 160:
		var p := Vector3(rock_rng.randf_range(-620, 620), 0, rock_rng.randf_range(-620, 620))
		var near := false
		for j in range(0, net.size(), 4):
			if Vector2(p.x - net[j].x, p.z - net[j].z).length() < 9.5:
				near = true
				break
		if near or not keep_clear.call(p):
			continue
		p.y = ground_height.call(p.x, p.z)
		var s := rock_rng.randf_range(0.35, 1.7) * (1.0 if rock_rng.randf() < 0.8 else 1.8)
		rocks.append(Transform3D(Basis(Vector3.UP, rock_rng.randf() * TAU).scaled(Vector3(s, s * rock_rng.randf_range(0.7, 1.1), s * rock_rng.randf_range(0.8, 1.3))), p))
	R.boulders(parent, world, rocks)

	# Trees (visual) away from the road.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var broadleaf: Array[Vector3] = []
	var conifers: Array[Vector3] = []
	for i in 1950:
		var p := Vector2(rng.randf_range(-636, 636), rng.randf_range(-636, 636))
		if noise.get_noise_2d(p.x * 2.0, p.y * 2.0) < -0.18:
			continue
		if p.distance_to(Vector2(road[12].x, road[12].z)) < 42.0 or p.distance_to(Vector2(road[VILLAGE_AT].x, road[VILLAGE_AT].z)) < 120.0:
			continue
		var near := false
		for j in range(0, net.size(), 6):
			if p.distance_to(Vector2(net[j].x, net[j].z)) < 14.0:
				near = true
				break
		if near:
			continue
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		# Conifers cluster on the higher, shadier ground; broadleaf trees in the valleys.
		(conifers if noise.get_noise_2d(p.x * 0.7 + 400.0, p.y * 0.7) > 0.05 else broadleaf).append(Vector3(p.x, y, p.y))
	# Forest corridors: on a few stretches the road runs through dense woods with undergrowth.
	var wood_rng := RandomNumberGenerator.new()
	wood_rng.seed = 47
	var under: Array[Vector3] = []
	for i in range(0, n_road, 2):
		if noise.get_noise_2d(road[i].x * 1.3 + 900.0, road[i].z * 1.3) < 0.12: continue
		if absi(i - VILLAGE_AT) < 26: continue
		if Vector2(road[i].x - road[0].x, road[i].z - road[0].z).length() < 60.0: continue
		var tangent := road[(i + 1) % n_road] - road[(i - 1 + n_road) % n_road]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		for sign: float in [-1.0, 1.0]:
			for k in 3:
				var p := road[i] + side * sign * wood_rng.randf_range(9.5, 38.0) + tangent.normalized() * wood_rng.randf_range(-3.0, 3.0)
				p.y = ground_height.call(p.x, p.z)
				var conifer := noise.get_noise_2d(p.x * 0.7 + 400.0, p.z * 0.7) > -0.1
				(conifers if conifer else broadleaf).append(p)
				wood_rng.randf()   # (kept for the layout; all trunks get colliders below)
			var b := road[i] + side * sign * wood_rng.randf_range(7.0, 12.0)
			b.y = ground_height.call(b.x, b.z)
			under.append(b)
	# Road proximity through a coarse cell lookup, then an exact check against every road point.
	var road_cells := {}
	for j in net.size():
		var rc := Vector2i(floori(net[j].x / 16.0), floori(net[j].z / 16.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				road_cells[rc + Vector2i(dx, dz)] = true
	var near_road := func(p: Vector2, d: float) -> bool:
		if not road_cells.has(Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))):
			return false
		for j in net.size():
			if p.distance_squared_to(Vector2(net[j].x, net[j].z)) < d * d:
				return true
		return false
	# Trees were only visual: their trunks now collide (except the few right at the verge, which
	# the old sparse road check let through).
	for list: Array[Vector3] in [broadleaf, conifers]:
		for p in list:
			if V.keep(p) and Vector2(p.x, p.z).length() < 600.0 and not near_road.call(Vector2(p.x, p.z), 9.0):
				world.add_box(p + Vector3.UP * 1.8, Vector3(0.22, 1.8, 0.22), Vector3.ZERO, 0.7)
	# Closed woods on a jittered 10 m grid.
	var grid_rng := RandomNumberGenerator.new()
	grid_rng.seed = 92
	for gx in range(-660, 661, 10):
		for gz in range(-660, 661, 10):
			var p := Vector2(gx + grid_rng.randf_range(-3.5, 3.5), gz + grid_rng.randf_range(-3.5, 3.5))
			if woods.call(p.x, p.y) < 0.5 or grid_rng.randf() < 0.3:
				continue
			if near_road.call(p, 13.0):
				continue
			var q := Vector3(p.x, ground_height.call(p.x, p.y), p.y)
			if not V.keep(q):
				continue
			(conifers if noise.get_noise_2d(p.x * 0.7 + 400.0, p.y * 0.7) > -0.15 else broadleaf).append(q)
			if Vector2(p.x, p.y).length() < 600.0:
				world.add_box(q + Vector3.UP * 1.8, Vector3(0.22, 1.8, 0.22), Vector3.ZERO, 0.7)
	# Nothing grows on the district road: the forest corridors and hedges follow the loop only.
	var off_chord := func(list: Array[Vector3], clear: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		for p in list:
			var free := true
			for j in range(0, chord.size(), 2):
				if Vector2(p.x - chord[j].x, p.z - chord[j].z).length() < clear:
					free = false
					break
			if free: out.append(p)
		return out
	broadleaf = off_chord.call(broadleaf, 9.5)   # as far as the tree colliders keep off roads
	conifers = off_chord.call(conifers, 9.5)
	under = off_chord.call(under, CHORD_HALF_W + 3.0)
	V.plant(parent, "broadleaf", broadleaf, 31, 0.75, 1.25, false)
	V.plant(parent, "conifer", conifers, 32, 0.6, 1.0, false)
	V.plant(parent, "bush", under, 35, 0.7, 1.6, false)
	var hedges: Array[Vector3] = []
	for i in range(0, n_road, 3):
		var tangent := road[(i + 1) % n_road] - road[(i - 1 + n_road) % n_road]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		for sign: float in [-1.0, 1.0]:
			var p := road[i] + side * sign * rng.randf_range(6.4, 11.5)
			p.y = ground_height.call(p.x, p.z)
			if p.distance_to(road[0]) < 20.0:
				continue   # keep the start and the service bay beside it clear
			hedges.append(p)
	V.plant(parent, "bush", off_chord.call(hedges, CHORD_HALF_W + 3.0), 33, 0.8, 2.0, false)
	V.roadside_grass(parent, road, true, half_w + 0.7, half_w + 16.0, 6.0, 34, ground_height,
		func(p: Vector3) -> bool:
			for j in range(0, mini(chord.size(), 12)):
				if Vector2(p.x - chord[j].x, p.z - chord[j].z).length() < CHORD_HALF_W + 9.0: return true
			for j in range(maxi(0, chord.size() - 12), chord.size()):
				if Vector2(p.x - chord[j].x, p.z - chord[j].z).length() < CHORD_HALF_W + 9.0: return true
			return false)
	V.roadside_grass(parent, chord, false, CHORD_HALF_W + 0.6, CHORD_HALF_W + 14.0, 6.0, 36, ground_height,
		func(p: Vector3) -> bool:
			for j in range(0, n_road, 3):
				if Vector2(p.x - road[j].x, p.z - road[j].z).length() < half_w + 1.5: return true
			return false)
	_junction_dressing(parent, world, road, chord, half_w, ground_height)
	_hill_landmarks(world, parent, road, ground_height)
	_hill_village(world, parent, road, half_w, ground_height)
	# Roadworks before Lindenau: a cone line along the right edge and two drums at its end.
	for i in range(VILLAGE_AT - 46, VILLAGE_AT - 30, 2):
		var d := road[(i + 1) % n_road] - road[i - 1]
		d.y = 0.0
		d = d.normalized()
		var side := Vector3(-d.z, 0, d.x)
		var c := road[i] + side * (half_w - 0.45)
		props.append({"kind": "cone", "position": Vector3(c.x, float(ground_height.call(c.x, c.z)), c.z), "yaw": atan2(-d.z, d.x)})
		if i == VILLAGE_AT - 32:
			for k in 2:
				var b := road[i] + side * (half_w + 1.3 + k * 0.7)
				props.append({"kind": "barrel", "position": Vector3(b.x, float(ground_height.call(b.x, b.z)), b.z)})
	var lookout := _hill_lookout(world, parent, road, ground_height)

	var speeds := PackedFloat32Array()
	speeds.resize(n_road)
	for i in n_road:
		var a := road[(i - 4 + n_road) % n_road]
		var b := road[i]
		var c := road[(i + 4) % n_road]
		var ang := (b - a).normalized().angle_to((c - b).normalized())
		speeds[i] = clampf(26.0 - ang * 60.0, 11.0, 26.0)
	var s0 := road[0]
	var s1 := road[1]
	# Traffic on the network: two cars on the loop, a third over the district road and back along
	# the loop in the loop traffic's direction (no head-on meetings at the junctions).
	var net_route := chord.duplicate()
	for i in range(CHORD_TO + 2, CHORD_FROM - 1):
		net_route.append(road[i])
	var net_speeds := PackedFloat32Array()
	net_speeds.resize(net_route.size())
	var m := net_route.size()
	for i in m:
		var a := net_route[(i - 4 + m) % m]
		var b := net_route[i]
		var c := net_route[(i + 4) % m]
		var ang := (b - a).normalized().angle_to((c - b).normalized())
		net_speeds[i] = clampf(24.0 - ang * 60.0, 9.0, 24.0)
	# Slow over the junction mouths (turning in and out).
	for i in m:
		if i < 6 or absi(i - chord.size()) < 6 or i > m - 6:
			net_speeds[i] = minf(net_speeds[i], 8.0)
	var mid := chord.size() / 2
	var ai_routes := [
		{"waypoints": road, "speeds": speeds, "spawn": car_xform(road[144], road[145] - road[144])},
		{"waypoints": road, "speeds": speeds, "spawn": car_xform(road[320], road[321] - road[320])},
		{"waypoints": net_route, "speeds": net_speeds, "spawn": car_xform(chord[mid], chord[mid + 1] - chord[mid])},
	]
	return {"props": props.duplicate(), "spawns": [car_xform(s0, s1 - s0), car_xform(road[n_road - 6], road[n_road - 5] - road[n_road - 6])],
		"waypoints": road, "speeds": speeds, "ai_routes": ai_routes,
		"map_paths": [C.closed_route(road), chord, lookout],
		"map_places": [{"name": "Waldhof", "position": road[12]}, {"name": "Lindenau", "position": road[VILLAGE_AT]}, {"name": "Aussichtspunkt", "position": lookout[4]},
			{"name": "Bergweide", "position": road[194]}, {"name": "Talblick", "position": road[410]}],
		"ai_spawns": [car_xform(road[144], road[145] - road[144]), car_xform(road[320], road[321] - road[320])],
		"environment": {"sky_top": Color(0.26, 0.48, 0.75), "horizon": Color(0.68, 0.76, 0.80),
			"fog": Color(0.70, 0.78, 0.81), "fog_density": 0.00060, "sun": Vector3(-34, -54, 0), "sun_energy": 1.25}}


const VILLAGE_AT := 300
const CHORD_FROM := 335
const CHORD_TO := 45
const CHORD_HALF_W := 3.25   # 6.5 m district road


## District road between two loop points: leaves each at right angles towards the valley, a gentle
## S through the middle, elevation from the terrain smoothed for drivable grades and pinned to the
## loop's at both junctions. Starts and ends just inside the loop's asphalt.
static func _valley_road(road: PackedVector3Array, from: int, to: int, heights: PackedFloat32Array,
		nx: int, nz: int, ox: float, oz: float, cell: float) -> PackedVector3Array:
	var n := road.size()
	var ends: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	for i: int in [from, to]:
		var t := road[(i + 1) % n] - road[(i - 1 + n) % n]
		var inward := Vector3(-t.z, 0, t.x).normalized()
		if inward.dot(-Vector3(road[i].x, 0, road[i].z)) < 0.0:
			inward = -inward
		ends.append(road[i] + inward * 3.6)
		dirs.append(inward)
	var p0 := ends[0]
	var p3 := ends[1]
	var reach := p0.distance_to(p3) * 0.38
	var p1 := p0 + dirs[0] * reach
	var p2 := p3 + dirs[1] * reach
	var length := p0.distance_to(p3) * 1.15
	var count := maxi(20, int(length / 4.0))
	var pts := PackedVector3Array()
	for k in count + 1:
		var t := float(k) / count
		var u := 1.0 - t
		var p := p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t
		# A gentle S across the valley floor.
		var d := (p2 - p1).normalized()
		p += Vector3(-d.z, 0, d.x) * sin(t * TAU) * 38.0 * sin(t * PI)
		pts.append(p)
	var elev := PackedFloat32Array()
	elev.resize(pts.size())
	for k in pts.size():
		elev[k] = C.sample(heights, nx, nz, ox, oz, cell, pts[k].x, pts[k].z)
	for _iter in 40:
		var e2 := elev.duplicate()
		for k in range(1, pts.size() - 1):
			e2[k] = (elev[maxi(k - 2, 0)] + elev[k - 1] + elev[k] * 2.0 + elev[k + 1] + elev[mini(k + 2, pts.size() - 1)]) / 6.0
		e2[0] = road[from].y
		e2[pts.size() - 1] = road[to].y
		elev = e2
	# Level with the main road over the junction mouths.
	for k in pts.size():
		var w0 := 1.0 - smoothstep(0.0, 28.0, pts[k].distance_to(p0))
		var w1 := 1.0 - smoothstep(0.0, 28.0, pts[k].distance_to(p3))
		elev[k] = lerpf(lerpf(elev[k], road[from].y, w0), road[to].y, w1)
	# At most 7 % anywhere: where the valley side rises faster the carve cuts the road in (or banks
	# it up). Sweeps from both junctions, the second keeping within reach of the first.
	const GRADE := 0.07
	for _pass in 3:
		for k in range(1, pts.size()):
			var run := Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length() * GRADE
			elev[k] = clampf(elev[k], elev[k - 1] - run, elev[k - 1] + run)
		elev[pts.size() - 1] = road[to].y
		for k in range(pts.size() - 2, -1, -1):
			var run := Vector2(pts[k].x - pts[k + 1].x, pts[k].z - pts[k + 1].z).length() * GRADE
			elev[k] = clampf(elev[k], elev[k + 1] - run, elev[k + 1] + run)
		elev[0] = road[from].y
	# Round off the kinks the limiter leaves (crests and dips).
	for _iter in 6:
		var e2 := elev.duplicate()
		for k in range(1, pts.size() - 1):
			e2[k] = (elev[k - 1] + elev[k] * 2.0 + elev[k + 1]) * 0.25
		elev = e2
	for k in pts.size():
		pts[k].y = elev[k]
	return pts


## Junction furniture: a "give way" sign (Vorfahrt achten) and a stop line on the district road at
## each mouth, delineator posts along it.
static func _junction_dressing(parent: Node3D, world: SBWorld, road: PackedVector3Array, chord: PackedVector3Array,
		half_w: float, height: Callable) -> void:
	var white := C.mat(Color(0.92, 0.92, 0.9), 0.6)
	var post := C.mat(Color(0.55, 0.57, 0.6), 0.4, 0.6)
	var n := chord.size()
	for end in 2:
		var k := 1 if end == 0 else n - 2   # ~3 m beyond the main road's edge
		var out := (chord[k - 1 if end == 0 else k + 1] - chord[k]).normalized()   # towards the main road
		out.y = 0.0
		out = out.normalized()
		var right := out.cross(Vector3.UP)
		var mouth := chord[k] + out * 1.5
		# Broken give-way line across the approach lane (right-hand traffic: right half).
		for m in 5:
			var c := mouth + right * (0.35 + m * 0.6)
			C.box(parent, null, Vector3(c.x, float(height.call(c.x, c.z)) + 0.05, c.z), Vector3(0.25, 0.004, 0.12), Vector3(0, atan2(out.x, out.z), 0), white, 0.6, false, false)
		# Inverted triangle sign on a post at the right verge.
		var sp := mouth + right * (CHORD_HALF_W + 1.4)
		var ground := float(height.call(sp.x, sp.z))
		C.box(parent, world, Vector3(sp.x, ground + 1.1, sp.z), Vector3(0.04, 1.1, 0.04), Vector3.ZERO, post, 0.6, true, false)
		var tri := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.9, 0.78, 0.03)
		tri.mesh = prism
		var face := StandardMaterial3D.new()
		face.albedo_texture = _give_way_texture()
		tri.material_override = face
		tri.position = Vector3(sp.x, ground + 2.05, sp.z)
		tri.rotation = Vector3(PI, atan2(out.x, out.z), 0)   # point down, face the approaching driver
		parent.add_child(tri)
	# Corner fillets: asphalt quarter circles (R 9 m) between the district road's edges and the main
	# road's edge, so the mouth is a real junction instead of two strips meeting at right angles.
	var asphalt := C.surface_material("asphalt", 2.0, Color.WHITE, 0.3)
	var nr := road.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const R := 9.0
	for i: int in [CHORD_FROM, CHORD_TO]:
		var t := road[(i + 1) % nr] - road[(i - 1 + nr) % nr]
		t.y = 0.0
		t = t.normalized()
		var inward := Vector3(-t.z, 0, t.x)
		if inward.dot(-Vector3(road[i].x, 0, road[i].z)) < 0.0:
			inward = -inward
		var edge := road[i] + inward * half_w
		for side: float in [-1.0, 1.0]:
			var along := t * side
			var corner := edge + along * CHORD_HALF_W
			var centre := edge + along * (CHORD_HALF_W + R) + inward * R
			var arc: Array[Vector3] = []
			for k in 9:
				var a := PI * 0.5 * k / 8.0
				arc.append(centre - inward * R * cos(a) - along * R * sin(a))
			for k in 8:
				# Both windings: the fan's orientation flips with the side.
				for q: Vector3 in [corner, arc[k], arc[k + 1], corner, arc[k + 1], arc[k]]:
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(q.x, float(height.call(q.x, q.z)) + 0.042, q.z))
	var fillets := MeshInstance3D.new()
	fillets.mesh = st.commit()
	fillets.material_override = asphalt
	fillets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fillets)
	# Delineator posts every ~50 m on both sides, as on the main road.
	var markers: Array[Transform3D] = []
	for k in range(6, n - 6, 12):
		var d := (chord[k + 1] - chord[k - 1])
		d.y = 0.0
		d = d.normalized()
		var side := Vector3(-d.z, 0, d.x)
		for sgn: float in [-1.0, 1.0]:
			var q := chord[k] + side * sgn * (CHORD_HALF_W + 0.8)
			q.y = float(height.call(q.x, q.z))
			markers.append(Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), q))
	C.roadside_markers(parent, markers)


static var _give_way: ImageTexture
static func _give_way_texture() -> ImageTexture:
	if _give_way: return _give_way
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.82, 0.08, 0.07))
	for y in 64:
		for x in 64:
			# Prism faces map the whole texture; a white inner area with a red rim.
			if x > 9 and x < 54 and y > 9 and y < 54:
				img.set_pixel(x, y, Color(0.96, 0.96, 0.95))
	img.generate_mipmaps()
	_give_way = ImageTexture.create_from_image(img)
	return _give_way

## Lindenau: a street village on both sides of the hill road with a church behind the houses and
## town signs at both ends. Houses sit at the lowest corner of their footprint (cut into the slope).
static func _hill_village(world: SBWorld, parent: Node3D, road: PackedVector3Array, half_w: float, height: Callable) -> void:
	var village := preload("res://scripts/maps/village.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3001
	var n := road.size()
	var frame := func(i: int) -> Array:
		var d := road[(i + 1) % n] - road[(i - 1 + n) % n]
		d.y = 0
		d = d.normalized()
		return [d, Vector3(-d.z, 0, d.x)]
	var floor_at := func(c: Vector3, yaw: float, l: float, w: float) -> Vector3:
		var lowest := INF
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var q := c + Basis(Vector3.UP, yaw) * Vector3(corner.x * l * 0.5, 0, corner.y * w * 0.5)
			lowest = minf(lowest, height.call(q.x, q.z))
		return Vector3(c.x, lowest, c.z)
	var steep := func(c: Vector3, yaw: float, l: float, w: float) -> bool:
		var lo := INF
		var hi := -INF
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var q := c + Basis(Vector3.UP, yaw) * Vector3(corner.x * l * 0.5, 0, corner.y * w * 0.5)
			var hq: float = height.call(q.x, q.z)
			lo = minf(lo, hq)
			hi = maxf(hi, hq)
		return hi - lo > 2.0
	var trees: Array[Vector3] = []
	for i in range(VILLAGE_AT - 16, VILLAGE_AT + 17, 4):
		var f: Array = frame.call(i)
		var d: Vector3 = f[0]
		var side: Vector3 = f[1]
		var yaw := atan2(-d.z, d.x)
		for sgn: float in [-1.0, 1.0]:
			if sgn < 0.0 and absi(i - VILLAGE_AT) <= 4:
				continue   # the church stands here behind the row
			var l := rng.randf_range(9.0, 12.5)
			var w := rng.randf_range(7.5, 9.0)
			var c := road[i] + side * sgn * (half_w + 9.5 + w * 0.5 + rng.randf_range(0.0, 3.0))
			var storeys := 1 + int(rng.randf() < 0.55)
			if not steep.call(c, yaw, l, w):
				village.house(world, floor_at.call(c, yaw, l, w), yaw, l, w, storeys, rng)
			var garden := road[i] + side * sgn * (half_w + 24.0 + rng.randf_range(0.0, 5.0)) + d * rng.randf_range(-4.0, 4.0)
			garden.y = height.call(garden.x, garden.z)
			trees.append(garden)
			if rng.randf() < 0.5:
				var back := road[i] + side * sgn * (half_w + 34.0) + d * 6.0
				var byaw := yaw + PI * 0.5
				var bl := rng.randf_range(8.0, 10.0)
				if not steep.call(back, byaw, bl, 7.5):
					village.house(world, floor_at.call(back, byaw, bl, 7.5), byaw, bl, 7.5, 1, rng)
	# Church behind the row, tower towards the road.
	var f0: Array = frame.call(VILLAGE_AT)
	var cd: Vector3 = f0[0]
	var cs: Vector3 = f0[1]
	var cyaw := atan2(-cs.z, cs.x)
	var nave := road[VILLAGE_AT] - cs * (half_w + 26.0)
	var tower := road[VILLAGE_AT] - cs * (half_w + 14.0)
	tower.y = height.call(tower.x, tower.z) - 0.5
	var plaster := C.noise_mat(Color(0.90, 0.87, 0.80), 0.05, 2.5, 0.92)
	var slate := C.noise_mat(Color(0.26, 0.26, 0.29), 0.1, 3.0, 0.8)
	_church_nave(parent, world, floor_at.call(nave, cyaw, 18.0, 9.5), cyaw, plaster, slate)
	C.box(parent, world, tower + Vector3.UP * 11.5, Vector3(2.6, 11.5, 2.6), Vector3(0, cyaw, 0), plaster, 0.8)
	var spire := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 3.6
	cone.height = 10.0
	cone.radial_segments = 4
	spire.mesh = cone
	spire.material_override = slate
	spire.position = tower + Vector3.UP * 28.0
	spire.rotation.y = cyaw + PI * 0.25
	parent.add_child(spire)
	_church_tower_details(parent, tower, cyaw, plaster)
	# Gravel path from the road edge up to the tower portal.
	var path := PackedVector3Array()
	var from_door := tower + cs * 3.7
	var to_road := road[VILLAGE_AT] - cs * (half_w + 0.6)
	for k in 6:
		var q := from_door.lerp(to_road, k / 5.0)
		path.append(Vector3(q.x, height.call(q.x, q.z), q.z))
	parent.add_child(C.road_mesh(path, 1.1, C.road_material(1, 2.2, 12.0, "dirt"), false, 0.05, 12.0, height))
	village.build(parent)
	V.plant(parent, "broadleaf", trees, 3002, 0.7, 1.0, false)
	for t in trees:
		if V.keep(t): world.add_box(t + Vector3.UP * 1.8, Vector3(0.22, 1.8, 0.22), Vector3.ZERO, 0.7)
	# Street lamps along the village road (pooled spot lights at night, see street_lighting.gd).
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.9, 0.88, 0.8)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.85, 0.62)
	lens.emission_energy_multiplier = 0.0
	var lamp_post := C.mat(Color(0.25, 0.27, 0.28), 0.5, 0.6)
	var lights := PackedVector3Array()
	for k in 5:
		var i := VILLAGE_AT - 16 + k * 8
		var fl: Array = frame.call(i)
		var d: Vector3 = fl[0]
		var side: Vector3 = fl[1]
		var sgn := 1.0 if k % 2 == 0 else -1.0
		var foot := road[i] + side * sgn * (half_w + 1.2)
		foot.y = height.call(foot.x, foot.z)
		C.box(parent, world, foot + Vector3.UP * 2.75, Vector3(0.07, 2.75, 0.07), Vector3.ZERO, lamp_post, 0.6)
		var head := foot + Vector3.UP * 5.45 - side * sgn * 0.9
		C.box(parent, null, foot + Vector3.UP * 5.5 - side * sgn * 0.45, Vector3(0.04, 0.04, 0.5), Vector3(0, atan2(-side.z, side.x) + PI * 0.5, 0), lamp_post, 0.6, false)
		C.box(parent, null, head, Vector3(0.22, 0.06, 0.12), Vector3(0, atan2(-d.z, d.x), 0), lens, 0.6, false)
		lights.append(head - Vector3.UP * 0.1)
	var lighting := preload("res://scripts/maps/street_lighting.gd").new()
	lighting.name = "VillageLighting"
	parent.add_child(lighting)
	lighting.setup(lights, lens)
	# Yellow town signs at both ends.
	var sign_mat := C.mat(Color(0.95, 0.78, 0.10), 0.5)
	var post_mat := C.mat(Color(0.62, 0.63, 0.65), 0.4, 0.7)
	for end: int in [VILLAGE_AT - 24, VILLAGE_AT + 24]:
		var fe: Array = frame.call(end)
		var d: Vector3 = fe[0]
		var side: Vector3 = fe[1]
		var toward := d if end < VILLAGE_AT else -d
		var spot := road[end] + side * (half_w + 1.4) * (1.0 if end < VILLAGE_AT else -1.0)
		spot.y = height.call(spot.x, spot.z)
		C.box(parent, world, spot + Vector3.UP * 1.1, Vector3(0.05, 1.1, 0.05), Vector3.ZERO, post_mat, 0.6)
		var yaw := atan2(-toward.z, toward.x)
		C.box(parent, null, spot + Vector3.UP * 2.0, Vector3(0.03, 0.4, 0.62), Vector3(0, yaw, 0), sign_mat, 0.6, false)
		C.label3d(parent, "Lindenau", spot + Vector3.UP * 2.0 - toward * 0.04, yaw + PI * 0.5, 0.3, Color(0.05, 0.05, 0.05))


static func _hill_landmarks(world: SBWorld, parent: Node3D, road: PackedVector3Array, height: Callable) -> void:
	var plaster := _mat(Color(0.70, 0.63, 0.47))
	var tile := _mat(Color(0.46, 0.17, 0.10))
	var wood := _mat(Color(0.26, 0.17, 0.10))
	var glass := _mat(Color(0.13, 0.25, 0.29), 0.35, 0.15)
	var gravel := C.surface_material("gravel", 2.1, Color(0.80, 0.78, 0.71))
	var farms := preload("res://scripts/maps/village.gd").new()
	var farm_rng := RandomNumberGenerator.new()
	for index: int in [12, 194, 410]:
		var point := road[index]
		var tangent := road[index + 1] - road[index - 1]
		var forward := Vector3(tangent.x, 0, tangent.z).normalized()
		var side := Vector3(-forward.z, 0, forward.x)
		var yaw := atan2(-forward.z, forward.x)
		var center := point + side * 23.0
		center.y = height.call(center.x, center.z)
		var rotation := Vector3(0, yaw, 0)
		# Farmhouse facing the yard and a timber barn beside it.
		farm_rng.seed = index * 7 + 1
		var lowest := func(c: Vector3, y: float, l: float, w: float) -> Vector3:
			var low := INF
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var q := c + Basis(Vector3.UP, y) * Vector3(corner.x * l * 0.5, 0, corner.y * w * 0.5)
				low = minf(low, height.call(q.x, q.z))
			return Vector3(c.x, low - 0.1, c.z)
		farms.house(world, lowest.call(center, yaw, 13.4, 7.4), yaw, 13.4, 7.4, 2, farm_rng)
		var barn := point + side * 30.0 + forward * 17.0
		farms.house(world, lowest.call(barn, yaw + PI * 0.5, 15.0, 10.0), yaw + PI * 0.5, 15.0, 10.0, 2, farm_rng, true)
		var approach := PackedVector3Array([point - forward * 17.0, point - forward * 11.0 + side * 6.0,
			point - forward * 4.0 + side * 11.0, center - side * 7.0, point + forward * 16.0 + side * 11.0,
			point + forward * 25.0 + side * 3.5])
		parent.add_child(C.road_mesh(approach, 2.4, gravel, false, 0.026, 12.0, height))
		var sign := point + forward * 7.0 - side * 6.3
		sign.y = height.call(sign.x, sign.z)
		_box(parent, world, sign + Vector3.UP * 0.89, Vector3(0.09, 0.89, 0.09), rotation, wood)
		_box(parent, world, sign + Vector3.UP * 1.70, Vector3(0.11, 0.36, 1.40), rotation, wood, 0.7, false)
		C.label3d(parent, "WALDHOF" if index == 12 else ("BERGWEIDE" if index == 194 else "TALBLICK"),
			sign + Vector3.UP * 1.70 - forward * 0.12, yaw - PI * 0.5, 0.40)
	farms.build(parent)


static func _hill_lookout(world: SBWorld, parent: Node3D, road: PackedVector3Array, height: Callable) -> PackedVector3Array:
	var point := road[94]
	var tangent := road[95] - road[93]
	var forward := Vector3(tangent.x, 0, tangent.z).normalized()
	var side := Vector3(-forward.z, 0, forward.x)
	var yaw := atan2(-forward.z, forward.x)
	var route := PackedVector3Array([point - forward * 16.0, point - forward * 9.0 + side * 6.0,
		point + side * 12.0, point + forward * 13.0 + side * 19.0, point + forward * 28.0 + side * 20.0,
		point + forward * 42.0 + side * 12.0, point + forward * 52.0 + side * 4.0])
	for i in route.size():
		route[i].y = height.call(route[i].x, route[i].z)
	parent.add_child(C.road_mesh(route, 3.8, C.surface_material("gravel", 2.1), false, 0.06, 12.0, height))
	var wood := _mat(Color(0.40, 0.29, 0.17))
	var rail := _mat(Color(0.58, 0.48, 0.31))
	for i in 5:
		var p := point + forward * (11.0 + i * 4.5) + side * 25.0
		p.y = height.call(p.x, p.z)
		_box(parent, world, p + Vector3.UP * 0.58, Vector3(0.1, 0.58, 0.1), Vector3(0, yaw, 0), wood)
		if i < 4:
			p += forward * 2.25
			p.y = height.call(p.x, p.z)
			_box(parent, world, p + Vector3.UP * 0.94, Vector3(2.28, 0.09, 0.09), Vector3(0, yaw, 0), rail)
	var sign := point + side * 11.0 + forward * 11.0
	sign.y = float(height.call(sign.x, sign.z))
	_box(parent, world, sign + Vector3.UP * 0.84, Vector3(0.09, 0.84, 0.09), Vector3(0, yaw, 0), wood)
	_box(parent, world, sign + Vector3.UP * 1.76, Vector3(0.1, 0.43, 2.0), Vector3(0, yaw, 0), wood, 0.75, false)
	C.label3d(parent, "AUSSICHTSPUNKT", sign + Vector3.UP * 1.76 - forward * 0.11, yaw - PI * 0.5, 0.47)
	return route


static func _service_campus(world: SBWorld, parent: Node3D) -> void:
	# A sheltered engineering office and landscaped pedestrian frontage behind the pits.
	# Solid volumes have matching native physics colliders; markings and plants are visual.
	var campus := Node3D.new()
	campus.name = "ServiceCampus"
	parent.add_child(campus)
	var pavement := C.surface_material("pavement", 1.6, Color(0.84, 0.84, 0.80))
	var wall := _mat(Color(0.54, 0.51, 0.46))
	var trim := _mat(Color(0.12, 0.17, 0.20), 0.4, 0.55)
	var soil := _mat(Color(0.17, 0.12, 0.08))
	var timber := _mat(Color(0.38, 0.23, 0.12))
	_box(campus, world, Vector3(158, 0.09, -89), Vector3(12, 0.09, 23), Vector3.ZERO, pavement)
	# Glass office (the city facade shader: curtain wall with rooms behind it on all four sides,
	# lit at night; before, only the front had windows and the rest was a bare block).
	var city := preload("res://scripts/maps/city.gd")
	city._facade_box(campus, world, Vector3(151, 2.7, -89), Vector3(6, 2.7, 12), city._facade_material(wall.albedo_color, Color(0.75, 0.76, 0.77), 2))
	_box(campus, world, Vector3(151, 5.48, -89), Vector3(6.4, 0.08, 12.4), Vector3.ZERO, trim)
	C.label3d(campus, "VEHICLE DEVELOPMENT  /  01", Vector3(157.2, 4.8, -89), PI * 0.5, 0.40)
	# Raised planting islands edge the walkway; openings remain wide enough for vehicles.
	for z: float in [-107, -71]:
		_box(campus, world, Vector3(164, 0.27, z), Vector3(3.5, 0.27, 1.6), Vector3.ZERO, pavement)
		_box(campus, world, Vector3(164, 0.55, z), Vector3(3.3, 0.025, 1.4), Vector3.ZERO, soil, 1, false)
		var shrubs: Array[Vector3] = [Vector3(161.5, 0.55, z), Vector3(164, 0.55, z), Vector3(166.5, 0.55, z)]
		V.plant(campus, "bush", shrubs, int(z), 0.55, 0.7)
	# Timber benches, bollards and short approach markings make the frontage legible.
	for z: float in [-99, -79]:
		_box(campus, world, Vector3(163, 0.60, z), Vector3(0.42, 0.10, 1.5), Vector3.ZERO, timber)
		_box(campus, world, Vector3(162.6, 0.94, z), Vector3(0.07, 0.4, 1.5), Vector3.ZERO, timber)
		for dz: float in [-1.1, 1.1]:
			_box(campus, world, Vector3(163, 0.3, z + dz), Vector3(0.32, 0.3, 0.07), Vector3.ZERO, trim)
	for z in range(-109, -68, 5):
		_box(campus, world, Vector3(169, 0.65, z), Vector3(0.12, 0.65, 0.12), Vector3.ZERO, trim)
		_box(campus, world, Vector3(169, 1.15, z), Vector3(0.125, 0.08, 0.125), Vector3.ZERO, _mat(Color(0.88, 0.72, 0.18)), 1, false)


static func proving_shelters() -> Array[Dictionary]:
	var shelters: Array[Dictionary] = []
	for i in 4:
		shelters.append({"center": Vector3(182, 2.61, -74 - i * 10), "half_extents": Vector3(7.4, 2.61, 4.9)})
	for x: float in [32, 47, 62]:
		shelters.append({"center": Vector3(x, 1.455, -65), "half_extents": Vector3(5.8, 1.455, 3.3)})
	return shelters


## Village church nave (18 x 9.5 m, long axis along the yaw's x): a tall single space on a stone
## plinth, steep slate roof, plastered gables, four tall round-arched windows a side with
## buttresses between them, and a semicircular apse with a half-cone roof at the far end (-x; the
## tower stands against the +x end, towards the road). It used to be a two-storey house with
## shutters.
static func _church_nave(parent: Node3D, world: SBWorld, ground: Vector3, yaw: float, plaster: Material, slate: Material) -> void:
	const L := 18.0
	const W := 9.5
	const H := 8.0
	var root := Node3D.new()
	root.position = ground
	root.rotation.y = yaw
	parent.add_child(root)
	var stone := C.noise_mat(Color(0.55, 0.52, 0.47), 0.12, 3.0, 0.9)
	var glass := C.mat(Color(0.16, 0.19, 0.24), 0.15, 0.4)
	var sandstone := C.noise_mat(Color(0.74, 0.66, 0.55), 0.08, 3.0, 0.85)
	var add := func(mesh: Mesh, at: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = at
		mi.rotation = rot
		root.add_child(mi)
	var box := func(size: Vector3) -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		return b
	if world:
		world.add_box(ground + Basis(Vector3.UP, yaw) * Vector3(0, H * 0.5, 0), Vector3(L, H, W) * 0.5, Vector3(0, yaw, 0), 0.8)
	add.call(box.call(Vector3(L + 0.3, 0.9, W + 0.3)), Vector3(0, 0.45, 0), stone)      # plinth
	add.call(box.call(Vector3(L, H, W)), Vector3(0, H * 0.5, 0), plaster)               # walls
	add.call(box.call(Vector3(L + 0.25, 0.3, W + 0.25)), Vector3(0, H - 0.15, 0), plaster)   # eaves cornice
	# Steep roof (50 deg) and the two gables.
	var pitch := deg_to_rad(50.0)
	var rise := W * 0.5 * tan(pitch)
	var slope := W * 0.5 / cos(pitch) + 0.5
	for sgn: float in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, sgn * pitch)
		var centre := Vector3(0, H + rise * 0.5, sgn * W * 0.25) + tilt * Vector3(0, 0.14, sgn * 0.25)
		var slab := MeshInstance3D.new()
		slab.mesh = box.call(Vector3(L + 0.6, 0.18, slope))
		slab.material_override = slate
		slab.transform = Transform3D(tilt, centre)
		root.add_child(slab)
	var prism := PrismMesh.new()
	prism.size = Vector3(W, rise, 0.3)
	for end: float in [-1.0, 1.0]:
		add.call(prism, Vector3(end * (L * 0.5 - 0.15), H + rise * 0.5, 0), plaster, Vector3(0, PI * 0.5, 0))
	# Round-arched windows (sandstone surround, dark leaded glass) and buttresses between them.
	var arch := CylinderMesh.new()
	arch.top_radius = 0.6
	arch.bottom_radius = 0.6
	arch.height = 0.12
	arch.radial_segments = 16
	var arch_frame := CylinderMesh.new()
	arch_frame.top_radius = 0.78
	arch_frame.bottom_radius = 0.78
	arch_frame.height = 0.1
	arch_frame.radial_segments = 16
	for side: float in [-1.0, 1.0]:
		var z := side * (W * 0.5 + 0.02)
		for k in 4:
			var x := -L * 0.5 + 3.0 + k * 4.0
			add.call(box.call(Vector3(1.56, 3.2, 0.1)), Vector3(x, 3.9, z), sandstone)
			add.call(arch_frame, Vector3(x, 5.5, z), sandstone, Vector3(PI * 0.5, 0, 0))
			add.call(box.call(Vector3(1.2, 3.0, 0.14)), Vector3(x, 3.9, z + side * 0.02), glass)
			add.call(arch, Vector3(x, 5.5, z + side * 0.02), glass, Vector3(PI * 0.5, 0, 0))
			add.call(box.call(Vector3(1.4, 0.16, 0.3)), Vector3(x, 2.3, z + side * 0.1), sandstone)   # sill
		for k in 5:
			var x := -L * 0.5 + 1.0 + k * 4.0
			if k == 0: x = -L * 0.5 + 0.6
			add.call(box.call(Vector3(0.7, 5.2, 0.7)), Vector3(x, 2.6, side * (W * 0.5 + 0.35)), stone)     # buttress
			add.call(box.call(Vector3(0.7, 0.9, 0.5)), Vector3(x, 5.5, side * (W * 0.5 + 0.25)), stone, Vector3(side * -0.5, 0, 0))   # sloped cap
	# Apse: a half cylinder at the east end with a half-cone roof.
	var apse := CylinderMesh.new()
	apse.top_radius = 3.6
	apse.bottom_radius = 3.6
	apse.height = 6.4
	apse.radial_segments = 20
	add.call(apse, Vector3(-L * 0.5, 3.2, 0), plaster)
	var apse_roof := CylinderMesh.new()
	apse_roof.top_radius = 0.05
	apse_roof.bottom_radius = 3.9
	apse_roof.height = 3.0
	apse_roof.radial_segments = 20
	add.call(apse_roof, Vector3(-L * 0.5, 6.4 + 1.5, 0), slate)
	if world:
		world.add_box(ground + Basis(Vector3.UP, yaw) * Vector3(-L * 0.5 - 1.8, 3.2, 0), Vector3(1.8, 3.2, 3.0), Vector3(0, yaw, 0), 0.8)
	# Two narrow round-arched windows in the apse.
	for a: float in [-0.6, 0.6]:
		var at := Vector3(-L * 0.5 - cos(a) * 3.62, 3.8, sin(a) * 3.62)
		add.call(box.call(Vector3(0.1, 2.4, 0.8)), at, glass, Vector3(0, a, 0))


## Village church tower: stone plinth, slit windows, clock faces, louvred belfry openings, cornice
## and a ball and cross with a weathercock on the spire (the tower was a plain white block).
static func _church_tower_details(parent: Node3D, base: Vector3, yaw: float, plaster: Material) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = yaw
	parent.add_child(root)
	var stone := C.noise_mat(Color(0.55, 0.52, 0.47), 0.12, 3.0, 0.9)
	var dark := C.mat(Color(0.07, 0.07, 0.08), 0.9)
	var louvre := C.mat(Color(0.32, 0.26, 0.2), 0.8)
	var dial := C.mat(Color(0.95, 0.94, 0.9), 0.5)
	var gold := C.mat(Color(0.83, 0.66, 0.25), 0.35, 0.9)
	var add := func(mesh: Mesh, at: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = at
		mi.rotation = rot
		root.add_child(mi)
	var box := func(size: Vector3) -> BoxMesh:
		var b := BoxMesh.new()
		b.size = size
		return b
	add.call(box.call(Vector3(5.5, 1.1, 5.5)), Vector3(0, 0.85, 0), stone)            # plinth
	add.call(box.call(Vector3(5.6, 0.35, 5.6)), Vector3(0, 23.05, 0), plaster)         # cornice
	add.call(box.call(Vector3(5.45, 0.22, 5.45)), Vector3(0, 13.6, 0), plaster)        # string course
	for face in 4:
		var ang := face * PI * 0.5
		var out := Vector3(sin(ang), 0, cos(ang))
		var along := Vector3(cos(ang), 0, -sin(ang))
		var rot := Vector3(0, ang, 0)
		var at := func(h: float, side: float, depth: float) -> Vector3:
			return out * (2.6 + depth) + along * side + Vector3.UP * h
		# Slit windows on two storeys.
		for h: float in [6.0, 10.5]:
			add.call(box.call(Vector3(0.32, 1.3, 0.08)), at.call(h, 0.0, 0.0), dark, rot)
		# Clock face with hands at ten past ten.
		var disc := CylinderMesh.new()
		disc.top_radius = 0.95
		disc.bottom_radius = 0.95
		disc.height = 0.06
		disc.radial_segments = 24
		var rim := CylinderMesh.new()
		rim.top_radius = 1.05
		rim.bottom_radius = 1.05
		rim.height = 0.04
		rim.radial_segments = 24
		add.call(rim, at.call(16.0, 0.0, 0.02), gold, Vector3(PI * 0.5, ang, 0))
		add.call(disc, at.call(16.0, 0.0, 0.05), dial, Vector3(PI * 0.5, ang, 0))
		for hand: Vector2 in [Vector2(0.62, deg_to_rad(60.0)), Vector2(0.82, deg_to_rad(-60.0))]:
			var hm: BoxMesh = box.call(Vector3(0.07, hand.x, 0.02))
			var dir := Vector3(sin(hand.y), cos(hand.y), 0)
			var hub: Vector3 = at.call(16.0, 0.0, 0.09)
			var mi := MeshInstance3D.new()
			mi.mesh = hm
			mi.material_override = dark
			mi.position = hub + (along * dir.x + Vector3.UP * dir.y) * hand.x * 0.5
			mi.basis = Basis(Vector3.UP, ang) * Basis(Vector3(0, 0, 1), -hand.y)
			root.add_child(mi)
		# Two louvred belfry openings under the cornice.
		for side: float in [-1.0, 1.0]:
			add.call(box.call(Vector3(0.85, 2.3, 0.1)), at.call(20.4, side * 0.85, -0.02), dark, rot)
			for k in 5:
				add.call(box.call(Vector3(0.82, 0.07, 0.16)), at.call(19.5 + k * 0.42, side * 0.85, 0.0), louvre, rot + Vector3(0.5, 0, 0))
	# Ball, cross and weathercock on the spire tip.
	var ball := SphereMesh.new()
	ball.radius = 0.32
	ball.height = 0.64
	add.call(ball, Vector3(0, 33.25, 0), gold)
	add.call(box.call(Vector3(0.12, 1.7, 0.12)), Vector3(0, 34.3, 0), gold)
	add.call(box.call(Vector3(0.9, 0.12, 0.12)), Vector3(0, 34.6, 0), gold)
	add.call(box.call(Vector3(0.55, 0.32, 0.05)), Vector3(0.1, 35.35, 0), gold)
	# West portal on the face away from the nave (local +x): stone surround with a round arch and
	# keystone, a plank door with iron bands and ring, and two steps (buried below for slopes).
	var wood := C.noise_mat(Color(0.30, 0.19, 0.11), 0.15, 6.0, 0.85)
	var iron := C.mat(Color(0.12, 0.12, 0.13), 0.6, 0.7)
	var face_x := 2.75   # plinth face
	var sill := 0.45
	var disc_x := func(radius: float) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = 0.1
		c.radial_segments = 20
		return c
	var axis_x := Vector3(0, 0, PI * 0.5)   # cylinder axis along x (out of the face)
	add.call(box.call(Vector3(0.1, 2.5, 2.3)), Vector3(face_x + 0.05, sill + 1.25, 0), stone)          # surround jambs
	add.call(disc_x.call(1.15), Vector3(face_x + 0.05, sill + 2.5, 0), stone, axis_x)                  # surround arch
	add.call(box.call(Vector3(0.12, 0.42, 0.34)), Vector3(face_x + 0.08, sill + 3.5, 0), stone)        # keystone
	add.call(box.call(Vector3(0.1, 2.4, 1.6)), Vector3(face_x + 0.1, sill + 1.2, 0), wood)            # door leaves
	add.call(disc_x.call(0.8), Vector3(face_x + 0.1, sill + 2.4, 0), wood, axis_x)                    # arched head
	add.call(box.call(Vector3(0.02, 3.15, 0.04)), Vector3(face_x + 0.16, sill + 1.58, 0), dark)        # meeting stile
	for h: float in [0.5, 1.5, 2.3]:
		add.call(box.call(Vector3(0.03, 0.07, 1.5)), Vector3(face_x + 0.16, sill + h, 0), iron)        # strap hinges
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.1
	for side: float in [-0.22, 0.22]:
		add.call(ring, Vector3(face_x + 0.18, sill + 1.05, side), iron, axis_x)
	add.call(box.call(Vector3(0.45, sill + 0.6, 2.6)), Vector3(face_x + 0.22, (sill - 0.6) * 0.5, 0), stone)              # upper step
	add.call(box.call(Vector3(0.45, sill * 0.5 + 0.6, 3.0)), Vector3(face_x + 0.62, (sill * 0.5 - 0.6) * 0.5, 0), stone)   # lower step
