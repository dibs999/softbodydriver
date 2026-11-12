extends RefCounted
## An 8.5 km motorway loop with service access, overpasses and opposing traffic.

const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")
const STRAIGHT := 2600.0
const RADIUS := 520.0
## Church tower of the village beyond the north-east bend, and the village's extent around it
## (kept clear of the field patchwork).
const VILLAGE := Vector3(STRAIGHT / 2 + RADIUS + 260.0, 0, -160.0)
const VILLAGE_MIN := Vector2(-175.0, -130.0)
const VILLAGE_MAX := Vector2(185.0, 130.0)
const CARRIAGE_OFFSET := 7.6   # centre of a carriageway from the median
const CARRIAGE_HALF := 6.9
const SHOULDER_HIGH_U_A := true   # which UV side of carriageway A is its outer edge (checked in renders)
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
	# The carriageways are drawn 4 mm above the physics plane (they were 3 cm: the bottom of every
	# tyre disappeared in the asphalt); every ground layer below them keeps its order, 2.6 cm lower.
	var grass := C.surface_material("grass", 3.5, Color(0.73, 0.92, 0.66))
	C.quad(parent, Vector3(0, -0.046, 0), Vector2(6200, 5000), grass)
	var concrete := C.noise_mat(Color(0.66, 0.66, 0.63), 0.1, 0.5, 0.8, 0.2)
	var metal := C.mat(Color(0.72, 0.74, 0.76), 0.35, 0.85)
	var road := C.road_material(3, CARRIAGE_HALF * 2.0, 14.0, "autobahn")
	# RQ 31-like cross-section per carriageway: 0.75 m safety strip at the median, three 3.75 m lanes,
	# a 30 cm solid edge line and the hard shoulder on the outside (both carriageways, mirrored).
	road.set_shader_parameter("shoulder_m", CARRIAGE_HALF * 2.0 - 0.75 - 3.0 * 3.75)
	road.set_shader_parameter("inner_strip_m", 0.75)
	road.set_shader_parameter("edge_line_m", 0.30)
	var road_b: ShaderMaterial = road.duplicate()
	road.set_shader_parameter("shoulder_high_u", SHOULDER_HIGH_U_A)
	road_b.set_shader_parameter("shoulder_high_u", not SHOULDER_HIGH_U_A)
	var center := _loop()
	var a_center := _offset(center, CARRIAGE_OFFSET)
	var b_center := _offset(center, -CARRIAGE_OFFSET)
	parent.add_child(C.road_mesh(a_center, CARRIAGE_HALF, road, true, 0.004, 14.0))
	parent.add_child(C.road_mesh(b_center, CARRIAGE_HALF, road_b, true, 0.004, 14.0))
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
	_backdrop_hills(parent)
	var R := preload("res://scripts/maps/roadside.gd")
	R.rail(parent, _offset(outer_rail, CARRIAGE_OFFSET + CARRIAGE_HALF + 1.0), -1.0)
	var inner_rail := _offset(center, -(CARRIAGE_OFFSET + CARRIAGE_HALF + 1.0))
	inner_rail.append(inner_rail[0])
	R.rail(parent, inner_rail, 1.0)
	# Bankett: a strip of grit and grass between the asphalt and the guard rails on both sides of
	# each carriageway (not across the service area's slip roads).
	var verge := C.verge_material(0.85, 14.0)
	verge.set_shader_parameter("grass_color", Color(0.56, 0.68, 0.34))
	var a_outer := PackedVector3Array()
	for i in range(open_end, center.size() + open_start + 1):
		a_outer.append(a_center[i % center.size()])
	parent.add_child(C.verge_mesh(a_center, CARRIAGE_HALF, 0.85, verge, true, 0.004, 14.0, Callable(), [-1.0]))
	parent.add_child(C.verge_mesh(a_outer, CARRIAGE_HALF, 0.85, verge, false, 0.004, 14.0, Callable(), [1.0]))
	parent.add_child(C.verge_mesh(b_center, CARRIAGE_HALF, 0.85, verge, true, 0.004, 14.0))
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

	# Overpasses across the two straights: a farm road on earth ramps, bridged over the motorway.
	var deck_mat := C.noise_mat(Color(0.6, 0.6, 0.58), 0.12, 0.3, 0.85, 0.1)
	var lane_road := C.road_material(2, 6.5, 12.0, "rural")
	for x: float in [-420.0, 380.0, 1030.0]:
		for z: float in [-RADIUS, RADIUS]:
			_overpass(parent, world, x, z, 2.0 * (CARRIAGE_OFFSET + CARRIAGE_HALF + 4.0), deck_mat, concrete, grass, lane_road)

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
		var conifer := rng.randf() < 0.35
		# The village plants its own garden trees (checked after the draw: same sequence as before).
		if p.x > VILLAGE.x + VILLAGE_MIN.x - 10.0 and p.x < VILLAGE.x + VILLAGE_MAX.x + 10.0 \
				and p.z > VILLAGE.z + VILLAGE_MIN.y - 10.0 and p.z < VILLAGE.z + VILLAGE_MAX.y + 10.0:
			continue
		(conifers if conifer else trees).append(p)
	_countryside(parent, world, center, trees, rng)
	# Solid trunks for the countryside trees (behind the fence, but a car can break through).
	# Some field-edge trees landed on the motorway: drop those, and give the rest solid trunks
	# well away from the carriageway (junctions and bridges stay clear).
	for list: Array[Vector3] in [trees, conifers]:
		var kept: Array[Vector3] = []
		for p in list:
			var qx := absf(p.x) - STRAIGHT / 2
			var off := absf(absf(p.z) - RADIUS) if absf(p.x) <= STRAIGHT / 2 else absf(Vector2(qx, p.z).length() - RADIUS)
			if off < 24.0:
				continue
			kept.append(p)
			if off > 30.0 and V.keep(p):
				world.add_box(p + Vector3.UP * 1.8, Vector3(0.22, 1.8, 0.22), Vector3.ZERO, 0.7)
		list.assign(kept)
	V.plant(parent, "broadleaf", trees, 91, 0.8, 1.3, false)
	V.plant(parent, "conifer", conifers, 92, 0.7, 1.05, false)
	_landmarks(parent, world, metal)
	_motorway_furniture(parent, world, center, a_center, b_center, open_start, open_end)

	# Traffic: right-hand traffic, carriageway A follows the loop, B goes the other way.
	# Lane centres of the marked cross-section (0.75 m strip, 3.75 m lanes from the median side):
	# middle lane 0.525 m and right lane 3.225 m off the carriageway centre.
	var lane_a_mid := _offset(center, CARRIAGE_OFFSET - 0.525)
	var lane_a_right := _offset(center, CARRIAGE_OFFSET + 3.225)
	var lane_b := _offset(center, -(CARRIAGE_OFFSET - 0.525))
	lane_b.reverse()
	var speeds_a := C.speeds_from_curvature(lane_a_mid, 36.0, 30.0, 40.0)
	var speeds_b := C.speeds_from_curvature(lane_b, 34.0, 30.0, 40.0)
	# Roadworks on the far straight: a line of Leitbaken (sign 605, panels facing the traffic) on
	# the edge of the hard shoulder (outer side of carriageway A) and a few drums parked on it.
	var props: Array = []
	var last := Vector3.INF
	for i in center.size():
		var p := center[i]
		var q := center[(i + 1) % center.size()]
		if absf(p.z - RADIUS) > 0.5 or absf(q.z - RADIUS) > 0.5 or minf(p.x, q.x) < 150.0 or maxf(p.x, q.x) > 420.0:
			continue
		var steps := maxi(1, int(p.distance_to(q) / 9.0))
		for s in steps:
			var c := p.lerp(q, float(s) / steps) + Vector3(0, 0, CARRIAGE_OFFSET + CARRIAGE_HALF - 2.4)
			if last == Vector3.INF or c.distance_to(last) > 8.0:
				props.append({"kind": "beacon", "position": Vector3(c.x, 0.0, c.z)})
				last = c
	for d in 3:
		props.append({"kind": "barrel", "position": Vector3(146.0 - d * 0.7, 0.0, RADIUS + CARRIAGE_OFFSET + CARRIAGE_HALF - 1.0)})
	# Water-filled barriers across the closed shoulder at the start of the works.
	for d in 2:
		props.append({"kind": "barrier", "position": Vector3(153.5, 0.0, RADIUS + CARRIAGE_OFFSET + CARRIAGE_HALF - 0.7 - d * 1.25), "yaw": PI * 0.5})
	var spawn_i := 20
	var truck_x := (SERVICE_START + SERVICE_END) * 0.5 + 54.0
	var truck_access := PackedVector3Array([Vector3(truck_x - 12.0, 0, -RADIUS + 35.0),
		Vector3(truck_x - 12.0, 0, -RADIUS + 59.0), Vector3(truck_x, 0, -RADIUS + 73.0)])
	return {
		"spawns": [C.car_xform(lane_a_right[spawn_i], lane_a_right[spawn_i + 1] - lane_a_right[spawn_i]),
			C.car_xform(lane_a_right[spawn_i - 4], lane_a_right[spawn_i - 3] - lane_a_right[spawn_i - 4])],
		"waypoints": lane_a_mid, "speeds": speeds_a, "props": props,
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


## Road bridge across both carriageways at x, centred on the motorway line z: deck on three pier
## rows with parapets along its sides, concrete abutments, and at each end an earth ramp - a
## trapezoid with 1:1.5 grass slopes - that carries the road down to the fields over 60 m.
static func _overpass(parent: Node3D, world: SBWorld, x: float, z: float, span: float, deck_mat: Material,
		concrete: Material, grass: Material, road: Material) -> void:
	const DECK_Y := 7.2          # road surface height on the bridge
	const HALF := 7.0            # half width of deck and ramp crown
	const RAMP := 60.0
	var deck_half := span * 0.5 + 6.0
	# Deck slab: drivable (the farm road can be driven over the motorway).
	C.box(parent, world, Vector3(x, DECK_Y - 0.6, z), Vector3(HALF, 0.6, deck_half), Vector3.ZERO, deck_mat, 0.8, true)
	var cap_mat := C.noise_mat(Color(0.70, 0.70, 0.68), 0.1, 0.4, 0.85, 0.12)
	var steel := C.mat(Color(0.56, 0.58, 0.60), 0.45, 0.7)
	var posts: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		# Raised concrete cap with a service walkway, and the edge beam whose lighter face and
		# drip line run along the outside of the deck (the bridge's visible "cornice").
		C.box(parent, world, Vector3(x + side * (HALF - 0.45), DECK_Y + 0.1, z), Vector3(0.75, 0.1, deck_half), Vector3.ZERO, cap_mat, 0.8, false)
		C.box(parent, world, Vector3(x + side * (HALF + 0.12), DECK_Y - 0.45, z), Vector3(0.18, 0.75, deck_half + 0.05), Vector3.ZERO, cap_mat, 0.8, false)
		# Steel railing on the cap: posts every 2 m, a top handrail and two knee rails. It and a
		# guard rail (Schutzplanke) at the kerb are one barrier for the physics.
		for k in int(deck_half) + 1:
			for dir: float in [-1.0, 1.0]:
				if k == 0 and dir > 0.0: continue
				posts.append(Transform3D(Basis.from_scale(Vector3(0.07, 1.0, 0.07)), Vector3(x + side * (HALF - 0.12), DECK_Y + 0.7, z + dir * k * 2.0)))
		for rail_y: float in [1.18, 0.82, 0.5]:
			C.box(parent, world, Vector3(x + side * (HALF - 0.12), DECK_Y + rail_y, z), Vector3(0.04 if rail_y < 1.0 else 0.06, 0.03 if rail_y < 1.0 else 0.04, deck_half), Vector3.ZERO, steel, 0.6, false)
		C.box(parent, world, Vector3(x + side * (HALF - 1.25), DECK_Y + 0.55, z), Vector3(0.04, 0.17, deck_half - 0.5), Vector3.ZERO, steel, 0.6, false)
		for k in int(deck_half / 2.0) + 1:
			for dir: float in [-1.0, 1.0]:
				if k == 0 and dir > 0.0: continue
				posts.append(Transform3D(Basis.from_scale(Vector3(0.1, 0.75, 0.06)), Vector3(x + side * (HALF - 1.2), DECK_Y + 0.37, z + dir * k * 4.0)))
		world.add_box(Vector3(x + side * (HALF - 1.1), DECK_Y + 0.6, z), Vector3(0.15, 0.6, deck_half), Vector3.ZERO, 0.4)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3.ONE
	C.scatter_multimesh(parent, post_mesh, steel, posts, false)
	# Round piers on three rows with a cap beam each, elastomer bearings under the deck.
	var pier_mesh := CylinderMesh.new()
	pier_mesh.top_radius = 0.55
	pier_mesh.bottom_radius = 0.6
	pier_mesh.height = DECK_Y - 1.8
	pier_mesh.radial_segments = 20
	var bearing := C.mat(Color(0.12, 0.12, 0.12), 0.8)
	for pz: float in [z - span * 0.5 - 2.0, z, z + span * 0.5 + 2.0]:
		for px: float in [-4.0, 4.0]:
			var pier := MeshInstance3D.new()
			pier.mesh = pier_mesh
			pier.material_override = concrete
			pier.position = Vector3(x + px, (DECK_Y - 1.8) * 0.5, pz)
			parent.add_child(pier)
			world.add_box(pier.position, Vector3(0.6, (DECK_Y - 1.8) * 0.5, 0.6), Vector3.ZERO, 0.7)
			C.box(parent, world, Vector3(x + px, DECK_Y - 1.25, pz), Vector3(0.35, 0.05, 0.35), Vector3.ZERO, bearing, 0.8, false)
		C.box(parent, world, Vector3(x, DECK_Y - 1.55, pz), Vector3(HALF - 0.6, 0.25, 0.75), Vector3.ZERO, concrete, 0.7, false)   # pier cap
	# Road across the deck and both ramps as one strip (the ramps follow the slope).
	var road_pts := PackedVector3Array()
	var z0 := z - deck_half - RAMP - 40.0   # on into the fields a little way
	var z1 := z + deck_half + RAMP + 40.0
	var height := func(zz: float) -> float:
		var out := absf(zz - z) - deck_half
		return DECK_Y if out <= 0.0 else DECK_Y * clampf(1.0 - out / RAMP, 0.0, 1.0)
	var n := 48
	for i in n + 1:
		var zz := lerpf(z0, z1, float(i) / n)
		road_pts.append(Vector3(x, height.call(zz), zz))
	parent.add_child(C.road_mesh(road_pts, 3.25, road, false, 0.004, 12.0))
	# Earth ramps and abutments.
	for end: float in [-1.0, 1.0]:
		var start := z + end * deck_half
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := 16
		var prev: Array = []
		for k in steps + 1:
			var d := float(k) / steps * RAMP
			var h := DECK_Y * (1.0 - d / RAMP)
			var zz := start + end * d
			var foot := HALF + 1.5 * h
			var ring := [Vector3(x - foot, 0.0, zz), Vector3(x - HALF, h - 0.02, zz), Vector3(x + HALF, h - 0.02, zz), Vector3(x + foot, 0.0, zz)]
			if k > 0:
				for f in 3:
					var a: Vector3 = prev[f]
					var b: Vector3 = prev[f + 1]
					var c: Vector3 = ring[f + 1]
					var e: Vector3 = ring[f]
					var normal := (b - a).cross(e - a).normalized()
					if normal.y < 0.0:
						normal = -normal
						for v: Vector3 in [a, c, b, a, e, c]:
							st.set_normal(normal); st.set_uv(Vector2(v.x, v.z) * 0.25); st.add_vertex(v)
					else:
						for v: Vector3 in [a, b, c, a, c, e]:
							st.set_normal(normal); st.set_uv(Vector2(v.x, v.z) * 0.25); st.add_vertex(v)
			prev = ring
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = grass
		parent.add_child(mi)
		# The ramp crown is drivable: one inclined slab from the field up to the deck.
		var theta := atan(DECK_Y / RAMP)
		var slant := RAMP / cos(theta)
		var top_mid := Vector3(x, DECK_Y * 0.5, start + end * RAMP * 0.5)
		var normal := Vector3(0.0, cos(theta), end * sin(theta))
		world.add_box(top_mid - normal * 0.5, Vector3(HALF, 0.5, slant * 0.5 + 0.3), Vector3(end * theta, 0.0, 0.0), 0.9)
		# Abutment: a concrete wall under the deck end, wing walls along the ramp's first metres.
		C.box(parent, world, Vector3(x, (DECK_Y - 1.2) * 0.5, start - end * 0.4), Vector3(HALF + 0.6, (DECK_Y - 1.2) * 0.5, 0.6), Vector3.ZERO, concrete, 0.7)
		for side: float in [-1.0, 1.0]:
			C.box(parent, world, Vector3(x + side * (HALF + 0.3), DECK_Y * 0.5, start + end * 3.0), Vector3(0.3, DECK_Y * 0.5, 3.0), Vector3.ZERO, concrete, 0.7, false)


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
	parent.add_child(C.road_mesh(road, 4.0, asphalt, false, -0.010))
	C.quad(parent, Vector3(mid, -0.014, z + 44), Vector2(104, 26), asphalt)
	C.box(parent, world, Vector3(mid, 2.2, z + 63), Vector3(11, 2.2, 4.5), Vector3.ZERO, concrete)
	C.box(parent, world, Vector3(mid, 4.5, z + 62), Vector3(11.5, 0.22, 6.4), Vector3.ZERO, navy, 0.8, false)
	var glass := C.mat(Color(0.14, 0.30, 0.39), 0.26, 0.35)
	# The rest area is open all night: the glass front glows warm after dark (driven like a lamp
	# lens by a light-less street_lighting node).
	glass.emission_enabled = true
	glass.emission = Color(0.30, 0.24, 0.15)
	glass.emission_energy_multiplier = 0.0
	var shop_light := preload("res://scripts/maps/street_lighting.gd").new()
	shop_light.name = "RestAreaWindows"
	parent.add_child(shop_light)
	shop_light.setup(PackedVector3Array(), glass)
	for x: float in [-7.0, -2.5, 2.5, 7.0]:
		C.box(parent, world, Vector3(mid + x, 1.9, z + 58.48), Vector3(1.85, 0.92, 0.06), Vector3.ZERO, glass, 0.8, false)
	C.label3d(parent, "RASTSTÄTTE   NORDRING", Vector3(mid, 3.67, z + 58.38), PI, 0.68)
	C.box(parent, world, Vector3(SERVICE_START + 34.0, 2.15, z + 23), Vector3(0.10, 0.68, 2.1), Vector3.ZERO, navy, 0.8, false)
	C.box(parent, world, Vector3(SERVICE_START + 34.0, 0.95, z + 23), Vector3(0.07, 0.95, 0.08), Vector3.ZERO, metal, 0.7)
	C.label3d(parent, "P   ↗", Vector3(SERVICE_START + 33.88, 2.15, z + 23), -PI * 0.5, 0.74)
	var marks: Array[Transform3D] = []
	for slot in 19:
		marks.append(Transform3D(Basis.from_scale(Vector3(0.12, 1, 5.4)), Vector3(mid - 46.0 + slot * 5.1, -0.004, z + 52.0)))
	var paint := PlaneMesh.new()
	paint.size = Vector2.ONE
	C.scatter_multimesh(parent, paint, C.mat(Color(0.85, 0.85, 0.8)), marks, false)
	var truck_box := Vector3(mid + 54, 0, z + 73)
	C.quad(parent, truck_box + Vector3.UP * -0.015, Vector2(55, 36), asphalt)
	var trailer_colors := [C.mat(Color(0.82, 0.83, 0.84), 0.6), C.mat(Color(0.55, 0.12, 0.10), 0.6), C.mat(Color(0.20, 0.32, 0.52), 0.6)]
	var cab_colors := [C.mat(Color(0.88, 0.88, 0.86), 0.4, 0.3), C.mat(Color(0.12, 0.25, 0.45), 0.4, 0.3), C.mat(Color(0.65, 0.10, 0.08), 0.4, 0.3)]
	for slot in 8:
		var x := truck_box.x - 22 + 6.0 * slot
		C.quad(parent, Vector3(x, 0.0, truck_box.z + 6), Vector2(0.14, 18), concrete)
		if slot % 3 == 0:
			_parked_truck(parent, world, Vector3(x + 2.5, 0, truck_box.z + 6.0), trailer_colors[slot / 3 % 3], cab_colors[slot / 3 % 3], metal)
	_service_details(parent, world, z, mid, asphalt, concrete, metal, navy, glass)
	return road


## Lamp lenses (one shared material that glows at night) and pooled spot lights for them.
static func _street_lights(parent: Node3D, lenses: Array[Transform3D], lights: PackedVector3Array, size: Vector3, node_name: String) -> void:
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.9, 0.88, 0.8)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.85, 0.62)
	lens.emission_energy_multiplier = 0.0
	var mesh := BoxMesh.new()
	mesh.size = size
	C.scatter_multimesh(parent, mesh, lens, lenses, false)
	var lighting := preload("res://scripts/maps/street_lighting.gd").new()
	lighting.name = node_name
	parent.add_child(lighting)
	lighting.setup(lights, lens)


## A parked articulated lorry pointing -z (towards the exit): cab with windscreen, mirrors and
## bumper, a 13.6 m box trailer, wheels on both. One solid collider per part.
static func _parked_truck(parent: Node3D, world: SBWorld, at: Vector3, trailer: Material, cab: Material, metal: Material) -> void:
	var dark := C.mat(Color(0.07, 0.08, 0.09), 0.3, 0.2)
	var tyre := C.mat(Color(0.05, 0.05, 0.05), 0.9)
	# Trailer: box on a chassis, 1.2 m off the ground.
	C.box(parent, world, at + Vector3(0, 2.55, 2.2), Vector3(1.27, 1.35, 6.8), Vector3.ZERO, trailer, 0.7)
	C.box(parent, null, at + Vector3(0, 1.08, 2.2), Vector3(1.0, 0.12, 6.6), Vector3.ZERO, metal, 0.7, false)
	# Tractor: cab over the front axle, chassis and fuel tank.
	C.box(parent, world, at + Vector3(0, 2.15, -5.9), Vector3(1.25, 1.45, 1.15), Vector3.ZERO, cab, 0.7)
	C.box(parent, null, at + Vector3(0, 2.6, -7.07), Vector3(1.1, 0.55, 0.03), Vector3.ZERO, dark, 0.7, false)      # windscreen
	C.box(parent, null, at + Vector3(0, 0.85, -7.1), Vector3(1.25, 0.25, 0.08), Vector3.ZERO, metal, 0.7, false)     # bumper
	C.box(parent, null, at + Vector3(0, 1.35, -7.08), Vector3(0.8, 0.28, 0.02), Vector3.ZERO, dark, 0.7, false)      # grille
	for sx: float in [-1.0, 1.0]:
		C.box(parent, null, at + Vector3(sx * 1.38, 2.7, -6.9), Vector3(0.04, 0.3, 0.1), Vector3.ZERO, dark, 0.7, false)   # mirrors
	C.box(parent, null, at + Vector3(0, 0.95, -3.8), Vector3(0.9, 0.15, 1.6), Vector3.ZERO, metal, 0.7, false)       # chassis
	C.box(parent, null, at + Vector3(1.05, 0.9, -4.3), Vector3(0.25, 0.3, 0.6), Vector3.ZERO, metal, 0.7, false)     # fuel tank
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.52
	wheel.bottom_radius = 0.52
	wheel.height = 0.32
	wheel.radial_segments = 14
	var wheels: Array[Transform3D] = []
	for wz: float in [-6.0, -3.4, 5.4, 6.7, 8.0]:
		for sx: float in [-1.0, 1.0]:
			wheels.append(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), at + Vector3(sx * 1.05, 0.52, wz)))
	C.scatter_multimesh(parent, wheel, tyre, wheels)


## Rest area details: glass front with mullions and an entrance canopy, terrace with benches and
## bins, planters with trees round the car park, lamp posts, and a petrol station on its own
## forecourt beside the entry road with a canopy and two pump islands.
static func _service_details(parent: Node3D, world: SBWorld, z: float, mid: float, asphalt: Material, concrete: Material,
		metal: Material, navy: Material, glass: Material) -> void:
	var white := C.mat(Color(0.92, 0.92, 0.9), 0.6)
	var alu := C.mat(Color(0.78, 0.79, 0.8), 0.35, 0.8)
	var wood := C.mat(Color(0.45, 0.30, 0.18), 0.8)
	var soil := C.mat(Color(0.20, 0.15, 0.10), 0.95)
	# Mullions over the glass front and an entrance canopy on two posts.
	for k in 9:
		C.box(parent, null, Vector3(mid - 9.0 + k * 2.25, 1.9, z + 58.42), Vector3(0.05, 0.95, 0.04), Vector3.ZERO, alu, 0.6, false)
	C.box(parent, null, Vector3(mid, 2.88, z + 58.42), Vector3(9.1, 0.05, 0.05), Vector3.ZERO, alu, 0.6, false)
	C.box(parent, null, Vector3(mid, 3.05, z + 56.6), Vector3(3.2, 0.12, 1.9), Vector3.ZERO, navy, 0.8, false)
	for sx: float in [-1.0, 1.0]:
		C.box(parent, world, Vector3(mid + sx * 3.0, 1.5, z + 54.9), Vector3(0.08, 1.5, 0.08), Vector3.ZERO, alu, 0.6)
	# Terrace: benches with tables and litter bins either side of the entrance.
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var t := Vector3(mid + sx * (5.5 + k * 3.2), 0, z + 55.5)
			C.box(parent, world, t + Vector3(0, 0.75, 0), Vector3(0.9, 0.04, 0.4), Vector3.ZERO, wood, 0.6)
			C.box(parent, null, t + Vector3(0, 0.37, 0), Vector3(0.06, 0.37, 0.06), Vector3.ZERO, metal, 0.6, false)
			for bz: float in [-0.75, 0.75]:
				C.box(parent, world, t + Vector3(0, 0.45, bz), Vector3(0.9, 0.03, 0.17), Vector3.ZERO, wood, 0.6)
		C.box(parent, world, Vector3(mid + sx * 3.8, 0.45, z + 55.0), Vector3(0.22, 0.45, 0.22), Vector3.ZERO, C.mat(Color(0.15, 0.32, 0.20), 0.6), 0.6)
	# Planters with trees between the parking rows and the building, lamp posts along the lot.
	var trees: Array[Vector3] = []
	for k in 6:
		var px := mid - 45.0 + k * 18.0
		C.box(parent, world, Vector3(px, 0.25, z + 56.4), Vector3(1.4, 0.25, 0.9), Vector3.ZERO, concrete, 0.8)
		C.box(parent, null, Vector3(px, 0.47, z + 56.4), Vector3(1.3, 0.03, 0.8), Vector3.ZERO, soil, 0.8, false)
		trees.append(Vector3(px, 0.5, z + 56.4))
	V.plant(parent, "broadleaf", trees, 4711, 0.55, 0.75, false)
	var lot_lenses: Array[Transform3D] = []
	var lot_lights := PackedVector3Array()
	for k in 5:
		var lx := mid - 40.0 + k * 20.0
		C.box(parent, world, Vector3(lx, 4.0, z + 40.0), Vector3(0.09, 4.0, 0.09), Vector3.ZERO, metal, 0.6)
		C.box(parent, null, Vector3(lx, 8.0, z + 40.6), Vector3(0.18, 0.08, 0.7), Vector3.ZERO, metal, 0.6, false)
		lot_lenses.append(Transform3D(Basis.IDENTITY, Vector3(lx, 7.9, z + 40.8)))
		lot_lights.append(Vector3(lx, 7.75, z + 40.8))
	# Petrol station north of the entry road.
	var fx := SERVICE_START + 64.0
	var fz := z + 37.0   # posts clear of the entry road, which rises to z + 27 here
	# Forecourt from the entry road's edge (about z + 21) to behind the canopy.
	C.quad(parent, Vector3(fx, -0.012, fz - 4.0), Vector2(34, 22), asphalt)
	for px: float in [-11.0, 11.0]:
		for pz: float in [-4.0, 4.0]:
			C.box(parent, world, Vector3(fx + px, 2.6, fz + pz), Vector3(0.2, 2.6, 0.2), Vector3.ZERO, white, 0.6)
	C.box(parent, null, Vector3(fx, 5.35, fz), Vector3(12.5, 0.25, 5.5), Vector3.ZERO, white, 0.8, false)
	C.box(parent, null, Vector3(fx, 5.0, fz), Vector3(12.55, 0.4, 5.55), Vector3.ZERO, navy, 0.8, false)
	C.label3d(parent, "TANKSTELLE", Vector3(fx, 5.0, fz - 5.57), PI, 0.7, Color(0.95, 0.95, 0.92))
	for lx: float in [-8.0, -3.0, 3.0, 8.0]:
		for lz: float in [-2.5, 2.5]:
			lot_lenses.append(Transform3D(Basis.IDENTITY, Vector3(fx + lx, 5.08, fz + lz)))
			lot_lights.append(Vector3(fx + lx, 4.95, fz + lz))
	_street_lights(parent, lot_lenses, lot_lights, Vector3(0.6, 0.03, 0.4), "RestAreaLighting")
	var pump_body := C.mat(Color(0.92, 0.92, 0.9), 0.5)
	var display := C.mat(Color(0.05, 0.09, 0.07), 0.4)
	for ix: float in [-5.5, 5.5]:
		C.box(parent, world, Vector3(fx + ix, 0.12, fz), Vector3(3.0, 0.12, 0.6), Vector3.ZERO, concrete, 0.8)
		for px: float in [-1.4, 1.4]:
			var at := Vector3(fx + ix + px, 0, fz)
			C.box(parent, world, at + Vector3(0, 0.55, 0), Vector3(0.38, 0.3, 0.25), Vector3.ZERO, metal, 0.6)
			C.box(parent, null, at + Vector3(0, 1.35, 0), Vector3(0.36, 0.5, 0.23), Vector3.ZERO, pump_body, 0.6, false)
			C.box(parent, null, at + Vector3(0, 1.88, 0), Vector3(0.38, 0.06, 0.25), Vector3.ZERO, navy, 0.6, false)
			for f: float in [-1.0, 1.0]:
				C.box(parent, null, at + Vector3(0, 1.5, f * 0.235), Vector3(0.22, 0.12, 0.01), Vector3.ZERO, display, 0.6, false)
		for ex: float in [-3.3, 3.3]:
			C.box(parent, world, Vector3(fx + ix + ex, 0.6, fz), Vector3(0.1, 0.6, 0.1), Vector3.ZERO, C.mat(Color(0.86, 0.68, 0.12), 0.6), 0.6)


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
			var in_village := c.x > VILLAGE.x + VILLAGE_MIN.x - size.x * 0.4 and c.x < VILLAGE.x + VILLAGE_MAX.x + size.x * 0.4 \
					and c.y > VILLAGE.z + VILLAGE_MIN.y - size.y * 0.4 and c.y < VILLAGE.z + VILLAGE_MAX.y + size.y * 0.4
			if not in_village and _loop_distance(c.x, c.y) > reach * 0.35 + 30.0 and not (c.x > SERVICE_START - 150 and c.x < SERVICE_END + 150 and absf(c.y + RADIUS) < 220):
				var r := rng.randf()
				var pick := 0
				var acc := 0.0
				for i in kinds.size():
					acc += float(kinds[i][2])
					if r <= acc:
						pick = i
						break
				C.quad(parent, Vector3(c.x, -0.032, c.y), size, mats[pick])
				# Hedgerow trees along one long and one short edge.
				for t in 7:
					if rng.randf() < 0.45:
						trees.append(Vector3(c.x - size.x * 0.5 + size.x * t / 6.0, 0, c.y - size.y * 0.5 - 3.0))
				for t in 4:
					if rng.randf() < 0.35:
						trees.append(Vector3(c.x + size.x * 0.5 + 3.0, 0, c.y - size.y * 0.5 + size.y * t / 3.0))
			z += cell.y
		x += cell.x
	_village(parent, world, trees, rng)


## Street village beyond the north-east bend: a main street past the church (the tower portal
## opens onto it) and a cross street, houses along both with front gardens, some farms with a
## barn behind, a walled churchyard with gravestones and field tracks out into the farmland.
static func _village(parent: Node3D, world: SBWorld, trees: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var village := preload("res://scripts/maps/village.gd").new()
	var plaster := C.noise_mat(Color(0.88, 0.85, 0.78), 0.05, 2.5, 0.92)
	var slate := C.noise_mat(Color(0.26, 0.26, 0.29), 0.1, 3.0, 0.8)
	var vc := VILLAGE
	# Church: nave with arched windows, buttresses and apse (as in Lindenau), west tower with a
	# four-sided spire.
	preload("res://scripts/map_builder.gd")._church_nave(parent, world, vc + Vector3(0, 0, 10.5), PI * 0.5, plaster, slate)
	# Tower in Lindenau's proportions (23 m to the cornice, 10 m spire) so it takes the same
	# details: plinth, slit windows, clocks, louvred belfry, cornice, ball, cross and weathercock.
	var builder := preload("res://scripts/map_builder.gd")
	C.box(parent, world, vc + Vector3(0, 11.5, 0), Vector3(2.6, 11.5, 2.6), Vector3.ZERO, plaster, 0.8)
	var spire := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 3.6
	cone.height = 10.0
	cone.radial_segments = 4
	spire.mesh = cone
	spire.material_override = slate
	spire.position = vc + Vector3(0, 28.0, 0)
	spire.rotation.y = PI * 0.25
	parent.add_child(spire)
	builder._church_tower_details(parent, vc, PI * 0.5, plaster)
	# Streets: the main street along x passes 12 m in front of the tower (portal side, -z); the
	# cross street runs along z 42 m east of the tower.
	var main_z := vc.z - 12.0
	var cross_x := vc.x + 42.0
	var main := PackedVector3Array()
	for k in 31: main.append(Vector3(vc.x + VILLAGE_MIN.x + 15.0 + k * (VILLAGE_MAX.x - VILLAGE_MIN.x - 30.0) / 30.0, 0, main_z))
	var cross := PackedVector3Array()
	for k in 25: cross.append(Vector3(cross_x, 0, vc.z + VILLAGE_MIN.y + 12.0 + k * (VILLAGE_MAX.y - VILLAGE_MIN.y - 24.0) / 24.0))
	var street := C.road_material(1, 6.0, 12.0, "village")
	parent.add_child(C.road_mesh(main, 3.0, street, false, 0.004))
	parent.add_child(C.road_mesh(cross, 3.0, street, false, 0.006))
	# Pavements with kerbs along both streets, open where the streets cross.
	var paving := C.noise_mat(Color(0.43, 0.42, 0.41), 0.10, 1.2, 0.9)
	var kerb := C.noise_mat(Color(0.55, 0.54, 0.52), 0.06, 2.0, 0.85)
	var gap := 3.0 + 1.6
	var x0 := main[0].x
	var x1 := main[main.size() - 1].x
	var z0 := cross[0].z
	var z1 := cross[cross.size() - 1].z
	for sgn: float in [-1.0, 1.0]:
		for span: Vector2 in [Vector2(x0, cross_x - gap), Vector2(cross_x + gap, x1)]:
			var mid := (span.x + span.y) * 0.5
			var half := (span.y - span.x) * 0.5
			C.box(parent, null, Vector3(mid, 0.07, main_z + sgn * 3.8), Vector3(half, 0.07, 0.8), Vector3.ZERO, paving, 0.9, false)
			C.box(parent, null, Vector3(mid, 0.08, main_z + sgn * 3.06), Vector3(half, 0.08, 0.08), Vector3.ZERO, kerb, 0.9, false)
		for span: Vector2 in [Vector2(z0, main_z - gap), Vector2(main_z + gap, z1)]:
			var mid := (span.x + span.y) * 0.5
			var half := (span.y - span.x) * 0.5
			C.box(parent, null, Vector3(cross_x + sgn * 3.8, 0.07, mid), Vector3(0.8, 0.07, half), Vector3.ZERO, paving, 0.9, false)
			C.box(parent, null, Vector3(cross_x + sgn * 3.06, 0.08, mid), Vector3(0.08, 0.08, half), Vector3.ZERO, kerb, 0.9, false)
	# Field tracks continue from the street ends into the farmland.
	var track := C.road_material(1, 3.2, 12.0, "dirt")
	for ends: Array in [[main[0], Vector3(-1, 0, 0)], [main[main.size() - 1], Vector3(1, 0, 0)],
			[cross[0], Vector3(0, 0, -1)], [cross[cross.size() - 1], Vector3(0, 0, 1)]]:
		var a: Vector3 = ends[0]
		var d: Vector3 = ends[1]
		var path := PackedVector3Array()
		for k in 12:
			var bend := Vector3(d.z, 0, -d.x) * sin(k * 0.35) * 4.0 * (k / 11.0)
			path.append(a + d * (k * 9.0) + bend)
		if _loop_distance(path[path.size() - 1].x, path[path.size() - 1].z) > 70.0:
			parent.add_child(C.road_mesh(path, 1.6, track, false, 0.0))
	# Churchyard: low stone wall round tower and nave, open to the street at the portal, and rows
	# of gravestones beside the nave.
	var stone := C.noise_mat(Color(0.56, 0.53, 0.48), 0.12, 3.0, 0.9)
	var yard_min := Vector2(vc.x - 13.0, vc.z - 7.0)
	var yard_max := Vector2(vc.x + 13.0, vc.z + 31.0)
	var wall := func(a: Vector2, b: Vector2) -> void:
		var mid := (a + b) * 0.5
		var half := Vector3(maxf(absf(b.x - a.x) * 0.5, 0.25), 0.55, maxf(absf(b.y - a.y) * 0.5, 0.25))
		C.box(parent, world, Vector3(mid.x, 0.55, mid.y), half, Vector3.ZERO, stone, 0.8)
		C.box(parent, null, Vector3(mid.x, 1.14, mid.y), half + Vector3(0.06, -0.51, 0.06), Vector3.ZERO, plaster, 0.8, false)
	wall.call(Vector2(yard_min.x, yard_min.y), Vector2(vc.x - 2.2, yard_min.y))
	wall.call(Vector2(vc.x + 2.2, yard_min.y), Vector2(yard_max.x, yard_min.y))
	wall.call(Vector2(yard_min.x, yard_max.y), Vector2(yard_max.x, yard_max.y))
	wall.call(Vector2(yard_min.x, yard_min.y), Vector2(yard_min.x, yard_max.y))
	wall.call(Vector2(yard_max.x, yard_min.y), Vector2(yard_max.x, yard_max.y))
	var grave_stone := C.noise_mat(Color(0.40, 0.39, 0.38), 0.15, 4.0, 0.85)
	var grave_bed := C.noise_mat(Color(0.22, 0.30, 0.16), 0.2, 3.0, 0.95)
	for side: float in [-1.0, 1.0]:
		for row in 2:
			for k in 6:
				if rng.randf() < 0.2: continue
				var gx := vc.x + side * (7.6 + row * 2.3)
				var gz := vc.z + 2.0 + k * 3.6 + rng.randf_range(-0.2, 0.2)
				var tall := rng.randf_range(0.7, 1.05)
				C.box(parent, null, Vector3(gx, tall * 0.5, gz), Vector3(0.09, tall * 0.5, rng.randf_range(0.28, 0.4)), Vector3(0, rng.randf_range(-0.04, 0.04), 0), grave_stone, 0.8, false)
				C.box(parent, null, Vector3(gx - side * 0.95, 0.08, gz), Vector3(0.85, 0.08, 0.45), Vector3.ZERO, grave_bed, 0.9, false)
	# Houses along both sides of both streets, eaves to the street, door facing it.
	var hedges: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	var pickets: Array[Transform3D] = []
	var church_box := Rect2(yard_min - Vector2(4, 4), yard_max - yard_min + Vector2(8, 8))
	var placed: Array[Vector3] = []
	var add_house := func(on: Vector3, facing: Vector3) -> void:
		# A third of the houses stand gable-end to the street (door then on the side).
		var gable := rng.randf() < 0.35
		var length := rng.randf_range(9.0, 11.0) if gable else rng.randf_range(10.0, 13.0)
		var width := rng.randf_range(7.5, 9.0)
		var depth := length if gable else width
		var p := on - facing * (4.6 + rng.randf_range(3.0, 4.5) + depth * 0.5)
		if church_box.has_point(Vector2(p.x, p.z)) or _loop_distance(p.x, p.z) < 75.0: return
		if placed.any(func(q: Vector3) -> bool: return q.distance_to(p) < 15.5): return
		var yaw := atan2(facing.x, facing.z) + (PI * 0.5 if gable else 0.0) + rng.randf_range(-0.04, 0.04)
		village.house(world, p, yaw, length, width, 1 + int(rng.randf() < 0.65), rng)
		placed.append(p)
		# Front garden boundary at the back of the pavement: hedge, picket fence or open.
		var frontage := (width if gable else length) + rng.randf_range(2.0, 5.0)
		var along := Vector3(facing.z, 0, -facing.x)
		var line := on - facing * 1.75
		var kind := rng.randf()
		if kind < 0.45:
			hedges.append(Transform3D(Basis(Vector3.UP, atan2(along.x, along.z)).scaled_local(Vector3(0.7, rng.randf_range(0.9, 1.3), frontage)), line - facing * 0.35 + Vector3.UP * 0.55))
		elif kind < 0.8:
			var rb := Basis(Vector3.UP, atan2(along.x, along.z))
			for h: float in [0.35, 0.8]:
				rails.append(Transform3D(rb.scaled_local(Vector3(0.04, 0.07, frontage)), line + Vector3.UP * h))
			var n := int(frontage / 0.14)
			for k in n:
				pickets.append(Transform3D(rb, line + along * (-frontage * 0.5 + (k + 0.5) * frontage / n) + Vector3.UP * 0.5))
		var basis := Basis(Vector3.UP, atan2(facing.x, facing.z))
		if rng.randf() < 0.35:
			# Farm: a barn across the yard behind the house.
			var barn := p + basis * Vector3(rng.randf_range(-3.0, 3.0), 0, -(depth * 0.5 + 9.5))
			if not church_box.has_point(Vector2(barn.x, barn.z)):
				village.house(world, barn, atan2(facing.x, facing.z) + PI * 0.5, rng.randf_range(9.0, 12.0), rng.randf_range(7.0, 8.5), 1, rng, true)
		if rng.randf() < 0.7:
			trees.append(p + basis * Vector3(rng.randf_range(-6.0, 6.0), 0, -(depth * 0.5 + rng.randf_range(16.0, 22.0))))
	for street_pts: Array in [[main, Vector3(1, 0, 0)], [cross, Vector3(0, 0, 1)]]:
		var pts: PackedVector3Array = street_pts[0]
		var along: Vector3 = street_pts[1]
		var normal := Vector3(along.z, 0, -along.x)
		var length_m := pts[0].distance_to(pts[pts.size() - 1])
		var slot := 6.0
		while slot < length_m - 6.0:
			var on := pts[0] + along * slot
			for sgn: float in [-1.0, 1.0]:
				if rng.randf() < 0.18: continue
				# Keep the crossing open.
				if street_pts[1] == Vector3(1, 0, 0) and absf(on.x - cross_x) < 12.0: continue
				if street_pts[1] == Vector3(0, 0, 1) and absf(on.z - main_z) < 12.0: continue
				add_house.call(on + normal * sgn * 3.0, -normal * sgn)
			slot += rng.randf_range(16.5, 19.5)
	var unit := BoxMesh.new()
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.17, 0.30, 0.12), 0.25, 1.5, 0.95), hedges)
	C.scatter_multimesh(parent, unit, C.mat(Color(0.86, 0.85, 0.80), 0.8), rails, false)
	var picket := BoxMesh.new()
	picket.size = Vector3(0.025, 1.0, 0.07)
	C.scatter_multimesh(parent, picket, C.mat(Color(0.86, 0.85, 0.80), 0.8), pickets, false)
	# Street lamps every ~34 m, alternating sides, at the kerb.
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for street_pts: Array in [[main, Vector3(1, 0, 0)], [cross, Vector3(0, 0, 1)]]:
		var pts: PackedVector3Array = street_pts[0]
		var along: Vector3 = street_pts[1]
		var normal := Vector3(along.z, 0, -along.x)
		var k := 0
		var slot := 10.0
		while slot < pts[0].distance_to(pts[pts.size() - 1]) - 5.0:
			var sgn := 1.0 if k % 2 == 0 else -1.0
			var base := pts[0] + along * slot + normal * sgn * 3.35
			if not church_box.has_point(Vector2(base.x, base.z)) or sgn > 0.0:
				poles.append(Transform3D(Basis.IDENTITY, base + Vector3.UP * 2.75))
				heads.append(Transform3D(Basis(Vector3.UP, atan2(normal.x, normal.z)), base - normal * sgn * 0.45 + Vector3.UP * 5.45))
			k += 1
			slot += 34.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.08
	pole.height = 5.5
	pole.radial_segments = 8
	C.scatter_multimesh(parent, pole, C.mat(Color(0.30, 0.31, 0.32), 0.6, 0.6), poles, false)
	var head := BoxMesh.new()
	head.size = Vector3(0.32, 0.16, 1.1)
	C.scatter_multimesh(parent, head, C.mat(Color(0.25, 0.26, 0.27), 0.5, 0.5), heads, false)
	# Lens under each head, lit at night with pooled spot lights (street_lighting.gd).
	var lenses: Array[Transform3D] = []
	var light_at := PackedVector3Array()
	for h in heads:
		lenses.append(Transform3D(h.basis, h.origin - Vector3.UP * 0.09))
		light_at.append(h.origin - Vector3.UP * 0.2)
	_street_lights(parent, lenses, light_at, Vector3(0.24, 0.03, 0.8), "VillageLighting")
	village.build(parent)


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
		C.quad(parent, Vector3(x, -0.039, -210), Vector2(410, 112), wheat, 0.07)
		C.quad(parent, Vector3(x - 45.0, -0.038, 230), Vector2(365, 142), gravel, -0.05)
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


## Rolling, partly wooded hills on the horizon beyond the countryside: the plain used to run
## flat to the edge of the world. Visual only; the fields and the wildlife fence end long before.
static func _backdrop_hills(parent: Node3D) -> void:
	var cell := 25.0
	var ox := -3100.0
	var oz := -2500.0
	var nx := 249
	var nz := 201
	var noise := FastNoiseLite.new()
	noise.seed = 4040
	noise.frequency = 0.0011
	noise.fractal_octaves = 4
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var trees: Array[Vector3] = []
	var conifers: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4041
	for ix in nx:
		for iz in nz:
			var x := ox + ix * cell
			var z := oz + iz * cell
			var out := maxf(absf(z) - 990.0, absf(x) - 2300.0)
			var rise := smoothstep(0.0, 520.0, out)
			var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var h := -0.6 if out <= 0.0 else rise * (45.0 + 140.0 * n) - 0.6 * (1.0 - smoothstep(0.0, 40.0, out))
			heights[ix * nz + iz] = h
			var wood := smoothstep(0.52, 0.62, n) * smoothstep(40.0, 200.0, out)
			colors[ix * nz + iz] = Color(0.66, 0.76, 0.50).lerp(Color(0.30, 0.38, 0.22), wood)
			if wood > 0.5 and rng.randf() < 0.55:
				var q := Vector3(x + rng.randf_range(-10, 10), h - 0.5, z + rng.randf_range(-10, 10))
				(conifers if rng.randf() < 0.6 else trees).append(q)
	C.terrain_tiles(parent, ox, oz, cell, nx, nz, heights, C.terrain_material("grass", 3.5, Color(0.73, 0.92, 0.66)), colors)
	V.plant(parent, "conifer", conifers, 4042, 1.0, 1.4, false, true)
	V.plant(parent, "broadleaf", trees, 4043, 1.0, 1.4, false, true)
