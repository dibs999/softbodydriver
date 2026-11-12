extends RefCounted
## Shared helpers for the procedural maps: materials, colliding boxes, fast terrain meshes,
## road ribbons with lane markings, guard rails and simple props.

static var _noise_textures: Dictionary = {}
const SURFACE_PATH := "res://materials/surfaces/"
const ROAD_SHADER := preload("res://materials/surfaces/road.gdshader")
const GROUND_SHADER := preload("res://materials/surfaces/ground.gdshader")

static func car_xform(pos: Vector3, heading: Vector3) -> Transform3D:
	var f := Vector3(heading.x, 0, heading.z).normalized()
	var r := f.cross(Vector3.UP)
	return Transform3D(Basis(f, Vector3.UP, r), pos)


static func closed_route(points: PackedVector3Array) -> PackedVector3Array:
	var route := points.duplicate()
	if not route.is_empty():
		route.append(route[0])
	return route


static func mat(color: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


## Per-surface look of the large-scale variation: [brightness, patch scale m, patch tint, tint amount,
## roughness, wet response].
const GROUND_LOOK := {
	"grass": [0.16, 46.0, Color(0.78, 0.70, 0.42), 0.55, 0.96, 0.35],
	"asphalt": [0.18, 34.0, Color(0.62, 0.62, 0.64), 0.35, 0.86, 1.0],
	"pavement": [0.07, 28.0, Color(0.70, 0.68, 0.62), 0.25, 0.88, 0.9],
	"gravel": [0.12, 22.0, Color(0.72, 0.64, 0.52), 0.45, 0.96, 0.6],
	"sand": [0.10, 60.0, Color(0.80, 0.62, 0.44), 0.50, 0.98, 0.4],
}


static func surface_material(kind: String, tile_metres: float, tint := Color.WHITE,
		normal_strength := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("albedo_tex", load(SURFACE_PATH + kind + ".jpg"))
	m.set_shader_parameter("tile_metres", tile_metres)
	m.set_shader_parameter("tint", tint)
	var look: Array = GROUND_LOOK.get(kind, [0.08, 30.0, Color.WHITE, 0.0, 0.9, 0.6])
	m.set_shader_parameter("macro_strength", look[0])
	m.set_shader_parameter("macro_scale", look[1])
	m.set_shader_parameter("macro_tint", look[2])
	m.set_shader_parameter("macro_tint_amount", look[3])
	m.set_shader_parameter("roughness", look[4])
	m.set_shader_parameter("wet_response", look[5])
	if normal_strength > 0.0 and ResourceLoader.exists(SURFACE_PATH + kind + "_normal.jpg"):
		m.set_shader_parameter("has_normal", true)
		m.set_shader_parameter("normal_tex", load(SURFACE_PATH + kind + "_normal.jpg"))
		m.set_shader_parameter("normal_strength", normal_strength)
	return m


static func terrain_material(kind: String, tile_metres: float, tint := Color.WHITE) -> ShaderMaterial:
	if kind == "grass" and tint == Color.WHITE:
		tint = Color(0.6, 0.78, 0.52)   # the photo is late-summer grass; maps are greener
	var m := surface_material(kind, tile_metres, tint)
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("meadow", kind == "grass")
	# Earth and stone on embankments and steep hillsides instead of grass or sand everywhere.
	m.set_shader_parameter("has_slope", true)
	m.set_shader_parameter("slope_tex", load(SURFACE_PATH + "gravel.jpg"))
	m.set_shader_parameter("slope_tile", 2.6)
	m.set_shader_parameter("slope_tint", Color(0.60, 0.55, 0.47) if kind != "sand" else Color(0.80, 0.60, 0.46))
	m.set_shader_parameter("slope_start", 0.84)
	m.set_shader_parameter("slope_full", 0.62)
	return m


static func noise_mat(base: Color, variation: float, scale: float, rough := 0.95, freq := 0.05, vertex_color := false) -> StandardMaterial3D:
	var m := mat(Color.WHITE, rough)
	var tint := Color(0.85, 0.85, 0.85) if vertex_color else base
	var key := [tint, variation, freq]
	if not _noise_textures.has(key):
		_noise_textures[key] = _make_noise_texture(tint, variation, freq)
	m.albedo_texture = _noise_textures[key]
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar = true
	m.vertex_color_use_as_albedo = vertex_color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _make_noise_texture(tint: Color, variation: float, frequency: float) -> ImageTexture:
	# Finish small, reusable tiles during map loading so they need no upload during driving.
	const SIZE := 128
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	var samples := noise.get_seamless_image(SIZE, SIZE).get_data()
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var dark := tint.darkened(variation)
	var light := tint.lightened(variation)
	for y in SIZE:
		for x in SIZE:
			image.set_pixel(x, y, dark.lerp(light, samples[y * SIZE + x] / 255.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


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
		path: PackedVector3Array, half_w: float, blend: float, depth := 0.06, closed := true) -> void:
	var reach := half_w + blend
	var best := PackedFloat32Array()
	best.resize(nx * nz)
	best.fill(1e9)
	var by := PackedFloat32Array()
	by.resize(nx * nz)
	var n := path.size()
	for i in (n if closed else n - 1):
		var a := path[i]
		var b := path[(i + 1) % n]
		var start := Vector2(a.x, a.z)
		var segment := Vector2(b.x, b.z) - start
		var length_sq := maxf(segment.length_squared(), 0.000001)
		var min_x := maxi(0, ceili((minf(a.x, b.x) - reach - ox) / cell))
		var max_x := mini(nx - 1, floori((maxf(a.x, b.x) + reach - ox) / cell))
		var min_z := maxi(0, ceili((minf(a.z, b.z) - reach - oz) / cell))
		var max_z := mini(nz - 1, floori((maxf(a.z, b.z) + reach - oz) / cell))
		for ix in range(min_x, max_x + 1):
			for iz in range(min_z, max_z + 1):
				var offset := Vector2(ox + ix * cell, oz + iz * cell) - start
				var along := clampf(offset.dot(segment) / length_sq, 0.0, 1.0)
				var d := (offset - segment * along).length_squared()
				var k := ix * nz + iz
				if d < best[k]:
					best[k] = d
					by[k] = lerpf(a.y, b.y, along)
	for k in nx * nz:
		if best[k] < reach * reach:
			var t := clampf((sqrt(best[k]) - half_w) / blend, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			h[k] = lerpf(by[k] - depth, h[k], t)


## Physics copy of a heightfield, raised under the road meshes by each road's lift. A road mesh is
## drawn `lift` above the terrain so the terrain never shows through it; on the bare terrain the
## wheels and props sank into the drawn road by that lift (3-6 cm: the bottom of every tyre cut
## off by the road surface). Full lift within the road's half width, fading out over one cell
## beyond it, so the bilinear surface reaches the full lift wherever the road is drawn.
## roads: [{"points": PackedVector3Array, "half_w": float, "lift": float, "closed": bool}].
static func raise_under_roads(h: PackedFloat32Array, nx: int, nz: int, ox: float, oz: float, cell: float,
		roads: Array) -> PackedFloat32Array:
	var raise := PackedFloat32Array()
	raise.resize(nx * nz)
	raise.fill(0.0)
	for road: Dictionary in roads:
		var path: PackedVector3Array = road["points"]
		var half_w: float = road["half_w"]
		var lift: float = road["lift"]
		var reach := half_w + cell
		var n := path.size()
		for i in (n if road.get("closed", false) else n - 1):
			var a := path[i]
			var b := path[(i + 1) % n]
			var start := Vector2(a.x, a.z)
			var segment := Vector2(b.x, b.z) - start
			var length_sq := maxf(segment.length_squared(), 0.000001)
			var min_x := maxi(0, ceili((minf(a.x, b.x) - reach - ox) / cell))
			var max_x := mini(nx - 1, floori((maxf(a.x, b.x) + reach - ox) / cell))
			var min_z := maxi(0, ceili((minf(a.z, b.z) - reach - oz) / cell))
			var max_z := mini(nz - 1, floori((maxf(a.z, b.z) + reach - oz) / cell))
			for ix in range(min_x, max_x + 1):
				for iz in range(min_z, max_z + 1):
					var offset := Vector2(ox + ix * cell, oz + iz * cell) - start
					var along := clampf(offset.dot(segment) / length_sq, 0.0, 1.0)
					var d := (offset - segment * along).length()
					if d >= reach: continue
					var k := ix * nz + iz
					raise[k] = maxf(raise[k], lift * (1.0 - smoothstep(half_w, reach, d)))
	var out := h.duplicate()
	for k in nx * nz:
		out[k] += raise[k]
	return out


## Terrain mesh straight from packed arrays (fast). `colors` (optional, nx * nz) gives vertex colours.
static func terrain_mesh(ox: float, oz: float, cell: float, nx: int, nz: int, h: PackedFloat32Array,
		material: Material, colors := PackedColorArray(), region := Rect2i()) -> MeshInstance3D:
	if not region.has_area():
		region = Rect2i(0, 0, nx, nz)
	var rows := region.size.y
	var columns := region.size.x
	var count := rows * columns
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tint := PackedColorArray()
	verts.resize(count)
	normals.resize(count)
	uvs.resize(count)
	if colors.size() == nx * nz:
		tint.resize(count)
	for x in columns:
		var ix := region.position.x + x
		for z in rows:
			var iz := region.position.y + z
			var i := x * rows + z
			verts[i] = Vector3(ox + ix * cell, h[ix * nz + iz], oz + iz * cell)
			var hx0 := h[maxi(ix - 1, 0) * nz + iz]
			var hx1 := h[mini(ix + 1, nx - 1) * nz + iz]
			var hz0 := h[ix * nz + maxi(iz - 1, 0)]
			var hz1 := h[ix * nz + mini(iz + 1, nz - 1)]
			normals[i] = Vector3(hx0 - hx1, 2.0 * cell, hz0 - hz1).normalized()
			uvs[i] = Vector2(verts[i].x, verts[i].z) * 0.1
			if not tint.is_empty():
				tint[i] = colors[ix * nz + iz]
	var idx := PackedInt32Array()
	idx.resize((columns - 1) * (rows - 1) * 6)
	var k := 0
	for ix in columns - 1:
		for iz in rows - 1:
			var a := ix * rows + iz
			var b := (ix + 1) * rows + iz
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
	if not tint.is_empty():
		arrays[Mesh.ARRAY_COLOR] = tint
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = material
	return mi


static func terrain_tiles(parent: Node3D, ox: float, oz: float, cell: float, nx: int, nz: int,
		heights: PackedFloat32Array, material: Material, colors := PackedColorArray()) -> void:
	const TILE := 96
	for x in range(0, nx - 1, TILE):
		for z in range(0, nz - 1, TILE):
			# Adjacent tiles share border samples, including normals and colors.
			var region := Rect2i(x, z, mini(TILE + 1, nx - x), mini(TILE + 1, nz - z))
			parent.add_child(terrain_mesh(ox, oz, cell, nx, nz, heights, material, colors, region))


static func road_material(lanes: int, width: float, texture_length: float, style: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	var dirt := style == "dirt" or style == "desert"
	var kind := "gravel" if dirt else "asphalt"
	m.set_shader_parameter("surface_color", load(SURFACE_PATH + kind + ".jpg"))
	m.set_shader_parameter("surface_normal", load(SURFACE_PATH + kind + "_normal.jpg"))
	m.set_shader_parameter("texture_repeats", Vector2(width, texture_length) / (2.1 if dirt else 2.0))
	m.set_shader_parameter("road_width", width)
	m.set_shader_parameter("lanes", lanes)
	m.set_shader_parameter("dirt", dirt)
	m.set_shader_parameter("v_metres", texture_length)
	if style == "rural":
		# German country road: white centre line, 6 m dashes with 12 m gaps (yellow is only for
		# temporary roadworks markings).
		m.set_shader_parameter("divider_color", Color(0.86, 0.85, 0.80))
		m.set_shader_parameter("dash_period", 18.0)
		m.set_shader_parameter("dash_fraction", 6.0 / 18.0)
	elif style == "autobahn":
		# German motorway: 6 m dashes with 12 m gaps between the lanes.
		m.set_shader_parameter("dash_period", 18.0)
		m.set_shader_parameter("dash_fraction", 6.0 / 18.0)
	elif style == "village":
		# Unmarked village street, patched and worn.
		m.set_shader_parameter("markings", false)
		m.set_shader_parameter("wear", 1.1)
	elif style == "desert":
		m.set_shader_parameter("dirt_tint", Color(0.66, 0.56, 0.46))   # compacted, darker than the loose sand
	return m


## Road ribbon along a polyline (points with y). Closed loop if `closed`.
static func road_mesh(points: PackedVector3Array, half_w: float, material: Material, closed := true, lift := 0.04,
		v_scale := 12.0, height_at := Callable()) -> MeshInstance3D:
	if height_at.is_valid() and points.size() >= 2:
		# Follow the terrain between waypoints as well, especially at the shoulders.
		var samples := PackedVector3Array()
		var segments := points.size() if closed else points.size() - 1
		for i in segments:
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var count := maxi(1, ceili(a.distance_to(b) / 2.0))
			for j in count:
				samples.append(a.lerp(b, float(j) / count))
		if not closed:
			samples.append(points[-1])
		points = samples
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var segs := n if closed else n - 1
	var v := 0.0
	var strips := 4 if height_at.is_valid() else 1
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
		for j in strips:
			var left := float(j) / strips
			var right := float(j + 1) / strips
			var al := a + na * (2.0 * left - 1.0)
			var ar := a + na * (2.0 * right - 1.0)
			var bl := b + nb * (2.0 * left - 1.0)
			var br := b + nb * (2.0 * right - 1.0)
			var q := [[al, Vector2(left, v)], [br, Vector2(right, v2)], [ar, Vector2(right, v)],
				[al, Vector2(left, v)], [bl, Vector2(left, v2)], [br, Vector2(right, v2)]]
			for vertex in q:
				var p: Vector3 = vertex[0]
				if height_at.is_valid():
					p.y = height_at.call(p.x, p.z)
				p.y += lift
				st.set_uv(vertex[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
		v = v2
	if material is ShaderMaterial:
		st.generate_tangents()
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
	if material == null:
		return   # colliders only; the caller draws the barrier
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)


static func scatter_multimesh(parent: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], shadow := true) -> void:
	if xforms.is_empty():
		return
	# Whole-map batches defeat frustum culling. Partition repeated props spatially;
	# the physics colliders remain active independently of these visual batches.
	if xforms.size() > 64:
		var chunks: Dictionary = {}
		for xf in xforms:
			var key := Vector2i(floori(xf.origin.x / 192), floori(xf.origin.z / 192))
			if not chunks.has(key):
				var transforms: Array[Transform3D] = []
				chunks[key] = transforms
			chunks[key].append(xf)
		for chunk: Array[Transform3D] in chunks.values():
			_scatter_chunk(parent, mesh, material, chunk, shadow)
	else:
		_scatter_chunk(parent, mesh, material, xforms, shadow)

static func _scatter_chunk(parent: Node3D, mesh: Mesh, material: Material, xforms: Array[Transform3D], shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	var largest := 0.0
	for xf in xforms:
		largest = maxf(largest, (mesh.get_aabb().size * xf.basis.get_scale().abs()).length())
	# Buildings, trees and pavement preserve the skyline. Small props have a shorter range.
	if largest < 9.0:
		mmi.visibility_range_end = 600.0
		mmi.visibility_range_end_margin = 30.0
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


static func roadside_markers(parent: Node3D, bases: Array[Transform3D]) -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.95, 0.2)
	var reflector := BoxMesh.new()
	reflector.size = Vector3(0.13, 0.15, 0.21)
	var posts: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	for base in bases:
		posts.append(base.translated(Vector3.UP * 0.475))
		reflectors.append(base.translated(Vector3.UP * 0.78))
	scatter_multimesh(parent, post, mat(Color(0.9, 0.9, 0.86)), posts, false)
	scatter_multimesh(parent, reflector, mat(Color(0.23, 0.18, 0.13)), reflectors, false)


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


## Unpaved verges on both sides of a road built with road_mesh (same points, closed flag and
## height function): strips from just under the asphalt edge out to `width` metres beyond it, UV.x 0
## at the asphalt and 1 outside. The inner edge sits slightly below the road surface so the asphalt
## edge stays crisp; the outer edge meets the terrain. `sides` picks the left (-1) and/or right (+1) strip.
static func verge_mesh(points: PackedVector3Array, half_w: float, width: float, material: Material, closed := true,
		road_lift := 0.04, v_scale := 12.0, height_at := Callable(), sides: Array = [-1.0, 1.0]) -> MeshInstance3D:
	if height_at.is_valid() and points.size() >= 2:
		var samples := PackedVector3Array()
		var segments := points.size() if closed else points.size() - 1
		for i in segments:
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var count := maxi(1, ceili(a.distance_to(b) / 2.0))
			for j in count:
				samples.append(a.lerp(b, float(j) / count))
		if not closed:
			samples.append(points[-1])
		points = samples
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var segs := n if closed else n - 1
	var inner := half_w - 0.06
	var outer := half_w + width
	var lift_in := maxf(0.01, road_lift - 0.012)
	var lift_out := 0.012
	var v := 0.0
	for i in segs:
		var a := points[i]
		var b := points[(i + 1) % n]
		var ip := (i - 1 + n) % n if closed else maxi(i - 1, 0)
		var inx := (i + 2) % n if closed else mini(i + 2, n - 1)
		var da := (b - points[ip]).normalized()
		var db := (points[inx] - a).normalized()
		var na := Vector3(-da.z, 0, da.x).normalized()
		var nb := Vector3(-db.z, 0, db.x).normalized()
		var v2 := v + a.distance_to(b) / v_scale
		for side: float in sides:
			var ai := a + na * (inner * side)
			var ao := a + na * (outer * side)
			var bi := b + nb * (inner * side)
			var bo := b + nb * (outer * side)
			var quad := [[ai, Vector2(0, v), lift_in], [bo, Vector2(1, v2), lift_out], [ao, Vector2(1, v), lift_out],
				[ai, Vector2(0, v), lift_in], [bi, Vector2(0, v2), lift_in], [bo, Vector2(1, v2), lift_out]]
			if side > 0.0:   # keep the winding facing up on both sides
				quad = [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
			for vertex in quad:
				var p: Vector3 = vertex[0]
				if height_at.is_valid():
					p.y = height_at.call(p.x, p.z)
				p.y += vertex[2]
				st.set_uv(vertex[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
		v = v2
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func verge_material(width: float, v_scale := 12.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://materials/surfaces/verge.gdshader")
	m.set_shader_parameter("width_m", width)
	m.set_shader_parameter("v_metres", v_scale)
	return m
