extends RefCounted
## An 8.5 km motorway loop with service access, overpasses and opposing traffic.

const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")
const STRAIGHT := 2600.0
const RADIUS := 520.0
const CARRIAGE_OFFSET := 7.6   # centre of a carriageway from the median
const CARRIAGE_HALF := 6.9
const SERVICE_START := -990.0
const SERVICE_END := -650.0


static func _loop(step := 10.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var perim := 2.0 * STRAIGHT + 2.0 * PI * RADIUS
	var n := int(perim / step)
	for i in n:
		var s := perim * i / n
		var p := Vector3.ZERO
		if s < STRAIGHT:
			p = Vector3(-STRAIGHT / 2 + s, 0, -RADIUS)
		elif s < STRAIGHT + PI * RADIUS:
			var a := (s - STRAIGHT) / RADIUS
			p = Vector3(STRAIGHT / 2 + sin(a) * RADIUS, 0, -cos(a) * RADIUS)
		elif s < 2 * STRAIGHT + PI * RADIUS:
			p = Vector3(STRAIGHT / 2 - (s - STRAIGHT - PI * RADIUS), 0, RADIUS)
		else:
			var a := (s - 2 * STRAIGHT - PI * RADIUS) / RADIUS
			p = Vector3(-STRAIGHT / 2 - sin(a) * RADIUS, 0, cos(a) * RADIUS)
		pts.append(p)
	return pts


static func _offset(pts: PackedVector3Array, off: float) -> PackedVector3Array:
	var n := pts.size()
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		var d := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
		out[i] = pts[i] + Vector3(-d.z, 0, d.x) * off
	return out


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	world.add_ground_plane(1.0)
	var grass := C.surface_material("grass", 3.5, Color(0.73, 0.92, 0.66))
	C.quad(parent, Vector3(0, -0.02, 0), Vector2(6200, 5000), grass)
	var concrete := C.noise_mat(Color(0.66, 0.66, 0.63), 0.1, 0.5, 0.8, 0.2)
	var metal := C.mat(Color(0.72, 0.74, 0.76), 0.35, 0.85)
	var road := C.road_material(3, CARRIAGE_HALF * 2.0, 14.0, "autobahn")
	var center := _loop()
	var a_center := _offset(center, CARRIAGE_OFFSET)
	var b_center := _offset(center, -CARRIAGE_OFFSET)
	parent.add_child(C.road_mesh(a_center, CARRIAGE_HALF, road, true, 0.03, 14.0))
	parent.add_child(C.road_mesh(b_center, CARRIAGE_HALF, road, true, 0.03, 14.0))
	# Verges beyond the guard rails; the service area keeps its paving.
	V.roadside_grass(parent, center, true, CARRIAGE_OFFSET + CARRIAGE_HALF + 1.6, CARRIAGE_OFFSET + CARRIAGE_HALF + 22.0, 1.6, 93,
		Callable(), func(p: Vector3) -> bool: return p.x > SERVICE_START - 40.0 and p.x < SERVICE_END + 40.0 and p.z < -RADIUS + 120.0)
	# Central reservation: concrete step barrier; guard rails on both outer edges.
	C.barrier(parent, world, center, 0.0, 0.85, 0.55, concrete)
	var open_start := 0
	var open_end := 0
	for i in center.size():
		if center[i].z == -RADIUS and center[i].x <= SERVICE_START:
			open_start = i
		if center[i].z == -RADIUS and center[i].x < SERVICE_END:
			open_end = i + 1
	var outer_rail := PackedVector3Array()
	for i in range(open_end, center.size() + open_start + 1):
		outer_rail.append(center[i % center.size()])
	# Outer guard rails: the colliders stay boxes, the visual is a galvanised W-beam on posts.
	C.barrier(parent, world, outer_rail, CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9, 0.75, 0.22, null, false)
	C.barrier(parent, world, center, -(CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9), 0.75, 0.22, null)
	var R := preload("res://scripts/maps/roadside.gd")
	R.rail(parent, _offset(outer_rail, CARRIAGE_OFFSET + CARRIAGE_HALF + 1.0), -1.0)
	var inner_rail := _offset(center, -(CARRIAGE_OFFSET + CARRIAGE_HALF + 1.0))
	inner_rail.append(inner_rail[0])
	R.rail(parent, inner_rail, 1.0)
	var service_road := _service_area(parent, world, concrete, metal)
	# Rail posts (visual).
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.8, 0.12)
	var posts: Array[Transform3D] = []
	for side: float in [1.0, -1.0]:
		var rail := _offset(center, side * (CARRIAGE_OFFSET + CARRIAGE_HALF + 1.05))
		for i in range(0, rail.size(), 2):
			if side < 0.0 or i <= open_start or i >= open_end:
				posts.append(Transform3D(Basis(), rail[i] + Vector3(0, 0.4, 0)))
	C.scatter_multimesh(parent, post, C.mat(Color(0.5, 0.5, 0.52), 0.5, 0.7), posts, false)
	var markers: Array[Transform3D] = []
	for i in range(0, center.size(), 4):
		var heading := (center[(i + 1) % center.size()] - center[i]).normalized()
		var side := Vector3(-heading.z, 0, heading.x)
		var basis := Basis(Vector3.UP, atan2(-heading.z, heading.x))
		for sign: float in [-1.0, 1.0]:
			if sign > 0.0 and i > open_start and i < open_end:
				continue
			markers.append(Transform3D(basis, center[i] + side * sign * (CARRIAGE_OFFSET + CARRIAGE_HALF + 0.35)))
	C.roadside_markers(parent, markers)

	# Overpasses across the two straights.
	var deck_mat := C.noise_mat(Color(0.6, 0.6, 0.58), 0.12, 0.3, 0.85, 0.1)
	for x: float in [-420.0, 380.0, 1030.0]:
		for z: float in [-RADIUS, RADIUS]:
			var span := 2.0 * (CARRIAGE_OFFSET + CARRIAGE_HALF + 4.0)
			C.box(parent, world, Vector3(x, 6.6, z), Vector3(7.0, 0.6, span * 0.5 + 6.0), Vector3.ZERO, deck_mat, 0.8, false)
			C.box(parent, world, Vector3(x, 7.6, z - span * 0.5 - 5.5), Vector3(7.0, 0.5, 0.25), Vector3.ZERO, concrete, 0.8, false)
			C.box(parent, world, Vector3(x, 7.6, z + span * 0.5 + 5.5), Vector3(7.0, 0.5, 0.25), Vector3.ZERO, concrete, 0.8, false)
			for pz: float in [z - span * 0.5 - 2.0, z, z + span * 0.5 + 2.0]:
				C.box(parent, world, Vector3(x, 3.0, pz), Vector3(0.7, 3.0, 0.7), Vector3.ZERO, concrete, 0.7)
			# Embankments at both ends.
			for ez: float in [z - span * 0.5 - 30.0, z + span * 0.5 + 30.0]:
				C.box(parent, world, Vector3(x, 2.5, ez), Vector3(9.0, 4.2, 24.0), Vector3(deg_to_rad(10.0) * signf(ez - z), 0, 0), grass, 0.9, false)

	# Sign gantries + distance boards on carriageway A.
	var sign_mat := C.mat(Color(0.1, 0.32, 0.72), 0.5)
	var texts := ["Hügelland  25 km    Wüste  80 km", "Stadt  12 km", "A 7   •   Nordring"]
	var k := 0
	for i in range(30, a_center.size(), 130):
		var p := a_center[i]
		var d := (a_center[(i + 1) % a_center.size()] - p).normalized()
		var side := Vector3(-d.z, 0, d.x)
		var yaw := atan2(-d.z, d.x)
		for o: float in [-CARRIAGE_HALF - 1.6, CARRIAGE_HALF + 1.6]:
			C.box(parent, world, p + side * o + Vector3(0, 3.3, 0), Vector3(0.18, 3.3, 0.18), Vector3(0, yaw, 0), metal, 0.6)
		C.box(parent, world, p + Vector3(0, 6.6, 0), Vector3(0.2, 0.2, CARRIAGE_HALF + 1.7), Vector3(0, yaw, 0), metal, 0.6, false)
		C.box(parent, world, p + Vector3(0, 7.6, 0) - d * 0.12, Vector3(0.05, 0.9, 4.6), Vector3(0, yaw, 0), sign_mat, 0.6, false)
		C.label3d(parent, texts[k % texts.size()], p + Vector3(0, 7.6, 0) - d * 0.2, yaw - PI * 0.5, 0.8)
		k += 1

	# Median lighting (visual) and trees / fields beyond the fence.
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.12
	pole.height = 10.0
	pole.radial_segments = 8
	pole.rings = 0
	var poles: Array[Transform3D] = []
	var fixtures: Array[Transform3D] = []
	for i in range(0, center.size(), 6):
		poles.append(Transform3D(Basis(), center[i] + Vector3(0, 5.0, 0)))
		var d := (center[(i + 1) % center.size()] - center[i]).normalized()
		fixtures.append(Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), center[i] + Vector3.UP * 9.85))
	C.scatter_multimesh(parent, pole, metal, poles)
	var fixture := BoxMesh.new()
	fixture.size = Vector3(0.42, 0.18, 2.6)
	C.scatter_multimesh(parent, fixture, C.mat(Color(0.83, 0.83, 0.75)), fixtures, false)
	var trees: Array[Vector3] = []
	var conifers: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 2100:
		var p := Vector3(rng.randf_range(-2250, 2250), 0, rng.randf_range(-950, 950))
		var q := Vector2(absf(p.x) - STRAIGHT / 2, 0.0)
		var dist: float
		if absf(p.x) <= STRAIGHT / 2:
			dist = absf(absf(p.z) - RADIUS)
		else:
			dist = absf(Vector2(q.x, p.z).length() - RADIUS)
		if dist < 45.0 or (p.x > SERVICE_START and p.x < SERVICE_END and p.z < -RADIUS + 87.0):
			continue
		(conifers if rng.randf() < 0.35 else trees).append(p)
	_countryside(parent, world, center, trees, rng)
	V.plant(parent, "broadleaf", trees, 91, 0.8, 1.3, false)
	V.plant(parent, "conifer", conifers, 92, 0.7, 1.05, false)
	_landmarks(parent, world, metal)
	_motorway_furniture(parent, world, center, a_center, b_center, open_start, open_end)

	# Traffic: right-hand traffic, carriageway A follows the loop, B goes the other way.
	var lane_a_mid := _offset(center, CARRIAGE_OFFSET + 0.4)
	var lane_a_right := _offset(center, CARRIAGE_OFFSET + 4.1)
	var lane_b := _offset(center, -(CARRIAGE_OFFSET + 0.4))
	lane_b.reverse()
	var speeds_a := C.speeds_from_curvature(lane_a_mid, 36.0, 30.0, 40.0)
	var speeds_b := C.speeds_from_curvature(lane_b, 34.0, 30.0, 40.0)
	var spawn_i := 20
	var truck_x := (SERVICE_START + SERVICE_END) * 0.5 + 54.0
	var truck_access := PackedVector3Array([Vector3(truck_x - 12.0, 0, -RADIUS + 35.0),
		Vector3(truck_x - 12.0, 0, -RADIUS + 59.0), Vector3(truck_x, 0, -RADIUS + 73.0)])
	return {
		"spawns": [C.car_xform(lane_a_right[spawn_i], lane_a_right[spawn_i + 1] - lane_a_right[spawn_i]),
			C.car_xform(lane_a_right[spawn_i - 4], lane_a_right[spawn_i - 3] - lane_a_right[spawn_i - 4])],
		"waypoints": lane_a_mid, "speeds": speeds_a,
		"map_paths": [C.closed_route(center), service_road, truck_access],
		"map_places": [
			{"name": "Raststätte Nordring", "position": Vector3((SERVICE_START + SERVICE_END) * 0.5, 0, -RADIUS + 44)},
			{"name": "Lkw-Stellplatz", "position": truck_access[-1]},
			{"name": "Windpark", "position": Vector3(-875, 0, -RADIUS - 270)},
		],
		"ai_routes": [
			{"waypoints": lane_a_mid, "speeds": speeds_a, "spawn": C.car_xform(lane_a_mid[60], lane_a_mid[61] - lane_a_mid[60])},
			{"waypoints": lane_b, "speeds": speeds_b, "spawn": C.car_xform(lane_b[100], lane_b[101] - lane_b[100])},
			{"waypoints": lane_b, "speeds": speeds_b, "spawn": C.car_xform(lane_b[350], lane_b[351] - lane_b[350])},
		],
		"environment": {"sky_top": Color(0.26, 0.46, 0.8), "horizon": Color(0.68, 0.76, 0.86), "fog": Color(0.72, 0.78, 0.86),
			"fog_density": 0.00045, "sun": Vector3(-40, -30, 0), "sun_energy": 1.3},
	}


static func _service_area(parent: Node3D, world: SBWorld, concrete: Material, metal: Material) -> PackedVector3Array:
	var z := -RADIUS
	var mid := (SERVICE_START + SERVICE_END) * 0.5
	var asphalt := C.surface_material("asphalt", 2.0, Color(0.88, 0.89, 0.91))
	var navy := C.mat(Color(0.08, 0.23, 0.43), 0.62)
	var road := PackedVector3Array([
		Vector3(SERVICE_START + 16, 0, z + 10.8), Vector3(SERVICE_START + 41, 0, z + 14.6),
		Vector3(SERVICE_START + 83, 0, z + 27.0), Vector3(mid - 50, 0, z + 35.0),
		Vector3(mid + 50, 0, z + 35.0), Vector3(SERVICE_END - 83, 0, z + 27.0),
		Vector3(SERVICE_END - 41, 0, z + 14.6), Vector3(SERVICE_END - 16, 0, z + 10.8),
	])
	parent.add_child(C.road_mesh(road, 4.0, asphalt, false, 0.016))
	C.quad(parent, Vector3(mid, 0.012, z + 44), Vector2(104, 26), asphalt)
	C.box(parent, world, Vector3(mid, 2.2, z + 63), Vector3(11, 2.2, 4.5), Vector3.ZERO, concrete)
	C.box(parent, world, Vector3(mid, 4.5, z + 62), Vector3(11.5, 0.22, 6.4), Vector3.ZERO, navy, 0.8, false)
	var glass := C.mat(Color(0.14, 0.30, 0.39), 0.26, 0.35)
	for x: float in [-7.0, -2.5, 2.5, 7.0]:
		C.box(parent, world, Vector3(mid + x, 1.9, z + 58.48), Vector3(1.85, 0.92, 0.06), Vector3.ZERO, glass, 0.8, false)
	C.label3d(parent, "RASTSTÄTTE   NORDRING", Vector3(mid, 3.67, z + 58.38), PI, 0.68)
	C.box(parent, world, Vector3(SERVICE_START + 34.0, 2.15, z + 23), Vector3(0.10, 0.68, 2.1), Vector3.ZERO, navy, 0.8, false)
	C.box(parent, world, Vector3(SERVICE_START + 34.0, 0.95, z + 23), Vector3(0.07, 0.95, 0.08), Vector3.ZERO, metal, 0.7)
	C.label3d(parent, "P   ↗", Vector3(SERVICE_START + 33.88, 2.15, z + 23), -PI * 0.5, 0.74)
	var marks: Array[Transform3D] = []
	for slot in 19:
		marks.append(Transform3D(Basis.from_scale(Vector3(0.12, 1, 5.4)), Vector3(mid - 46.0 + slot * 5.1, 0.022, z + 52.0)))
	var paint := PlaneMesh.new()
	paint.size = Vector2.ONE
	C.scatter_multimesh(parent, paint, C.mat(Color(0.85, 0.85, 0.8)), marks, false)
	var truck_color := C.mat(Color(0.49, 0.57, 0.63))
	var truck_box := Vector3(mid + 54, 0, z + 73)
	C.quad(parent, truck_box + Vector3.UP * 0.011, Vector2(55, 36), asphalt)
	for slot in 8:
		var x := truck_box.x - 22 + 6.0 * slot
		C.quad(parent, Vector3(x, 0.026, truck_box.z + 6), Vector2(0.14, 18), concrete)
		if slot % 3 == 0:
			C.box(parent, world, Vector3(x + 2.5, 2.35, truck_box.z + 5.0), Vector3(1.35, 1.35, 6.4), Vector3.ZERO, truck_color, 0.7)
			C.box(parent, world, Vector3(x + 2.5, 0.49, truck_box.z + 9.0), Vector3(1.35, 0.49, 1.28), Vector3.ZERO, metal)
	return road


## Distance of a point from the loop's centre line.
static func _loop_distance(x: float, z: float) -> float:
	if absf(x) <= STRAIGHT / 2:
		return absf(absf(z) - RADIUS)
	return absf(Vector2(absf(x) - STRAIGHT / 2, z).length() - RADIUS)


## Patchwork farmland around the loop (wheat, rapeseed, maize, meadow, ploughed), hedgerow trees
## along the field edges and a small village with a church tower.
static func _countryside(parent: Node3D, world: SBWorld, center: PackedVector3Array, trees: Array[Vector3],
		rng: RandomNumberGenerator) -> void:
	var kinds := [
		["grass", Color(1.30, 1.12, 0.55), 0.30],   # ripe wheat
		["grass", Color(1.75, 1.55, 0.25), 0.12],   # rapeseed in flower
		["grass", Color(0.55, 0.85, 0.40), 0.18],   # maize
		["grass", Color(0.80, 1.05, 0.68), 0.22],   # meadow
		["sand", Color(0.98, 0.74, 0.54), 0.18],    # ploughed
	]
	var mats: Array = []
	for k: Array in kinds:
		mats.append(C.surface_material(k[0], 3.2 if k[0] == "grass" else 4.0, k[1]))
	var cell := Vector2(150.0, 105.0)
	var x := -STRAIGHT / 2 - RADIUS - 600.0
	while x < STRAIGHT / 2 + RADIUS + 600.0:
		var z := -RADIUS - 520.0
		while z < RADIUS + 520.0:
			var c := Vector2(x + cell.x * 0.5 + rng.randf_range(-12, 12), z + cell.y * 0.5 + rng.randf_range(-10, 10))
			var size := cell - Vector2(rng.randf_range(6, 16), rng.randf_range(6, 14))
			var reach := size.length() * 0.5
			# Fields run up to the wildlife fence; the raised carriageways and verges cover their inner edge.
			if _loop_distance(c.x, c.y) > reach * 0.35 + 30.0 and not (c.x > SERVICE_START - 150 and c.x < SERVICE_END + 150 and absf(c.y + RADIUS) < 220):
				var r := rng.randf()
				var pick := 0
				var acc := 0.0
				for i in kinds.size():
					acc += float(kinds[i][2])
					if r <= acc:
						pick = i
						break
				C.quad(parent, Vector3(c.x, -0.006, c.y), size, mats[pick])
				# Hedgerow trees along one long and one short edge.
				for t in 7:
					if rng.randf() < 0.45:
						trees.append(Vector3(c.x - size.x * 0.5 + size.x * t / 6.0, 0, c.y - size.y * 0.5 - 3.0))
				for t in 4:
					if rng.randf() < 0.35:
						trees.append(Vector3(c.x + size.x * 0.5 + 3.0, 0, c.y - size.y * 0.5 + size.y * t / 3.0))
			z += cell.y
		x += cell.x
	# Village beyond the north-east bend: houses round a church.
	var plaster := [C.mat(Color(0.86, 0.82, 0.72)), C.mat(Color(0.78, 0.74, 0.66)), C.mat(Color(0.83, 0.77, 0.62))]
	var roof := C.mat(Color(0.52, 0.20, 0.13), 0.8)
	var vc := Vector3(STRAIGHT / 2 + RADIUS + 260.0, 0, -160.0)
	C.box(parent, world, vc + Vector3(0, 11, 0), Vector3(2.6, 11, 2.6), Vector3.ZERO, plaster[0], 0.8)
	C.box(parent, world, vc + Vector3(0, 24, 0), Vector3(1.6, 2.5, 1.6), Vector3(0, PI * 0.25, 0), roof, 0.8, false)
	C.box(parent, world, vc + Vector3(0, 5, 9), Vector3(5, 5, 8), Vector3.ZERO, plaster[1], 0.8)
	for i in 22:
		var a := rng.randf() * TAU
		var d := rng.randf_range(22, 95)
		var p := vc + Vector3(cos(a) * d, 0, sin(a) * d)
		if _loop_distance(p.x, p.z) < 70.0: continue
		var yaw := snappedf(rng.randf() * PI, PI * 0.5) + rng.randf_range(-0.2, 0.2)
		var w := rng.randf_range(4.5, 7.0)
		var l := rng.randf_range(5.5, 9.0)
		C.box(parent, world, p + Vector3(0, 2.8, 0), Vector3(l, 2.8, w), Vector3(0, yaw, 0), plaster[i % 3], 0.8)
		for sgn: float in [-1.0, 1.0]:
			var side := Vector3(-sin(yaw), 0, -cos(yaw)) * 0.0 + Basis(Vector3.UP, yaw) * Vector3(0, 0, sgn * w * 0.5)
			C.box(parent, world, p + side + Vector3(0, 6.3, 0), Vector3(l + 0.4, 0.15, w * 0.58), Vector3(sgn * 0.6, yaw, 0), roof, 0.8, false)
		trees.append(p + Basis(Vector3.UP, yaw) * Vector3(0, 0, w + 6.0))


## Wildlife fence, emergency telephones every 2 km, kilometre boards every 500 m and a noise
## barrier along the southern straight.
static func _motorway_furniture(parent: Node3D, world: SBWorld, center: PackedVector3Array, a_center: PackedVector3Array,
		b_center: PackedVector3Array, open_start: int, open_end: int) -> void:
	var n := center.size()
	var fence_off := CARRIAGE_OFFSET + CARRIAGE_HALF + 7.0
	var posts: Array[Transform3D] = []
	var wires: Array[Transform3D] = []
	var mesh_panels: Array[Transform3D] = []
	for sgn: float in [1.0, -1.0]:
		var line := _offset(center, sgn * fence_off)
		for i in n:
			if sgn > 0.0 and i > open_start - 3 and i < open_end + 3: continue
			var a := line[i]
			var b := line[(i + 1) % n]
			posts.append(Transform3D(Basis.IDENTITY, a + Vector3.UP * 0.9))
			var d := b - a
			var basis := Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, d.length()))
			mesh_panels.append(Transform3D(basis, (a + b) * 0.5 + Vector3.UP * 0.85))
			wires.append(Transform3D(basis, (a + b) * 0.5 + Vector3.UP * 1.75))
	var post := CylinderMesh.new()
	post.top_radius = 0.04
	post.bottom_radius = 0.05
	post.height = 1.8
	post.radial_segments = 6
	C.scatter_multimesh(parent, post, C.mat(Color(0.30, 0.24, 0.16), 0.9), posts, false)
	var panel := QuadMesh.new()
	panel.size = Vector2(0.0, 0.0)
	var mesh_box := BoxMesh.new()
	mesh_box.size = Vector3(0.01, 1.5, 1.0)
	var mesh_mat := C.mat(Color(0.45, 0.47, 0.45, 0.35), 0.6, 0.6)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	C.scatter_multimesh(parent, mesh_box, mesh_mat, mesh_panels, false)
	var wire := BoxMesh.new()
	wire.size = Vector3(0.012, 0.012, 1.0)
	C.scatter_multimesh(parent, wire, C.mat(Color(0.3, 0.3, 0.3), 0.5, 0.6), wires, false)
	# Emergency telephones (orange) and kilometre boards on both outer verges, batched.
	var phone_mat := C.mat(Color(0.95, 0.45, 0.08), 0.5)
	var board_mat := C.mat(Color(0.92, 0.92, 0.9), 0.6)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var board_parts: Array[Transform3D] = []
	var phone_parts: Array[Transform3D] = []
	var travelled := 0.0
	var next_board := 100.0
	var next_phone := 400.0
	for i in n:
		travelled += center[i].distance_to(center[(i + 1) % n])
		if travelled < next_board: continue
		var d := (center[(i + 1) % n] - center[i]).normalized()
		var side := Vector3(-d.z, 0, d.x)
		var yaw := atan2(-d.z, d.x)
		var rot := Basis(Vector3.UP, yaw)
		for sgn: float in [1.0, -1.0]:
			if sgn > 0.0 and i > open_start - 3 and i < open_end + 3: continue
			var base := center[i] + side * sgn * (CARRIAGE_OFFSET + CARRIAGE_HALF + 2.3)
			board_parts.append(Transform3D(rot.scaled_local(Vector3(0.08, 1.5, 0.08)), base + Vector3.UP * 0.75))
			board_parts.append(Transform3D(rot.scaled_local(Vector3(0.04, 0.44, 0.64)), base + Vector3.UP * 1.65))
			C.label3d(parent, "%.1f" % (travelled / 1000.0), base + Vector3.UP * 1.65 - side * sgn * 0.03, yaw + (PI * 0.5 if sgn > 0 else -PI * 0.5), 0.22, Color(0.05, 0.05, 0.05))
			if travelled >= next_phone:
				var ph := base + d * 6.0
				phone_parts.append(Transform3D(rot.scaled_local(Vector3(0.32, 1.3, 0.32)), ph + Vector3.UP * 0.65))
				phone_parts.append(Transform3D(rot.scaled_local(Vector3(0.40, 0.24, 0.40)), ph + Vector3.UP * 1.42))
				world.add_box(ph + Vector3.UP * 0.65, Vector3(0.16, 0.65, 0.16), Vector3(0, yaw, 0), 0.6)
		if travelled >= next_phone: next_phone += 2000.0
		next_board += 500.0
	C.scatter_multimesh(parent, unit, board_mat, board_parts, false)
	C.scatter_multimesh(parent, unit, phone_mat, phone_parts, false)
	# Noise barrier: 4 m panels along the outer edge of the southern straight (carriageway B side).
	var wall_mat := C.noise_mat(Color(0.42, 0.50, 0.44), 0.08, 1.5, 0.85)
	var post_mat := C.mat(Color(0.5, 0.5, 0.52), 0.5, 0.7)
	var panels: Array[Transform3D] = []
	var wall_posts: Array[Transform3D] = []
	var zc := RADIUS + CARRIAGE_OFFSET + CARRIAGE_HALF + 3.2
	for k in 250:
		var x0 := -600.0 + k * 4.0
		panels.append(Transform3D(Basis.from_scale(Vector3(4.0, 4.0, 0.16)), Vector3(x0 + 2.0, 2.0, zc)))
		wall_posts.append(Transform3D(Basis.from_scale(Vector3(0.16, 4.2, 0.24)), Vector3(x0, 2.1, zc)))
	world.add_box(Vector3(-100.0, 2.0, zc), Vector3(500.0, 2.0, 0.08), Vector3.ZERO, 0.8)
	C.scatter_multimesh(parent, unit, wall_mat, panels)
	C.scatter_multimesh(parent, unit, post_mat, wall_posts, false)


static func _landmarks(parent: Node3D, world: SBWorld, metal: Material) -> void:
	var gravel := C.noise_mat(Color(0.41, 0.32, 0.19), 0.25, 0.12)
	var wheat := C.noise_mat(Color(0.57, 0.46, 0.20), 0.18, 0.09)
	for x: float in [-1750.0, -760.0, 610.0, 1260.0]:
		C.quad(parent, Vector3(x, -0.013, -210), Vector2(410, 112), wheat, 0.07)
		C.quad(parent, Vector3(x - 45.0, -0.012, 230), Vector2(365, 142), gravel, -0.05)
	var white := C.mat(Color(0.76, 0.78, 0.78), 0.72)
	var red := C.mat(Color(0.71, 0.18, 0.12), 0.7)
	for i in 6:
		var p := Vector3(-1350 + i * 190.0, 0, -RADIUS - 240.0 - (i % 2) * 75.0)
		C.box(parent, world, p + Vector3.UP * 25.0, Vector3(1.15, 25.0, 1.15), Vector3.ZERO, white, 0.8, false)
		C.box(parent, world, p + Vector3(0, 50, -0.8), Vector3(2.7, 1.5, 1.9), Vector3.ZERO, metal, 0.8, false)
		for blade in 3:
			var angle := TAU / 3.0 * blade + i * 0.37
			var direction := Vector3(-sin(angle), cos(angle), 0)
			var hub := p + Vector3(0, 50, -3.2)
			C.box(parent, world, hub + direction * 9.5, Vector3(0.58, 9.5, 0.17), Vector3(0, 0, angle), white, 0.8, false)
			C.box(parent, world, hub + direction * 20.4, Vector3(0.45, 1.4, 0.15), Vector3(0, 0, angle), red, 0.8, false)
