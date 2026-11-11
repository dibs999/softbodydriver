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


const FACADE_SHADER := preload("res://materials/facade.gdshader")


## Facade palettes: wall colour, window frame colour, style (0 plaster, 1 brick, 2 glass office).
static func _facade_material(base: Color, frame: Color, style: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("wall_color", base)
	m.set_shader_parameter("frame_color", frame)
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("grain", load(C.SURFACE_PATH + "pavement.jpg"))
	if style == 2:
		m.set_shader_parameter("floor_height", 3.8)
		m.set_shader_parameter("bay_width", 1.6)
		m.set_shader_parameter("recess", 0.05)
	elif style == 1:
		m.set_shader_parameter("window_width", 0.46)
		m.set_shader_parameter("window_height", 0.6)
	return m


## Facade shader reads the building size from the instance scale, so use a unit box.
static func _facade_box(parent: Node3D, world: SBWorld, center: Vector3, half: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = material
	mi.transform = Transform3D(Basis.from_scale(half * 2.0), center)
	parent.add_child(mi)
	world.add_box(center, half, Vector3.ZERO, 0.8)


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

	var facades: Array[Material] = [
		_facade_material(Color(0.62, 0.58, 0.51), Color(0.9, 0.89, 0.85), 0),
		_facade_material(Color(0.47, 0.49, 0.5), Color(0.2, 0.21, 0.22), 2),
		_facade_material(Color(0.7, 0.64, 0.54), Color(0.32, 0.25, 0.2), 0),
		_facade_material(Color(0.52, 0.53, 0.55), Color(0.75, 0.76, 0.77), 2),
		_facade_material(Color(0.55, 0.33, 0.24), Color(0.92, 0.92, 0.9), 1),
		_facade_material(Color(0.78, 0.74, 0.66), Color(0.25, 0.27, 0.3), 0),
	]
	var roof_mat := C.mat(Color(0.25, 0.25, 0.26), 0.8)
	var pavements: Array[Transform3D] = []
	var street_trees: Array[Vector3] = []
	var grates: Array[Transform3D] = []
	var roofs: Array[Transform3D] = []
	var rooftop_units: Array[Transform3D] = []
	var plinths: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	var cornices: Array[Transform3D] = []
	var parapets: Array[Transform3D] = []
	var gables: Array[Transform3D] = []
	var ac_units: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	var antennas: Array[Transform3D] = []
	var gates: Array[Transform3D] = []
	var dumpsters: Array[Transform3D] = []
	var dumpster_lids: Array[Transform3D] = []
	var bins: Array = []   # loose wheelie bins (soft-body props)
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
				for t in trees:
					if V.keep(t): world.add_box(t + Vector3.UP * 1.5, Vector3(0.2, 1.5, 0.2), Vector3.ZERO, 0.7)
				V.plant(parent, "broadleaf", trees, block.x * 31 + block.y, 0.75, 1.1)
				if block == Vector2i(4, 5):
					places.append({"name": "Stadtpark", "position": c})
				continue
			if block in [Vector2i(5, 5), Vector2i(7, 6)]:
				_plaza(parent, world, c, bx == 5, pavement, metal)
				places.append({"name": "U-Bahn Nordplatz" if bx == 5 else "Skulpturenplatz", "position": c})
				continue
			# Street trees in grates on the two kerbs without lamps; trunks collide.
			for k in 3:
				var t := 14.0 + k * 22.0
				for p: Vector3 in [Vector3(x0 + t, KERB, z0 + BLOCK - 1.7), Vector3(x0 + BLOCK - 1.7, KERB, z0 + t)]:
					if not V.keep(p): continue
					street_trees.append(p)
					world.add_box(p + Vector3.UP * 1.5, Vector3(0.16, 1.5, 0.16), Vector3.ZERO, 0.7)
					grates.append(Transform3D(Basis.from_scale(Vector3(1.5, 1.0, 1.5)), p + Vector3.UP * 0.005))
			# Collection day on some streets: pairs of wheelie bins at the kerb between the trees,
			# handles and wheels towards the road.
			if (bx * 3 + bz) % 7 == 0:
				for t: float in [25.0]:
					for k in 2:
						bins.append({"kind": "bin", "position": Vector3(x0 + t + k * 0.68, KERB, z0 + BLOCK - 1.0), "yaw": PI * 0.5})
						bins.append({"kind": "bin", "position": Vector3(x0 + BLOCK - 1.0, KERB, z0 + t + k * 0.68), "yaw": PI})
			# 1..4 buildings per block.
			var split := rng.randi_range(1, 2)
			var margin := 3.0
			if split == 2:
				# Back alleys between the four houses: gates at the four mouths, dumpsters inside.
				var mid := Vector2(x0 + BLOCK * 0.5, z0 + BLOCK * 0.5)
				for edge: float in [margin + 1.5, BLOCK - margin - 1.5]:
					for gate_pos: Vector3 in [Vector3(mid.x, KERB + 1.1, z0 + edge), Vector3(x0 + edge, KERB + 1.1, mid.y)]:
						var across_x := absf(gate_pos.x - mid.x) < 0.1
						var gate_half := Vector3(1.5, 1.1, 0.06) if across_x else Vector3(0.06, 1.1, 1.5)
						gates.append(Transform3D(Basis.from_scale(gate_half * 2.0), gate_pos))
						world.add_box(gate_pos, gate_half, Vector3.ZERO, 0.6)
				for k in 2:
					var along := rng.randf_range(6.0, 16.0) * (1.0 if k == 0 else -1.0)
					var dp := Vector3(mid.x + along, KERB, mid.y) if rng.randf() < 0.5 else Vector3(mid.x, KERB, mid.y + along)
					var yaw := Basis(Vector3.UP, 0.0 if absf(dp.z - mid.y) < 0.1 else PI * 0.5)
					dumpsters.append(Transform3D(yaw.scaled_local(Vector3(1.8, 1.2, 1.1)), dp + Vector3.UP * 0.62))
					var along_alley := yaw.x * (1.0 if along > 0.0 else -1.0)
					for n in (2 if k == 0 and (bx + 2 * bz) % 3 == 0 else 0):
						# Side by side beyond the dumpster's end, lids towards the alley wall.
						bins.append({"kind": "bin", "position": dp + along_alley * (1.4 + n * 0.68), "yaw": atan2(-yaw.x.z, yaw.x.x) + PI * 0.5})
					dumpster_lids.append(Transform3D(yaw.scaled_local(Vector3(1.86, 0.08, 1.16)), dp + Vector3.UP * 1.26))
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
					# Plinth, floor bands every two storeys and a cornice with parapet instead of a bare box.
					# Buildings over 12 m have a shop ground floor (facade shader) and no stone plinth
					# in front of its shop windows and glass doors.
					if hgt <= 12.0:
						plinths.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0 + 0.16, 0.9, half.z * 2.0 + 0.16)), Vector3(bxc, KERB + 0.45, bzc)))
					var band := 6.4
					while band < hgt - 2.0:
						bands.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0 + 0.12, 0.16, half.z * 2.0 + 0.12)), Vector3(bxc, KERB + band, bzc)))
						band += 6.4
					var pitched := hgt < 13.0 and urban < 0.35
					if pitched:
						# Low houses at the edge of town: gabled tile roofs.
						var ridge := Basis(Vector3.UP, PI * 0.5 if half.x > half.z else 0.0)
						var span := minf(half.x, half.z)
						# Roof rise as on real town houses (~45 degrees on narrow ones, capped at 6 m).
						var rise := minf(span * 0.9, 6.0)
						gables.append(Transform3D(ridge.scaled_local(Vector3(span * 2.1, rise, maxf(half.x, half.z) * 2.05)), Vector3(bxc, KERB + hgt + rise * 0.5, bzc)))
					else:
						roofs.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.02, 0.65, half.z * 2.02)), Vector3(bxc, KERB + hgt + 0.32, bzc)))
						cornices.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0 + 0.5, 0.45, half.z * 2.0 + 0.5)), Vector3(bxc, KERB + hgt - 0.2, bzc)))
						for side_x: float in [-1.0, 1.0]:
							parapets.append(Transform3D(Basis.from_scale(Vector3(0.25, 0.9, half.z * 2.0)), Vector3(bxc + side_x * (half.x - 0.12), KERB + hgt + 1.0, bzc)))
						for side_z: float in [-1.0, 1.0]:
							parapets.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0, 0.9, 0.25)), Vector3(bxc, KERB + hgt + 1.0, bzc + side_z * (half.z - 0.12))))
						# Roof clutter: stair house, AC units, water tank, antenna.
						rooftop_units.append(Transform3D(Basis.from_scale(Vector3(4.2, 3.0, 3.2)), Vector3(bxc + half.x * 0.35, KERB + hgt + 2.1, bzc - half.z * 0.3)))
						for k in rng.randi_range(2, 5):
							ac_units.append(Transform3D(Basis.from_scale(Vector3(1.4, 1.0, 1.0)), Vector3(bxc + rng.randf_range(-0.7, 0.7) * half.x, KERB + hgt + 1.15, bzc + rng.randf_range(-0.7, 0.7) * half.z)))
						if rng.randf() < 0.4:
							tanks.append(Transform3D(Basis.IDENTITY, Vector3(bxc - half.x * 0.4, KERB + hgt + 2.4, bzc + half.z * 0.35)))
						if hgt > 30.0 and rng.randf() < 0.5:
							antennas.append(Transform3D(Basis.from_scale(Vector3(0.12, 9.0, 0.12)), Vector3(bxc - half.x * 0.2, KERB + hgt + 5.0, bzc - half.z * 0.2)))
	C.scatter_multimesh(parent, box_mesh, pavement, pavements, false)
	C.scatter_multimesh(parent, box_mesh, roof_mat, roofs, false)
	C.scatter_multimesh(parent, box_mesh, metal, rooftop_units, false)
	var stone := C.noise_mat(Color(0.56, 0.54, 0.50), 0.08, 2.0, 0.9)
	var dark_stone := C.noise_mat(Color(0.30, 0.29, 0.28), 0.1, 2.0, 0.9)
	C.scatter_multimesh(parent, box_mesh, dark_stone, plinths)
	C.scatter_multimesh(parent, box_mesh, stone, bands, false)
	C.scatter_multimesh(parent, box_mesh, stone, cornices)
	C.scatter_multimesh(parent, box_mesh, stone, parapets, false)
	var gable := PrismMesh.new()
	gable.size = Vector3.ONE
	C.scatter_multimesh(parent, gable, C.noise_mat(Color(0.48, 0.20, 0.13), 0.12, 3.0, 0.85), gables)
	C.scatter_multimesh(parent, box_mesh, C.mat(Color(0.62, 0.63, 0.64), 0.5, 0.6), ac_units, false)
	var tank := CylinderMesh.new()
	tank.top_radius = 1.1
	tank.bottom_radius = 1.1
	tank.height = 2.4
	tank.radial_segments = 12
	C.scatter_multimesh(parent, tank, C.mat(Color(0.42, 0.33, 0.24), 0.8), tanks, false)
	C.scatter_multimesh(parent, box_mesh, metal, antennas, false)
	C.scatter_multimesh(parent, box_mesh, C.mat(Color(0.22, 0.23, 0.24), 0.45, 0.7), gates)
	C.scatter_multimesh(parent, box_mesh, C.noise_mat(Color(0.20, 0.30, 0.42), 0.18, 3.0, 0.7), dumpsters, false)
	C.scatter_multimesh(parent, box_mesh, C.mat(Color(0.12, 0.12, 0.12), 0.7), dumpster_lids, false)
	for i in buildings.size():
		C.scatter_multimesh(parent, box_mesh, facades[i], buildings[i])

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
	var lens := SphereMesh.new()
	lens.radius = 0.1
	lens.height = 0.2
	lens.radial_segments = 8
	lens.rings = 4
	var signals := preload("res://scripts/maps/traffic_signals.gd").new()
	signals.name = "TrafficSignals"
	signals.stop_offset = STREET * 0.5 + 1.5
	var colours := [Color(1.0, 0.12, 0.05), Color(1.0, 0.62, 0.05), Color(0.1, 1.0, 0.3)]
	var heights := [4.6, 4.32, 4.04]
	var lens_xforms := {"x": [[], [], []], "z": [[], [], []]}
	var signal_posts: Array[Transform3D] = []
	var signal_heads: Array[Transform3D] = []
	for ix in BLOCKS + 1:
		for iz in BLOCKS + 1:
			var cx := origin + STREET * 0.5 + ix * PITCH
			var cz := origin + STREET * 0.5 + iz * PITCH
			signals.centers.append(Vector2(cx, cz))
			for corner in [Vector2(1, 1), Vector2(-1, -1)]:
				var p := Vector3(cx + corner.x * (STREET * 0.5 + 1.2), 0, cz + corner.y * (STREET * 0.5 + 1.2))
				world.add_box(p + Vector3(0, 2.0, 0), Vector3(0.09, 2.0, 0.09), Vector3.ZERO, 0.6)
				signal_posts.append(Transform3D(Basis.from_scale(Vector3(0.18, 4.0, 0.18)), p + Vector3.UP * 2.0))
				signal_heads.append(Transform3D(Basis.from_scale(Vector3(0.36, 0.90, 0.36)), p + Vector3.UP * 4.3))
				for k in 3:
					# One lens set faces traffic along X, the other traffic along Z.
					lens_xforms["x"][k].append(Transform3D(Basis(), p + Vector3(-corner.x * 0.19, heights[k], 0)))
					lens_xforms["z"][k].append(Transform3D(Basis(), p + Vector3(0, heights[k], -corner.y * 0.19)))
	C.scatter_multimesh(parent, box_mesh, metal, signal_posts, false)
	C.scatter_multimesh(parent, box_mesh, light_box, signal_heads, false)
	for axis in ["x", "z"]:
		for k in 3:
			var m := C.mat(colours[k] * 0.25, 0.3)
			m.emission_enabled = true
			m.emission = colours[k]
			m.emission_energy_multiplier = 0.0
			signals.lenses[axis].append(m)
			var arr: Array[Transform3D] = []
			for xf in lens_xforms[axis][k]: arr.append(xf)
			C.scatter_multimesh(parent, lens, m, arr, false)
	parent.add_child(signals)
	var lamp_pole := CylinderMesh.new()
	lamp_pole.top_radius = 0.06
	lamp_pole.bottom_radius = 0.1
	lamp_pole.height = 7.0
	lamp_pole.radial_segments = 8
	lamp_pole.rings = 0
	var lamps: Array[Transform3D] = []
	var lamp_heads: Array[Transform3D] = []
	var lamp_lights := PackedVector3Array()
	var lenses: Array[Transform3D] = []
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
				lamp_lights.append(Vector3(x0 + t, 6.85, z0 - 0.35))
				lamp_lights.append(Vector3(x0 - 0.35, 6.85, z0 + t))
				lenses.append(Transform3D(Basis.from_scale(Vector3(0.16, 0.02, 0.5)), Vector3(x0 + t, 6.92, z0 - 0.3)))
				lenses.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.02, 0.16)), Vector3(x0 - 0.3, 6.92, z0 + t)))
	C.scatter_multimesh(parent, lamp_pole, metal, lamps, false)
	V.plant(parent, "broadleaf", street_trees, 4242, 0.55, 0.72)
	var grate := PlaneMesh.new()
	grate.size = Vector2.ONE
	C.scatter_multimesh(parent, grate, C.noise_mat(Color(0.16, 0.13, 0.1), 0.4, 0.8), grates, false)
	C.scatter_multimesh(parent, box_mesh, metal, lamp_heads, false)
	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = Color(0.9, 0.88, 0.8)
	lens_material.emission_enabled = true
	lens_material.emission = Color(1.0, 0.85, 0.62)
	lens_material.emission_energy_multiplier = 0.0
	C.scatter_multimesh(parent, box_mesh, lens_material, lenses, false)
	var street_lighting := preload("res://scripts/maps/street_lighting.gd").new()
	street_lighting.name = "StreetLighting"
	parent.add_child(street_lighting)
	street_lighting.setup(lamp_lights, lens_material)

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
	# Roadworks: the kerb lane of an east-west street away from the traffic loop is closed by a
	# cone line with a taper and a few drums.
	var props: Array = []
	_works = Vector3i(-1, -1, 0)
	for k in range(BLOCKS - 2, 1, -1):
		var zs := origin + k * PITCH + STREET * 0.5
		var done := false
		for j in range(2, BLOCKS - 2):
			var x0 := origin + j * PITCH + STREET
			var mid := Vector3(x0 + BLOCK * 0.5, 0.0, zs)
			var clear := true
			for r in route:
				if Vector2(r.x - mid.x, r.z - mid.z).length() < 45.0:
					clear = false
					break
			if not clear:
				continue
			for n in 14:
				var x := x0 + 10.0 + n * 3.8
				var z := zs + (4.1 + maxf(0.0, 3.0 - n) * 0.9)   # taper into the lane divider
				props.append({"kind": "cone", "position": Vector3(x, 0.0, z)})
			for d in 3:
				props.append({"kind": "barrel", "position": Vector3(x0 + 32.0 + d * 0.7, 0.0, zs + 6.6)})
			for d in 2:
				props.append({"kind": "barrier", "position": Vector3(x0 + 22.0, 0.0, zs + 5.0 + d * 1.25), "yaw": PI * 0.5})
			_works = Vector3i(k, j, 1)
			done = true
			break
		if done:
			break
	props.append_array(bins)
	_street_life(parent, world, origin, metal)
	var speeds := C.speeds_from_curvature(route, 13.5, 6.0, 25.0)
	var spawn_p := Vector3(origin + STREET * 0.5 + 5 * PITCH - 4.0, 0, origin + STREET * 0.5 + 5 * PITCH + 20.0)
	var map_paths: Array[PackedVector3Array] = []
	for i in BLOCKS + 1:
		var s := origin + STREET * 0.5 + i * PITCH
		map_paths.append(PackedVector3Array([Vector3(origin, 0, s), Vector3(-origin, 0, s)]))
		map_paths.append(PackedVector3Array([Vector3(s, 0, origin), Vector3(s, 0, -origin)]))
	return {
		"props": props,
		"spawns": [C.car_xform(spawn_p, Vector3(0, 0, 1)), C.car_xform(spawn_p + Vector3(0, 0, -12), Vector3(0, 0, 1))],
		"waypoints": route, "speeds": speeds,
		"map_paths": map_paths, "map_places": places,
		"surface_regions": surface_regions,
		"traffic_signals": signals,
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
				_facade_box(parent, world, h + Vector3.UP * height * 0.5, Vector3(7.2, height * 0.5, 10), _facade_material(colors[i], Color(0.93, 0.92, 0.88), 0))
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
	## Six terraced family houses: plastered or brick walls with gable ends, framed windows front and
	## back, front doors with steps, chimneys, hedged front gardens with paths, fenced back gardens
	## with sheds and trees.
	var p := Vector3(center.x, KERB, center.z)
	var window := C.mat(Color(0.10, 0.15, 0.19), 0.08, 0.4)
	var roof := C.noise_mat(Color(0.40, 0.19, 0.14), 0.12, 3.0, 0.85)
	var trim := C.mat(Color(0.86, 0.85, 0.80), 0.7)
	var walls := [C.noise_mat(Color(0.62, 0.38, 0.28), 0.10, 6.0, 0.9), C.noise_mat(Color(0.70, 0.67, 0.55), 0.06, 3.0, 0.9),
		C.noise_mat(Color(0.56, 0.60, 0.62), 0.06, 3.0, 0.9)]
	var windows: Array[Transform3D] = []
	var sills: Array[Transform3D] = []
	var roofs: Array[Transform3D] = []
	var gables: Array = []
	for i in 3:
		var batch: Array[Transform3D] = []
		gables.append(batch)
	var doors: Array[Transform3D] = []
	var steps: Array[Transform3D] = []
	var chimneys: Array[Transform3D] = []
	var paths: Array[Transform3D] = []
	var hedges: Array[Transform3D] = []
	var fences: Array[Transform3D] = []
	var sheds: Array[Transform3D] = []
	var trees: Array[Vector3] = []
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(1.86, 1.34, 0.11)
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(15.8, 0.32, 6.24)
	var unit := BoxMesh.new()
	var gable := PrismMesh.new()
	gable.size = Vector3.ONE
	C.quad(parent, p + Vector3.UP * 0.006, Vector2(66, 64), grass)
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var house := p + Vector3(-21.0 + i * 21.0, 0, side * 19.0)
			C.box(parent, world, house + Vector3.UP * 2.7, Vector3(7.6, 2.7, 5.5), Vector3.ZERO, walls[i])
			for slope: float in [-1.0, 1.0]:
				roofs.append(Transform3D(Basis(Vector3.RIGHT, 0.32 * slope), house + Vector3(0, 6.2, slope * 2.85)))
			# Gable end walls close the triangles under the roof.
			for end: float in [-1.0, 1.0]:
				gables[i].append(Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(11.0, 1.85, 0.2)), house + Vector3(end * 7.5, 5.4 + 0.925, 0)))
			for face: float in [side, -side]:
				for floor_index in 2:
					for x: float in [-4.6, 0.0, 4.6]:
						if face == side and floor_index == 0 and x == 0.0:
							continue
						var w := house + Vector3(x, 1.62 + 2.35 * floor_index, face * 5.53)
						windows.append(Transform3D(Basis(), w))
						sills.append(Transform3D(Basis.from_scale(Vector3(2.1, 0.08, 0.26)), w + Vector3(0, -0.72, face * 0.08)))
						sills.append(Transform3D(Basis.from_scale(Vector3(2.1, 0.16, 0.12)), w + Vector3(0, 0.74, face * 0.02)))
						# White frame and a centre mullion over the glass.
						var fz := face * 0.065
						for fy: float in [-0.67, 0.67]:
							sills.append(Transform3D(Basis.from_scale(Vector3(2.0, 0.1, 0.05)), w + Vector3(0, fy, fz)))
						for fx: float in [-0.93, 0.0, 0.93]:
							sills.append(Transform3D(Basis.from_scale(Vector3(0.1 if fx != 0.0 else 0.07, 1.34, 0.05)), w + Vector3(fx, 0, fz)))
			doors.append(Transform3D(Basis.from_scale(Vector3(1.1, 2.1, 0.08)), house + Vector3(0, 1.17, side * 5.53)))
			sills.append(Transform3D(Basis.from_scale(Vector3(1.5, 0.14, 0.14)), house + Vector3(0, 2.3, side * 5.56)))
			steps.append(Transform3D(Basis.from_scale(Vector3(1.8, 0.16, 1.0)), house + Vector3(0, 0.08, side * 6.0)))
			steps.append(Transform3D(Basis.from_scale(Vector3(15.32, 0.45, 11.08)), house + Vector3(0, 0.22, 0)))
			chimneys.append(Transform3D(Basis.from_scale(Vector3(0.7, 1.9, 0.7)), house + Vector3(4.2, 6.9, -side * 1.5)))
			# Front garden: path to the door and a hedge with a gap for it.
			paths.append(Transform3D(Basis.from_scale(Vector3(1.3, 0.05, 11.0)), house + Vector3(0, 0.02, side * 11.5)))
			for gap: float in [-1.0, 1.0]:
				var hp := house + Vector3(gap * 5.75, 0.55, side * 13.0)
				hedges.append(Transform3D(Basis.from_scale(Vector3(8.5, 1.1, 0.7)), hp))
				world.add_box(hp, Vector3(4.25, 0.55, 0.35), Vector3.ZERO, 0.6)
			sheds.append(Transform3D(Basis.from_scale(Vector3(2.2, 2.1, 2.6)), house + Vector3(5.5, 1.05, -side * 14.0)))
			trees.append(house + Vector3(-4.5, 0, -side * 13.0))
	# Fences between the plots and between the two rows of back gardens.
	for fx: float in [-10.5, 10.5]:
		fences.append(Transform3D(Basis.from_scale(Vector3(0.06, 1.0, 64.0)), p + Vector3(fx, 0.5, 0)))
	fences.append(Transform3D(Basis.from_scale(Vector3(63.0, 1.0, 0.06)), p + Vector3(0, 0.5, 0)))
	C.scatter_multimesh(parent, roof_mesh, roof, roofs)
	for i in 3:
		C.scatter_multimesh(parent, gable, walls[i], gables[i])
	C.scatter_multimesh(parent, window_mesh, window, windows, false)
	C.scatter_multimesh(parent, unit, trim, sills, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.30, 0.17, 0.10), 0.1, 6.0, 0.7), doors, false)
	C.scatter_multimesh(parent, unit, C.mat(Color(0.55, 0.54, 0.51)), steps, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.45, 0.22, 0.16), 0.1, 6.0), chimneys)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.58, 0.56, 0.52), 0.1, 2.0), paths, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.16, 0.30, 0.11), 0.25, 1.5), hedges)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.44, 0.33, 0.22), 0.12, 5.0), fences, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.36, 0.30, 0.22), 0.12, 5.0), sheds)
	for t in trees:
		if V.keep(t): world.add_box(t + Vector3.UP * 1.5, Vector3(0.18, 1.5, 0.18), Vector3.ZERO, 0.7)
	V.plant(parent, "broadleaf", trees, 913, 0.55, 0.8)


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
		_fountain(parent, world, p)


## Market fountain: a round sandstone basin (9 m) with a moulded rim, a water surface, a column with
## two bowls that spill into each other, a fine spray, and benches round it facing the water. It
## replaced an abstract sculpture of three boxes.
static func _fountain(parent: Node3D, world: SBWorld, p: Vector3) -> void:
	var sandstone := C.noise_mat(Color(0.56, 0.49, 0.40), 0.10, 3.0, 0.85)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.13, 0.24, 0.27, 0.86)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.06
	water.metallic = 0.25
	var falling := StandardMaterial3D.new()
	falling.albedo_color = Color(0.70, 0.80, 0.86, 0.16)
	falling.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	falling.roughness = 0.1
	var add := func(mesh: Mesh, at: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = at
		parent.add_child(mi)
	var cyl := func(r_top: float, r_bottom: float, h: float, segs := 32) -> CylinderMesh:
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bottom
		c.height = h
		c.radial_segments = segs
		return c
	var ring := func(inner: float, outer: float) -> TorusMesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 48
		t.ring_segments = 12
		return t
	# Basin: a low floor, a round wall with a moulded rim (rings, so the water shows), water inside.
	add.call(cyl.call(4.45, 4.55, 0.24), p + Vector3.UP * 0.12, sandstone)
	add.call(ring.call(4.15, 4.65), p + Vector3.UP * 0.42, sandstone)
	add.call(ring.call(4.3, 4.78), p + Vector3.UP * 0.66, sandstone)
	add.call(cyl.call(4.32, 4.32, 0.02), p + Vector3.UP * 0.55, water)
	# Column with a wide lower bowl and a smaller upper one, water falling from each rim.
	add.call(cyl.call(0.32, 0.45, 2.4, 16), p + Vector3.UP * 1.7, sandstone)
	add.call(cyl.call(1.7, 0.35, 0.45, 24), p + Vector3.UP * 2.5, sandstone)
	add.call(ring.call(1.58, 1.82), p + Vector3.UP * 2.74, sandstone)
	add.call(cyl.call(1.62, 1.62, 0.02, 24), p + Vector3.UP * 2.75, water)
	add.call(cyl.call(0.2, 0.28, 1.2, 12), p + Vector3.UP * 3.3, sandstone)
	add.call(cyl.call(0.9, 0.2, 0.3, 20), p + Vector3.UP * 3.95, sandstone)
	add.call(ring.call(0.82, 0.98), p + Vector3.UP * 4.11, sandstone)
	add.call(cyl.call(0.86, 0.86, 0.02, 20), p + Vector3.UP * 4.12, water)
	var finial := SphereMesh.new()
	finial.radius = 0.22
	finial.height = 0.44
	add.call(finial, p + Vector3.UP * 4.35, sandstone)
	# Curtains of water from the bowl rims (thin translucent tubes).
	add.call(cyl.call(1.72, 1.82, 1.95, 32), p + Vector3.UP * 1.52, falling)
	add.call(cyl.call(0.92, 1.0, 1.3, 24), p + Vector3.UP * 3.38, falling)
	# Spray where the water lands.
	var spray := CPUParticles3D.new()
	spray.amount = 70
	spray.lifetime = 0.9
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	spray.emission_ring_radius = 1.8
	spray.emission_ring_inner_radius = 1.6
	spray.emission_ring_height = 0.05
	spray.emission_ring_axis = Vector3.UP
	spray.direction = Vector3.UP
	spray.spread = 35.0
	spray.initial_velocity_min = 0.4
	spray.initial_velocity_max = 1.2
	spray.gravity = Vector3(0, -4.0, 0)
	spray.scale_amount_min = 0.5
	spray.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = 0.03
	drop.height = 0.06
	drop.radial_segments = 4
	drop.rings = 2
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.55)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = drop_mat
	spray.mesh = drop
	spray.position = p + Vector3.UP * 0.58
	spray.visibility_range_end = 70.0
	parent.add_child(spray)
	if world:
		# An octagon of boxes approximates the round basin wall; the column stands in the middle.
		for k in 8:
			var a := TAU * k / 8.0
			world.add_box(p + Vector3(cos(a), 0, sin(a)) * 4.3 + Vector3.UP * 0.37, Vector3(0.3, 0.37, 1.85), Vector3(0, -a, 0), 0.7)
		world.add_box(p + Vector3.UP * 1.5, Vector3(0.45, 1.5, 0.45), Vector3.ZERO, 0.7)
	# Benches round the fountain, facing the water.
	var wood := C.noise_mat(Color(0.42, 0.28, 0.16), 0.1, 5.0, 0.8)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var out := Vector3(cos(a), 0, sin(a))
		var at := p + out * 7.5
		var yaw := atan2(out.x, out.z)
		var along := Vector3(out.z, 0, -out.x)
		C.box(parent, world, at + Vector3.UP * 0.45, Vector3(0.9, 0.04, 0.22), Vector3(0, yaw, 0), wood, 0.6)
		C.box(parent, null, at + out * 0.22 + Vector3.UP * 0.75, Vector3(0.9, 0.22, 0.03), Vector3(0, yaw, 0), wood, 0.6, false)
		for leg: float in [-0.75, 0.75]:
			C.box(parent, null, at + along * leg + Vector3.UP * 0.21, Vector3(0.04, 0.21, 0.2), Vector3(0, yaw, 0), C.mat(Color(0.2, 0.21, 0.22), 0.5, 0.6), 0.6, false)


## Closed kerb lane (street line, block, side) of the roadworks: no parked cars there.
static var _works := Vector3i(-1, -1, 0)

const SPECIAL_BLOCKS := [Vector2i(1, 5), Vector2i(6, 3), Vector2i(7, 4), Vector2i(6, 5), Vector2i(8, 7), Vector2i(4, 6),
	Vector2i(4, 5), Vector2i(7, 2), Vector2i(2, 7)]

## Parked cars along the kerbs of the side streets (not on the AI loop, the spawn street or beside
## special blocks), and street furniture on the pavements: benches, bins, bike racks, corner
## bollards, and manhole covers in the carriageway.
static func _street_life(parent: Node3D, world: SBWorld, origin: float, metal: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var parked: Array[Transform3D] = []
	var benches: Array[Transform3D] = []
	var bench_backs: Array[Transform3D] = []
	var bins: Array[Transform3D] = []
	var racks: Array[Transform3D] = []
	var bollards: Array[Transform3D] = []
	var manholes: Array[Transform3D] = []
	var gullies: Array[Transform3D] = []
	for line in BLOCKS + 1:
		var s := origin + STREET * 0.5 + line * PITCH
		for axis in 2:   # 0: street along x at z = s, 1: street along z at x = s
			for j in BLOCKS:
				var a0 := origin + STREET + j * PITCH
				var d := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
				var side_v := Vector3(0, 0, 1) if axis == 0 else Vector3(-1, 0, 0)
				var centre := (Vector3(a0, 0, s) if axis == 0 else Vector3(s, 0, a0))
				# Manholes in the carriageway.
				for t: float in [18.0, 52.0]:
					manholes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), centre + d * t + side_v * (2.0 if j % 2 == 0 else -2.0) + Vector3.UP * 0.035))
				var parking_ok := line >= 2 and line <= BLOCKS - 2 and not (axis == 1 and line == 5)
				# Gully grates in the gutter, 30 cm off the kerb, every ~25 m on both sides.
				for side: float in [-1.0, 1.0]:
					for t: float in [10.0, 35.0, 60.0]:
						gullies.append(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), centre + d * (t + rng.randf_range(-1.5, 1.5)) + side_v * side * (STREET * 0.5 - 0.3) + Vector3.UP * 0.036))
				for side: float in [-1.0, 1.0]:
					var blk := Vector2i(j, line - (1 if side < 0.0 else 0)) if axis == 0 else Vector2i(line - (1 if side > 0.0 else 0), j)
					if blk in SPECIAL_BLOCKS:
						continue
					if parking_ok and not (axis == 0 and line == _works.x and j == _works.y and int(side) == _works.z):
						var t := 9.0
						while t < BLOCK - 9.0:
							if rng.randf() < 0.30:
								var p := centre + d * (t + rng.randf_range(-0.4, 0.4)) + side_v * side * (STREET * 0.5 - 1.25)
								var heading := d * side   # right-hand traffic: cars face their direction of travel
								parked.append(Transform3D(Basis.looking_at(-heading, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.03, 0.03)), p))
							t += 6.3
					# Pavement furniture, 1.1 m in from the kerb.
					var walk := centre + side_v * side * (STREET * 0.5 + 1.1) + Vector3.UP * KERB
					var yaw := atan2(d.x, d.z)
					for t: float in [22.0, 50.0]:
						var roll := rng.randf()
						var p := walk + d * t
						if roll < 0.35:
							benches.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.45))
							bench_backs.append(Transform3D(Basis(Vector3.UP, yaw), p + side_v * side * 0.22 + Vector3.UP * 0.75))
							world.add_box(p + Vector3.UP * 0.45, Vector3(0.9, 0.45, 0.3).rotated(Vector3.UP, yaw).abs(), Vector3.ZERO, 0.6)
						elif roll < 0.65:
							bins.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.5))
							world.add_box(p + Vector3.UP * 0.5, Vector3(0.25, 0.5, 0.25), Vector3.ZERO, 0.6)
						elif roll < 0.8:
							for k in 4:
								racks.append(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + d * (k * 0.8 - 1.2) + Vector3.UP * 0.4))
			# Bollards at the block corners of this line.
			for j in BLOCKS + 1:
				var c := origin + STREET * 0.5 + j * PITCH
				var corner := Vector3(c, 0, s) if axis == 0 else Vector3(s, 0, c)
				for dx: float in [-1.0, 1.0]:
					for dz: float in [-1.0, 1.0]:
						var b := corner + Vector3(dx * (STREET * 0.5 + 0.6), KERB, dz * (STREET * 0.5 + 0.6))
						if axis == 0:
							bollards.append(Transform3D(Basis.IDENTITY, b + Vector3(dx * 0.9, 0.5, 0)))
	var P := preload("res://scripts/maps/parked_cars.gd")
	P.place(parent, world, parked)
	_signage(parent, world, origin, metal)
	var seat := BoxMesh.new()
	seat.size = Vector3(1.8, 0.08, 0.45)
	var back := BoxMesh.new()
	back.size = Vector3(1.8, 0.45, 0.06)
	var wood := C.noise_mat(Color(0.42, 0.28, 0.16), 0.1, 5.0, 0.8)
	C.scatter_multimesh(parent, seat, wood, benches, false)
	C.scatter_multimesh(parent, back, wood, bench_backs, false)
	var bin := CylinderMesh.new()
	bin.top_radius = 0.26
	bin.bottom_radius = 0.22
	bin.height = 1.0
	bin.radial_segments = 10
	C.scatter_multimesh(parent, bin, C.mat(Color(0.14, 0.26, 0.17), 0.5, 0.3), bins, false)
	# Kreuzberger Bügel: an inverted U of 48 mm steel tube, 0.8 m high and 0.6 m wide, set in the
	# pavement (they were floating rings).
	var rack := _hoop_mesh(0.3, 0.8, 0.12, 0.024)
	var rack_xf: Array[Transform3D] = []
	for xf in racks: rack_xf.append(Transform3D(xf.basis, xf.origin - Vector3.UP * 0.4))
	C.scatter_multimesh(parent, rack, metal, rack_xf, false)
	var bollard := CylinderMesh.new()
	bollard.top_radius = 0.08
	bollard.bottom_radius = 0.09
	bollard.height = 1.0
	bollard.radial_segments = 8
	C.scatter_multimesh(parent, bollard, C.mat(Color(0.18, 0.18, 0.2), 0.4, 0.6), bollards, false)
	# Cast-iron manhole covers (DN 600 opening, ~0.8 m frame) and slotted gully grates, flat decals
	# on the carriageway with worn, lighter raised parts.
	var cover := PlaneMesh.new()
	cover.size = Vector2(0.8, 0.8)
	C.scatter_multimesh(parent, cover, _iron_material(_manhole_texture()), manholes, false)
	var grate := PlaneMesh.new()
	grate.size = Vector2(0.35, 0.5)
	C.scatter_multimesh(parent, grate, _iron_material(_gully_texture()), gullies, false)


const STREET_NAMES := ["Lindenstraße", "Marktgasse", "Bahnhofstraße", "Goethestraße", "Schillerplatz", "Uferweg",
	"Hafenstraße", "Kirchgasse", "Mühlenweg", "Parkallee", "Ringstraße"]

## Street signs and city furniture: name plates at the corners, speed-limit signs, bus stops with
## glass shelters, advertising columns and turn arrows painted before the intersections.
static func _signage(parent: Node3D, world: SBWorld, origin: float, metal: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var poles: Array[Transform3D] = []
	var plates: Array[Transform3D] = []
	var discs: Array[Transform3D] = []
	var columns: Array[Transform3D] = []
	var arrows: Array[Transform3D] = []
	var white := C.mat(Color(0.94, 0.94, 0.92), 0.5)
	for i in BLOCKS + 1:
		for j in BLOCKS + 1:
			var c := Vector3(origin + STREET * 0.5 + i * PITCH, 0, origin + STREET * 0.5 + j * PITCH)
			# Name plates on one corner of each intersection, for both streets.
			var corner := c + Vector3(STREET * 0.5 + 0.7, KERB, STREET * 0.5 + 0.7)
			poles.append(Transform3D(Basis.from_scale(Vector3(0.07, 3.0, 0.07)), corner + Vector3.UP * 1.5))
			plates.append(Transform3D(Basis.from_scale(Vector3(0.9, 0.22, 0.02)), corner + Vector3(0.45, 2.75, 0)))
			plates.append(Transform3D(Basis.from_scale(Vector3(0.02, 0.22, 0.9)), corner + Vector3(0, 2.5, 0.45)))
			C.label3d(parent, STREET_NAMES[j % STREET_NAMES.size()], corner + Vector3(0.45, 2.75, -0.02), 0.0, 0.13, Color(0.05, 0.05, 0.05))
			C.label3d(parent, STREET_NAMES[(i + 5) % STREET_NAMES.size()], corner + Vector3(-0.02, 2.5, 0.45), -PI * 0.5, 0.13, Color(0.05, 0.05, 0.05))
			world.add_box(corner + Vector3.UP * 1.5, Vector3(0.05, 1.5, 0.05), Vector3.ZERO, 0.6)
			# Advertising column on some corners.
			if (i * 7 + j * 3) % 9 == 0:
				var ac := c + Vector3(-(STREET * 0.5 + 2.2), KERB, -(STREET * 0.5 + 2.2))
				columns.append(Transform3D(Basis.IDENTITY, ac + Vector3.UP * 1.6))
				world.add_box(ac + Vector3.UP * 1.6, Vector3(0.55, 1.6, 0.55), Vector3.ZERO, 0.6)
			# Turn arrows in the right-hand lanes of the four approaches.
			for k in 4:
				var d := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][k] as Vector3
				var right := Vector3(-d.z, 0, d.x)
				var p := c - d * (STREET * 0.5 + 12.0) + right * 6.0 + Vector3.UP * 0.02
				arrows.append(Transform3D(Basis.looking_at(d, Vector3.UP), p))   # tip (texture top) along travel
	# Speed-limit 50 signs at the kerb after every second intersection, and bus stops.
	for line in range(1, BLOCKS, 2):
		var s := origin + STREET * 0.5 + line * PITCH
		for j in range(0, BLOCKS, 3):
			var a0 := origin + STREET + j * PITCH
			var sp := Vector3(a0 + 6.0, KERB, s + STREET * 0.5 + 0.6)
			poles.append(Transform3D(Basis.from_scale(Vector3(0.06, 2.4, 0.06)), sp + Vector3.UP * 1.2))
			discs.append(Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), sp + Vector3(-0.04, 2.3, 0)))
			C.label3d(parent, "50", sp + Vector3(-0.07, 2.3, 0), -PI * 0.5, 0.28, Color(0.02, 0.02, 0.02))
			world.add_box(sp + Vector3.UP * 1.2, Vector3(0.04, 1.2, 0.04), Vector3.ZERO, 0.6)
			if j % 2 == 0:
				_bus_stop(parent, world, Vector3(a0 + 40.0, KERB, s - STREET * 0.5 - 2.2), metal, white)
	C.scatter_multimesh(parent, unit, metal, poles, false)
	C.scatter_multimesh(parent, unit, white, plates, false)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.32
	disc.bottom_radius = 0.32
	disc.height = 0.02
	disc.radial_segments = 20
	var limit := StandardMaterial3D.new()
	limit.albedo_texture = _limit_texture()
	C.scatter_multimesh(parent, disc, limit, discs, false)
	var column := CylinderMesh.new()
	column.top_radius = 0.55
	column.bottom_radius = 0.6
	column.height = 3.2
	column.radial_segments = 16
	var posters := StandardMaterial3D.new()
	posters.albedo_texture = _poster_texture()
	posters.roughness = 0.7
	C.scatter_multimesh(parent, column, posters, columns)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.25
	cap.bottom_radius = 0.66
	cap.height = 0.35
	cap.radial_segments = 16
	var caps: Array[Transform3D] = []
	for xf in columns: caps.append(xf.translated(Vector3.UP * 1.77))
	C.scatter_multimesh(parent, cap, C.mat(Color(0.12, 0.22, 0.16), 0.5, 0.4), caps, false)
	var arrow := PlaneMesh.new()
	arrow.size = Vector2(1.3, 5.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = _arrow_texture()
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	paint.alpha_scissor_threshold = 0.5
	paint.roughness = 0.7
	C.scatter_multimesh(parent, arrow, paint, arrows, false)


static func _bus_stop(parent: Node3D, world: SBWorld, p: Vector3, metal: Material, white: Material) -> void:
	var glass := C.mat(Color(0.55, 0.65, 0.7, 0.35), 0.1, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	C.box(parent, world, p + Vector3(0, 2.45, 0), Vector3(2.0, 0.06, 0.8), Vector3.ZERO, metal, 0.6, false)
	C.box(parent, world, p + Vector3(0, 1.2, -0.75), Vector3(2.0, 1.2, 0.02), Vector3.ZERO, glass, 0.6)
	for x: float in [-1.95, 1.95]:
		C.box(parent, world, p + Vector3(x, 1.2, -0.1), Vector3(0.04, 1.2, 0.68), Vector3.ZERO, glass, 0.6)
		C.box(parent, world, p + Vector3(x, 1.22, -0.78), Vector3(0.05, 1.22, 0.05), Vector3.ZERO, metal, 0.6, false)
	C.box(parent, world, p + Vector3(0, 0.45, -0.5), Vector3(1.5, 0.04, 0.2), Vector3.ZERO, metal, 0.6, false)
	C.box(parent, world, p + Vector3(2.4, 1.4, 0.6), Vector3(0.04, 1.4, 0.04), Vector3.ZERO, metal, 0.6)
	C.box(parent, world, p + Vector3(2.4, 2.6, 0.6), Vector3(0.25, 0.25, 0.02), Vector3.ZERO, C.mat(Color(0.95, 0.75, 0.1), 0.5), 0.6, false)
	C.label3d(parent, "H", p + Vector3(2.4, 2.6, 0.63), PI, 0.3, Color(0.1, 0.45, 0.2))


static var _tex_cache := {}
static func _limit_texture() -> ImageTexture:
	if _tex_cache.has("limit"): return _tex_cache["limit"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img.set_pixel(x, y, Color(0.8, 0.06, 0.05) if d > 0.74 else Color(0.97, 0.97, 0.97))
	img.generate_mipmaps()
	_tex_cache["limit"] = ImageTexture.create_from_image(img)
	return _tex_cache["limit"]


static func _poster_texture() -> ImageTexture:
	if _tex_cache.has("poster"): return _tex_cache["poster"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var img := Image.create(512, 160, false, Image.FORMAT_RGB8)
	img.fill(Color(0.80, 0.78, 0.72))
	# A row of overlapping posters: coloured ground, a headline bar, lines of text, a picture block.
	var x := 0
	while x < 512:
		var w := rng.randi_range(48, 90)
		var top := rng.randi_range(4, 20)
		var col := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.85), rng.randf_range(0.55, 0.95))
		img.fill_rect(Rect2i(x, top, w - 3, 160 - top - 6), col)
		img.fill_rect(Rect2i(x + 5, top + 8, w - 13, 12), col.darkened(0.65) if col.get_luminance() > 0.5 else col.lightened(0.7))
		img.fill_rect(Rect2i(x + 5, top + 30, w - 13, 50), Color.from_hsv(rng.randf(), 0.5, 0.6))
		for line in 5:
			img.fill_rect(Rect2i(x + 5, top + 90 + line * 9, rng.randi_range(18, w - 13), 3), col.darkened(0.5))
		x += w
	img.generate_mipmaps()
	_tex_cache["poster"] = ImageTexture.create_from_image(img)
	return _tex_cache["poster"]


static func _iron_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.55
	m.metallic = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Manhole cover: a frame ring, a lighter worn rim, concentric rings and radial ribs (raised, worn
## bright), two lifting holes; outside the frame transparent.
static func _manhole_texture() -> ImageTexture:
	if _tex_cache.has("manhole"): return _tex_cache["manhole"]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.12
	for y in n:
		for x in n:
			var p := Vector2(x - (n - 1) * 0.5, y - (n - 1) * 0.5) / (n * 0.5)
			var r := p.length()
			var grime := 0.85 + 0.2 * noise.get_noise_2d(x, y)
			var c := Color(0.0, 0.0, 0.0, 0.0)
			if r <= 1.0:
				var dark := Color(0.13, 0.12, 0.115) * grime
				var bright := Color(0.36, 0.34, 0.31) * grime
				var raised := false
				if r > 0.86:
					raised = r > 0.9                     # frame
				elif r > 0.80:
					raised = false                       # joint between frame and lid
				else:
					var ring := fmod(r * 7.0, 1.0) < 0.28
					var rib := fmod((atan2(p.y, p.x) + PI) / TAU * 24.0, 1.0) < 0.22 and r > 0.18
					raised = ring or rib or r < 0.1
					for hole: Vector2 in [Vector2(0.55, 0.0), Vector2(-0.55, 0.0)]:
						if p.distance_to(hole) < 0.06:
							raised = false
							dark = Color(0.03, 0.03, 0.03)
				c = bright if raised else dark
				c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex_cache["manhole"] = ImageTexture.create_from_image(img)
	return _tex_cache["manhole"]


## Gully grate: a steel frame and longitudinal slots over the dark sump.
static func _gully_texture() -> ImageTexture:
	if _tex_cache.has("gully"): return _tex_cache["gully"]
	var w := 48
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var frame := x < 4 or x >= w - 4 or y < 4 or y >= h - 4
			var bar := (x - 4) % 5 < 2 or (y - 4) % 28 < 3
			var c := Color(0.30, 0.29, 0.27) if frame or bar else Color(0.02, 0.02, 0.02)
			if frame: c = Color(0.38, 0.36, 0.33)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_tex_cache["gully"] = ImageTexture.create_from_image(img)
	return _tex_cache["gully"]


static func _arrow_texture() -> ImageTexture:
	if _tex_cache.has("arrow"): return _tex_cache["arrow"]
	# 64 x 256 with 4 x 4 supersampled edge coverage: bilinear filtering then draws a smooth outline at
	# the scissor threshold instead of a staircase of 4-cm texels.
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var cover := 0
			for sy in 4:
				for sx in 4:
					var u := (x + (sx + 0.5) / 4.0 - w * 0.5) / (w * 0.5)
					var v := (y + (sy + 0.5) / 4.0) / h          # 0 = tip
					var head := v < 0.35 and absf(u) < (v / 0.35) * 0.95
					var shaft := v >= 0.35 and v < 0.995 and absf(u) < 0.28
					if head or shaft: cover += 1
			img.set_pixel(x, y, Color(0.93, 0.93, 0.9, cover / 16.0))
	img.generate_mipmaps()
	_tex_cache["arrow"] = ImageTexture.create_from_image(img)
	return _tex_cache["arrow"]


## Tube bent into an inverted U in the local x-y plane: legs at x = +-half_w from y = 0, joined by
## a rounded top (bend radius `bend`) at `height`.
static func _hoop_mesh(half_w: float, height: float, bend: float, radius: float) -> ArrayMesh:
	var path := PackedVector3Array()
	path.append(Vector3(-half_w, -0.05, 0))
	path.append(Vector3(-half_w, height - bend, 0))
	for i in range(1, 7):
		var a := PI - i * (PI * 0.5) / 6.0
		path.append(Vector3(-half_w + bend + cos(a) * bend, height - bend + sin(a) * bend, 0))
	path.append(Vector3(half_w - bend, height, 0))
	for i in range(1, 7):
		var a := PI * 0.5 - i * (PI * 0.5) / 6.0
		path.append(Vector3(half_w - bend + cos(a) * bend, height - bend + sin(a) * bend, 0))
	path.append(Vector3(half_w, -0.05, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 8
	var rings: Array = []
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var n := Vector3(0, 0, 1)
		var b := t.cross(n).normalized()
		var ring := []
		for k in SIDES:
			var ang := TAU * k / SIDES
			ring.append([path[i] + (n * cos(ang) + b * sin(ang)) * radius, (n * cos(ang) + b * sin(ang))])
		rings.append(ring)
	for i in path.size() - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()
