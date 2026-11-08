extends RefCounted
## Shared helpers for the procedural maps: materials, colliding boxes, fast terrain meshes,
## road ribbons with lane markings, guard rails and simple props.

static func car_xform(pos: Vector3, heading: Vector3) -> Transform3D:
	var f := Vector3(heading.x, 0, heading.z).normalized()
	var r := f.cross(Vector3.UP)
	return Transform3D(Basis(f, Vector3.UP, r), pos)


static func mat(color: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


static func noise_mat(base: Color, variation: float, scale: float, rough := 0.95, freq := 0.05, vertex_color := false) -> StandardMaterial3D:
	var m := mat(base if not vertex_color else Color.WHITE, rough)
	var n := FastNoiseLite.new()
	n.frequency = freq
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	var c := base if not vertex_color else Color(0.85, 0.85, 0.85)
	g.set_color(0, c.darkened(variation))
	g.set_color(1, c.lightened(variation))
	tex.color_ramp = g
	m.albedo_texture = tex
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar = true
	m.vertex_color_use_as_albedo = vertex_color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func box(parent: Node3D, world: SBWorld, center: Vector3, half: Vector3, euler: Vector3, material: Material,
		friction := 0.8, collide := true, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mi.mesh = bm
	mi.material_override = material
	mi.transform = Transform3D(Basis.from_euler(euler, EULER_ORDER_XYZ), center)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		world.add_box(center, half, euler, friction)
	return mi


static func quad(parent: Node3D, center: Vector3, size: Vector2, material: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = material
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func sample(h: PackedFloat32Array, nx: int, nz: int, ox: float, oz: float, cell: float, x: float, z: float) -> float:
	var fx := clampf((x - ox) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - oz) / cell, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(h[ix * nz + iz], h[(ix + 1) * nz + iz], tx), lerpf(h[ix * nz + iz + 1], h[(ix + 1) * nz + iz + 1], tx), tz)


## Flattens the terrain along a path (points with y): within half_w the height is the path height,
## blended back to the terrain over `blend` metres. Only cells near the path are visited.
static func carve_path(h: PackedFloat32Array, nx: int, nz: int, ox: float, oz: float, cell: float,
		path: PackedVector3Array, half_w: float, blend: float, depth := 0.06) -> void:
	var reach := half_w + blend
	var best := PackedFloat32Array()
	best.resize(nx * nz)
	best.fill(1e9)
	var by := PackedFloat32Array()
	by.resize(nx * nz)
	var rc := int(ceil(reach / cell)) + 1
	var n := path.size()
	for i in n:
		# Sample the segment densely enough for the grid resolution.
		var a := path[i]
		var b := path[(i + 1) % n]
		var steps := maxi(1, int(a.distance_to(b) / (cell * 0.5)))
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			var cx := int(round((p.x - ox) / cell))
			var cz := int(round((p.z - oz) / cell))
			for ix in range(maxi(cx - rc, 0), mini(cx + rc + 1, nx)):
				for iz in range(maxi(cz - rc, 0), mini(cz + rc + 1, nz)):
					var dx := ox + ix * cell - p.x
					var dz := oz + iz * cell - p.z
					var d := dx * dx + dz * dz
					var k := ix * nz + iz
					if d < best[k]:
						best[k] = d
						by[k] = p.y
	for k in nx * nz:
		if best[k] < reach * reach:
			var t := clampf((sqrt(best[k]) - half_w) / blend, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			h[k] = lerpf(by[k] - depth, h[k], t)


## Terrain mesh straight from packed arrays (fast). `colors` (optional, nx * nz) gives vertex colours.
static func terrain_mesh(ox: float, oz: float, cell: float, nx: int, nz: int, h: PackedFloat32Array,
		material: Material, colors := PackedColorArray()) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	uvs.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var i := ix * nz + iz
			verts[i] = Vector3(ox + ix * cell, h[i], oz + iz * cell)
			var hx0 := h[maxi(ix - 1, 0) * nz + iz]
			var hx1 := h[mini(ix + 1, nx - 1) * nz + iz]
			var hz0 := h[ix * nz + maxi(iz - 1, 0)]
			var hz1 := h[ix * nz + mini(iz + 1, nz - 1)]
			normals[i] = Vector3(hx0 - hx1, 2.0 * cell, hz0 - hz1).normalized()
			uvs[i] = Vector2(verts[i].x, verts[i].z) * 0.1
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for ix in nx - 1:
		for iz in nz - 1:
			var a := ix * nz + iz
			var b := (ix + 1) * nz + iz
			var c := a + 1
			var d := b + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = d
			idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if colors.size() == nx * nz:
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = material
	return mi


## Lane-marking texture: `lanes` lanes, `style` = "rural" | "autobahn" | "city" | "dirt".
static func road_material(lanes: int, style: String) -> StandardMaterial3D:
	var w := 32 * lanes + 16
	var img := Image.create(w, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = lanes * 31 + style.length()
	var base := Color(0.16, 0.16, 0.17)
	if style == "dirt":
		base = Color(0.55, 0.43, 0.3)
	for y in 128:
		for x in w:
			var c := base.lerp(base.lightened(0.15), rng.randf() * 0.7)
			img.set_pixel(x, y, c)
	if style != "dirt":
		var white := Color(0.92, 0.92, 0.88)
		for y in 128:
			for x in [2, 3, w - 4, w - 3]:
				img.set_pixel(x, y, white)
			for l in range(1, lanes):
				var lx := 8 + l * 32
				var dashed := (y % 64) < (24 if style == "autobahn" else 32)
				if style == "rural" and l == lanes / 2:
					dashed = (y % 64) < 32
				if dashed:
					img.set_pixel(lx, y, white if not (style == "rural" and l == lanes / 2) else Color(0.95, 0.85, 0.45))
					img.set_pixel(lx + 1, y, white if not (style == "rural" and l == lanes / 2) else Color(0.95, 0.85, 0.45))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.88 if style != "dirt" else 0.98
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Road ribbon along a polyline (points with y). Closed loop if `closed`.
static func road_mesh(points: PackedVector3Array, half_w: float, material: Material, closed := true, lift := 0.04,
		v_scale := 12.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var segs := n if closed else n - 1
	var v := 0.0
	for i in segs:
		var a := points[i]
		var b := points[(i + 1) % n]
		var ip := (i - 1 + n) % n if closed else maxi(i - 1, 0)
		var inx := (i + 2) % n if closed else mini(i + 2, n - 1)
		var da := (b - points[ip]).normalized()
		var db := (points[inx] - a).normalized()
		var na := Vector3(-da.z, 0, da.x).normalized() * half_w
		var nb := Vector3(-db.z, 0, db.x).normalized() * half_w
		var v2 := v + a.distance_to(b) / v_scale
		var up := Vector3(0, lift, 0)
		var q := [[a - na + up, Vector2(0, v)], [b + nb + up, Vector2(1, v2)], [a + na + up, Vector2(1, v)],
			[a - na + up, Vector2(0, v)], [b - nb + up, Vector2(0, v2)], [b + nb + up, Vector2(1, v2)]]
		for e in q:
			st.set_uv(e[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(e[0])
		v = v2
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Barrier / guard rail along a polyline offset sideways by `offset` (colliding segments).
static func barrier(parent: Node3D, world: SBWorld, points: PackedVector3Array, offset: float, height: float,
		thickness: float, material: Material, closed := true, segment := 20.0) -> void:
	var n := points.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mm.mesh = bm
	var xfs: Array[Transform3D] = []
	var acc := 0.0
	var start := points[0]
	var segs := n if closed else n - 1
	for i in segs:
		var a := points[i]
		var b := points[(i + 1) % n]
		acc += a.distance_to(b)
		if acc < segment and i < segs - 1:
			continue
		var d := b - start
		var len := Vector2(d.x, d.z).length()
		if len < 0.5:
			continue
		var dir := Vector3(d.x, 0, d.z) / len
		var side := Vector3(-dir.z, 0, dir.x)
		var mid := (start + b) * 0.5 + side * offset + Vector3(0, height * 0.5, 0)
		var yaw := atan2(-dir.z, dir.x)
		var half := Vector3(len * 0.5 + 0.15, height * 0.5, thickness * 0.5)
		world.add_box(mid, half, Vector3(0, yaw, 0), 0.6)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(half * 2.0), mid))
		start = b
		acc = 0.0
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)


static func scatter_multimesh(parent: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], shadow := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


static func speeds_from_curvature(path: PackedVector3Array, vmax: float, vmin: float, k := 60.0) -> PackedFloat32Array:
	var n := path.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := path[(i - 3 + n) % n]
		var b := path[i]
		var c := path[(i + 3) % n]
		var ang := (b - a).normalized().angle_to((c - b).normalized())
		out[i] = clampf(vmax - ang * k, vmin, vmax)
	return out


static func label3d(parent: Node3D, text: String, pos: Vector3, yaw: float, size := 1.6, color := Color.WHITE) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = size / 96.0
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation = Vector3(0, yaw, 0)
	parent.add_child(l)
