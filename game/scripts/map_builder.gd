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


static func _cone(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.17
	cm.height = 0.7
	cm.radial_segments = 12
	cm.rings = 0
	mi.mesh = cm
	mi.material_override = _mat(Color(1.0, 0.38, 0.05), 0.6)
	mi.position = pos + Vector3(0, 0.35, 0)
	parent.add_child(mi)


# =========================================================================== proving grounds
static func build_proving_grounds(world: SBWorld, parent: Node3D) -> Dictionary:
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
	var nx := 41
	var nz := 41
	var hcell := 2.0
	var ox := -200.0
	var oz := -150.0
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var dx := (ix - 20.0) / 20.0
			var dz := (iz - 20.0) / 20.0
			var r2 := dx * dx + dz * dz
			heights[ix * nz + iz] = 7.0 * pow(1.0 - r2, 2.0) if r2 < 1.0 else 0.0
	world.add_heightfield(ox, oz, hcell, nx, nz, heights, 1.0)
	parent.add_child(C.terrain_mesh(ox, oz, hcell, nx, nz, heights, grass))

	var spawns: Array[Transform3D] = [
		car_xform(Vector3(-145, 0, -5), Vector3(1, 0, 0)),
		car_xform(Vector3(-15, 0, -32), Vector3(1, 0, 0)),
		car_xform(Vector3(-30, 0, -32), Vector3(1, 0, 0)),
	]
	return {"spawns": spawns, "waypoints": waypoints, "speeds": speeds,
		"rain_shelters": proving_shelters(), "service_approach": facilities["service_approach"], "pit_approach": facilities["pit_approach"],
		"surface_regions": [{"rect": Rect2(-200, -150, 80, 80), "surface": "grass"}] + landscape_regions,
		"map_paths": [C.closed_route(waypoints), C.closed_route(training), handling, facilities["service_approach"], facilities["pit_approach"]],
		"map_places": [{"name": "Sprung- und Crashbahn", "position": Vector3(124, 0, -40)},
			{"name": "Fahrdynamik-Oval", "position": Vector3(20, 0, -130)},
			{"name": "Handling-Parcours", "position": handling[3]},
			{"name": "Werkstatt und Boxen", "position": workshop}],
		"ai_spawns": [car_xform(waypoints[0], waypoints[1] - waypoints[0]), car_xform(waypoints[64], waypoints[65] - waypoints[64])]}


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
	# Carve the road into the terrain.
	var half_w := 4.5
	C.carve_path(heights, nx, nz, ox, oz, cell, road, half_w + 0.75, 13.0, 0.05)
	world.add_heightfield(ox, oz, cell, nx, nz, heights, 1.0)
	var grass := C.terrain_material("grass", 3.4)
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	for x in nx:
		for z in nz:
			var meadow := smoothstep(-0.24, 0.28, noise.get_noise_2d(x * 7.2, z * 7.2))
			colors[x * nz + z] = Color(0.65, 0.72, 0.49).lerp(Color(1.0, 1.0, 0.75), meadow)
	C.terrain_tiles(parent, ox, oz, cell, nx, nz, heights, grass, colors)
	var ground_height := func(x: float, z: float) -> float:
		return C.sample(heights, nx, nz, ox, oz, cell, x, z)
	parent.add_child(C.road_mesh(road, half_w, C.road_material(2, half_w * 2.0, 12.0, "rural"), true, 0.05, 12.0, ground_height))
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

	# Trees (visual) away from the road.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var broadleaf: Array[Vector3] = []
	var conifers: Array[Vector3] = []
	for i in 1950:
		var p := Vector2(rng.randf_range(-636, 636), rng.randf_range(-636, 636))
		if noise.get_noise_2d(p.x * 2.0, p.y * 2.0) < -0.18:
			continue
		if p.distance_to(Vector2(road[12].x, road[12].z)) < 42.0:
			continue
		var near := false
		for j in range(0, n_road, 6):
			if p.distance_to(Vector2(road[j].x, road[j].z)) < 14.0:
				near = true
				break
		if near:
			continue
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		# Conifers cluster on the higher, shadier ground; broadleaf trees in the valleys.
		(conifers if noise.get_noise_2d(p.x * 0.7 + 400.0, p.y * 0.7) > 0.05 else broadleaf).append(Vector3(p.x, y, p.y))
	V.plant(parent, "broadleaf", broadleaf, 31, 0.75, 1.25, false)
	V.plant(parent, "conifer", conifers, 32, 0.6, 1.0, false)
	var hedges: Array[Vector3] = []
	for i in range(0, n_road, 3):
		var tangent := road[(i + 1) % n_road] - road[(i - 1 + n_road) % n_road]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		for sign: float in [-1.0, 1.0]:
			var p := road[i] + side * sign * rng.randf_range(6.4, 11.5)
			p.y = ground_height.call(p.x, p.z)
			hedges.append(p)
	V.plant(parent, "bush", hedges, 33, 0.8, 2.0, false)
	_hill_landmarks(world, parent, road, ground_height)
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
	return {"spawns": [car_xform(s0, s1 - s0), car_xform(road[n_road - 6], road[n_road - 5] - road[n_road - 6])],
		"waypoints": road, "speeds": speeds,
		"map_paths": [C.closed_route(road), lookout],
		"map_places": [{"name": "Waldhof", "position": road[12]}, {"name": "Aussichtspunkt", "position": lookout[4]},
			{"name": "Bergweide", "position": road[194]}, {"name": "Talblick", "position": road[410]}],
		"ai_spawns": [car_xform(road[144], road[145] - road[144]), car_xform(road[320], road[321] - road[320])],
		"environment": {"sky_top": Color(0.26, 0.48, 0.75), "horizon": Color(0.68, 0.76, 0.80),
			"fog": Color(0.70, 0.78, 0.81), "fog_density": 0.00060, "sun": Vector3(-34, -54, 0), "sun_energy": 1.25}}


static func _hill_landmarks(world: SBWorld, parent: Node3D, road: PackedVector3Array, height: Callable) -> void:
	var plaster := _mat(Color(0.70, 0.63, 0.47))
	var tile := _mat(Color(0.46, 0.17, 0.10))
	var wood := _mat(Color(0.26, 0.17, 0.10))
	var glass := _mat(Color(0.13, 0.25, 0.29), 0.35, 0.15)
	var gravel := C.surface_material("gravel", 2.1, Color(0.80, 0.78, 0.71))
	for index: int in [12, 194, 410]:
		var point := road[index]
		var tangent := road[index + 1] - road[index - 1]
		var forward := Vector3(tangent.x, 0, tangent.z).normalized()
		var side := Vector3(-forward.z, 0, forward.x)
		var yaw := atan2(-forward.z, forward.x)
		var center := point + side * 23.0
		center.y = height.call(center.x, center.z)
		var rotation := Vector3(0, yaw, 0)
		_box(parent, world, center + Vector3.UP * 1.15, Vector3(6.7, 2.0, 3.5), rotation, plaster)
		for slope: float in [-1.0, 1.0]:
			_box(parent, world, center + side * (1.95 * slope) + Vector3.UP * 3.62, Vector3(7.0, 0.14, 2.20),
				Vector3(0.37 * slope, yaw, 0), tile, 0.85, false)
		for window_x: float in [-4.5, 0.0, 4.5]:
			var window := center + forward * window_x - side * 3.52 + Vector3.UP * 1.7
			_box(parent, world, window, Vector3(0.57, 0.66, 0.04), rotation, glass, 0.8, false)
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
	var glass := _mat(Color(0.10, 0.20, 0.25), 0.18, 0.65)
	var soil := _mat(Color(0.17, 0.12, 0.08))
	var timber := _mat(Color(0.38, 0.23, 0.12))
	_box(campus, world, Vector3(158, 0.09, -89), Vector3(12, 0.09, 23), Vector3.ZERO, pavement)
	_box(campus, world, Vector3(151, 2.7, -89), Vector3(6, 2.7, 12), Vector3.ZERO, wall)
	_box(campus, world, Vector3(151, 5.48, -89), Vector3(6.4, 0.08, 12.4), Vector3.ZERO, trim)
	# Six recessed window bays separated by frame mullions.
	for i in 6:
		var z := -99.0 + i * 4.0
		_box(campus, world, Vector3(157.03, 2.9, z), Vector3(0.04, 1.3, 1.55), Vector3.ZERO, glass, 1, false)
		for dz: float in [-1.60, 0, 1.60]:
			_box(campus, world, Vector3(157.10, 2.9, z + dz), Vector3(0.07, 1.36, 0.045), Vector3.ZERO, trim, 1, false)
		_box(campus, world, Vector3(157.14, 1.56, z), Vector3(0.18, 0.055, 1.7), Vector3.ZERO, pavement, 1, false)
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
