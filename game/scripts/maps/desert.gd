extends RefCounted
## "Wüste": 1 km² of dunes, mesas and a dirt-track loop with jumps, boulders and cacti.

const C := preload("res://scripts/maps/common.gd")


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	var nx := 257
	var nz := 257
	var cell := 4.0
	var ox := -512.0
	var oz := -512.0
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
	mesa.frequency = 0.0035
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var x := ox + ix * cell
			var z := oz + iz * cell
			var h := (dunes.get_noise_2d(x, z) * 0.5 + 0.5) * 14.0 + ridges.get_noise_2d(x, z) * 3.0
			# Flat-topped mesas with steep cliffs.
			var m := mesa.get_noise_2d(x, z)
			if m > 0.38:
				h += 22.0 * clampf((m - 0.38) / 0.06, 0.0, 1.0)
			# Rim of mountains around the map.
			h += 40.0 * clampf((maxf(absf(x), absf(z)) - 430.0) / 70.0, 0.0, 1.0)
			heights[ix * nz + iz] = h

	# Dirt-track loop.
	var track := PackedVector3Array()
	var n_track := 400
	for i in n_track:
		var a := TAU * i / n_track
		var r := 280.0 + 70.0 * sin(2.0 * a + 0.4) + 35.0 * cos(5.0 * a)
		track.append(Vector3(cos(a) * r, 0, sin(a) * r * 0.85))
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
	for j in [60, 250]:
		for k in range(-6, 7):
			var t := 1.0 - absf(k) / 6.0
			elev[(j + k) % n_track] += 2.2 * t * t if k <= 0 else 0.0
	for i in n_track:
		track[i].y = elev[i]
	var half_w := 6.0
	C.carve_path(heights, nx, nz, ox, oz, cell, track, half_w, 14.0, 0.08)
	world.add_heightfield(ox, oz, cell, nx, nz, heights, 0.82)

	# Vertex colours: sand on flats, red rock on steep slopes and mesa walls.
	var colors := PackedColorArray()
	colors.resize(nx * nz)
	var sand := Color(0.86, 0.69, 0.46)
	var rock := Color(0.62, 0.33, 0.2)
	for ix in nx:
		for iz in nz:
			var i := ix * nz + iz
			var hx := heights[mini(ix + 1, nx - 1) * nz + iz] - heights[maxi(ix - 1, 0) * nz + iz]
			var hz := heights[ix * nz + mini(iz + 1, nz - 1)] - heights[ix * nz + maxi(iz - 1, 0)]
			var slope := Vector2(hx, hz).length() / (2.0 * cell)
			colors[i] = sand.lerp(rock, clampf((slope - 0.35) / 0.4, 0.0, 1.0)).darkened(clampf(heights[i] / 200.0, 0.0, 0.2))
	parent.add_child(C.terrain_mesh(ox, oz, cell, nx, nz, heights, C.noise_mat(sand, 0.12, 0.06, 0.97, 0.08, true), colors))
	parent.add_child(C.road_mesh(track, half_w, C.road_material(2, "dirt"), true, 0.05))

	# Boulders (colliding) and cacti / shrubs (visual).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var rock_mat := C.noise_mat(Color(0.55, 0.35, 0.24), 0.2, 0.4, 0.95, 0.2)
	for i in 120:
		var p := Vector2(rng.randf_range(-420, 420), rng.randf_range(-420, 420))
		if _near_track(p, track, 14.0):
			continue
		var s := rng.randf_range(0.6, 2.6)
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		C.box(parent, world, Vector3(p.x, y + s * 0.35, p.y), Vector3(s, s * 0.7, s * 0.8),
			Vector3(rng.randf() * 0.4, rng.randf() * PI, rng.randf() * 0.4), rock_mat, 0.7)
	var cactus := CylinderMesh.new()
	cactus.top_radius = 0.18
	cactus.bottom_radius = 0.24
	cactus.height = 3.0
	var xfs: Array[Transform3D] = []
	for i in 260:
		var p := Vector2(rng.randf_range(-430, 430), rng.randf_range(-430, 430))
		if _near_track(p, track, 10.0):
			continue
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		var s := rng.randf_range(0.6, 1.3)
		xfs.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, y + 1.4 * s, p.y)))
	C.scatter_multimesh(parent, cactus, C.mat(Color(0.25, 0.42, 0.2), 0.8), xfs)
	var shrub := SphereMesh.new()
	shrub.radius = 0.7
	shrub.height = 0.8
	var sx: Array[Transform3D] = []
	for i in 500:
		var p := Vector2(rng.randf_range(-440, 440), rng.randf_range(-440, 440))
		if _near_track(p, track, 8.0):
			continue
		var y := C.sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		var s := rng.randf_range(0.5, 1.4)
		sx.append(Transform3D(Basis().scaled(Vector3(s, s * 0.6, s)), Vector3(p.x, y + 0.1, p.y)))
	C.scatter_multimesh(parent, shrub, C.mat(Color(0.45, 0.42, 0.25), 1.0), sx, false)

	var speeds := C.speeds_from_curvature(track, 24.0, 12.0, 50.0)
	for j in [60, 250]:
		for k in range(-12, 3):
			speeds[(j + k) % n_track] = minf(speeds[(j + k) % n_track], 17.0)
	return {"spawns": [C.car_xform(track[0], track[1] - track[0]), C.car_xform(track[n_track - 8], track[n_track - 7] - track[n_track - 8])],
		"waypoints": track, "speeds": speeds,
		"ai_spawns": [C.car_xform(track[130], track[131] - track[130]), C.car_xform(track[300], track[301] - track[300])],
		"environment": {"sky_top": Color(0.32, 0.5, 0.78), "horizon": Color(0.92, 0.82, 0.68), "fog": Color(0.93, 0.83, 0.68),
			"fog_density": 0.0009, "sun": Vector3(-55, -120, 0), "sun_energy": 1.5, "sun_color": Color(1.0, 0.95, 0.85)}}


static func _near_track(p: Vector2, track: PackedVector3Array, dist: float) -> bool:
	for j in range(0, track.size(), 5):
		if p.distance_to(Vector2(track[j].x, track[j].z)) < dist:
			return true
	return false
