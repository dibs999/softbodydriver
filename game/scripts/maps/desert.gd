extends RefCounted
## Dunes, a sandstone plateau and a rally loop with a field station at the start.

const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
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
			if m > 0.38:
				h += 46.0 * smoothstep(0.38, 0.49, m)
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
	# Two jump ramps on the track (bumps in the elevation profile).
	var jumps := [112, 463]
	for j: int in jumps:
		for k in range(-6, 7):
			var t := 1.0 - absf(k) / 6.0
			elev[(j + k) % n_track] += 2.2 * t * t if k <= 0 else 0.0
	for i in n_track:
		track[i].y = elev[i]
	var half_w := 6.0
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
	world.add_heightfield(ox, oz, cell, nx, nz, heights, 0.82)

	# Vertex colours: sand on flats, red rock on steep slopes and mesa walls.
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var sand := Color(1.0, 0.89, 0.69)
	var rock := Color(0.76, 0.45, 0.30)
	for ix in nx:
		for iz in nz:
			var i := ix * nz + iz
			var hx := heights[mini(ix + 1, nx - 1) * nz + iz] - heights[maxi(ix - 1, 0) * nz + iz]
			var hz := heights[ix * nz + mini(iz + 1, nz - 1)] - heights[ix * nz + maxi(iz - 1, 0)]
			var slope := Vector2(hx, hz).length() / (2.0 * cell)
			var band := 0.5 + 0.5 * sin(heights[i] * 0.95 + 0.35 * sin(ix * 0.04))
			var cliff := rock.lerp(Color(0.86, 0.58, 0.41), band * 0.52)
			var dust := sand.lerp(Color(0.88, 0.72, 0.53), 0.28 + 0.22 * sin(ix * 0.022 + iz * 0.036))
			colors[i] = dust.lerp(cliff, smoothstep(0.17, 0.73, slope)).darkened(clampf(heights[i] / 330.0, 0.0, 0.22))
	C.terrain_tiles(parent, ox, oz, cell, nx, nz, heights, C.terrain_material("gravel", 5.0, Color(0.80, 0.72, 0.62)), colors)
	var ground_height := func(x: float, z: float) -> float:
		return C.sample(heights, nx, nz, ox, oz, cell, x, z)
	parent.add_child(C.road_mesh(track, half_w, C.road_material(2, half_w * 2.0, 12.0, "desert"), true, 0.052, 12.0, ground_height))
	parent.add_child(C.road_mesh(shortcut, 3.6, C.road_material(2, 7.2, 12.0, "desert"), false, 0.043, 12.0, ground_height))
	var mine := _mine(parent, world, shortcut, ground_height)

	# Boulders (colliding) and cacti / shrubs (visual).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var rock_mat := C.noise_mat(Color(0.63, 0.40, 0.29), 0.2, 0.4, 0.95, 0.2)
	var boulder := SphereMesh.new()
	boulder.radial_segments = 7
	boulder.rings = 3
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
	C.scatter_multimesh(parent, boulder, rock_mat, boulders, false)
	var cactus := CylinderMesh.new()
	cactus.top_radius = 0.18
	cactus.bottom_radius = 0.24
	cactus.height = 3.0
	cactus.radial_segments = 8
	cactus.rings = 0
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
		arms.append(stalk * Transform3D(Basis(Vector3.BACK, -0.75).scaled_local(Vector3(0.72, 0.52, 0.72)), Vector3(0.53, 0.2, 0)))
		if i % 3 != 0:
			arms.append(stalk * Transform3D(Basis(Vector3.BACK, 0.8).scaled_local(Vector3(0.68, 0.44, 0.68)), Vector3(-0.5, -0.14, 0)))
	for i in range(4, n_track, 13):
		var tangent := track[(i + 1) % n_track] - track[i - 1]
		var side := Vector3(-tangent.z, 0, tangent.x).normalized()
		var p := track[i] + side * (-1.0 if i % 2 == 0 else 1.0) * rng.randf_range(11.0, 18.0)
		if _near_track(Vector2(p.x, p.z), shortcut, 6.0, false):
			continue
		p.y = ground_height.call(p.x, p.z)
		var stalk := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3.UP * 1.4)
		xfs.append(stalk)
		arms.append(stalk * Transform3D(Basis(Vector3.BACK, -0.75).scaled_local(Vector3(0.72, 0.52, 0.72)), Vector3(0.53, 0.2, 0)))
	var cactus_mat := C.mat(Color(0.25, 0.42, 0.2), 0.8)
	C.scatter_multimesh(parent, cactus, cactus_mat, xfs)
	C.scatter_multimesh(parent, cactus, cactus_mat, arms, false)
	var sx: Array[Vector3] = []
	for i in 680:
		var p := Vector2(rng.randf_range(-840, 840), rng.randf_range(-840, 840))
		if _near_track(p, track, 8.0) or _near_track(p, shortcut, 6.0, false):
			continue
		sx.append(Vector3(p.x, C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y), p.y))
	V.plant(parent, "dry_shrub", sx, 680, 0.45, 1.1, false)
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
	return {"spawns": [C.car_xform(track[0], track[1] - track[0]), C.car_xform(track[n_track - 8], track[n_track - 7] - track[n_track - 8])],
		"waypoints": track, "speeds": speeds,
		"map_paths": [C.closed_route(track), shortcut],
		"map_places": [{"name": "Rallyelager Red Mesa", "position": track[6]}, {"name": "Alte Mine", "position": mine},
			{"name": "Dünensprung", "position": track[jumps[0]]}, {"name": "Schluchtsprung", "position": track[jumps[1]]}],
		"ai_spawns": [C.car_xform(track[200], track[201] - track[200]), C.car_xform(track[540], track[541] - track[540])],
		"environment": {"sky_top": Color(0.32, 0.5, 0.78), "horizon": Color(0.92, 0.82, 0.68), "fog": Color(0.93, 0.83, 0.68),
			"fog_density": 0.00065, "sun": Vector3(-43, -120, 0), "sun_energy": 1.5, "sun_color": Color(1.0, 0.93, 0.80)}}


static func _near_track(p: Vector2, track: PackedVector3Array, dist: float, closed := true) -> bool:
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
