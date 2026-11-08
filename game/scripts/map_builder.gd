extends RefCounted
## Builds the maps: visual geometry (Godot meshes) + matching static colliders in the SBWorld.
## Returns {"spawns": Array[Transform3D], "waypoints": PackedVector3Array, "speeds": PackedFloat32Array}.

const FACE_POS_X := 0.0           # yaw that makes a car (local +X forward) face world +X


static func car_xform(pos: Vector3, heading: Vector3) -> Transform3D:
	## Transform for spawning a car at `pos` (ground) facing `heading`.
	var f := Vector3(heading.x, 0, heading.z).normalized()
	var up := Vector3.UP
	var r := f.cross(up)
	return Transform3D(Basis(f, up, r), pos)


static func _mat(color: Color, rough := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


static func _noise_material(base: Color, variation: float, scale: float, rough := 0.95) -> StandardMaterial3D:
	var m := _mat(base, rough)
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var grad := Gradient.new()
	grad.set_color(0, base.darkened(variation))
	grad.set_color(1, base.lightened(variation))
	tex.color_ramp = grad
	m.albedo_texture = tex
	m.uv1_scale = Vector3(scale, scale, scale)
	m.uv1_triplanar = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _box(parent: Node3D, world: SBWorld, center: Vector3, half: Vector3, euler: Vector3, mat: Material, friction := 1.0, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = half * 2.0
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_euler(euler, EULER_ORDER_XYZ), center)
	parent.add_child(mi)
	if collide:
		world.add_box(center, half, euler, friction)


static func _ramp(parent: Node3D, world: SBWorld, x_start: float, z: float, half_len: float, angle: float, mat: Material) -> void:
	## Ramp rising along +X from (x_start, 0, z).
	var h := 0.4
	var cx := x_start + half_len * cos(angle) + h * sin(angle)
	var cy := half_len * sin(angle) - h * cos(angle)
	_box(parent, world, Vector3(cx, cy, z), Vector3(half_len, h, 2.8), Vector3(0, 0, angle), mat)


static func _flat_quad(parent: Node3D, center: Vector3, size: Vector2, mat: Material, yaw := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _cone(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.17
	cm.height = 0.7
	mi.mesh = cm
	mi.material_override = _mat(Color(1.0, 0.38, 0.05), 0.6)
	mi.position = pos + Vector3(0, 0.35, 0)
	parent.add_child(mi)


# =========================================================================== proving grounds
static func build_proving_grounds(world: SBWorld, parent: Node3D) -> Dictionary:
	world.add_ground_plane(1.0)
	var grass := _noise_material(Color(0.22, 0.36, 0.14), 0.25, 0.08)
	var asphalt := _noise_material(Color(0.2, 0.2, 0.21), 0.18, 0.25, 0.85)
	var concrete := _noise_material(Color(0.62, 0.61, 0.58), 0.12, 0.5, 0.8)
	var line := _mat(Color(0.92, 0.92, 0.88), 0.6)
	var red := _mat(Color(0.75, 0.1, 0.08), 0.6)

	_flat_quad(parent, Vector3(0, -0.01, 0), Vector2(3000, 3000), grass)
	_flat_quad(parent, Vector3(0, 0.0, 0), Vector2(520, 360), asphalt)

	# Oval track painted on the pad (straights along X).
	var waypoints := PackedVector3Array()
	var speeds := PackedFloat32Array()
	var straight := 180.0
	var radius := 70.0
	var cz := 80.0
	var steps := 72
	for i in steps:
		var t := float(i) / steps
		var p := Vector3.ZERO
		var perim := 2.0 * straight + 2.0 * PI * radius
		var s := t * perim
		var spd := 30.0
		if s < straight:
			p = Vector3(-straight / 2 + s, 0, cz - radius)
		elif s < straight + PI * radius:
			var a := (s - straight) / radius
			p = Vector3(straight / 2 + sin(a) * radius, 0, cz - cos(a) * radius)
			spd = 19.0
		elif s < 2 * straight + PI * radius:
			p = Vector3(straight / 2 - (s - straight - PI * radius), 0, cz + radius)
		else:
			var a := (s - 2 * straight - PI * radius) / radius
			p = Vector3(-straight / 2 - sin(a) * radius, 0, cz + cos(a) * radius)
			spd = 19.0
		waypoints.append(p)
		speeds.append(spd)
	for i in waypoints.size():
		var a := waypoints[i]
		var b := waypoints[(i + 1) % waypoints.size()]
		var mid := (a + b) * 0.5
		var d := b - a
		var yaw := atan2(-d.z, d.x)
		for side: float in [-6.5, 6.5]:
			var n := Vector3(-d.z, 0, d.x).normalized() * side
			_flat_quad(parent, mid + n + Vector3(0, 0.012, 0), Vector2(d.length(), 0.2), line, yaw)

	# Start grid lines.
	for i in 6:
		_flat_quad(parent, Vector3(-20 + i * 9, 0.012, -40), Vector2(0.3, 4.0), line)

	# Feature lane along +X starting at the spawn (z = -40).
	# Ramps: rotated slabs whose leading top edge sits exactly on the ground.
	_ramp(parent, world, 38.0, -40.0, 5.0, deg_to_rad(9.0), concrete)
	_ramp(parent, world, 120.0, -28.0, 3.5, deg_to_rad(14.0), concrete)
	# Speed bumps.
	for i in 5:
		_box(parent, world, Vector3(95 + i * 9, 0.0, -40), Vector3(0.45, 0.09, 3.0), Vector3.ZERO, red)
	# Pothole / rough strip: small blocks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 40:
		var pos := Vector3(150 + rng.randf() * 40, 0.0, -43 + rng.randf() * 6)
		_box(parent, world, pos, Vector3(0.35 + rng.randf() * 0.3, 0.05 + rng.randf() * 0.06, 0.3 + rng.randf() * 0.3),
			Vector3(0, rng.randf() * PI, 0), asphalt)
	# Crash wall at the end of the lane.
	_box(parent, world, Vector3(225, 1.5, -40), Vector3(1.0, 1.5, 12.0), Vector3.ZERO, concrete, 0.8)
	for i in 5:
		_flat_quad(parent, Vector3(223.9, 0.6 + i * 0.5, -40), Vector2(0.01, 0.01), red)
	# Jersey barriers around the lane.
	for i in 18:
		_box(parent, world, Vector3(10 + i * 12, 0.4, -47), Vector3(5.8, 0.4, 0.3), Vector3.ZERO, concrete, 0.7)
	# Pole / tree for side impacts.
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.18
	pc.bottom_radius = 0.18
	pc.height = 5.0
	pole.mesh = pc
	pole.material_override = _mat(Color(0.5, 0.5, 0.52), 0.4, 0.8)
	pole.position = Vector3(-60, 2.5, -20)
	parent.add_child(pole)
	world.add_box(Vector3(-60, 2.5, -20), Vector3(0.16, 2.5, 0.16), Vector3.ZERO, 0.6)

	# Slalom cones (visual).
	for i in 10:
		_cone(parent, Vector3(-40 - i * 14, 0, -40))
	# A steep hill: heightfield bump on the pad's far side.
	var nx := 41
	var nz := 41
	var hcell := 2.0
	var ox := -200.0
	var oz := -150.0
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var dx := (ix - 20.0) / 20.0
			var dz := (iz - 20.0) / 20.0
			var r2 := dx * dx + dz * dz
			heights[ix * nz + iz] = maxf(0.0, 7.0 * (1.0 - r2)) if r2 < 1.0 else 0.0
	world.add_heightfield(ox, oz, hcell, nx, nz, heights, 1.0)
	parent.add_child(_terrain_mesh(ox, oz, hcell, nx, nz, heights, grass))

	var spawns: Array[Transform3D] = [
		car_xform(Vector3(0, 0, -40), Vector3(1, 0, 0)),
		car_xform(Vector3(-15, 0, -32), Vector3(1, 0, 0)),
		car_xform(Vector3(-30, 0, -32), Vector3(1, 0, 0)),
	]
	return {"spawns": spawns, "waypoints": waypoints, "speeds": speeds,
		"ai_spawns": [car_xform(waypoints[0], waypoints[1] - waypoints[0]), car_xform(waypoints[36], waypoints[37] - waypoints[36])]}


# =========================================================================== hill roads
static func build_hill_roads(world: SBWorld, parent: Node3D) -> Dictionary:
	var nx := 257
	var nz := 257
	var cell := 2.0
	var ox := -256.0
	var oz := -256.0
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var x := ox + ix * cell
			var z := oz + iz * cell
			var edge := clampf((Vector2(x, z).length() - 200.0) / 50.0, 0.0, 1.0)
			heights[ix * nz + iz] = (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 26.0 + edge * 25.0

	# Closed road loop.
	var road := PackedVector3Array()
	var n_road := 360
	for i in n_road:
		var a := TAU * i / n_road
		var r := 150.0 + 32.0 * sin(3.0 * a) + 14.0 * cos(5.0 * a + 0.7)
		road.append(Vector3(cos(a) * r, 0, sin(a) * r))
	# Road elevation = terrain sampled along the loop, heavily smoothed for drivable grades.
	var elev := PackedFloat32Array()
	elev.resize(n_road)
	for i in n_road:
		elev[i] = _sample(heights, nx, nz, ox, oz, cell, road[i].x, road[i].z)
	for _iter in 30:
		var e2 := elev.duplicate()
		for i in n_road:
			e2[i] = (elev[(i - 2 + n_road) % n_road] + elev[(i - 1 + n_road) % n_road] + elev[i] * 2.0 + elev[(i + 1) % n_road] + elev[(i + 2) % n_road]) / 6.0
		elev = e2
	for i in n_road:
		road[i].y = elev[i]
	# Carve the road into the terrain.
	var half_w := 4.5
	var blend := 12.0
	for ix in nx:
		for iz in nz:
			var p := Vector2(ox + ix * cell, oz + iz * cell)
			var best := 1e9
			var by := 0.0
			for i in range(0, n_road, 2):
				var q := Vector2(road[i].x, road[i].z)
				var d := p.distance_squared_to(q)
				if d < best:
					best = d
					by = road[i].y
			var dist := sqrt(best)
			if dist < half_w + blend:
				var t := clampf((dist - half_w) / blend, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				heights[ix * nz + iz] = lerpf(by - 0.05, heights[ix * nz + iz], t)
	world.add_heightfield(ox, oz, cell, nx, nz, heights, 1.0)
	var grass := _noise_material(Color(0.25, 0.38, 0.15), 0.3, 0.05)
	parent.add_child(_terrain_mesh(ox, oz, cell, nx, nz, heights, grass))
	parent.add_child(_road_mesh(road, half_w))

	# Trees (visual) away from the road.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var tree := CylinderMesh.new()
	tree.top_radius = 0.0
	tree.bottom_radius = 1.6
	tree.height = 7.0
	mm.mesh = tree
	var xforms: Array[Transform3D] = []
	for i in 900:
		var p := Vector2(rng.randf_range(-240, 240), rng.randf_range(-240, 240))
		var near := false
		for j in range(0, n_road, 6):
			if p.distance_to(Vector2(road[j].x, road[j].z)) < 14.0:
				near = true
				break
		if near:
			continue
		var y := _sample(heights, nx, nz, ox, oz, cell, p.x, p.y)
		var s := rng.randf_range(0.7, 1.4)
		xforms.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, y + 3.5 * s, p.y)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(0.1, 0.24, 0.1), 0.9)
	parent.add_child(mmi)

	var speeds := PackedFloat32Array()
	speeds.resize(n_road)
	for i in n_road:
		var a := road[(i - 4 + n_road) % n_road]
		var b := road[i]
		var c := road[(i + 4) % n_road]
		var ang := (b - a).normalized().angle_to((c - b).normalized())
		speeds[i] = clampf(26.0 - ang * 60.0, 11.0, 26.0)
	var s0 := road[0]
	var s1 := road[1]
	return {"spawns": [car_xform(s0, s1 - s0), car_xform(road[n_road - 6], road[n_road - 5] - road[n_road - 6])],
		"waypoints": road, "speeds": speeds,
		"ai_spawns": [car_xform(road[90], road[91] - road[90]), car_xform(road[200], road[201] - road[200])]}


static func _sample(h: PackedFloat32Array, nx: int, nz: int, ox: float, oz: float, cell: float, x: float, z: float) -> float:
	var fx := clampf((x - ox) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - oz) / cell, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := h[ix * nz + iz]
	var h10 := h[(ix + 1) * nz + iz]
	var h01 := h[ix * nz + iz + 1]
	var h11 := h[(ix + 1) * nz + iz + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func _terrain_mesh(ox: float, oz: float, cell: float, nx: int, nz: int, h: PackedFloat32Array, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in nx - 1:
		for iz in nz - 1:
			var p00 := Vector3(ox + ix * cell, h[ix * nz + iz], oz + iz * cell)
			var p10 := Vector3(ox + (ix + 1) * cell, h[(ix + 1) * nz + iz], oz + iz * cell)
			var p01 := Vector3(ox + ix * cell, h[ix * nz + iz + 1], oz + (iz + 1) * cell)
			var p11 := Vector3(ox + (ix + 1) * cell, h[(ix + 1) * nz + iz + 1], oz + (iz + 1) * cell)
			for p: Vector3 in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(p.x, p.z) * 0.1)
				st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _road_mesh(road: PackedVector3Array, half_w: float) -> MeshInstance3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.17, 0.17, 0.18))
	for y in 64:
		for x in 64:
			var c := Color(0.17, 0.17, 0.18).lerp(Color(0.21, 0.21, 0.22), randf() * 0.6)
			if x < 3 or x > 60:
				c = Color(0.9, 0.9, 0.86)
			elif x >= 31 and x <= 32 and y < 32:
				c = Color(0.9, 0.85, 0.5)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := road.size()
	var v := 0.0
	for i in n:
		var a := road[i]
		var b := road[(i + 1) % n]
		var da := (road[(i + 1) % n] - road[(i - 1 + n) % n]).normalized()
		var db := (road[(i + 2) % n] - road[i]).normalized()
		var na := Vector3(-da.z, 0, da.x).normalized() * half_w
		var nb := Vector3(-db.z, 0, db.x).normalized() * half_w
		var len := a.distance_to(b)
		var v2 := v + len / 12.0
		var lift := Vector3(0, 0.04, 0)
		var q := [[a - na + lift, Vector2(0, v)], [b + nb + lift, Vector2(1, v2)], [a + na + lift, Vector2(1, v)],
			[a - na + lift, Vector2(0, v)], [b - nb + lift, Vector2(0, v2)], [b + nb + lift, Vector2(1, v2)]]
		for e in q:
			st.set_uv(e[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(e[0])
		v = v2
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
