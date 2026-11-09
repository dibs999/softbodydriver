extends RefCounted
## "Stadt": downtown street grid with raised kerbs, high-rise blocks, traffic lights, street lamps,
## a park and an AI traffic loop around the blocks.

const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")
const BLOCKS := 10
const BLOCK := 72.0         # block size (kerb to kerb)
const STREET := 16.0        # street width (2 lanes each way)
const PITCH := BLOCK + STREET
const KERB := 0.14


static func _facade_material(base: Color, seed: int) -> StandardMaterial3D:
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	img.fill(base)
	for fy in 4:
		for fx in 4:
			var x := fx * 128
			var y := fy * 128
			var stone := base.lerp(base.darkened(0.18), rng.randf())
			img.fill_rect(Rect2i(x, y, 128, 128), stone)
			# Fine masonry joints and staggered blocks remain crisp at street level.
			for course in 8:
				img.fill_rect(Rect2i(x, y + course * 16, 128, 1), stone.darkened(0.11))
				for joint in 3:
					img.fill_rect(Rect2i(x + joint * 44 + (course % 2) * 20, y + course * 16, 1, 16), stone.darkened(0.12))
			img.fill_rect(Rect2i(x, y + 122, 128, 6), stone.darkened(0.22))
			img.fill_rect(Rect2i(x + 126, y, 2, 122), stone.darkened(0.16))
			var lit := rng.randf() < 0.14
			var glass := Color(0.76, 0.64, 0.37) if lit else Color(0.13, 0.19, 0.26).lerp(Color(0.35, 0.46, 0.56), rng.randf() * 0.5)
			img.fill_rect(Rect2i(x + 20, y + 22, 90, 84), stone.darkened(0.58))
			for row in 72:
				var reflection := glass.lerp(Color(0.55, 0.63, 0.68), (1.0 - row / 72.0) * 0.42)
				img.fill_rect(Rect2i(x + 28, y + 28 + row, 74, 1), reflection)
			# Different blind heights and window dividers break the repeated grid.
			var blind := rng.randi_range(0, 26) if not lit else 0
			if blind > 3: img.fill_rect(Rect2i(x + 28, y + 28, 74, blind), stone.darkened(0.30))
			img.fill_rect(Rect2i(x + 62, y + 28, 4, 72), stone.lightened(0.2))
			if (fx + fy + seed) % 3 == 0:
				img.fill_rect(Rect2i(x + 28, y + 70, 74, 2), stone.lightened(0.12))
			img.fill_rect(Rect2i(x + 16, y + 102, 98, 6), stone.lightened(0.32))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.065, 0.075, 0.065)
	m.roughness = 0.55
	m.metallic = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	world.add_ground_plane(1.0)
	var asphalt := C.surface_material("asphalt", 2.0, Color.WHITE, 0.30)
	var pavement := C.surface_material("pavement", 1.8, Color.WHITE, 0.30)
	var grass := C.surface_material("grass", 2.8, Color(0.70, 0.90, 0.64))
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
	var shopfronts: Array[Transform3D] = []
	var awnings: Array[Transform3D] = []
	var pavements: Array[Transform3D] = []
	var roofs: Array[Transform3D] = []
	var rooftop_units: Array[Transform3D] = []
	var buildings: Array[Array] = []
	for i in facades.size():
		var batch: Array[Transform3D] = []
		buildings.append(batch)
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var places: Array[Dictionary] = []
	var surface_regions: Array[Dictionary] = []

	# Keep collision at each address and batch repeated building geometry by material.
	for bx in BLOCKS:
		for bz in BLOCKS:
			var x0 := origin + STREET + bx * PITCH
			var z0 := origin + STREET + bz * PITCH
			var c := Vector3(x0 + BLOCK * 0.5, KERB * 0.5, z0 + BLOCK * 0.5)
			var block := Vector2i(bx, bz)
			world.add_box(c, Vector3(BLOCK, KERB, BLOCK) * 0.5, Vector3.ZERO, 0.9)
			pavements.append(Transform3D(Basis.from_scale(Vector3(BLOCK, KERB, BLOCK)), c))
			if block in [Vector2i(1, 5), Vector2i(6, 3), Vector2i(7, 4)]:
				_district(parent, world, c, block, asphalt, pavement, metal)
				var district_name := "Werkstatthöfe" if bx == 1 else ("Altstadtgasse" if bx == 6 else "Hochstraße")
				places.append({"name": district_name, "position": c})
				surface_regions.append({"rect": Rect2(c.x - 36, c.z - 36, 72, 72), "surface": "gravel" if bx == 1 else "pavement"})
				continue
			if block == Vector2i(6, 5):
				_parking_deck(parent, world, c, asphalt, pavement, line)
				places.append({"name": "Parkdeck Süd", "position": c})
				continue
			if block == Vector2i(8, 7):
				_freight_yard(parent, world, c, asphalt, metal)
				places.append({"name": "Frachtterminal", "position": c})
				continue
			if block == Vector2i(4, 6):
				_market(parent, world, c, pavement, metal)
				places.append({"name": "Wochenmarkt", "position": c})
				continue
			if block in [Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 3)]:
				_townhouses(parent, world, c, grass)
				if block == Vector2i(2, 3):
					places.append({"name": "Wohnviertel", "position": c})
				continue
			if block in [Vector2i(4, 5), Vector2i(7, 2), Vector2i(2, 7)]:
				# Park with trees and a fountain.
				C.quad(parent, c + Vector3(0, KERB * 0.5 + 0.01, 0), Vector2(BLOCK - 8, BLOCK - 8), grass)
				var path_center := c + Vector3(0, KERB * 0.5 + 0.02, 0)
				C.quad(parent, path_center, Vector2(3.2, BLOCK - 3.0), pavement)
				C.quad(parent, path_center + Vector3.UP * 0.002, Vector2(BLOCK - 3.0, 3.2), pavement)
				C.box(parent, world, c + Vector3(0, 0.5, 0), Vector3(5, 0.45, 5), Vector3.ZERO, pavement, 0.8)
				C.quad(parent, c + Vector3(0, 0.954, 0), Vector2(8.8, 8.8), C.mat(Color(0.16, 0.47, 0.6), 0.28))
				var trees: Array[Vector3] = []
				for i in 18:
					var p := c + Vector3(rng.randf_range(-28, 28), KERB, rng.randf_range(-28, 28))
					if Vector2(p.x - c.x, p.z - c.z).length() < 9.0:
						continue
					trees.append(p)
				V.plant(parent, "broadleaf", trees, block.x * 31 + block.y, 0.75, 1.1)
				if block == Vector2i(4, 5):
					places.append({"name": "Stadtpark", "position": c})
				continue
			if block in [Vector2i(5, 5), Vector2i(7, 6)]:
				_plaza(parent, world, c, bx == 5, pavement, metal)
				places.append({"name": "U-Bahn Nordplatz" if bx == 5 else "Skulpturenplatz", "position": c})
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
					var urban := 1.0 - smoothstep(100.0, 450.0, dist_center)
					var hgt := rng.randf_range(6.0, 17.0) + urban * rng.randf_range(12.0, 67.0)
					var half := Vector3(w * 0.5 - 1.5, hgt * 0.5, w * 0.5 - 1.5)
					var pos := Vector3(bxc, KERB + hgt * 0.5, bzc)
					var facade: Array[Transform3D] = buildings[rng.randi() % facades.size()]
					facade.append(Transform3D(Basis.from_scale(half * 2.0), pos))
					world.add_box(pos, half, Vector3.ZERO, 0.7)
					roofs.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.02, 0.65, half.z * 2.02)), Vector3(bxc, KERB + hgt + 0.32, bzc)))
					rooftop_units.append(Transform3D(Basis.from_scale(Vector3(half.x * 0.8, 2.9, half.z * 0.65)), Vector3(bxc + half.x * 0.18, KERB + hgt + 1.4, bzc)))
					if sz == 0:
						shopfronts.append(Transform3D(Basis(), Vector3(bxc, KERB + 1.4, bzc - half.z - 0.06)))
						awnings.append(Transform3D(Basis(), Vector3(bxc, KERB + 2.9, bzc - half.z - 0.55)))
					if sx == 0:
						var facing := Basis(Vector3.UP, PI * 0.5)
						shopfronts.append(Transform3D(facing, Vector3(bxc - half.x - 0.06, KERB + 1.4, bzc)))
						awnings.append(Transform3D(facing, Vector3(bxc - half.x - 0.55, KERB + 2.9, bzc)))
	C.scatter_multimesh(parent, box_mesh, pavement, pavements, false)
	C.scatter_multimesh(parent, box_mesh, roof_mat, roofs, false)
	C.scatter_multimesh(parent, box_mesh, metal, rooftop_units, false)
	for i in buildings.size():
		C.scatter_multimesh(parent, box_mesh, facades[i], buildings[i])
	var window := BoxMesh.new()
	window.size = Vector3(5.0, 2.65, 0.11)
	C.scatter_multimesh(parent, window, C.mat(Color(0.15, 0.26, 0.33), 0.32), shopfronts, false)
	var awning := BoxMesh.new()
	awning.size = Vector3(5.5, 0.22, 1.25)
	C.scatter_multimesh(parent, awning, C.mat(Color(0.24, 0.43, 0.39)), awnings, false)

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
	var crosswalk_x := Basis.from_scale(Vector3(2.7, 1, 0.55))
	var crosswalk_z := Basis.from_scale(Vector3(0.55, 1, 2.7))
	for ix in range(1, BLOCKS):
		for iz in range(1, BLOCKS):
			var cx := origin + STREET * 0.5 + ix * PITCH
			var cz := origin + STREET * 0.5 + iz * PITCH
			for side: float in [-10.0, 10.0]:
				for stripe in range(-7, 8):
					dashes.append(Transform3D(crosswalk_x, Vector3(cx + side, 0.017, cz + stripe)))
					dashes.append(Transform3D(crosswalk_z, Vector3(cx + stripe, 0.017, cz + side)))
	C.scatter_multimesh(parent, dash, line, dashes, false)

	# Traffic lights (colliding poles) at intersections, street lamps along the kerbs.
	var light_box := C.mat(Color(0.1, 0.1, 0.1), 0.6)
	var red := C.mat(Color(0.9, 0.1, 0.05), 0.3)
	red.emission_enabled = true
	red.emission = Color(1, 0.1, 0.05)
	var green := C.mat(Color(0.1, 0.9, 0.2), 0.3)
	green.emission_enabled = true
	green.emission = Color(0.1, 1.0, 0.25)
	var lens := SphereMesh.new()
	lens.radius = 0.1
	lens.height = 0.2
	lens.radial_segments = 8
	lens.rings = 4
	var signal_posts: Array[Transform3D] = []
	var signal_heads: Array[Transform3D] = []
	var reds: Array[Transform3D] = []
	var greens: Array[Transform3D] = []
	for ix in BLOCKS + 1:
		for iz in BLOCKS + 1:
			var cx := origin + STREET * 0.5 + ix * PITCH
			var cz := origin + STREET * 0.5 + iz * PITCH
			for corner in [Vector2(1, 1), Vector2(-1, -1)]:
				var p := Vector3(cx + corner.x * (STREET * 0.5 + 1.2), 0, cz + corner.y * (STREET * 0.5 + 1.2))
				world.add_box(p + Vector3(0, 2.0, 0), Vector3(0.09, 2.0, 0.09), Vector3.ZERO, 0.6)
				signal_posts.append(Transform3D(Basis.from_scale(Vector3(0.18, 4.0, 0.18)), p + Vector3.UP * 2.0))
				signal_heads.append(Transform3D(Basis.from_scale(Vector3(0.36, 0.90, 0.36)), p + Vector3.UP * 4.3))
				var red_axis := (ix + iz) % 2 == 0
				reds.append(Transform3D(Basis(), p + (Vector3(-corner.x * 0.18, 4.55, 0) if red_axis else Vector3(0, 4.55, -corner.y * 0.18))))
				greens.append(Transform3D(Basis(), p + (Vector3(0, 4.04, -corner.y * 0.18) if red_axis else Vector3(-corner.x * 0.18, 4.04, 0))))
	C.scatter_multimesh(parent, box_mesh, metal, signal_posts, false)
	C.scatter_multimesh(parent, box_mesh, light_box, signal_heads, false)
	C.scatter_multimesh(parent, lens, red, reds, false)
	C.scatter_multimesh(parent, lens, green, greens, false)
	var lamp_pole := CylinderMesh.new()
	lamp_pole.top_radius = 0.06
	lamp_pole.bottom_radius = 0.1
	lamp_pole.height = 7.0
	lamp_pole.radial_segments = 8
	lamp_pole.rings = 0
	var lamps: Array[Transform3D] = []
	var lamp_heads: Array[Transform3D] = []
	for i in BLOCKS:
		for j in BLOCKS:
			var x0 := origin + STREET + i * PITCH
			var z0 := origin + STREET + j * PITCH
			for k in 4:
				var t := 10.0 + k * 17.0
				lamps.append(Transform3D(Basis(), Vector3(x0 + t, 3.5, z0 + 0.8)))
				lamps.append(Transform3D(Basis(), Vector3(x0 + 0.8, 3.5, z0 + t)))
				lamp_heads.append(Transform3D(Basis.from_scale(Vector3(0.23, 0.14, 1.45)), Vector3(x0 + t, 7, z0 + 0.23)))
				lamp_heads.append(Transform3D(Basis.from_scale(Vector3(1.45, 0.14, 0.23)), Vector3(x0 + 0.23, 7, z0 + t)))
	C.scatter_multimesh(parent, lamp_pole, metal, lamps, false)
	C.scatter_multimesh(parent, box_mesh, metal, lamp_heads, false)

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
	var spawn_p := Vector3(origin + STREET * 0.5 + 5 * PITCH - 4.0, 0, origin + STREET * 0.5 + 5 * PITCH + 20.0)
	var map_paths: Array[PackedVector3Array] = []
	for i in BLOCKS + 1:
		var s := origin + STREET * 0.5 + i * PITCH
		map_paths.append(PackedVector3Array([Vector3(origin, 0, s), Vector3(-origin, 0, s)]))
		map_paths.append(PackedVector3Array([Vector3(s, 0, origin), Vector3(s, 0, -origin)]))
	return {
		"spawns": [C.car_xform(spawn_p, Vector3(0, 0, 1)), C.car_xform(spawn_p + Vector3(0, 0, -12), Vector3(0, 0, 1))],
		"waypoints": route, "speeds": speeds,
		"map_paths": map_paths, "map_places": places,
		"surface_regions": surface_regions,
		"ai_routes": [
			{"waypoints": route, "speeds": speeds, "spawn": C.car_xform(route[3], route[4] - route[3])},
			{"waypoints": route, "speeds": speeds, "spawn": C.car_xform(route[route.size() / 2], route[route.size() / 2 + 1] - route[route.size() / 2])},
		],
		"environment": {"sky_top": Color(0.3, 0.45, 0.7), "horizon": Color(0.7, 0.72, 0.76), "fog": Color(0.66, 0.68, 0.72),
			"fog_density": 0.0012, "sun": Vector3(-35, 60, 0), "sun_energy": 1.2},
	}


static func _district(parent: Node3D, world: SBWorld, c: Vector3, block: Vector2i, asphalt: Material, pavement: Material, metal: Material) -> void:
	var p := Vector3(c.x, KERB, c.z)
	var brick := C.surface_material("pavement", 1.4, Color(0.68, 0.42, 0.28))
	var dark := C.mat(Color("23333b"))
	if block.x == 1:
		C.quad(parent, p + Vector3.UP * 0.006, Vector2(68, 68), C.surface_material("gravel", 2.0))
		# Open-front workshops: three walls and a roof, with room to drive inside.
		for z: float in [-20, 20]:
			var h := p + Vector3(15, 0, z)
			C.box(parent, world, h + Vector3(13, 3.4, 0), Vector3(0.3, 3.4, 9), Vector3.ZERO, brick)
			for side: float in [-1, 1]:
				C.box(parent, world, h + Vector3(0, 3.4, side * 9), Vector3(13, 3.4, 0.3), Vector3.ZERO, brick)
			C.box(parent, world, h + Vector3(0, 6.9, 0), Vector3(13.4, 0.24, 9.5), Vector3.ZERO, metal)
			for x: float in [4, 10, 16]:
				C.box(parent, world, p + Vector3(x, 0.10, z), Vector3(0.65, 0.10, 0.20), Vector3.ZERO, dark, 0.8, false)
			C.label3d(parent, "SERVICE  /  " + ("01" if z < 0 else "02"), h + Vector3(-13.35, 5.9, 0), -PI * 0.5, 0.55)
		for i in 5:
			C.box(parent, world, p + Vector3(-24, 0.65, -22 + i * 11), Vector3(1.2, 0.65, 1.2), Vector3.ZERO, metal)
	elif block.x == 6:
		var colors := [Color("ad7960"), Color("c0b697"), Color("8d9c9c"), Color("bca17d")]
		for side: float in [-1, 1]:
			for i in 4:
				var h := p + Vector3(-25.5 + i * 17, 0, side * 22)
				var height := 9.0 + (i % 3) * 2.2
				C.box(parent, world, h + Vector3.UP * height * 0.5, Vector3(7.2, height * 0.5, 10), Vector3.ZERO, _facade_material(colors[i], 520 + i))
				C.box(parent, world, h + Vector3.UP * (height + 0.15), Vector3(7.5, 0.15, 10.3), Vector3.ZERO, brick, 0.8, false)
				C.box(parent, world, h + Vector3(0, 2.1, -side * 10.05), Vector3(5.3, 1.45, 0.1), Vector3.ZERO, dark, 0.8, false)
				C.box(parent, world, h + Vector3(0, 3.9, -side * 11.0), Vector3(5.7, 0.12, 1.4), Vector3.ZERO, C.mat(colors[(i+1)%4]), 0.8, false)
				C.label3d(parent, ["CAFÉ", "ATELIER", "BÜCHER", "BÄCKEREI"][i], h + Vector3(0, 4.5, -side * 10.2), PI if side > 0 else 0.0, 0.45)
		C.quad(parent, p + Vector3.UP * 0.009, Vector2(70, 19), pavement)
		for x: float in [-19, 19]:
			C.box(parent, world, p + Vector3(x, 0.35, 0), Vector3(2.4, 0.35, 1.2), Vector3.ZERO, brick)
	else:
		# A real raised road with a drive-through underpass and two gradual approaches.
		var height := 3.6
		var run := 25.0
		var angle := atan2(height, run)
		C.quad(parent, p + Vector3.UP * 0.008, Vector2(70, 50), asphalt)
		C.box(parent, world, p + Vector3(0, height - 0.2, 0), Vector3(9, 0.2, 4.3), Vector3.ZERO, pavement)
		for side: float in [-1, 1]:
			C.box(parent, world, p + Vector3(side * 21.5, height * 0.5 - 0.2, 0), Vector3(Vector2(run,height).length() * 0.5, 0.2, 4.3), Vector3(0,0,-side*angle), pavement)
			for z: float in [-4.0, 4.0]:
				C.box(parent, world, p + Vector3(side * 6.5, 1.6, z), Vector3(0.5,1.6,0.3), Vector3.ZERO, pavement)
			C.box(parent, world, p + Vector3(0,height+0.4,side*4.2), Vector3(8.8,0.3,0.16), Vector3.ZERO, metal)
		C.label3d(parent, "HOCHSTRASSE  /  30", p + Vector3(0, height + 1.0, -4.4), PI, 0.5)
	# Shallow curb transitions keep the entrances usable at sensible speeds.
	for side: float in [-1, 1]:
		C.box(parent, world, p + Vector3(side * 37.0, -0.12, 0), Vector3(2.0,0.05,5.8), Vector3(0,0,-side*atan2(KERB,4.0)), pavement)


static func _parking_deck(parent: Node3D, world: SBWorld, center: Vector3, asphalt: Material, concrete: Material, paint: Material) -> void:
	var p := Vector3(center.x, KERB, center.z)
	var stripe := C.mat(Color(0.90, 0.61, 0.19))
	var deck_top := 3.2
	var ramp_run := 24.0
	var angle := atan2(deck_top, ramp_run)
	var depth := 0.22
	var ramp := p + Vector3(-18.0 + sin(angle) * depth, deck_top * 0.5 - cos(angle) * depth, 0)
	C.quad(parent, p + Vector3.UP * 0.004, Vector2(70.0, 58.0), asphalt)
	C.box(parent, world, ramp, Vector3(Vector2(ramp_run, deck_top).length() * 0.5, depth, 3.4), Vector3(0, 0, angle), concrete, 1.0)
	C.box(parent, world, p + Vector3(11.5, deck_top * 0.5, 0), Vector3(17.5, deck_top * 0.5, 15.5), Vector3.ZERO, concrete)
	for side: float in [-1.0, 1.0]:
		C.box(parent, world, p + Vector3(11.5, deck_top + 0.37, side * 15.5), Vector3(17.5, 0.37, 0.19), Vector3.ZERO, concrete)
		C.box(parent, world, p + Vector3(-5.9, deck_top + 0.37, side * 9.5), Vector3(0.17, 0.37, 6.0), Vector3.ZERO, concrete)
		C.quad(parent, p + Vector3(11.5, deck_top + 0.012, side * 14.4), Vector2(34, 0.16), stripe)
	C.box(parent, world, p + Vector3(29, deck_top + 0.37, 0), Vector3(0.20, 0.37, 15.5), Vector3.ZERO, concrete)
	for x in range(-2, 28, 4):
		for side: float in [-1.0, 1.0]:
			C.quad(parent, p + Vector3(x, deck_top + 0.014, side * 11.0), Vector2(0.12, 5.6), paint)
	var entry := p + Vector3(-34.0, 0, 0)
	var curb_angle := atan2(KERB, 3.6)
	C.box(parent, world, entry + Vector3(-3.8, -0.13, 0), Vector3(1.81, 0.05, 3.4), Vector3(0, 0, curb_angle), concrete)
	var sign := p + Vector3(-27, 1.9, -4.5)
	C.box(parent, world, sign, Vector3(0.08, 0.36, 0.94), Vector3.ZERO, C.mat(Color(0.09, 0.27, 0.49)), 0.7, false)
	C.box(parent, world, sign - Vector3.UP * 0.92, Vector3(0.07, 0.92, 0.07), Vector3.ZERO, concrete)
	C.label3d(parent, "P  PARKDECK", sign - Vector3.RIGHT * 0.09, -PI * 0.5, 0.25)


static func _freight_yard(parent: Node3D, world: SBWorld, center: Vector3, asphalt: Material, metal: Material) -> void:
	var p := Vector3(center.x, KERB, center.z)
	var concrete := C.mat(Color(0.46, 0.49, 0.52))
	var orange := C.mat(Color(0.73, 0.30, 0.14))
	var green := C.mat(Color(0.17, 0.40, 0.42))
	C.quad(parent, p + Vector3.UP * 0.004, Vector2(69, 69), asphalt)
	C.box(parent, world, p + Vector3(0, 4.5, 22), Vector3(28, 4.5, 9), Vector3.ZERO, concrete)
	C.box(parent, world, p + Vector3(0, 9.1, 21), Vector3(28.6, 0.3, 10.6), Vector3.ZERO, metal, 0.8, false)
	for bay in 7:
		var x := -23.0 + bay * 7.5
		C.box(parent, world, p + Vector3(x, 2.3, 12.91), Vector3(2.65, 2.3, 0.11), Vector3.ZERO, metal, 0.75, false)
		C.quad(parent, p + Vector3(x, 0.014, 8.2), Vector2(4.7, 0.15), orange)
	for x: float in [-25.0, 25.0]:
		for slot in 3:
			var row := p + Vector3(x, 1.42, -26.0 + slot * 8.0)
			C.box(parent, world, row, Vector3(6.2, 1.42, 1.45), Vector3.ZERO, orange if slot % 2 == 0 else green)
			if slot == 0:
				C.box(parent, world, row + Vector3(0.32, 2.84, 0), Vector3(6.2, 1.42, 1.45), Vector3.ZERO, green)
	C.label3d(parent, "FRACHTTERMINAL  /  08", p + Vector3(0, 6.55, 12.85), PI, 1.0)


static func _market(parent: Node3D, world: SBWorld, center: Vector3, pavement: Material, metal: Material) -> void:
	var p := Vector3(center.x, KERB, center.z)
	var tile := C.surface_material("pavement", 1.8, Color(0.82, 0.74, 0.65))
	var timber := C.mat(Color(0.40, 0.25, 0.13))
	var canvas := [C.mat(Color(0.68, 0.19, 0.19)), C.mat(Color(0.20, 0.46, 0.43)), C.mat(Color(0.86, 0.65, 0.28))]
	C.quad(parent, p + Vector3.UP * 0.005, Vector2(58, 58), tile)
	for side: float in [-1.0, 1.0]:
		for i in 4:
			var stall := p + Vector3(-18.0 + i * 12.0, 0, side * 16.0)
			C.box(parent, world, stall + Vector3(0, 0.67, 0), Vector3(3.4, 0.67, 1.5), Vector3.ZERO, timber, 0.8)
			for end: float in [-1.0, 1.0]:
				C.box(parent, world, stall + Vector3(end * 3.23, 1.77, 0), Vector3(0.09, 1.77, 0.09), Vector3.ZERO, metal, 0.75, false)
			C.box(parent, world, stall + Vector3.UP * 3.6, Vector3(3.72, 0.12, 2.1), Vector3.ZERO, canvas[i % canvas.size()], 0.8, false)
	C.box(parent, world, p + Vector3(0, 0.45, 0), Vector3(4.5, 0.45, 4.5), Vector3.ZERO, pavement)
	var market_tree: Array[Vector3] = [p + Vector3.UP * 0.9]
	V.plant(parent, "broadleaf", market_tree, 77, 0.95, 1.0)


static func _townhouses(parent: Node3D, world: SBWorld, center: Vector3, grass: Material) -> void:
	var p := Vector3(center.x, KERB, center.z)
	var window := C.mat(Color(0.17, 0.27, 0.34), 0.30)
	var roof := C.mat(Color(0.37, 0.19, 0.15))
	var walls := [C.mat(Color(0.65, 0.43, 0.32)), C.mat(Color(0.65, 0.63, 0.51)), C.mat(Color(0.54, 0.58, 0.61))]
	var windows: Array[Transform3D] = []
	var roofs: Array[Transform3D] = []
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(1.86, 1.34, 0.11)
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(15.8, 0.32, 6.24)
	C.quad(parent, p + Vector3.UP * 0.006, Vector2(66, 64), grass)
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var house := p + Vector3(-21.0 + i * 21.0, 0, side * 19.0)
			C.box(parent, world, house + Vector3.UP * 2.7, Vector3(7.6, 2.7, 5.5), Vector3.ZERO, walls[i])
			for slope: float in [-1.0, 1.0]:
				roofs.append(Transform3D(Basis(Vector3.RIGHT, 0.32 * slope), house + Vector3(0, 6.2, slope * 2.85)))
			for floor_index in 2:
				for x: float in [-4.6, 0.0, 4.6]:
					windows.append(Transform3D(Basis(), house + Vector3(x, 1.62 + 2.35 * floor_index, side * 5.53)))
	C.scatter_multimesh(parent, roof_mesh, roof, roofs)
	C.scatter_multimesh(parent, window_mesh, window, windows, false)


static func _plaza(parent: Node3D, world: SBWorld, center: Vector3, station: bool, concrete: Material, metal: Material) -> void:
	var p := Vector3(center.x, KERB, center.z)
	var tiles := C.surface_material("pavement", 1.8, Color(0.80, 0.84, 0.85), 0.25)
	var glass := C.mat(Color(0.15, 0.30, 0.39), 0.3, 0.30)
	var accent := C.mat(Color(0.08, 0.35, 0.37) if station else Color(0.65, 0.27, 0.17), 0.52)
	C.quad(parent, p + Vector3.UP * 0.003, Vector2(61, 60), tiles)
	for sign: float in [-1.0, 1.0]:
		C.box(parent, world, p + Vector3(0, 0.35, sign * 24), Vector3(19, 0.35, 1.35), Vector3.ZERO, concrete)
		C.box(parent, world, p + Vector3(0, 0.71, sign * 24), Vector3(18.7, 0.05, 1.14), Vector3.ZERO, C.mat(Color(0.23, 0.37, 0.19)), 0.8, false)
	if station:
		for x: float in [-14.0, -5.0, 5.0, 14.0]:
			C.box(parent, world, p + Vector3(x, 2.3, 0), Vector3(0.19, 2.3, 0.19), Vector3.ZERO, metal, 0.7)
		C.box(parent, world, p + Vector3(0, 4.65, 0), Vector3(17, 0.21, 5.8), Vector3.ZERO, accent, 0.8, false)
		C.box(parent, world, p + Vector3(0, 1.33, 3.8), Vector3(8.1, 1.33, 0.14), Vector3.ZERO, glass)
		C.label3d(parent, "U   /   NORDPLATZ", p + Vector3(0, 4.67, -5.85), PI, 0.70)
		C.label3d(parent, "U   /   NORDPLATZ", p + Vector3(0, 4.67, 5.85), 0.0, 0.70)
	else:
		C.box(parent, world, p + Vector3(0, 0.72, 0), Vector3(4.0, 0.72, 4.0), Vector3.ZERO, concrete)
		for i in 3:
			C.box(parent, world, p + Vector3.UP * (2.1 + i * 2.3), Vector3(1.4, 1.15, 1.35), Vector3(0, i * 0.42, 0.13), accent, 0.8, false)
