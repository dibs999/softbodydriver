extends RefCounted
## Procedural vegetation shared by all maps: broadleaf trees, conifers, bushes and dry desert
## shrubs. Each species has a few seeded variants built from tapered limbs and alpha-tested
## leaf cards with volumetric normals; textures are painted once at load time.

const C := preload("res://scripts/maps/common.gd")
const FOLIAGE_SHADER := preload("res://materials/foliage.gdshader")
const VARIANTS := 3

static var _meshes: Dictionary = {}
static var _textures: Dictionary = {}
static var _bark: Material


## Graphics settings from the "Game" autoload (absent in isolated tools: full quality).
static func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Game") if tree else null


static func density() -> float:
	var game := _game()
	return game.vegetation_density() if game and game.has_method("vegetation_density") else 1.0


## Deterministic thinning for the "Bäume und Büsche" setting. Maps that add trunk colliders must
## ask before adding them, so that no invisible tree is left in the road.
static func keep(p: Vector3) -> bool:
	var d := density()
	if d >= 0.999:
		return true
	var h := fposmod(sin(p.x * 12.9898 + p.z * 78.233) * 43758.5453, 1.0)
	return h < d


## Distance at which trees switch to their low-detail mesh, and the far limit (view distance).
const LOD_DISTANCE := 130.0


## Places one species at ground points (base of the trunk). Colliders stay the caller's job.
static func plant(parent: Node3D, kind: String, ground: Array[Vector3], seed := 1,
		min_scale := 0.8, max_scale := 1.25, shadow := true, backdrop := false) -> void:
	## backdrop: trees that are only ever seen from far away (horizon hills) get just the low-detail
	## cards in 600 m chunks: thousands of tiny near/far chunk pairs cost a draw call each.
	if ground.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buckets: Array = []
	for v in VARIANTS:
		var list: Array[Transform3D] = []
		buckets.append(list)
	for p in ground:
		var s := rng.randf_range(min_scale, max_scale)
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.05))
		var b := lean * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
		var bucket: Array[Transform3D] = buckets[rng.randi() % VARIANTS]
		if keep(p):
			bucket.append(Transform3D(b, p - Vector3.UP * 0.15 * s))
	var game := _game()
	var far := float(game.view_distance()) if game and game.has_method("view_distance") else 4000.0
	var small := kind == "bush" or kind == "dry_shrub"
	for v in VARIANTS:
		var list: Array[Transform3D] = buckets[v]
		if list.is_empty():
			continue
		# Spatial chunks with a detailed mesh near the camera and a few large cards beyond.
		# Sparse rows (trees every 20 m along a berm) left one or two trees per 160 m cell, each
		# cell a near and a far draw call: grow the cells until they hold ~8 trees on average.
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for xf: Transform3D in list:
			lo = lo.min(Vector2(xf.origin.x, xf.origin.z))
			hi = hi.max(Vector2(xf.origin.x, xf.origin.z))
		var area := maxf(1.0, (hi.x - lo.x + 1.0) * (hi.y - lo.y + 1.0))
		var cell_size := 600.0 if backdrop else clampf(sqrt(area * 8.0 / list.size()), 160.0, 600.0)
		var chunks: Dictionary = {}
		for xf in list:
			var size := cell_size
			var key := Vector2i(floori(xf.origin.x / size), floori(xf.origin.z / size))
			if not chunks.has(key):
				var arr: Array[Transform3D] = []
				chunks[key] = arr
			chunks[key].append(xf)
		for arr: Array[Transform3D] in chunks.values():
			if small:
				_chunk(parent, mesh(kind, v), arr, shadow, 0.0, minf(far, 260.0))
			elif backdrop:
				_chunk(parent, mesh(kind + "_far", v), arr, false, 0.0, far)
			else:
				_chunk(parent, mesh(kind, v), arr, shadow, 0.0, LOD_DISTANCE)
				_chunk(parent, mesh(kind + "_far", v), arr, false, LOD_DISTANCE, far * 0.8)


static func _chunk(parent: Node3D, m: Mesh, xforms: Array[Transform3D], shadow: bool, begin: float, end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = 10.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 10.0
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


static func mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "%s_%d" % [kind, variant]
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var detail := 1.0
		if kind.ends_with("_far"):
			kind = kind.trim_suffix("_far")
			detail = 0.22
		match kind:
			"conifer": _meshes[key] = _conifer(rng, detail)
			"bush": _meshes[key] = _bush(rng, "broadleaf", Color(0.86, 0.95, 0.78), Color(0.7, 0.82, 0.55))
			"dry_shrub": _meshes[key] = _bush(rng, "dry", Color(0.95, 0.9, 0.8), Color(0.8, 0.72, 0.55))
			"poplar": _meshes[key] = _broadleaf(rng, 0.42, 1.6, detail)
			_: _meshes[key] = _broadleaf(rng, 1.0, 1.0, detail)
	return _meshes[key]


# ------------------------------------------------------------------------------- geometry
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u)
	var length := a.distance_to(b)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var quad := [[a + d0 * ra, d0, Vector2(float(i) / sides, 0)], [b + d1 * rb, d1, Vector2(float(i + 1) / sides, length)],
			[a + d1 * ra, d1, Vector2(float(i + 1) / sides, 0)], [a + d0 * ra, d0, Vector2(float(i) / sides, 0)],
			[b + d0 * rb, d0, Vector2(float(i) / sides, length)], [b + d1 * rb, d1, Vector2(float(i + 1) / sides, length)]]
		for q in quad:
			st.set_normal(q[1])
			st.set_uv(q[2])
			st.add_vertex(q[0])


## One leaf card: centre, facing normal, up direction in the card plane, size; `normal` is the
## lighting normal (crown-shaped), `ao` darkens inner cards.
static func _card(st: SurfaceTool, center: Vector3, facing: Vector3, up: Vector3, size: Vector2,
		normal: Vector3, ao: float, rnd: float) -> void:
	var right := up.cross(facing).normalized() * size.x * 0.5
	var top := facing.cross(right).normalized() * size.y * 0.5
	var corners := [center - right - top, center + right - top, center + right + top, center - right + top]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	st.set_color(Color(ao, rnd, 0))
	st.set_normal(normal)
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])


static func _finish(trunk: SurfaceTool, leaves: SurfaceTool, leaf_material: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	trunk.commit(m)
	m.surface_set_material(0, _bark_material())
	leaves.commit(m)
	m.surface_set_material(1, leaf_material)
	return m


static func _broadleaf(rng: RandomNumberGenerator, width: float, tall: float, detail := 1.0) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(8.0, 10.5) * tall
	var fork := height * rng.randf_range(0.36, 0.46)
	var crown_c := Vector3(0, height * 0.64, 0)
	var crown_r := Vector3(3.3 * width, height * 0.34, 3.3 * width)
	_limb(trunk, Vector3.ZERO, Vector3(0, fork, 0), 0.30 * width + 0.06, 0.2 * width + 0.04, 8 if detail >= 1.0 else 4)
	# Main limbs towards crown lobes, a few secondary branches and the cards around them.
	var lobes := rng.randi_range(4, 6)
	var lobe_centers: Array[Vector3] = []
	for i in lobes:
		var a := TAU * i / lobes + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(0.35, 0.62)
		var y := rng.randf_range(-0.35, 0.55)
		lobe_centers.append(crown_c + Vector3(cos(a) * crown_r.x * r, y * crown_r.y, sin(a) * crown_r.z * r))
	lobe_centers.append(crown_c + Vector3(0, crown_r.y * 0.55, 0))
	for c in lobe_centers:
		var start := Vector3(0, fork * rng.randf_range(0.92, 1.0), 0)
		var mid := start.lerp(c, 0.55) + Vector3(0, 0.4, 0)
		if detail >= 1.0:
			_limb(trunk, start, mid, 0.17 * width + 0.03, 0.10 * width + 0.02, 5)
			_limb(trunk, mid, c, 0.10 * width + 0.02, 0.04, 4)
	var cards := maxi(14, int(150 * (0.55 + 0.45 * width) * detail))
	var grow := 1.0 / sqrt(maxf(detail, 0.05)) * (0.75 if detail < 1.0 else 1.0)
	# Leaf clusters: each lobe breaks up into a few clumps on twigs, so the crown shows lit
	# clusters with shaded hollows and some sky between them instead of an even ball of leaves.
	var clumps: Array[Vector3] = []
	var clump_r: Array[float] = []
	for c in lobe_centers:
		for k in (3 if detail >= 1.0 else 1):
			var off := Vector3(rng.randfn(), rng.randfn() * 0.7 + 0.2, rng.randfn()).normalized() * crown_r.x * rng.randf_range(0.22, 0.48)
			clumps.append(c + off)
			clump_r.append(crown_r.x * rng.randf_range(0.34, 0.48))
			if detail >= 1.0:
				_limb(trunk, c, c + off, 0.035, 0.015, 3)
	for i in cards:
		var ci := rng.randi() % clumps.size()
		var c: Vector3 = clumps[ci]
		var dir := Vector3(rng.randfn(), rng.randfn() * 0.8 + 0.25, rng.randfn()).normalized()
		var depth := pow(rng.randf_range(0.15, 1.0), 0.5)
		var p := c + dir * clump_r[ci] * depth if detail >= 1.0 else c + dir * crown_r.x * 0.6 * depth
		var rel := (p - crown_c) / crown_r
		var outward := (rel + Vector3(0, 0.35, 0)).normalized()
		var facing := (outward + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.7).normalized()
		# Shade: deep inside the crown, on a clump's underside and on its inner face.
		var clump_lit := clampf(0.55 + 0.45 * dir.dot((rel + Vector3(0, 0.6, 0)).normalized()), 0.0, 1.0)
		var ao := clampf((0.25 + 0.6 * rel.length() + 0.25 * rel.y) * (0.55 + 0.45 * clump_lit) * (0.75 + 0.25 * depth), 0.25, 1.0)
		var sz := rng.randf_range(1.8, 2.5) * (0.75 + 0.25 * width) * grow
		_card(leaves, p, facing, Vector3(rng.randfn(), 1.0, rng.randfn()).normalized(), Vector2(sz, sz), outward, ao, rng.randf())
	return _finish(trunk, leaves, _leaf_material("broadleaf", Color(0.95, 1.0, 0.9), Color(0.78, 0.9, 0.62)))


static func _conifer(rng: RandomNumberGenerator, detail := 1.0) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := rng.randf_range(12.0, 16.0)
	var base_r := rng.randf_range(2.4, 3.1)
	_limb(trunk, Vector3.ZERO, Vector3(0, height, 0), 0.27, 0.03, 7 if detail >= 1.0 else 4)
	var y := rng.randf_range(1.4, 2.2)
	var whorl := 0
	while y < height - 0.6:
		var f := (height - y) / height
		var length := base_r * pow(f, 0.9) + 0.35
		var count := (8 if f > 0.3 else 6) if detail >= 1.0 else 3
		var phase := rng.randf() * TAU
		for i in count:
			var a := phase + TAU * i / count + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(a), 0, sin(a))
			var droop := rng.randf_range(-0.42, -0.18) * (0.5 + f)
			var axis := (out + Vector3(0, droop, 0)).normalized()
			var center := Vector3(0, y, 0) + axis * length * 0.52
			var lit := (out + Vector3(0, 0.55, 0)).normalized()
			var ao := clampf(0.45 + 0.45 * (1.0 - f) + 0.25 * (length / base_r), 0.35, 1.0)
			var side := axis.cross(Vector3.UP).normalized()
			# Flat branch spray plus a slightly tilted crossing card for thickness.
			var face_up := side.cross(axis).normalized()
			if face_up.y < 0: face_up = -face_up
			var spray := 1.0 if detail >= 1.0 else 1.7
			_card(leaves, center, face_up, axis, Vector2(length * 0.75 * spray, length * 1.1 * spray), lit, ao, rng.randf())
			if detail >= 1.0:
				var tilted := (face_up + side * 0.9).normalized()
				_card(leaves, center - Vector3(0, 0.12, 0), tilted, axis, Vector2(length * 0.5, length), lit, ao * 0.9, rng.randf())
				# Dense, shaded inner foliage around the trunk: a spruce crown is opaque near the stem.
				var inner := Vector3(0, y + 0.15, 0) + out * length * 0.22
				_card(leaves, inner, (out + Vector3(0, 0.4, 0)).normalized(), Vector3.UP, Vector2(length * 0.55, length * 0.7), lit, ao * 0.55, rng.randf())
		y += rng.randf_range(0.45, 0.65) * (0.7 + 0.3 * (1.0 - float(whorl) / 30.0)) * (1.0 if detail >= 1.0 else 3.2)
		whorl += 1
	# Leader shoot.
	_card(leaves, Vector3(0, height - 0.2, 0), Vector3(1, 0, 0), Vector3.UP, Vector2(0.7, 1.4), Vector3.UP, 1.0, 0.5)
	_card(leaves, Vector3(0, height - 0.2, 0), Vector3(0, 0, 1), Vector3.UP, Vector2(0.7, 1.4), Vector3.UP, 1.0, 0.5)
	return _finish(trunk, leaves, _leaf_material("needle", Color(0.92, 0.98, 0.95), Color(0.75, 0.86, 0.74)))


static func _bush(rng: RandomNumberGenerator, texture: String, a: Color, b: Color) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := rng.randf_range(0.9, 1.3)
	var h := r * rng.randf_range(0.75, 1.0)
	for i in 4:
		var tip := Vector3(rng.randfn() * r * 0.4, h * rng.randf_range(0.6, 0.9), rng.randfn() * r * 0.4)
		_limb(trunk, Vector3.ZERO, tip, 0.045, 0.015, 4)
	for i in 40:
		var dir := Vector3(rng.randfn(), absf(rng.randfn()) * 0.8 + 0.2, rng.randfn()).normalized()
		var p := Vector3(0, h * 0.45, 0) + Vector3(dir.x * r, dir.y * h * 0.62, dir.z * r) * rng.randf_range(0.4, 0.9)
		var outward := (dir + Vector3(0, 0.3, 0)).normalized()
		var facing := (outward + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.8).normalized()
		var ao := clampf(0.4 + 0.6 * p.y / (h * 1.1), 0.35, 1.0)
		var sz := rng.randf_range(0.9, 1.3) * r
		_card(leaves, p, facing, Vector3(rng.randfn() * 0.4, 1.0, rng.randfn() * 0.4).normalized(), Vector2(sz, sz), outward, ao, rng.randf())
	return _finish(trunk, leaves, _leaf_material(texture, a, b))


# ------------------------------------------------------------------------------- materials
static func _bark_material() -> Material:
	if _bark == null:
		_bark = C.noise_mat(Color(0.25, 0.2, 0.15), 0.35, 0.9, 0.95)
	return _bark


static func _leaf_material(texture: String, a: Color, b: Color) -> ShaderMaterial:
	var key := [texture, a, b]
	if not _textures.has(key):
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("leaf_tex", _leaf_texture(texture))
		m.set_shader_parameter("tint_a", a)
		m.set_shader_parameter("tint_b", b)
		if texture == "broadleaf":
			m.set_shader_parameter("shade_floor", 0.34)
		if texture == "needle":
			m.set_shader_parameter("autumn_amount", 0.0)
			m.set_shader_parameter("wind_strength", 0.6)
		elif texture == "dry":
			m.set_shader_parameter("autumn_amount", 0.0)
			m.set_shader_parameter("translucency", 0.25)
		_textures[key] = m
	return _textures[key]


static func _leaf_texture(kind: String) -> ImageTexture:
	var cache_key := "tex_" + kind
	if _textures.has(cache_key):
		return _textures[cache_key]
	const SIZE := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var bg := Color(0.17, 0.27, 0.08, 0.0)
	if kind == "needle":
		bg = Color(0.1, 0.19, 0.11, 0.0)
	elif kind == "dry" or kind == "grass_dry":
		bg = Color(0.34, 0.31, 0.2, 0.0)
	# Transparent texels carry the leaf colour so mip levels do not darken the fringes.
	img.fill(bg)
	if kind.begins_with("grass"):
		# Tuft of blades rising from the bottom edge, slightly curved, varied height.
		var dry_grass := kind == "grass_dry"
		for b in 70:
			var x0 := rng.randf_range(30, 226)
			var top := Vector2(x0 + rng.randf_range(-40, 40), rng.randf_range(20, 150))
			var bend := Vector2(rng.randf_range(-18, 18), 0)
			var base_col := Color(0.2, 0.32, 0.1) if not dry_grass else Color(0.5, 0.44, 0.28)
			base_col = base_col.lerp(Color(0.36, 0.42, 0.18) if not dry_grass else Color(0.62, 0.55, 0.36), rng.randf()) * rng.randf_range(0.8, 1.15)
			var steps := 24
			var prev := Vector2(x0, 255)
			for k in range(1, steps + 1):
				var f := float(k) / steps
				var pt := Vector2(x0, 255).lerp(top, f) + bend * f * f
				_line(img, prev, pt, lerpf(4.0, 1.0, f), base_col.lerp(base_col * 1.3, f))
				prev = pt
	elif kind == "needle":
		# Spruce spray: stem from bottom to top with side shoots, all covered in needles.
		var shoots: Array = [[Vector2(128, 250), Vector2(128, 8), 3.0]]
		for i in 9:
			var y := 220.0 - i * 23.0
			var spread := 100.0 * (1.0 - i / 11.0)
			for s: float in [-1.0, 1.0]:
				shoots.append([Vector2(128, y), Vector2(128 + s * spread, y - 46.0), 1.6])
		for shoot: Array in shoots:
			var a: Vector2 = shoot[0]
			var b: Vector2 = shoot[1]
			var steps := int(a.distance_to(b) / 2.0)
			var dir := (b - a).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for k in steps:
				var p := a.lerp(b, float(k) / steps)
				var len := 15.0 * (1.0 - 0.5 * float(k) / steps)
				for s: float in [-1.0, 1.0]:
					var tip := p + (nrm * s + dir * 0.55).normalized() * len * rng.randf_range(0.7, 1.1)
					var shade := rng.randf_range(0.7, 1.15)
					_line(img, p, tip, 1.3, Color(0.12, 0.25, 0.13) * shade)
			_line(img, a, b, float(shoot[2]), Color(0.24, 0.18, 0.11))
	else:
		var dry := kind == "dry"
		# Twigs fanning out from the bottom, leaves along them.
		for t in 9:
			var a := Vector2(128 + rng.randf_range(-20, 20), 250)
			var b := Vector2(rng.randf_range(20, 236), rng.randf_range(10, 120))
			_line(img, a, b, 2.2, Color(0.25, 0.2, 0.13))
			var n := 30 if not dry else 34
			for k in n:
				var p := a.lerp(b, rng.randf_range(0.2, 1.0)) + Vector2(rng.randfn(), rng.randfn()) * 14.0
				var ang := (b - a).angle() + rng.randf_range(-1.3, 1.3)
				var length := rng.randf_range(22, 36) if not dry else rng.randf_range(9, 15)
				var width := length * rng.randf_range(0.34, 0.46)
				var base := Color(0.2, 0.33, 0.09) if not dry else Color(0.42, 0.4, 0.26)
				base = base.lerp(Color(0.26, 0.36, 0.1), rng.randf() * 0.5) * rng.randf_range(0.75, 1.2)
				_leaf(img, p, ang, length, width, base)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[cache_key] = tex
	return tex


static func _line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var r := int(ceil(width * 0.5))
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and dx * dx + dy * dy <= r * r:
					img.set_pixel(x, y, Color(color, 1.0))


static func _leaf(img: Image, center: Vector2, angle: float, length: float, width: float, color: Color) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var nrm := Vector2(-dir.y, dir.x)
	var r := int(length * 0.5) + 1
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := int(center.x) + dx
			var y := int(center.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(dx, dy)
			var u := d.dot(dir) / (length * 0.5)       # -1..1 along the leaf
			var v := d.dot(nrm) / (width * 0.5)
			var edge := sqrt(maxf(0.0, 1.0 - u * u)) * (1.0 - 0.25 * u)  # pointed tip
			if absf(v) > edge:
				continue
			var shade := 0.82 + 0.3 * (v * 0.5 + 0.5)                       # light from one side
			if absf(v) < 0.08 and u > -0.9:
				shade *= 1.18                                              # midrib
			img.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))


## Ground cover: grass tufts (crossed blade cards), only drawn near the camera.
static func grass(parent: Node3D, ground: Array[Vector3], seed := 1, dry := false, min_scale := 0.7, max_scale := 1.3) -> void:
	var game := _game()
	var reach := float(game.grass_distance()) if game and game.has_method("grass_distance") else 85.0
	if ground.is_empty() or reach <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var xforms: Array[Transform3D] = []
	# Each point grows a small clump of 2-4 tufts of different size instead of one identical plug,
	# so the cover reads as patches of grass rather than evenly planted bunches.
	for p in ground:
		var s := rng.randf_range(min_scale, max_scale)
		for k in rng.randi_range(2, 4):
			var off := Vector3(rng.randfn(), 0, rng.randfn()) * 0.28 * s if k > 0 else Vector3.ZERO
			var ks := s * (0.95 if k == 0 else rng.randf_range(0.45, 0.8))
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ks, ks * rng.randf_range(0.75, 1.3), ks)), p + off - Vector3.UP * 0.02))
	var tuft := _tuft_mesh(dry)
	var chunks: Dictionary = {}
	for xf in xforms:
		var key := Vector2i(floori(xf.origin.x / 48.0), floori(xf.origin.z / 48.0))
		if not chunks.has(key):
			var list: Array[Transform3D] = []
			chunks[key] = list
		chunks[key].append(xf)
	for list: Array[Transform3D] in chunks.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tuft
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = reach
		mmi.visibility_range_end_margin = 15.0
		parent.add_child(mmi)


static func _tuft_mesh(dry: bool) -> ArrayMesh:
	var key := "tuft_dry" if dry else "tuft"
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := PI * i / 3.0
		var facing := Vector3(cos(a), 0, sin(a))
		_card(st, Vector3(0, 0.22, 0), facing, Vector3.UP, Vector2(0.75, 0.46), Vector3.UP, 1.0, float(i) / 3.0)
	var m := ArrayMesh.new()
	st.commit(m)
	var mat := _leaf_material("grass_dry" if dry else "grass", Color(0.74, 0.76, 0.64), Color(0.6, 0.66, 0.5))
	mat.set_shader_parameter("autumn_amount", 0.0)
	mat.set_shader_parameter("ground_ao", true)
	m.surface_set_material(0, mat)
	_meshes[key] = m
	return m


## Grass bands on both sides of a road polyline, `inner`..`outer` metres from its centre line.
## `height` (x, z) -> y follows the terrain; `blocked` (Vector3) -> bool skips occupied ground.
static func roadside_grass(parent: Node3D, path: PackedVector3Array, closed: bool, inner: float, outer: float,
		per_metre: float, seed: int, height := Callable(), blocked := Callable(), dry := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points: Array[Vector3] = []
	var segments := path.size() if closed else path.size() - 1
	for i in segments:
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var d := b - a
		d.y = 0
		var length := d.length()
		if length < 0.01:
			continue
		var side := Vector3(-d.z, 0, d.x) / length
		var count := int(length * per_metre)
		for k in count:
			var along := a.lerp(b, rng.randf())
			var lateral := rng.randf_range(inner, outer)
			# Denser near the road edge, thinning out into the field.
			if rng.randf() > 1.0 - 0.6 * (lateral - inner) / maxf(outer - inner, 0.1):
				continue
			var p := along + side * lateral * (1.0 if rng.randf() < 0.5 else -1.0)
			if height.is_valid():
				p.y = height.call(p.x, p.z)
			if blocked.is_valid() and blocked.call(p):
				continue
			points.append(p)
	grass(parent, points, seed, dry)


## Grass tufts scattered over a rectangle (x/z), `density` per square metre.
static func field_grass(parent: Node3D, rect: Rect2, density: float, seed: int, height := Callable(),
		blocked := Callable(), dry := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points: Array[Vector3] = []
	for i in int(rect.get_area() * density):
		var p := Vector3(rng.randf_range(rect.position.x, rect.end.x), 0.0, rng.randf_range(rect.position.y, rect.end.y))
		if height.is_valid():
			p.y = height.call(p.x, p.z)
		if blocked.is_valid() and blocked.call(p):
			continue
		points.append(p)
	grass(parent, points, seed, dry)
