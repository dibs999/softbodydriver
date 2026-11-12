extends RefCounted
## Dunes, a sandstone plateau and a rally loop with a field station at the start.

const C := preload("res://scripts/maps/common.gd")
const ROCKS := preload("res://scripts/maps/rocks.gd")
const V := preload("res://scripts/maps/vegetation.gd")
static var _post_index := 250
static var _props: Array = []
static var _post_side := 1.0


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	_props.clear()
	var nx := 481
	var nz := 481
	var cell := 4.0
	var ox := -960.0
	var oz := -960.0
	var dunes := FastNoiseLite.new()
	dunes.seed = 11
	dunes.frequency = 0.004
	dunes.fractal_octaves = 3
	var ridges := FastNoiseLite.new()
	ridges.seed = 5
	ridges.frequency = 0.012
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var mesa := FastNoiseLite.new()
	mesa.seed = 23
	mesa.frequency = 0.0022
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var x := ox + ix * cell
			var z := oz + iz * cell
			var h := (dunes.get_noise_2d(x, z) * 0.5 + 0.5) * 19.0 + ridges.get_noise_2d(x, z) * 3.0
			var plateau := 1.0 - smoothstep(95.0, 300.0, Vector2(x + 260.0, z - 290.0).length())
			var m := mesa.get_noise_2d(x, z) + plateau * 0.58
			# Away from the rally loop (and the shortcut and mine road beside it) the rock rises as
			# buttes: a talus apron, a near-vertical cap-rock wall and a flat top. A soft ramp over
			# the whole range made every small outcrop a striped cone. Near the loop the old, gentler
			# profile keeps the graded track as it was. The loop is r(a) in polar coordinates, so the
			# radial distance to it is cheap.
			var a := atan2(z / 0.90, x)
			var loop_r := 596.0 + 106.0 * sin(2.0 * a + 0.4) + 46.0 * cos(5.0 * a)
			# The loop itself only samples the terrain along its centre line (then carves a 15 m
			# corridor); the shortcut to the mine swings up to 78 m out between loop points 23 and 96.
			var a_pos := fposmod(a, TAU)
			var near_shortcut := a_pos > 0.15 and a_pos < 0.9
			var keep_from := 110.0 if near_shortcut else 18.0
			var off_track := smoothstep(keep_from, keep_from + (80.0 if near_shortcut else 14.0), absf(Vector2(x, z / 0.90).length() - loop_r))
			if m > 0.33:
				var soft := 46.0 * smoothstep(0.38, 0.49, m)
				var butte := 11.0 * smoothstep(0.33, 0.40, m) + 35.0 * smoothstep(0.40, 0.415, m) + 3.0 * smoothstep(0.415, 0.6, m)
				h += lerpf(soft, butte, off_track)
			h += 65.0 * smoothstep(790.0, 950.0, maxf(absf(x), absf(z))) * (0.7 + 0.3 * ridges.get_noise_2d(x, z))
			heights[ix * nz + iz] = h

	# Dirt-track loop.
	var track := PackedVector3Array()
	var n_track := 720
	for i in n_track:
		var a := TAU * i / n_track
		var r := 596.0 + 106.0 * sin(2.0 * a + 0.4) + 46.0 * cos(5.0 * a)
		track.append(Vector3(cos(a) * r, 0, sin(a) * r * 0.90))
	var elev := PackedFloat32Array()
	elev.resize(n_track)
	for i in n_track:
		elev[i] = C.sample(heights, nx, nz, ox, oz, cell, track[i].x, track[i].z)
	for _it in 40:
		var e2 := elev.duplicate()
		for i in n_track:
			e2[i] = (elev[(i - 1 + n_track) % n_track] + elev[i] * 2.0 + elev[(i + 1) % n_track]) * 0.25
		elev = e2
	# Graded stage: where the loop crosses the mesa plateau edge the averaged terrain still had
	# +18 % / -28 % grades and a cliff-like crest that flipped cars. Limit the grade to 10 % (a road
	# cut / fill through the edge), forwards and backwards, then smooth the transitions.
	const MAX_GRADE := 0.10
	for _pass in 6:
		for direction: int in [1, -1]:
			for k in n_track:
				var i := k if direction == 1 else n_track - 1 - k
				var prev := (i - direction + n_track) % n_track
				var ds := Vector2(track[i].x - track[prev].x, track[i].z - track[prev].z).length()
				elev[i] = clampf(elev[i], elev[prev] - MAX_GRADE * ds, elev[prev] + MAX_GRADE * ds)
		var e3 := elev.duplicate()
		for i in n_track:
			e3[i] = (elev[(i - 1 + n_track) % n_track] + elev[i] * 2.0 + elev[(i + 1) % n_track]) * 0.25
		elev = e3
	# Two jump ramps on the track (bumps in the elevation profile).
	var jumps := [112, 463]
	for j: int in jumps:
		for k in range(-6, 7):
			var t := 1.0 - absf(k) / 6.0
			elev[(j + k) % n_track] += 2.2 * t * t if k <= 0 else 0.0
	for i in n_track:
		track[i].y = elev[i]
	var half_w := 6.0
	# Roadside stop: the flattest open stretch beside the loop, clear of the start, the jumps, the
	# shortcut and other parts of the loop.
	var best_cost := INF
	for i in range(150, n_track - 30, 6):
		if absi(i - 463) < 25:
			continue
		var d := Vector3(track[i + 1].x - track[i - 1].x, 0, track[i + 1].z - track[i - 1].z).normalized()
		for sgn: float in [1.0, -1.0]:
			var sd := Vector3(-d.z, 0, d.x) * sgn
			var cost := 0.0
			for a: float in [-32.0, 0.0, 32.0]:
				for c: float in [14.0, 32.0, 54.0]:
					var q := track[i] + d * a + sd * c
					cost = maxf(cost, absf(C.sample(heights, nx, nz, ox, oz, cell, q.x, q.z) - track[i].y))
			var centre := track[i] + sd * 32.0
			for j in range(0, n_track, 4):
				if absi(j - i) > 25 and absi(j - i) < n_track - 25 and Vector2(track[j].x - centre.x, track[j].z - centre.z).length() < 70.0:
					cost = INF
			if cost < best_cost:
				best_cost = cost
				_post_index = i
				_post_side = sgn
	var post_dir := Vector3(track[_post_index + 1].x - track[_post_index - 1].x, 0, track[_post_index + 1].z - track[_post_index - 1].z).normalized()
	var post_centre := track[_post_index] + Vector3(-post_dir.z, 0, post_dir.x) * (32.0 * _post_side)
	_post_zone = Vector2(post_centre.x, post_centre.z)
	C.carve_path(heights, nx, nz, ox, oz, cell, track, half_w + 1.6, 14.0, 0.08)
	var shortcut := PackedVector3Array()
	for i in range(23, 96):
		var t := float(i - 23) / 72.0
		var direction := track[i + 1] - track[i - 1]
		var side := Vector3(-direction.z, 0, direction.x).normalized()
		var offset := sin(PI * t)
		var p := track[i] + side * (78.0 * offset * offset)
		var sand_y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.z)
		p.y = lerpf(track[i].y, sand_y, offset * 0.72)
		shortcut.append(p)
	for _pass in 9:
		var smooth := shortcut.duplicate()
		for i in range(1, shortcut.size() - 1):
			smooth[i].y = (shortcut[i - 1].y + shortcut[i].y * 2.0 + shortcut[i + 1].y) * 0.25
		shortcut = smooth
	C.carve_path(heights, nx, nz, ox, oz, cell, shortcut, 5.0, 11.0, 0.08, false)
	# The pistes are drawn 4-5 cm above the sand; the physics ground is raised under them by the
	# same amount so the wheels roll on the drawn surface instead of sinking into it.
	var physical := C.raise_under_roads(heights, nx, nz, ox, oz, cell, [
		{"points": track, "half_w": half_w, "lift": 0.052, "closed": true},
		{"points": shortcut, "half_w": 3.6, "lift": 0.043}])
	world.add_heightfield(ox, oz, cell, nx, nz, physical, 0.82)

	# Vertex colours: sand on flats, red rock on steep slopes and mesa walls.
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var sand := Color(1.0, 0.89, 0.69)
	var rock := Color(0.76, 0.45, 0.30)
	# Ground variety: dark desert pavement (varnished gravel), red soil and pale dry washes.
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = 19
	patch_noise.frequency = 0.012
	patch_noise.fractal_octaves = 3
	var wash_noise := FastNoiseLite.new()
	wash_noise.seed = 23
	wash_noise.frequency = 0.006
	wash_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	wash_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	for ix in nx:
		for iz in nz:
			var i := ix * nz + iz
			var hx := heights[mini(ix + 1, nx - 1) * nz + iz] - heights[maxi(ix - 1, 0) * nz + iz]
			var hz := heights[ix * nz + mini(iz + 1, nz - 1)] - heights[ix * nz + maxi(iz - 1, 0)]
			var slope := Vector2(hx, hz).length() / (2.0 * cell)
			var band := 0.5 + 0.5 * sin(heights[i] * 0.95 + 0.35 * sin(ix * 0.04))
			var cliff := rock.lerp(Color(0.86, 0.58, 0.41), band * 0.52)
			var dust := sand.lerp(Color(0.88, 0.72, 0.53), 0.28 + 0.22 * sin(ix * 0.022 + iz * 0.036))
			var wx := ox + ix * cell
			var wz := oz + iz * cell
			var pn := patch_noise.get_noise_2d(wx, wz)
			dust = dust.lerp(Color(0.70, 0.56, 0.43), smoothstep(0.18, 0.45, pn) * 0.75)      # desert pavement
			dust = dust.lerp(Color(1.0, 0.70, 0.52), smoothstep(0.20, 0.5, -pn) * 0.55)       # red soil
			dust = dust.lerp(Color(1.08, 1.0, 0.86), (1.0 - smoothstep(0.0, 0.06, wash_noise.get_noise_2d(wx, wz) + 0.5)) * 0.6)  # washes
			colors[i] = dust.lerp(cliff, smoothstep(0.17, 0.73, slope)).darkened(clampf(heights[i] / 330.0, 0.0, 0.22))
	var terrain_mat := C.terrain_material("gravel", 5.0, Color(0.80, 0.72, 0.62))
	terrain_mat.set_shader_parameter("has_strata", true)
	terrain_mat.set_shader_parameter("slope_tint", Color(1.0, 1.0, 1.0))
	C.terrain_tiles(parent, ox, oz, cell, nx, nz, heights, terrain_mat, colors)
	var ground_height := func(x: float, z: float) -> float:
		return C.sample(heights, nx, nz, ox, oz, cell, x, z)
	var road_mat := C.road_material(2, half_w * 2.0, 12.0, "desert")
	var shortcut_mat := C.road_material(2, 7.2, 12.0, "desert")
	for m: ShaderMaterial in [road_mat, shortcut_mat]:
		m.set_shader_parameter("ground_color", Color(0.74, 0.62, 0.47))
	parent.add_child(C.road_mesh(track, half_w, road_mat, true, 0.052, 12.0, ground_height))
	parent.add_child(C.road_mesh(shortcut, 3.6, shortcut_mat, false, 0.043, 12.0, ground_height))
	var mine := _mine(parent, world, shortcut, ground_height)

	# Boulders (colliding) and cacti / shrubs (visual).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var rock_mat := ROCKS.material()
	var boulders: Array[Transform3D] = []
	for i in 340:
		var p := Vector2(rng.randf_range(-855, 855), rng.randf_range(-855, 855))
		if _near_track(p, track, 19.0) or _near_track(p, shortcut, 16.0, false) or p.distance_to(Vector2(track[0].x, track[0].z)) < 45.0:
			continue
		var s := rng.randf_range(1.4, 6.8)
		var y: float = ground_height.call(p.x, p.y)
		var base := Vector3(p.x, y + s * 0.15, p.y)
		var yaw := rng.randf() * TAU
		boulders.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(1.0, 0.65, 0.78) * s), base))
		if s > 3.3:
			world.add_box(base, Vector3(0.36, 0.24, 0.28) * s, Vector3(0, yaw, 0), 0.7)
	for i in range(7, n_track, 17):
		# Clusters give the course visible scale without cluttering the driving line.
		var tangent := track[(i + 1) % n_track] - track[i - 1]
		var forward := Vector3(tangent.x, 0, tangent.z).normalized()
		var side := Vector3(-forward.z, 0, forward.x) * (-1.0 if i % 2 == 0 else 1.0)
		for _stone in rng.randi_range(3, 6):
			var p := track[i] + side * rng.randf_range(13.0, 27.0) + forward * rng.randf_range(-6.0, 6.0)
			if _near_track(Vector2(p.x, p.z), shortcut, 10.0, false):
				continue
			var size := rng.randf_range(0.9, 5.5)
			p.y = ground_height.call(p.x, p.z) + size * 0.19
			var yaw := rng.randf() * TAU
			boulders.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(1.0, 0.76, 0.82) * size), p))
			if size > 3.8:
				world.add_box(p, Vector3(0.35, 0.28, 0.28) * size, Vector3(0, yaw, 0), 0.7)
	# Four rock shapes; the large ones cast shadows.
	var by_variant: Array = [[], [], [], []]
	for k in boulders.size():
		by_variant[k % 4].append(boulders[k])
	for v in 4:
		var batch: Array[Transform3D] = []
		batch.assign(by_variant[v])
		C.scatter_multimesh(parent, ROCKS.mesh(v), rock_mat, batch, true)
	var cactus := _saguaro_mesh()
	var xfs: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	for i in 420:
		var p := Vector2(rng.randf_range(-825, 825), rng.randf_range(-825, 825))
		if _near_track(p, track, 10.0) or _near_track(p, shortcut, 8.0, false):
			continue
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		var s := rng.randf_range(0.6, 1.3)
		var facing := Basis(Vector3.UP, i * 2.4).scaled_local(Vector3.ONE * s)
		var stalk := Transform3D(facing, Vector3(p.x, y + 1.4 * s, p.y))
		xfs.append(stalk)
		_add_arms(arms, stalk, 1 if i % 3 == 0 else 2, rng)
	for i in range(4, n_track, 13):
		var tangent := track[(i + 1) % n_track] - track[i - 1]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		var p := track[i] + side * (-1.0 if i % 2 == 0 else 1.0) * rng.randf_range(11.0, 18.0)
		if _near_track(Vector2(p.x, p.z), shortcut, 6.0, false):
			continue
		p.y = ground_height.call(p.x, p.z)
		var stalk := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(Vector3.ONE * 1.7), p + Vector3.UP * 1.4 * 1.7)
		xfs.append(stalk)
		_add_arms(arms, stalk, 1 + rng.randi() % 2, rng)
	# More saguaros where the track shows them: 12-70 m to either side.
	for i in range(0, n_track, 2):
		if rng.randf() > 0.55: continue
		var tangent := track[(i + 1) % n_track] - track[(i - 1 + n_track) % n_track]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		var p := track[i] + side * (-1.0 if rng.randf() < 0.5 else 1.0) * rng.randf_range(12.0, 70.0)
		if _near_track(Vector2(p.x, p.z), track, 10.0) or _near_track(Vector2(p.x, p.z), shortcut, 7.0, false):
			continue
		p.y = ground_height.call(p.x, p.z)
		# Young saguaros are a single column; arms only grow on old, tall ones (5 m and more).
		var armed := rng.randf() < 0.6
		var s := rng.randf_range(1.5, 2.6) if armed else rng.randf_range(0.5, 1.1)
		var stalk := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(Vector3.ONE * s), p + Vector3.UP * 1.4 * s)
		xfs.append(stalk)
		if armed:
			_add_arms(arms, stalk, 1 + rng.randi() % 3, rng)
		if s > 0.8:
			world.add_box(p + Vector3.UP * 1.4 * s, Vector3(0.22, 1.4 * s, 0.22) * s, Vector3.ZERO, 0.6)
	# Dusty grey-green, darker in the grooves between the ribs (vertex colour).
	var cactus_mat := C.noise_mat(Color(0.36, 0.45, 0.29), 0.10, 2.5, 0.8, 0.05, true)
	cactus_mat.vertex_color_is_srgb = true
	C.scatter_multimesh(parent, cactus, cactus_mat, xfs)
	C.scatter_multimesh(parent, _saguaro_arm_mesh(0.9), cactus_mat, arms, false)
	var sx: Array[Vector3] = []
	for i in 680:
		var p := Vector2(rng.randf_range(-840, 840), rng.randf_range(-840, 840))
		if _near_track(p, track, 8.0) or _near_track(p, shortcut, 6.0, false):
			continue
		sx.append(Vector3(p.x, C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y), p.y))
	# Dense scrub in sight of the track, thinning out with distance.
	for i in 1400:
		var k := rng.randi() % n_track
		var tangent := track[(k + 1) % n_track] - track[(k - 1 + n_track) % n_track]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		var dist := 9.0 + pow(rng.randf(), 1.8) * 90.0
		var p := track[k] + side * (-1.0 if rng.randf() < 0.5 else 1.0) * dist
		if _near_track(Vector2(p.x, p.z), shortcut, 6.0, false) or _near_track(Vector2(p.x, p.z), track, 7.5):
			continue
		sx.append(Vector3(p.x, ground_height.call(p.x, p.z), p.z))
	V.plant(parent, "dry_shrub", sx, 680, 0.45, 1.1, false)
	# Weathered boulders along the track, a telegraph line and chevrons on the sharp bends.
	var R := preload("res://scripts/maps/roadside.gd")
	var rocks: Array[Transform3D] = []
	for i in 260:
		var k := rng.randi() % n_track
		var tangent := track[(k + 1) % n_track] - track[(k - 1 + n_track) % n_track]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		var p := track[k] + side * (-1.0 if rng.randf() < 0.5 else 1.0) * rng.randf_range(10.0, 60.0)
		if _near_track(Vector2(p.x, p.z), track, 9.0) or _near_track(Vector2(p.x, p.z), shortcut, 7.0, false):
			continue
		p.y = ground_height.call(p.x, p.z)
		var sc := rng.randf_range(0.4, 1.4) * (2.2 if rng.randf() < 0.12 else 1.0)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.6, 1.0), sc * rng.randf_range(0.8, 1.3))), p))
	R.boulders(parent, world, rocks)
	R.bend_signs(parent, track, half_w, ground_height, true, 0.30)
	var clear := func(p: Vector3) -> bool:
		return not _near_track(Vector2(p.x, p.z), shortcut, 9.0, false) and Vector2(p.x - track[6].x, p.z - track[6].z).length() > 45.0
	R.utility_line(parent, world, track, -18.0, ground_height, true, 55.0, clear)
	var pebble := SphereMesh.new()
	pebble.radius = 0.55
	pebble.height = 0.45
	pebble.radial_segments = 7
	pebble.rings = 3
	var pebbles: Array[Transform3D] = []
	for i in range(0, n_track, 3):
		var d := (track[(i + 1) % n_track] - track[i]).normalized()
		var side := Vector3(-d.z, 0, d.x).normalized()
		for sign: float in [-1.0, 1.0]:
			var p := track[i] + side * sign * (half_w + rng.randf_range(1.4, 5.0))
			p.y = C.sample(heights, nx, nz, ox, oz, cell, p.x, p.z) + 0.04
			var scale := rng.randf_range(0.4, 1.35)
			pebbles.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled_local(Vector3.ONE * scale), p))
	C.scatter_multimesh(parent, pebble, C.mat(Color(0.48, 0.3, 0.19)), pebbles, false)
	_rally_station(parent, world, track, ground_height)
	var post: Vector3 = _trading_post(parent, world, track, _post_index, ground_height)
	var marker_bases: Array[Transform3D] = []
	for i in range(0, n_track, 20):
		var direction := (track[(i + 1) % n_track] - track[i]).normalized()
		var side := Vector3(-direction.z, 0, direction.x).normalized()
		for edge: float in [-1.0, 1.0]:
			var p := track[i] + side * edge * 7.2
			p.y = ground_height.call(p.x, p.z)
			marker_bases.append(Transform3D(Basis(Vector3.UP, atan2(-direction.z, direction.x)), p))
	C.roadside_markers(parent, marker_bases)

	var speeds := C.speeds_from_curvature(track, 24.0, 12.0, 50.0)
	for j: int in jumps:
		for k in range(-12, 3):
			speeds[(j + k) % n_track] = minf(speeds[(j + k) % n_track], 17.0)
	return {"props": _props.duplicate(), "spawns": [C.car_xform(track[0], track[1] - track[0]), C.car_xform(track[n_track - 8], track[n_track - 7] - track[n_track - 8])],
		"waypoints": track, "speeds": speeds,
		"map_paths": [C.closed_route(track), shortcut],
		"map_places": [{"name": "Rallyelager Red Mesa", "position": track[6]}, {"name": "Raststätte Coyote Flats", "position": post}, {"name": "Alte Mine", "position": mine},
			{"name": "Dünensprung", "position": track[jumps[0]]}, {"name": "Schluchtsprung", "position": track[jumps[1]]}],
		"ai_routes": _traffic_routes(track, speeds, shortcut),
		"environment": {"sky_top": Color(0.32, 0.5, 0.78), "horizon": Color(0.92, 0.82, 0.68), "fog": Color(0.93, 0.83, 0.68),
			"fog_density": 0.00065, "sun": Vector3(-43, -120, 0), "sun_energy": 1.5, "sun_color": Color(1.0, 0.93, 0.80)}}


## Traffic: two cars on the rally loop as before, a third that takes the shortcut through the
## dunes (same direction as the loop traffic) and rejoins the loop after it.
static func _traffic_routes(track: PackedVector3Array, speeds: PackedFloat32Array, shortcut: PackedVector3Array) -> Array:
	var n := track.size()
	var via := PackedVector3Array()
	for i in range(0, 22): via.append(track[i])
	via.append_array(shortcut)
	for i in range(97, n): via.append(track[i])
	var via_speeds := C.speeds_from_curvature(via, 22.0, 11.0, 50.0)
	# Gently over the joins, where the shortcut leaves and rejoins the loop.
	var join_b := 22 + shortcut.size()
	for i in via.size():
		if absi(i - 22) < 5 or absi(i - join_b) < 5:
			via_speeds[i] = minf(via_speeds[i], 13.0)
	return [
		{"waypoints": track, "speeds": speeds, "spawn": C.car_xform(track[200], track[201] - track[200])},
		{"waypoints": track, "speeds": speeds, "spawn": C.car_xform(track[540], track[541] - track[540])},
		{"waypoints": via, "speeds": via_speeds, "spawn": C.car_xform(shortcut[shortcut.size() / 2], shortcut[shortcut.size() / 2 + 1] - shortcut[shortcut.size() / 2])},
	]


## Elbow arms on a saguaro trunk (`stalk`: trunk centre, scaled): at 45-70 % of its height, spread
## round the trunk, a little smaller each.
static func _add_arms(arms: Array[Transform3D], stalk: Transform3D, count: int, rng: RandomNumberGenerator) -> void:
	var start := rng.randf() * TAU
	for k in count:
		var yaw := start + TAU * k / count + rng.randf_range(-0.5, 0.5)
		var h := rng.randf_range(-0.3, 0.3)
		var size := rng.randf_range(0.85, 1.15)
		arms.append(stalk * Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3.ONE * size), Vector3(0, h, 0)))


## Saguaro: ribbed column with a rounded crown.
static func _saguaro_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	var rows: Array = []
	var profile: Array = []
	for k in 12:
		var y := -1.5 + 2.6 * k / 11.0
		profile.append(Vector2(0.23 - 0.03 * (y + 1.5) / 2.6, y))
	for k in range(1, 6):
		var a := PI * 0.5 * k / 5.0
		profile.append(Vector2(0.20 * cos(a), 1.1 + 0.20 * sin(a) * 1.4))
	for pr: Vector2 in profile:
		var row: Array = []
		for j in seg + 1:
			var t := TAU * j / seg
			var rib := 1.0 + 0.09 * cos(t * 12.0)
			row.append(Vector3(cos(t) * pr.x * rib, pr.y, sin(t) * pr.x * rib))
		rows.append(row)
	_ribbed_strip(st, rows, seg)
	st.generate_normals()
	return st.commit()


## Faces between consecutive rings, coloured by the rib: dusty grey-green crests, dark grooves.
static func _ribbed_strip(st: SurfaceTool, rows: Array, seg: int) -> void:
	for i in rows.size() - 1:
		for j in seg:
			var corners := [[i, j], [i + 1, j + 1], [i, j + 1], [i, j], [i + 1, j], [i + 1, j + 1]]
			for c: Array in corners:
				var t := TAU * float(c[1]) / seg
				var crest := 0.5 + 0.5 * cos(t * 12.0)
				st.set_color(Color(0.46, 0.53, 0.39) * (0.62 + 0.38 * crest))
				st.add_vertex(rows[c[0]][c[1]])


## Saguaro arm in its local frame: grows out along +x from inside the trunk, bends up through an
## elbow and rises as a ribbed column with a rounded tip.
static func _saguaro_arm_mesh(rise: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var r := 0.15
	var bend := 0.28
	var path: Array = []   # [centre, tangent, radius]
	path.append([Vector3(0.05, 0, 0), Vector3.RIGHT, r * 0.95])
	path.append([Vector3(0.30, 0, 0), Vector3.RIGHT, r])
	for k in range(1, 7):
		var a := PI * 0.5 * k / 6.0
		path.append([Vector3(0.30 + bend * sin(a), bend * (1.0 - cos(a)), 0), Vector3(cos(a), sin(a), 0), r])
	var top := 0.30 + bend
	for k in range(1, 5):
		path.append([Vector3(top, bend + rise * k / 4.0, 0), Vector3.UP, r * (1.0 - 0.06 * k / 4.0)])
	for k in range(1, 5):
		var a := PI * 0.5 * k / 4.0
		path.append([Vector3(top, bend + rise + r * 0.9 * sin(a), 0), Vector3.UP, r * 0.94 * cos(a) + 0.005])
	var rows: Array = []
	for pnt: Array in path:
		var centre: Vector3 = pnt[0]
		var tangent: Vector3 = pnt[1]
		var normal := tangent.cross(Vector3.BACK).normalized()
		var row: Array = []
		for j in seg + 1:
			var t := TAU * j / seg
			var rib := 1.0 + 0.09 * cos(t * 12.0)
			row.append(centre + (normal * cos(t) + Vector3.BACK * sin(t)) * float(pnt[2]) * rib)
		rows.append(row)
	_ribbed_strip(st, rows, seg)
	st.generate_normals()
	return st.commit()


static var _post_zone := Vector2(INF, INF)
static func _near_track(p: Vector2, track: PackedVector3Array, dist: float, closed := true) -> bool:
	if p.distance_to(_post_zone) < 50.0:
		return true
	for j in (track.size() if closed else track.size() - 1):
		var a := Vector2(track[j].x, track[j].z)
		var next := track[(j + 1) % track.size()]
		if p.distance_squared_to(a) > (dist + 10.0) * (dist + 10.0):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, a, Vector2(next.x, next.z))
		if p.distance_squared_to(closest) < dist * dist:
			return true
	return false


static func _mine(parent: Node3D, world: SBWorld, path: PackedVector3Array, height: Callable) -> Vector3:
	var index := path.size() / 2
	var track_point := path[index]
	var tangent := path[index + 1] - path[index - 1]
	var forward := Vector3(tangent.x, 0, tangent.z).normalized()
	var side := Vector3(-forward.z, 0, forward.x)
	var yaw := atan2(-forward.z, forward.x)
	var rotation := Vector3(0, yaw, 0)
	var p := track_point + side * 18.5
	p.y = height.call(p.x, p.z)
	var iron := C.mat(Color(0.38, 0.22, 0.15), 0.76, 0.3)
	var dark := C.mat(Color(0.12, 0.11, 0.10), 0.74)
	var wood := C.mat(Color(0.47, 0.32, 0.18), 0.84)
	for distance: float in [-8.0, 0.0, 8.0]:
		var post := p + forward * distance
		var ground: float = height.call(post.x, post.z)
		C.box(parent, world, Vector3(post.x, ground + 2.25, post.z), Vector3(0.25, 2.25, 0.24), rotation, wood, 0.75)
	C.box(parent, world, p + side * 2.5 + Vector3.UP * 4.35, Vector3(9.4, 0.2, 3.8), rotation, iron, 0.75, false)
	C.box(parent, world, p + side * 5.7 + Vector3.UP * 1.6, Vector3(8.6, 1.8, 0.23), rotation, dark)
	for slot in 3:
		var crate := p + forward * (-5.0 + slot * 3.4) + side * 3.2
		crate.y = float(height.call(crate.x, crate.z)) + 0.66
		C.box(parent, world, crate, Vector3(1.1, 0.66, 0.88), rotation, wood)
	# Two rusting wrecks left behind the yard, sat down on flat tyres and leaning, and stacks of
	# scrap tyres by the shed.
	var wrecks: Array[Transform3D] = []
	for k in 2:
		var w := p + side * (15.5 + 3.5 * k) + forward * (-7.0 + 12.0 * k)
		w.y = float(height.call(w.x, w.z)) - 0.12
		var b := Basis(Vector3.UP, yaw + 0.6 + 1.9 * k).rotated(forward, 0.05 - 0.09 * k).rotated(side, 0.03)
		wrecks.append(Transform3D(b, w))
	preload("res://scripts/maps/parked_cars.gd").place(parent, world, wrecks, 77,
		[Color(0.16, 0.07, 0.03), Color(0.22, 0.10, 0.04), Color(0.14, 0.10, 0.07)],
		["res://models/rubble/sedan.glb", "res://models/rubble/suv_4x4.glb"])   # no light bar on a wreck
	var tyre := TorusMesh.new()
	tyre.inner_radius = 0.2
	tyre.outer_radius = 0.33
	tyre.rings = 18
	tyre.ring_segments = 8
	var stacks: Array[Transform3D] = []
	for k in 2:
		var base := p + forward * (9.5 + 1.0 * k) + side * (1.0 + 0.9 * k)
		var gy: float = height.call(base.x, base.z)
		for level in 3 + k:
			stacks.append(Transform3D(Basis(Vector3.UP, level * 0.7), Vector3(base.x, gy + 0.065 + level * 0.13, base.z) + Vector3(0.03 * level, 0, 0)))
		world.add_box(Vector3(base.x, gy + 0.3, base.z), Vector3(0.33, 0.3, 0.33), Vector3.ZERO, 0.8)
	C.scatter_multimesh(parent, tyre, C.mat(Color(0.06, 0.06, 0.06), 0.95), stacks)
	var sign := track_point + side * 6.1
	sign.y = float(height.call(sign.x, sign.z))
	C.box(parent, world, sign + Vector3.UP * 0.93, Vector3(0.09, 0.93, 0.09), rotation, iron)
	C.box(parent, world, sign + Vector3.UP * 1.89, Vector3(0.11, 0.37, 1.6), rotation, wood, 0.7, false)
	C.label3d(parent, "ALTE MINE", sign + Vector3.UP * 1.89 - forward * 0.12, yaw - PI * 0.5, 0.46)
	return p


static func _rally_station(parent: Node3D, world: SBWorld, track: PackedVector3Array, height: Callable) -> void:
	var point := track[6]
	var heading := Vector3(track[7].x - point.x, 0, track[7].z - point.z).normalized()
	var side := Vector3(-heading.z, 0, heading.x)
	var yaw := atan2(-heading.z, heading.x)
	var rotation := Vector3(0, yaw, 0)
	var steel := C.mat(Color(0.19, 0.23, 0.25), 0.62)
	var amber := C.mat(Color(0.87, 0.48, 0.15), 0.62)
	var shade := C.mat(Color(0.58, 0.35, 0.23), 0.82)
	for edge: float in [-8.3, 8.3]:
		var foot := point + side * edge
		var base: float = height.call(foot.x, foot.z)
		var half := maxf(1.0, (point.y + 4.5 - base) * 0.5)
		foot.y = base + half
		C.box(parent, world, foot, Vector3(0.20, half, 0.20), rotation, steel, 0.65)
	var beam := point + Vector3.UP * 4.45
	C.box(parent, world, beam, Vector3(0.23, 0.20, 8.5), rotation, steel)
	C.box(parent, world, beam + Vector3.UP * 0.39, Vector3(0.27, 0.44, 3.9), rotation, amber, 0.8, false)
	C.label3d(parent, "RED MESA   /   RALLY", beam + Vector3.UP * 0.39 - heading * 0.30, yaw - PI * 0.5, 0.66)
	for stall in 3:
		var p := point + side * 17.0 + heading * (5.0 + stall * 8.0)
		p.y = height.call(p.x, p.z)
		for side_sign: float in [-1.0, 1.0]:
			var post := p + side * side_sign * 2.8
			var base: float = height.call(post.x, post.z)
			var half := maxf(0.4, (p.y + 3.1 - base) * 0.5)
			post.y = base + half
			C.box(parent, world, post, Vector3(0.12, half, 0.12), rotation, steel, 0.6)
		C.box(parent, world, p + Vector3.UP * 3.1, Vector3(3.9, 0.13, 3.2), rotation, shade, 0.75, false)


## Roadside stop beside the rally loop: a levelled gravel pad with a petrol canopy and pumps, a
## diner with a pole sign, a motel row with a covered walkway and a water tower behind it.
static func _trading_post(parent: Node3D, world: SBWorld, track: PackedVector3Array, index: int, height: Callable) -> Vector3:
	var n := track.size()
	var point := track[index]
	var heading := Vector3(track[(index + 1) % n].x - track[index - 1].x, 0, track[(index + 1) % n].z - track[index - 1].z).normalized()
	var side := Vector3(-heading.z, 0, heading.x) * _post_side
	var yaw := atan2(-heading.z, heading.x)
	var rot := Vector3(0, yaw, 0)
	var basis := Basis(Vector3.UP, yaw)
	var stucco := C.noise_mat(Color(0.83, 0.70, 0.55), 0.08, 2.0, 0.9)
	var trim := C.mat(Color(0.55, 0.20, 0.14), 0.7)
	var steel := C.mat(Color(0.75, 0.76, 0.77), 0.4, 0.7)
	var dark := C.mat(Color(0.12, 0.12, 0.13), 0.6)
	var glass := C.mat(Color(0.20, 0.28, 0.32), 0.1, 0.4)
	var gravel := C.surface_material("gravel", 2.2, Color(0.86, 0.74, 0.60))
	var white := C.mat(Color(0.92, 0.91, 0.88), 0.6)
	var y := point.y
	var at := func(along: float, across: float, up: float) -> Vector3:
		return Vector3(point.x, y + up, point.z) + heading * along + side * across
	# Label3D yaw that makes text read from `dir` (the label faces along its local +z).
	var face := func(dir: Vector3) -> float: return atan2(dir.x, dir.z)
	var lit_panel := StandardMaterial3D.new()
	lit_panel.albedo_color = Color(0.05, 0.08, 0.06)
	lit_panel.emission_enabled = true
	lit_panel.emission = Color(0.35, 0.95, 0.55)
	lit_panel.emission_energy_multiplier = 0.3
	var yellow := C.mat(Color(0.86, 0.68, 0.12), 0.6)
	var hose_mat := C.mat(Color(0.06, 0.06, 0.06), 0.7)
	# Level pad from the verge outwards (its body reaches down into the sand).
	C.box(parent, world, at.call(0.0, 30.0, -1.48), Vector3(34.0, 1.5, 20.0), rot, gravel, 0.9)
	# Petrol canopy with two pump islands.
	for a: float in [-7.0, 7.0]:
		for c: float in [16.0, 26.0]:
			C.box(parent, world, at.call(a, c, 2.6), Vector3(0.22, 2.6, 0.22), rot, steel, 0.6)
	C.box(parent, world, at.call(0.0, 21.0, 5.35), Vector3(9.0, 0.25, 7.0), rot, white, 0.8, false)
	C.box(parent, world, at.call(0.0, 21.0, 5.0), Vector3(9.05, 0.45, 7.05), rot, trim, 0.8, false)
	# Canopy fascia lettering on both long sides.
	for sgn: float in [-1.0, 1.0]:
		C.label3d(parent, "COYOTE  FUEL", at.call(0.0, 21.0 + sgn * 7.12, 5.0), face.call(side * sgn), 0.62, Color(0.96, 0.93, 0.86))
	for c: float in [18.5, 23.5]:
		C.box(parent, world, at.call(0.0, c, 0.12), Vector3(3.2, 0.12, 0.6), rot, C.mat(Color(0.6, 0.6, 0.58)), 0.8)
		# Yellow crash bollards at both island ends.
		for a: float in [-3.5, 3.5]:
			C.box(parent, world, at.call(a, c, 0.6), Vector3(0.1, 0.6, 0.1), rot, yellow, 0.6)
		for a: float in [-1.8, 1.8]:
			# Dispenser: grey cabinet, white body with a red band, lit price displays on both
			# faces, nozzles in holsters at the ends with hoses down to the cabinet.
			C.box(parent, world, at.call(a, c, 0.6), Vector3(0.42, 0.36, 0.26), rot, C.mat(Color(0.42, 0.43, 0.44), 0.6, 0.3), 0.6)
			C.box(parent, null, at.call(a, c, 1.45), Vector3(0.40, 0.5, 0.24), rot, white, 0.6, false)
			C.box(parent, null, at.call(a, c, 1.1), Vector3(0.405, 0.07, 0.245), rot, trim, 0.6, false)
			C.box(parent, null, at.call(a, c, 2.02), Vector3(0.42, 0.08, 0.26), rot, trim, 0.6, false)
			for f: float in [-1.0, 1.0]:
				C.box(parent, null, at.call(a, c + f * 0.245, 1.55), Vector3(0.24, 0.13, 0.01), rot, lit_panel, 0.6, false)
				C.label3d(parent, "3.49", at.call(a, c + f * 0.26, 1.55), face.call(side * f), 0.16, Color(0.6, 1.0, 0.7))
			for e: float in [-1.0, 1.0]:
				C.box(parent, null, at.call(a + e * 0.44, c, 1.35), Vector3(0.04, 0.14, 0.07), rot, dark, 0.6, false)
				C.box(parent, null, at.call(a + e * 0.47, c, 1.42), Vector3(0.03, 0.03, 0.10), rot, dark, 0.6, false)
				C.box(parent, null, at.call(a + e * 0.46, c, 0.95), Vector3(0.018, 0.42, 0.018), rot, hose_mat, 0.6, false)
	# A cluster of oil drums on the pad by the diner's end wall (where the pad is clear of dunes).
	for k in 5:
		var d: Vector3 = at.call(-31.0 + (k % 3) * 0.62, 31.5 + (k / 3) * 0.62, 0.03)
		_props.append({"kind": "barrel", "position": d})
	for k in 2:
		_props.append({"kind": "barrel", "position": at.call(-31.0 + k * 0.62, 32.74, 0.03)})
	# Diner: stucco box, window band, door, flat roof with a parapet, pole sign at the road.
	var diner: Vector3 = at.call(-20.0, 34.0, 2.2)
	C.box(parent, world, diner, Vector3(8.0, 2.2, 5.0), rot, stucco, 0.8)
	C.box(parent, world, diner + Vector3.UP * 2.35, Vector3(8.2, 0.25, 5.2), rot, trim, 0.8, false)
	# Window band towards the road: glass with aluminium mullions, sill and header, a striped
	# awning over it, a glass door with a push bar.
	var front := diner - side * 5.0
	var alu := C.mat(Color(0.78, 0.79, 0.8), 0.35, 0.8)
	var diner_glass := C.mat(Color(0.16, 0.22, 0.25), 0.06, 0.5)
	C.box(parent, null, front - side * 0.02 + Vector3.UP * 0.2, Vector3(6.4, 0.75, 0.03), rot, diner_glass, 0.6, false)
	for k in 9:
		C.box(parent, null, front - side * 0.05 + heading * (-6.4 + k * 1.6) + Vector3.UP * 0.2, Vector3(0.04, 0.78, 0.03), rot, alu, 0.6, false)
	C.box(parent, null, front - side * 0.1 + Vector3.UP * -0.6, Vector3(6.5, 0.06, 0.12), rot, alu, 0.6, false)
	C.box(parent, null, front - side * 0.06 + Vector3.UP * 0.98, Vector3(6.45, 0.05, 0.06), rot, alu, 0.6, false)
	var stripe_a := C.mat(Color(0.62, 0.16, 0.12), 0.8)
	var stripe_b := C.mat(Color(0.93, 0.91, 0.86), 0.8)
	for k in 16:
		var along := -6.6 + k * 0.88 + 0.44
		C.box(parent, null, front - side * 0.62 + heading * along + Vector3.UP * 1.25, Vector3(0.44, 0.04, 0.66), rot, stripe_a if k % 2 == 0 else stripe_b, 0.8, false)
	C.box(parent, null, front - side * 1.28 + Vector3.UP * 1.1, Vector3(7.05, 0.16, 0.02), rot, stripe_a, 0.8, false)
	var door_c := front + heading * 6.8 + Vector3.UP * -0.9
	C.box(parent, null, door_c - side * 0.03, Vector3(0.6, 1.1, 0.03), rot, diner_glass, 0.6, false)
	for e: float in [-1.0, 1.0]:
		C.box(parent, null, door_c - side * 0.05 + heading * e * 0.6, Vector3(0.04, 1.12, 0.04), rot, alu, 0.6, false)
	C.box(parent, null, door_c - side * 0.05 + Vector3.UP * 1.12, Vector3(0.64, 0.04, 0.04), rot, alu, 0.6, false)
	C.box(parent, null, door_c - side * 0.1, Vector3(0.45, 0.025, 0.025), rot, alu, 0.6, false)
	# Roof sign, air-conditioning units and a vent stack.
	# (on posts, clear of the roof edge when seen from the pad)
	C.box(parent, null, diner + Vector3.UP * 3.75 - side * 3.0, Vector3(2.6, 0.6, 0.06), rot, trim, 0.8, false)
	for f: float in [-1.0, 1.0]:
		C.label3d(parent, "DINER", diner + Vector3.UP * 3.75 - side * (3.0 + f * 0.08), face.call(-side * f), 0.95, Color(1.0, 0.95, 0.82))
	for e: float in [-1.0, 1.0]:
		C.box(parent, null, diner + Vector3.UP * 2.9 - side * 3.0 + heading * e * 2.2, Vector3(0.05, 0.3, 0.05), rot, steel, 0.6, false)
	for k in 2:
		C.box(parent, null, diner + Vector3.UP * 2.95 + heading * (-3.5 + k * 2.4) + side * 2.0, Vector3(0.7, 0.45, 0.55), rot, steel, 0.6, false)
	C.box(parent, null, diner + Vector3.UP * 3.1 + heading * 4.5 + side * 2.5, Vector3(0.12, 0.6, 0.12), rot, dark, 0.6, false)
	# Vending machine and a bench by the door.
	var vend := front - side * 0.45 + heading * 7.9 + Vector3.UP * -1.25
	C.box(parent, world, vend, Vector3(0.45, 0.95, 0.4), rot, trim, 0.6)
	C.box(parent, null, vend - side * 0.41 + Vector3.UP * 0.25, Vector3(0.3, 0.5, 0.01), rot, lit_panel, 0.6, false)
	var bench := front - side * 0.55 + heading * 3.0 + Vector3.UP * -1.75
	C.box(parent, world, bench, Vector3(1.0, 0.04, 0.22), rot, C.mat(Color(0.45, 0.3, 0.18), 0.8), 0.6)
	for e: float in [-1.0, 1.0]:
		C.box(parent, null, bench + heading * e * 0.85 + Vector3.UP * -0.22, Vector3(0.04, 0.22, 0.2), rot, dark, 0.6, false)
	var pole: Vector3 = at.call(-12.0, 12.5, 4.0)
	C.box(parent, world, pole, Vector3(0.18, 4.0, 0.18), rot, steel, 0.6)
	C.box(parent, world, pole + Vector3.UP * 4.6, Vector3(0.25, 1.1, 2.6), rot, trim, 0.8, false)
	# Lettering on both faces of the board (they face along the road) and a fuel price board below.
	for f: float in [-1.0, 1.0]:
		C.label3d(parent, "COYOTE FLATS", pole + Vector3.UP * 4.95 + heading * f * 0.27, face.call(heading * f), 0.55, Color(1.0, 0.92, 0.75))
		C.label3d(parent, "DINER  ·  GAS  ·  MOTEL", pole + Vector3.UP * 4.25 + heading * f * 0.27, face.call(heading * f), 0.32, Color(1.0, 0.92, 0.75))
	C.box(parent, null, pole + Vector3.UP * 2.9, Vector3(0.12, 0.5, 1.6), rot, white, 0.8, false)
	for f: float in [-1.0, 1.0]:
		C.label3d(parent, "REGULAR  3.49\nDIESEL      3.89", pole + Vector3.UP * 2.9 + heading * f * 0.13, face.call(heading * f), 0.22, Color(0.12, 0.12, 0.14))
	# Motel row with numbered doors under a covered walkway.
	var motel: Vector3 = at.call(14.0, 42.0, 1.6)
	C.box(parent, world, motel, Vector3(16.0, 1.6, 3.5), rot, stucco, 0.8)
	C.box(parent, world, motel + Vector3.UP * 1.75 - side * 1.2, Vector3(16.3, 0.15, 5.0), rot, trim, 0.8, false)
	for k in 8:
		var a := -14.0 + k * 4.0
		var door: Vector3 = motel + heading * a - side * 3.52 + Vector3.UP * -0.5
		C.box(parent, world, door, Vector3(0.5, 1.05, 0.04), rot, C.mat(Color(0.25, 0.38, 0.42), 0.6), 0.6, false)
		C.box(parent, world, door + heading * 1.3 + Vector3.UP * 0.6, Vector3(0.65, 0.4, 0.04), rot, glass, 0.6, false)
		C.label3d(parent, str(k + 1), door + Vector3.UP * 1.35 - side * 0.05, face.call(-side), 0.22)
		if k % 2 == 0:
			C.box(parent, world, motel + heading * (a + 2.0) - side * 6.0 + Vector3.UP * 0.0, Vector3(0.10, 1.7, 0.10), rot, steel, 0.6, false)
	# Water tower behind the buildings.
	var tower: Vector3 = at.call(-4.0, 52.0, 0.0)
	for leg in 4:
		var o := Vector3(2.2 if leg % 2 == 0 else -2.2, 0, 2.2 if leg < 2 else -2.2)
		C.box(parent, world, tower + o + Vector3.UP * 6.5, Vector3(0.15, 6.5, 0.15), Vector3.ZERO, steel, 0.6)
	var tank := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.2
	cyl.bottom_radius = 3.2
	cyl.height = 4.5
	tank.mesh = cyl
	tank.material_override = C.mat(Color(0.70, 0.66, 0.60), 0.5, 0.5)
	tank.position = tower + Vector3.UP * 15.2
	parent.add_child(tank)
	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 3.4
	cone.height = 1.6
	cap.mesh = cone
	cap.material_override = tank.material_override
	cap.position = tower + Vector3.UP * 18.2
	parent.add_child(cap)
	# Night: canopy lights over the pumps and a lamp at the diner, pooled spot lights.
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.95, 0.95, 0.9)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.92, 0.78)
	lens.emission_energy_multiplier = 0.0
	var lights := PackedVector3Array()
	for a: float in [-4.5, 0.0, 4.5]:
		for c: float in [18.0, 24.0]:
			var lamp: Vector3 = at.call(a, c, 4.72)
			C.box(parent, null, lamp, Vector3(0.6, 0.03, 0.25), rot, lens, 0.6, false)
			lights.append(lamp - Vector3.UP * 0.1)
	var porch: Vector3 = at.call(-20.0, 28.6, 3.4)
	C.box(parent, null, porch, Vector3(0.25, 0.08, 0.25), rot, lens, 0.6, false)
	lights.append(porch - Vector3.UP * 0.1)
	var lighting := preload("res://scripts/maps/street_lighting.gd").new()
	lighting.name = "CoyoteFlatsLighting"
	parent.add_child(lighting)
	lighting.setup(lights, lens)
	return at.call(0.0, 25.0, 0.0)
