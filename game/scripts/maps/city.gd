extends RefCounted
## "Stadt": downtown street grid with raised kerbs, high-rise blocks, traffic lights, street lamps,
## a park and an AI traffic loop around the blocks.

const C := preload("res://scripts/maps/common.gd")
const BLOCKS := 6
const BLOCK := 72.0         # block size (kerb to kerb)
const STREET := 16.0        # street width (2 lanes each way)
const PITCH := BLOCK + STREET
const KERB := 0.14


static func _facade_material(base: Color, seed: int) -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	img.fill(base)
	for fy in 4:
		for fx in 4:
			var lit := rng.randf() < 0.25
			var col := Color(0.95, 0.85, 0.55) if lit else Color(0.16, 0.2, 0.26).lerp(Color(0.35, 0.45, 0.55), rng.randf() * 0.5)
			for y in range(fy * 16 + 4, fy * 16 + 13):
				for x in range(fx * 16 + 3, fx * 16 + 13):
					img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.55
	m.metallic = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	world.add_ground_plane(1.0)
	var asphalt := C.noise_mat(Color(0.19, 0.19, 0.2), 0.15, 0.2, 0.85, 0.08)
	var pavement := C.noise_mat(Color(0.58, 0.57, 0.54), 0.08, 0.6, 0.8, 0.3)
	var grass := C.noise_mat(Color(0.28, 0.45, 0.18), 0.25, 0.1)
	var line := C.mat(Color(0.92, 0.92, 0.88), 0.6)
	var metal := C.mat(Color(0.3, 0.32, 0.34), 0.4, 0.8)
	var size := BLOCKS * PITCH + STREET
	var origin := -size * 0.5
	C.quad(parent, Vector3(0, -0.01, 0), Vector2(size + 600, size + 600), asphalt)

	var facades: Array[StandardMaterial3D] = []
	var bases := [Color(0.55, 0.53, 0.5), Color(0.42, 0.44, 0.47), Color(0.62, 0.58, 0.52), Color(0.32, 0.34, 0.36), Color(0.5, 0.42, 0.36)]
	for i in bases.size():
		facades.append(_facade_material(bases[i], 100 + i))
	var roof_mat := C.mat(Color(0.25, 0.25, 0.26), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024

	# Blocks: raised pavement slab (real kerb collision) + buildings, one park block.
	for bx in BLOCKS:
		for bz in BLOCKS:
			var x0 := origin + STREET + bx * PITCH
			var z0 := origin + STREET + bz * PITCH
			var c := Vector3(x0 + BLOCK * 0.5, KERB * 0.5, z0 + BLOCK * 0.5)
			C.box(parent, world, c, Vector3(BLOCK * 0.5, KERB * 0.5, BLOCK * 0.5), Vector3.ZERO, pavement, 0.9, true, false)
			if bx == 2 and bz == 3:
				# Park with trees and a fountain.
				C.quad(parent, c + Vector3(0, KERB * 0.5 + 0.01, 0), Vector2(BLOCK - 8, BLOCK - 8), grass)
				C.box(parent, world, c + Vector3(0, 0.5, 0), Vector3(5, 0.45, 5), Vector3.ZERO, pavement, 0.8)
				var tree := SphereMesh.new()
				tree.radius = 3.0
				tree.height = 5.0
				var trees: Array[Transform3D] = []
				for i in 18:
					var p := c + Vector3(rng.randf_range(-28, 28), 4.5, rng.randf_range(-28, 28))
					if Vector2(p.x - c.x, p.z - c.z).length() < 9.0:
						continue
					trees.append(Transform3D(Basis(), p))
				C.scatter_multimesh(parent, tree, C.mat(Color(0.16, 0.33, 0.14), 0.9), trees)
				continue
			# 1..4 buildings per block.
			var split := rng.randi_range(1, 2)
			var margin := 3.0
			for sx in split:
				for sz in split:
					var w := (BLOCK - margin * 2.0) / split
					var bxc := x0 + margin + w * (sx + 0.5)
					var bzc := z0 + margin + w * (sz + 0.5)
					var dist_center := Vector2(bxc, bzc).length()
					var hgt := rng.randf_range(12.0, 30.0) + maxf(0.0, 160.0 - dist_center) * rng.randf_range(0.15, 0.45)
					var half := Vector3(w * 0.5 - 1.5, hgt * 0.5, w * 0.5 - 1.5)
					var b := C.box(parent, world, Vector3(bxc, KERB + hgt * 0.5, bzc), half, Vector3.ZERO, facades[rng.randi() % facades.size()], 0.7)
					C.box(parent, world, Vector3(bxc, KERB + hgt + 0.4, bzc), Vector3(half.x * 0.7, 0.4, half.z * 0.7), Vector3.ZERO, roof_mat, 0.7, false)

	# Lane markings along every street (centre line + lane dashes, instanced).
	var dash := PlaneMesh.new()
	dash.size = Vector2(1, 1)
	var dashes: Array[Transform3D] = []
	for i in BLOCKS + 1:
		var s := origin + STREET * 0.5 + i * PITCH
		dashes.append(Transform3D(Basis().scaled(Vector3(size, 1, 0.15)), Vector3(0, 0.012, s)))
		dashes.append(Transform3D(Basis().scaled(Vector3(0.15, 1, size)), Vector3(s, 0.012, 0)))
		for d: float in [-4.0, 4.0]:
			for k in int(size / 12.0):
				var t := origin + 6.0 + k * 12.0
				dashes.append(Transform3D(Basis().scaled(Vector3(4.0, 1, 0.12)), Vector3(t, 0.012, s + d)))
				dashes.append(Transform3D(Basis().scaled(Vector3(0.12, 1, 4.0)), Vector3(s + d, 0.012, t)))
	C.scatter_multimesh(parent, dash, line, dashes, false)

	# Traffic lights (colliding poles) at intersections, street lamps along the kerbs.
	var light_box := C.mat(Color(0.1, 0.1, 0.1), 0.6)
	var red := C.mat(Color(0.9, 0.1, 0.05), 0.3)
	red.emission_enabled = true
	red.emission = Color(1, 0.1, 0.05)
	var green := C.mat(Color(0.1, 0.9, 0.2), 0.3)
	green.emission_enabled = true
	green.emission = Color(0.1, 1.0, 0.25)
	for ix in BLOCKS + 1:
		for iz in BLOCKS + 1:
			var cx := origin + STREET * 0.5 + ix * PITCH
			var cz := origin + STREET * 0.5 + iz * PITCH
			for corner in [Vector2(1, 1), Vector2(-1, -1)]:
				var p := Vector3(cx + corner.x * (STREET * 0.5 + 1.2), 0, cz + corner.y * (STREET * 0.5 + 1.2))
				C.box(parent, world, p + Vector3(0, 2.0, 0), Vector3(0.09, 2.0, 0.09), Vector3.ZERO, metal, 0.6)
				C.box(parent, world, p + Vector3(0, 4.3, 0), Vector3(0.18, 0.45, 0.18), Vector3.ZERO, light_box, 0.6, false)
				var lamp := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.1
				sm.height = 0.2
				lamp.mesh = sm
				lamp.material_override = red if (ix + iz) % 2 == 0 else green
				lamp.position = p + Vector3(-corner.x * 0.2, 4.45, 0)
				parent.add_child(lamp)
	var lamp_pole := CylinderMesh.new()
	lamp_pole.top_radius = 0.06
	lamp_pole.bottom_radius = 0.1
	lamp_pole.height = 7.0
	var lamps: Array[Transform3D] = []
	for i in BLOCKS:
		for j in BLOCKS:
			var x0 := origin + STREET + i * PITCH
			var z0 := origin + STREET + j * PITCH
			for k in 4:
				var t := 10.0 + k * 17.0
				lamps.append(Transform3D(Basis(), Vector3(x0 + t, 3.5, z0 + 0.8)))
				lamps.append(Transform3D(Basis(), Vector3(x0 + 0.8, 3.5, z0 + t)))
	C.scatter_multimesh(parent, lamp_pole, metal, lamps)

	# AI loop: rectangle around the inner blocks, right-hand lane.
	var lo := origin + STREET * 0.5 + 1 * PITCH
	var hi := origin + STREET * 0.5 + (BLOCKS - 1) * PITCH
	var route := PackedVector3Array()
	var lane := 4.0  # right lane offset from the centre line
	var corners := [Vector3(lo, 0, lo), Vector3(hi, 0, lo), Vector3(hi, 0, hi), Vector3(lo, 0, hi)]
	# Driving clockwise when seen from above with traffic on the right: offset each edge to its right.
	for e in 4:
		var a: Vector3 = corners[e]
		var b: Vector3 = corners[(e + 1) % 4]
		var d := (b - a).normalized()
		var right := Vector3(-d.z, 0, d.x)
		var steps := int(a.distance_to(b) / 8.0)
		for s in steps:
			route.append(a.lerp(b, float(s) / steps) + right * lane)
	var speeds := C.speeds_from_curvature(route, 13.5, 6.0, 25.0)
	var spawn_p := Vector3(origin + STREET * 0.5 + 3 * PITCH - 4.0, 0, origin + STREET * 0.5 + 3 * PITCH + 20.0)
	return {
		"spawns": [C.car_xform(spawn_p, Vector3(0, 0, 1)), C.car_xform(spawn_p + Vector3(0, 0, -12), Vector3(0, 0, 1))],
		"waypoints": route, "speeds": speeds,
		"ai_routes": [
			{"waypoints": route, "speeds": speeds, "spawn": C.car_xform(route[3], route[4] - route[3])},
			{"waypoints": route, "speeds": speeds, "spawn": C.car_xform(route[route.size() / 2], route[route.size() / 2 + 1] - route[route.size() / 2])},
		],
		"environment": {"sky_top": Color(0.3, 0.45, 0.7), "horizon": Color(0.7, 0.72, 0.76), "fog": Color(0.66, 0.68, 0.72),
			"fog_density": 0.0012, "sun": Vector3(-35, 60, 0), "sun_energy": 1.2},
	}
