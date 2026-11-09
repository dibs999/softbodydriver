extends RefCounted
## Furniture of rural roads, so they read as real roads rather than a ribbon through grass:
## W-beam guardrails on sharp bends and embankments, chevron boards on the outside of bends with
## a warning sign before them, wooden utility poles carrying sagging wires, post-and-rail pasture
## fences, boulders and hay bales. Everything that can be hit has a collider and stays outside the
## carriageway; wires, boards and sign faces are visual only.

const C := preload("res://scripts/maps/common.gd")

static var _materials := {}


static func _mat(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m: StandardMaterial3D
	match key:
		"steel":
			m = C.mat(Color(0.62, 0.63, 0.64), 0.42, 0.85)
		"post":
			m = C.mat(Color(0.48, 0.49, 0.5), 0.5, 0.7)
		"wood":
			m = C.noise_mat(Color(0.33, 0.25, 0.17), 0.12, 6.0, 0.95)
		"wood_grey":
			m = C.noise_mat(Color(0.42, 0.40, 0.36), 0.12, 6.0, 0.95)
		"wire":
			m = C.mat(Color(0.08, 0.08, 0.08), 0.6, 0.3)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"insulator":
			m = C.mat(Color(0.55, 0.62, 0.55), 0.25)
		"rock":
			m = C.noise_mat(Color(0.47, 0.46, 0.43), 0.22, 3.0, 0.92)
		"hay":
			m = C.noise_mat(Color(0.72, 0.62, 0.36), 0.18, 9.0, 1.0)
		"sign_back":
			m = C.mat(Color(0.55, 0.56, 0.57), 0.5, 0.6)
		_:
			m = C.mat(Color.MAGENTA)
	_materials[key] = m
	return m


## Signed turn (radians) of the road around point i, over a window of w points either side.
static func _turn(road: PackedVector3Array, i: int, w: int, closed: bool) -> float:
	var n := road.size()
	var ia := (i - w + n) % n if closed else maxi(0, i - w)
	var ib := (i + w) % n if closed else mini(n - 1, i + w)
	var d0 := road[i] - road[ia]
	var d1 := road[ib] - road[i]
	if Vector2(d0.x, d0.z).length() < 0.1 or Vector2(d1.x, d1.z).length() < 0.1:
		return 0.0
	return Vector2(d0.x, d0.z).angle_to(Vector2(d1.x, d1.z))


static func _side(road: PackedVector3Array, i: int, closed: bool) -> Vector3:
	var n := road.size()
	var a := road[(i - 1 + n) % n] if closed or i > 0 else road[i]
	var b := road[(i + 1) % n] if closed or i < n - 1 else road[i]
	var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	return Vector3(-d.z, 0, d.x)


## Groups consecutive flagged indices into runs [start, end] (inclusive), padded by `pad`.
static func _runs(flags: Array[bool], pad: int, closed: bool) -> Array:
	var n := flags.size()
	var grown: Array[bool] = []
	grown.resize(n)
	for i in n:
		if not flags[i]:
			continue
		for k in range(-pad, pad + 1):
			var j := i + k
			if closed:
				j = (j + n) % n
			elif j < 0 or j >= n:
				continue
			grown[j] = true
	var runs: Array = []
	var i := 0
	while i < n:
		if grown[i]:
			var s := i
			while i < n and grown[i]:
				i += 1
			runs.append([s, i - 1])
		else:
			i += 1
	return runs


# ------------------------------------------------------------------------------------ guardrails

## W-beam guardrails on the outside of sharp bends and where the ground falls away beside the
## road. Returns the number of rail runs built.
static func guardrails(parent: Node3D, world: SBWorld, road: PackedVector3Array, half_w: float,
		height: Callable, closed := true, bend := 0.22, drop := 1.4) -> int:
	var n := road.size()
	var offset := half_w + 1.15
	var flags_l: Array[bool] = []
	var flags_r: Array[bool] = []
	flags_l.resize(n)
	flags_r.resize(n)
	for i in n:
		var turn := _turn(road, i, 4, closed)
		var side := _side(road, i, closed)
		for s: float in [-1.0, 1.0]:
			var edge := road[i] + side * s * (offset + 3.0)
			var fall := road[i].y - float(height.call(edge.x, edge.z))
			# Outside of the bend: a left turn (positive angle here) has its outside on the right.
			var outside := (turn > bend and s > 0.0) or (turn < -bend and s < 0.0)
			if outside or fall > drop:
				if s < 0.0: flags_l[i] = true
				else: flags_r[i] = true
	var built := 0
	for pass_side: float in [-1.0, 1.0]:
		var flags := flags_l if pass_side < 0.0 else flags_r
		for run: Array in _runs(flags, 2, closed):
			var pts := PackedVector3Array()
			for i in range(int(run[0]), int(run[1]) + 1):
				var p := road[i % n] + _side(road, i % n, closed) * pass_side * offset
				p.y = float(height.call(p.x, p.z))
				pts.append(p)
			if _length(pts) < 12.0:
				continue
			_rail(parent, world, pts, pass_side)
			built += 1
	return built


static func _length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


## Resamples a polyline at a fixed spacing.
static func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3:
		out.append(pts[pts.size() - 1])
	return out


static func _rail(parent: Node3D, world: SBWorld, pts: PackedVector3Array, face: float) -> void:
	var line := _resample(pts, 2.0)
	var m := line.size()
	# W-beam section (lateral offset towards the road, height above ground).
	var section := [Vector2(0.0, 0.50), Vector2(-0.04, 0.55), Vector2(-0.01, 0.61), Vector2(-0.04, 0.67),
		Vector2(0.0, 0.72), Vector2(0.02, 0.72), Vector2(0.02, 0.50)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array[Transform3D] = []
	for i in m:
		var a := line[maxi(0, i - 1)]
		var b := line[mini(m - 1, i + 1)]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var lateral := Vector3(-dir.z, 0, dir.x) * -face   # towards the road
		var base := line[i]
		if i < m - 1:
			var nxt := line[i + 1]
			var d2 := Vector3(nxt.x - base.x, 0, nxt.z - base.z).normalized()
			var lat2 := Vector3(-d2.z, 0, d2.x) * -face
			for k in section.size() - 1:
				var p0: Vector2 = section[k]
				var p1: Vector2 = section[k + 1]
				var q := [base + lateral * p0.x + Vector3.UP * p0.y, base + lateral * p1.x + Vector3.UP * p1.y,
					nxt + lat2 * p1.x + Vector3.UP * p1.y, nxt + lat2 * p0.x + Vector3.UP * p0.y]
				st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
				st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])
		posts.append(Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), base + Vector3.UP * 0.36 - lateral * 0.06))
		# Collider per 4 m: the beam face at bumper height.
		if i % 2 == 0 and i < m - 2:
			var c := (line[i] + line[i + 2]) * 0.5 + Vector3.UP * 0.6 - lateral * 0.03
			var dd := line[i + 2] - line[i]
			world.add_box(c, Vector3(Vector2(dd.x, dd.z).length() * 0.5 + 0.1, 0.32, 0.06), Vector3(0, atan2(-dd.z, dd.x), 0), 0.35)
	st.generate_normals()
	var rail := MeshInstance3D.new()
	rail.mesh = st.commit()
	rail.material_override = _mat("steel")
	var mat: StandardMaterial3D = _mat("steel")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(rail)
	var post := BoxMesh.new()
	post.size = Vector3(0.10, 0.80, 0.12)
	C.scatter_multimesh(parent, post, _mat("post"), posts)


# ----------------------------------------------------------------------------- bends and signs

## Chevron boards on the outside of sharp bends, plus a warning sign ahead of each bend in both
## directions of travel.
static func bend_signs(parent: Node3D, road: PackedVector3Array, half_w: float, height: Callable,
		closed := true, bend := 0.30) -> void:
	var n := road.size()
	var flags: Array[bool] = []
	flags.resize(n)
	for i in n:
		flags[i] = absf(_turn(road, i, 4, closed)) > bend
	var boards: Array[Transform3D] = []
	var poles: Array[Transform3D] = []
	var warn_faces: Array[Transform3D] = []
	for run: Array in _runs(flags, 0, closed):
		var mid := (int(run[0]) + int(run[1])) / 2
		var turn := _turn(road, mid, 4, closed)
		var outside := 1.0 if turn > 0.0 else -1.0
		for i in range(int(run[0]), int(run[1]) + 1, 3):
			var k := i % n
			var side := _side(road, k, closed)
			var p := road[k] + side * outside * (half_w + 2.0)
			p.y = float(height.call(p.x, p.z))
			var face := -side * outside
			var yaw := atan2(face.x, face.z)
			boards.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 1.25))
			poles.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6))
		# Warning sign ~60 m ahead in each direction, on the right-hand verge.
		for dir_sign: int in [-1, 1]:
			var start := int(run[0]) if dir_sign > 0 else int(run[1])
			var j := start
			var travelled := 0.0
			while travelled < 60.0:
				var nj := j - dir_sign
				if not closed and (nj < 0 or nj >= n):
					break
				nj = (nj + n) % n
				travelled += road[j].distance_to(road[nj])
				j = nj
			var side := _side(road, j, closed)
			var right := side * (1.0 if dir_sign > 0 else -1.0) * -1.0
			var p := road[j] + right * (half_w + 1.6)
			p.y = float(height.call(p.x, p.z))
			var toward := Vector3(road[start].x - p.x, 0, road[start].z - p.z).normalized() * -1.0
			warn_faces.append(Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.z)), p + Vector3.UP * 2.0))
			poles.append(Transform3D(Basis.from_scale(Vector3(1, 2.2, 1)), p + Vector3.UP * 1.2))
	var board := BoxMesh.new()
	board.size = Vector3(0.6, 0.8, 0.03)
	var chevron := StandardMaterial3D.new()
	chevron.albedo_texture = _chevron_texture()
	chevron.roughness = 0.5
	C.scatter_multimesh(parent, board, chevron, boards)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.035
	pole.height = 1.2
	C.scatter_multimesh(parent, pole, _mat("post"), poles)
	var tri := PrismMesh.new()
	tri.size = Vector3(0.9, 0.8, 0.03)
	var warn := StandardMaterial3D.new()
	warn.albedo_texture = _warning_texture()
	warn.roughness = 0.5
	C.scatter_multimesh(parent, tri, warn, warn_faces)


static var _chevron_tex: ImageTexture
static func _chevron_texture() -> ImageTexture:
	if _chevron_tex:
		return _chevron_tex
	var img := Image.create(64, 96, false, Image.FORMAT_RGB8)
	img.fill(Color(0.95, 0.95, 0.95))
	for y in 96:
		for x in 64:
			# Two red chevrons pointing sideways (direction of the bend).
			var u := float(x) / 64.0
			var v := absf(float(y) / 96.0 - 0.5)
			var band := fposmod(u * 2.0 + v * 2.4, 1.0)
			if band < 0.45:
				img.set_pixel(x, y, Color(0.78, 0.06, 0.05))
	img.generate_mipmaps()
	_chevron_tex = ImageTexture.create_from_image(img)
	return _chevron_tex


static var _warning_tex: ImageTexture
static func _warning_texture() -> ImageTexture:
	if _warning_tex:
		return _warning_tex
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	img.fill(Color(0.78, 0.06, 0.05))
	for y in s:
		for x in s:
			var u := float(x) / s - 0.5
			var v := 1.0 - float(y) / s
			# Inner white triangle and a black bend arrow.
			var inside := v > 0.16 and absf(u) < (0.9 - v) * 0.5 - 0.02
			if inside:
				img.set_pixel(x, y, Color(0.96, 0.96, 0.96))
				var cx := 0.06 * sin((v - 0.2) * 9.0)
				if absf(u - cx) < 0.035 and v > 0.22 and v < 0.62:
					img.set_pixel(x, y, Color(0.03, 0.03, 0.03))
	img.generate_mipmaps()
	_warning_tex = ImageTexture.create_from_image(img)
	return _warning_tex


# ------------------------------------------------------------------------------- utility lines

## Wooden poles at `offset` beside the road (positive = left of travel), every `spacing` metres,
## carrying three sagging wires. `clear` (optional Callable(Vector3) -> bool) rejects positions.
static func utility_line(parent: Node3D, world: SBWorld, road: PackedVector3Array, offset: float,
		height: Callable, closed := true, spacing := 42.0, clear := Callable()) -> void:
	var tops: Array = []
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var insulators: Array[Transform3D] = []
	var travelled := spacing
	var n := road.size()
	var segs := n if closed else n - 1
	for i in segs:
		var a := road[i]
		var b := road[(i + 1) % n]
		travelled += a.distance_to(b)
		if travelled < spacing:
			continue
		travelled = 0.0
		var side := _side(road, i, closed)
		var p := a + side * offset
		if clear.is_valid() and not bool(clear.call(p)):
			tops.append(null)
			continue
		p.y = float(height.call(p.x, p.z))
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var yaw := atan2(-dir.z, dir.x)
		poles.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 4.0))
		arms.append(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + Vector3.UP * 7.6))
		var top := []
		for k: float in [-0.75, 0.0, 0.75]:
			var at := p + side * k + Vector3.UP * (7.75 if k != 0.0 else 8.05)
			insulators.append(Transform3D(Basis.IDENTITY, at - Vector3.UP * 0.08))
			top.append(at)
		tops.append(top)
		world.add_box(p + Vector3.UP * 2.0, Vector3(0.13, 2.0, 0.13), Vector3.ZERO, 0.6)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.11
	pole.bottom_radius = 0.14
	pole.height = 8.0
	pole.radial_segments = 8
	C.scatter_multimesh(parent, pole, _mat("wood_grey"), poles)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.9, 0.10, 0.10)
	C.scatter_multimesh(parent, arm, _mat("wood_grey"), arms)
	var ins := CylinderMesh.new()
	ins.top_radius = 0.03
	ins.bottom_radius = 0.045
	ins.height = 0.16
	ins.radial_segments = 6
	C.scatter_multimesh(parent, ins, _mat("insulator"), insulators, false)
	# Wires: catenary between consecutive poles as crossed ribbons (visible from any angle).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := tops.size()
	for i in (count if closed else count - 1):
		var t0: Variant = tops[i]
		var t1: Variant = tops[(i + 1) % count]
		if t0 == null or t1 == null:
			continue
		for w in 3:
			var a: Vector3 = t0[w]
			var b: Vector3 = t1[w]
			if a.distance_to(b) > spacing * 2.5:
				continue
			var prev := a
			for s in range(1, 11):
				var t := float(s) / 10.0
				var q := a.lerp(b, t) - Vector3.UP * (4.0 * 0.55 * t * (1.0 - t))
				_ribbon(st, prev, q, 0.018)
				prev = q
	var wires := MeshInstance3D.new()
	wires.mesh = st.commit()
	wires.material_override = _mat("wire")
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wires.visibility_range_end = 450.0
	parent.add_child(wires)


static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := (b - a).normalized()
	for off: Vector3 in [Vector3.UP * w, d.cross(Vector3.UP).normalized() * w]:
		st.set_normal(Vector3.UP)
		st.add_vertex(a - off); st.add_vertex(a + off); st.add_vertex(b + off)
		st.add_vertex(a - off); st.add_vertex(b + off); st.add_vertex(b - off)


# ------------------------------------------------------------------------- fences, rocks, hay

## Post-and-rail fence along a polyline (pasture boundaries).
static func fence(parent: Node3D, world: SBWorld, pts: PackedVector3Array, height: Callable) -> void:
	var line := _resample(pts, 2.6)
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for i in line.size():
		var p := line[i]
		p.y = float(height.call(p.x, p.z))
		line[i] = p
		posts.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6))
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var d := b - a
		var len := d.length()
		var basis := Basis.looking_at(d.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, len))
		for h: float in [0.55, 1.0]:
			rails.append(Transform3D(basis, (a + b) * 0.5 + Vector3.UP * h))
		world.add_box((a + b) * 0.5 + Vector3.UP * 0.6, Vector3(len * 0.5, 0.5, 0.06), Vector3(0, atan2(-d.z, d.x), 0), 0.5)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.2, 0.12)
	C.scatter_multimesh(parent, post, _mat("wood"), posts)
	var rail := BoxMesh.new()
	rail.size = Vector3(0.05, 0.10, 1.0)
	C.scatter_multimesh(parent, rail, _mat("wood"), rails)


static var _rock_meshes: Array[Mesh] = []
static func _rocks() -> Array[Mesh]:
	if not _rock_meshes.is_empty():
		return _rock_meshes
	for variant in 3:
		var noise := FastNoiseLite.new()
		noise.seed = 71 + variant
		noise.frequency = 1.6
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 14
		sphere.rings = 8
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			var r := 1.0 + 0.32 * noise.get_noise_3dv(v * 2.0)
			v *= r
			v.y = maxf(v.y * (0.55 + 0.15 * variant), -0.18)   # flattened, sunk into the ground
			verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		st.create_from(am, 0)
		st.generate_normals()
		_rock_meshes.append(st.commit())
	return _rock_meshes


## Boulders: transforms with scale; those larger than 0.9 m get a box collider.
static func boulders(parent: Node3D, world: SBWorld, xforms: Array[Transform3D]) -> void:
	var meshes := _rocks()
	var groups: Array = [[], [], []]
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		groups[i % 3].append(xf)
		var s := xf.basis.get_scale()
		if s.x > 0.9:
			world.add_box(xf.origin + Vector3.UP * s.y * 0.2, Vector3(s.x * 0.42, s.y * 0.32, s.z * 0.42), Vector3.ZERO, 0.8)
	for v in 3:
		var list: Array[Transform3D] = []
		list.assign(groups[v])
		C.scatter_multimesh(parent, meshes[v], _mat("rock"), list)


## Round hay bales lying on their side.
static func hay_bales(parent: Node3D, world: SBWorld, xforms: Array[Transform3D]) -> void:
	var bale := CylinderMesh.new()
	bale.top_radius = 0.65
	bale.bottom_radius = 0.65
	bale.height = 1.2
	bale.radial_segments = 16
	var list: Array[Transform3D] = []
	for xf in xforms:
		list.append(Transform3D(xf.basis * Basis(Vector3.RIGHT, PI * 0.5), xf.origin + Vector3.UP * 0.62))
		world.add_box(xf.origin + Vector3.UP * 0.62, Vector3(0.6, 0.6, 0.6), xf.basis.get_euler(), 0.7)
	C.scatter_multimesh(parent, bale, _mat("hay"), list)
