extends RefCounted
## "Autobahn": ~6 km closed motorway loop with two 3-lane carriageways, concrete median, guard
## rails, overpasses, sign gantries, lighting and traffic in both directions.

const C := preload("res://scripts/maps/common.gd")
const STRAIGHT := 1400.0
const RADIUS := 380.0
const CARRIAGE_OFFSET := 7.6   # centre of a carriageway from the median
const CARRIAGE_HALF := 6.9


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
	var grass := C.noise_mat(Color(0.3, 0.45, 0.18), 0.25, 0.04, 0.95, 0.03)
	C.quad(parent, Vector3(0, -0.02, 0), Vector2(5000, 5000), grass)
	var concrete := C.noise_mat(Color(0.66, 0.66, 0.63), 0.1, 0.5, 0.8, 0.2)
	var metal := C.mat(Color(0.72, 0.74, 0.76), 0.35, 0.85)
	var road := C.road_material(3, "autobahn")
	var center := _loop()
	var a_center := _offset(center, CARRIAGE_OFFSET)
	var b_center := _offset(center, -CARRIAGE_OFFSET)
	parent.add_child(C.road_mesh(a_center, CARRIAGE_HALF, road, true, 0.03, 14.0))
	parent.add_child(C.road_mesh(b_center, CARRIAGE_HALF, road, true, 0.03, 14.0))
	# Central reservation: concrete step barrier; guard rails on both outer edges.
	C.barrier(parent, world, center, 0.0, 0.85, 0.55, concrete)
	C.barrier(parent, world, center, CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9, 0.75, 0.22, metal)
	C.barrier(parent, world, center, -(CARRIAGE_OFFSET + CARRIAGE_HALF + 0.9), 0.75, 0.22, metal)
	# Rail posts (visual).
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.8, 0.12)
	var posts: Array[Transform3D] = []
	for side: float in [1.0, -1.0]:
		var rail := _offset(center, side * (CARRIAGE_OFFSET + CARRIAGE_HALF + 1.05))
		for i in range(0, rail.size(), 1):
			if i % 2 == 0:
				posts.append(Transform3D(Basis(), rail[i] + Vector3(0, 0.4, 0)))
	C.scatter_multimesh(parent, post, C.mat(Color(0.5, 0.5, 0.52), 0.5, 0.7), posts)

	# Overpasses across the two straights.
	var deck_mat := C.noise_mat(Color(0.6, 0.6, 0.58), 0.12, 0.3, 0.85, 0.1)
	for x: float in [-300.0, 350.0]:
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
	var texts := ["Ausfahrt Testgelände  1000 m", "Hügelland  25 km    Wüste  80 km", "Stadt  12 km", "Raststätte  2000 m"]
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
	var poles: Array[Transform3D] = []
	for i in range(0, center.size(), 6):
		poles.append(Transform3D(Basis(), center[i] + Vector3(0, 5.0, 0)))
	C.scatter_multimesh(parent, pole, metal, poles)
	var tree := CylinderMesh.new()
	tree.top_radius = 0.0
	tree.bottom_radius = 2.2
	tree.height = 9.0
	var trees: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 1400:
		var p := Vector3(rng.randf_range(-1700, 1700), 0, rng.randf_range(-800, 800))
		var q := Vector2(absf(p.x) - STRAIGHT / 2, 0.0)
		var dist: float
		if absf(p.x) <= STRAIGHT / 2:
			dist = absf(absf(p.z) - RADIUS)
		else:
			dist = absf(Vector2(q.x, p.z).length() - RADIUS)
		if dist < 40.0:
			continue
		var s := rng.randf_range(0.7, 1.5)
		trees.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0, 4.5 * s, 0)))
	C.scatter_multimesh(parent, tree, C.mat(Color(0.12, 0.27, 0.12), 0.9), trees)

	# Traffic: right-hand traffic, carriageway A follows the loop, B goes the other way.
	var lane_a_mid := _offset(center, CARRIAGE_OFFSET + 0.4)
	var lane_a_right := _offset(center, CARRIAGE_OFFSET + 4.1)
	var lane_b := _offset(center, -(CARRIAGE_OFFSET + 0.4))
	lane_b.reverse()
	var speeds_a := C.speeds_from_curvature(lane_a_mid, 36.0, 30.0, 40.0)
	var speeds_b := C.speeds_from_curvature(lane_b, 34.0, 30.0, 40.0)
	var spawn_i := 20
	return {
		"spawns": [C.car_xform(lane_a_right[spawn_i], lane_a_right[spawn_i + 1] - lane_a_right[spawn_i]),
			C.car_xform(lane_a_right[spawn_i - 4], lane_a_right[spawn_i - 3] - lane_a_right[spawn_i - 4])],
		"waypoints": lane_a_mid, "speeds": speeds_a,
		"ai_routes": [
			{"waypoints": lane_a_mid, "speeds": speeds_a, "spawn": C.car_xform(lane_a_mid[60], lane_a_mid[61] - lane_a_mid[60])},
			{"waypoints": lane_b, "speeds": speeds_b, "spawn": C.car_xform(lane_b[100], lane_b[101] - lane_b[100])},
			{"waypoints": lane_b, "speeds": speeds_b, "spawn": C.car_xform(lane_b[350], lane_b[351] - lane_b[350])},
		],
		"environment": {"sky_top": Color(0.26, 0.46, 0.8), "horizon": Color(0.68, 0.76, 0.86), "fog": Color(0.72, 0.78, 0.86),
			"fog_density": 0.00045, "sun": Vector3(-40, -30, 0), "sun_energy": 1.3},
	}
