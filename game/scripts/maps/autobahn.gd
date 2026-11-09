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
	C.barrier(parent, world, outer_rail, CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9, 0.75, 0.22, metal, false)
	C.barrier(parent, world, center, -(CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9), 0.75, 0.22, metal)
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
	V.plant(parent, "broadleaf", trees, 91, 0.8, 1.3, false)
	V.plant(parent, "conifer", conifers, 92, 0.7, 1.05, false)
	_landmarks(parent, world, metal)

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
