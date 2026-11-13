extends RefCounted
const V := preload("res://scripts/maps/vegetation.gd")
## A bounded engineering site: planted infields, accessible earth berms and perimeter rails.
## Terrain render meshes and physics use the same sampled heights. Tree trunks and rails collide.
const C := preload("res://scripts/maps/common.gd")
const INFIELDS := [Rect2(-180, 58, 110, 64), Rect2(120, 70, 70, 62)]
## The tunnel to the city: out through the service gate on the west into the berm.
const TUNNEL_MOUTH := Vector3(-381.0, 0.0, -5.0)
const TUNNEL_DIR := Vector3(-1.0, 0.0, 0.0)
## The tunnel built by the last build(): {"gate", "entrance", "width"}.
static var tunnel: Dictionary = {}

static func build(world: SBWorld, parent: Node3D) -> Array:
	var root := Node3D.new()
	root.name = "ProvingSurroundings"
	parent.add_child(root)
	var grass := C.surface_material("grass", 3.1, Color(0.50, 0.66, 0.50))
	var gravel := C.surface_material("gravel", 2.5, Color(0.74, 0.71, 0.64))
	var regions: Array = []
	var tree_points: Array[Vector3] = []
	# These islands sit inside the high-speed loop, away from the handling gates.
	for rect: Rect2 in INFIELDS:
		flat(root, rect.grow(1.0), 0.009, gravel)
		flat(root, rect, 0.012, grass)
		regions.append({"rect": rect, "surface": "grass"})
		V.field_grass(root, rect.grow(-1.5), 0.9, int(rect.position.x) + 700, func(_x: float, _z: float) -> float: return 0.012)
		for x in range(int(rect.position.x + 8), int(rect.end.x - 6), 18):
			for z: float in [rect.position.y + 9, rect.end.y - 9]:
				tree_points.append(Vector3(x, 0, z))
	# Raised natural ground is outside the original 750 x 440 m test pad.
	# Smooth toes meet the level site, instead of an abrupt edge or floating backdrop.
	for rect: Rect2 in [Rect2(-455, 220, 910, 80), Rect2(-455, -300, 910, 80), Rect2(-455, -220, 80, 440), Rect2(375, -220, 80, 440)]:
		var along_x := rect.size.x > rect.size.y
		var cell := 10.0
		var nx := int(rect.size.x / cell) + 1
		var nz := int(rect.size.y / cell) + 1
		var heights := PackedFloat32Array()
		heights.resize(nx * nz)
		for x in nx:
			for z in nz:
				var transverse := float(z) / (nz - 1) if along_x else float(x) / (nx - 1)
				var along := rect.position.x + x * cell if along_x else rect.position.y + z * cell
				var longitudinal := float(x) / (nx - 1) if along_x else float(z) / (nz - 1)
				var end_fade := smoothstep(0, 0.12, longitudinal) * smoothstep(0, 0.12, 1.0 - longitudinal)
				heights[x * nz + z] = end_fade * pow(sin(transverse * PI), 2) * (11.0 + 4.0 * sin(along * 0.017) + 2.0 * cos(along * 0.033))
		var physical := heights
		if rect.has_point(Vector2(TUNNEL_MOUTH.x - 30.0, TUNNEL_MOUTH.z)):
			# The road from the service gate cut into the berm's toe, and the tunnel's cut.
			var before := heights.duplicate()
			C.carve_path(heights, nx, nz, rect.position.x, rect.position.y, cell,
				PackedVector3Array([TUNNEL_MOUTH - TUNNEL_DIR * 8.0, TUNNEL_MOUTH + TUNNEL_DIR * 18.0]), 5.0, 12.0, 0.0, false)
			var old := heights.duplicate()
			physical = heights.duplicate()
			C.tunnel_cut(heights, nx, nz, rect.position.x, rect.position.y, cell, TUNNEL_MOUTH, TUNNEL_DIR, 1.0, 75.0, 12.0, -0.5)
			C.tunnel_cut_physical(physical, nx, nz, rect.position.x, rect.position.y, cell, TUNNEL_MOUTH, TUNNEL_DIR)
			var berm := rect
			var cover_ground := C.portal_ground(before, old, nx, nz, rect.position.x, rect.position.y, cell, TUNNEL_MOUTH, TUNNEL_DIR)
			var ground := func(x: float, z: float) -> float:
				if not berm.grow(-0.5).has_point(Vector2(x, z)):
					return 0.0
				return float(cover_ground.call(x, z))
			var asphalt := C.road_material(2, 7.0, 12.0, "rural")
			root.add_child(C.road_mesh(PackedVector3Array([Vector3(-366.0, 0.0, TUNNEL_MOUTH.z), TUNNEL_MOUTH]), 3.5, asphalt, false, 0.012, 12.0))
			tunnel = C.tunnel(root, world, TUNNEL_MOUTH, TUNNEL_DIR, "Stadt  ›", 9.0, 5.4, 70.0, ground, C.terrain_material("grass", 3.1, Color(0.50, 0.66, 0.50)),
				Color.WHITE, 17.0, 0.012)
		world.add_heightfield(rect.position.x, rect.position.y, cell, nx, nz, physical, 0.75)
		root.add_child(C.terrain_mesh(rect.position.x, rect.position.y, cell, nx, nz, heights, grass))
		regions.append({"rect": rect, "surface": "grass"})
		# Ground cover on the berms, denser along the toe facing the test pad.
		var sample_h := func(x: float, z: float) -> float: return C.sample(heights, nx, nz, rect.position.x, rect.position.y, cell, x, z)
		var pad := Rect2(-376, -221, 752, 442)
		V.field_grass(root, rect, 0.10, int(rect.position.y) + 900, sample_h, func(p: Vector3) -> bool: return pad.has_point(Vector2(p.x, p.z)))
		V.field_grass(root, rect.intersection(pad.grow(24.0)), 0.6, int(rect.position.x) + 950, sample_h,
			func(p: Vector3) -> bool: return pad.has_point(Vector2(p.x, p.z)))
		var count := int((rect.size.x if along_x else rect.size.y) / 20)
		for i in count:
			if i % 9 == 5: continue
			var jitter := sin(i * 1.73) * 5.0
			var side := cos(i * 2.31) * 15.0
			var p := Vector3(rect.position.x + (i + 0.5) * 20 + jitter if along_x else rect.get_center().x + side, 0,
				rect.get_center().y + side if along_x else rect.position.y + (i + 0.5) * 20 + jitter)
			if C.tunnel_zone(Vector2(p.x, p.z), Vector2(TUNNEL_MOUTH.x, TUNNEL_MOUTH.z), Vector2(TUNNEL_DIR.x, TUNNEL_DIR.z)):
				continue
			p.y = C.sample(heights, nx, nz, rect.position.x, rect.position.y, cell, p.x, p.z)
			tree_points.append(p)
	# Open 24 m service gate on the west. All circuit and pit access remains inside.
	var metal := C.mat(Color(0.52, 0.56, 0.57), 0.5, 0.7)
	var post := C.mat(Color(0.22, 0.25, 0.25), 0.65, 0.45)
	for route: Array in [
		[Vector3(-369,0,-214), Vector3(369,0,-214)], [Vector3(-369,0,214), Vector3(369,0,214)],
		[Vector3(369,0,-214), Vector3(369,0,214)], [Vector3(-369,0,-214), Vector3(-369,0,-17)],
		[Vector3(-369,0,7), Vector3(-369,0,214)]]:
		rail(root, world, route[0], route[1], metal, post)
	_trees(root, world, tree_points)
	return regions

static func flat(parent: Node3D, rect: Rect2, y: float, material: Material) -> void:
	var surface := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = rect.size
	surface.mesh = mesh
	surface.position = Vector3(rect.get_center().x, y, rect.get_center().y)
	surface.material_override = material
	parent.add_child(surface)

## Perimeter rail: posts every 8 m with a beam between them. Drawn as two spatially chunked
## multimeshes (each piece used to be its own mesh: ~580 draw calls round the test pad); every
## piece keeps its own collider.
static func rail(parent: Node3D, world: SBWorld, a: Vector3, b: Vector3, metal: Material, post: Material) -> void:
	var count := ceili(a.distance_to(b) / 8)
	var step := (b - a) / count
	var yaw := atan2(-step.z, step.x)
	var posts: Array[Transform3D] = []
	var beams: Array[Transform3D] = []
	for i in count:
		var p := a + step * i
		var pc := p + Vector3.UP * 0.55
		var bc := p + step * 0.5 + Vector3.UP * 0.78
		var beam_half := Vector3(step.length() * 0.5, 0.16, 0.065)
		world.add_box(pc, Vector3(0.09, 0.55, 0.09), Vector3.ZERO, 0.8)
		world.add_box(bc, beam_half, Vector3(0, yaw, 0), 0.8)
		posts.append(Transform3D(Basis.from_scale(Vector3(0.18, 1.1, 0.18)), pc))
		beams.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(beam_half * 2.0), bc))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	C.scatter_multimesh(parent, unit, post, posts)
	C.scatter_multimesh(parent, unit, metal, beams)

static func _trees(parent: Node3D, world: SBWorld, points: Array[Vector3]) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 5027
	var broadleaf: Array[Vector3] = []
	var conifers: Array[Vector3] = []
	for p: Vector3 in points:
		var conifer := random.randf() < 0.3
		if not V.keep(p): continue
		(conifers if conifer else broadleaf).append(p)
		var h := 1.8 if conifer else 2.2
		world.add_box(p + Vector3.UP * h, Vector3(0.22, h, 0.22), Vector3.ZERO, 0.7)
	V.plant(parent, "broadleaf", broadleaf, 5027, 0.85, 1.3)
	V.plant(parent, "conifer", conifers, 5028, 0.8, 1.15)
