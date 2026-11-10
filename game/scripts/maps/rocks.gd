extends RefCounted
## Shared procedural rocks: irregular, noise-displaced lumps cut by a few fracture planes with a
## flat buried base, and a world-space stratified rock material. Replaces the 7-segment spheres
## the maps used as boulders.

const ROCK_SHADER := preload("res://materials/surfaces/rock.gdshader")

static var _meshes := {}


## One of a few rock shapes (variant 0..3), radius ~0.5 at scale 1, base at y = -0.3.
static func mesh(variant: int) -> ArrayMesh:
	variant = posmod(variant, 4)
	if _meshes.has(variant):
		return _meshes[variant]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 18
	sphere.rings = 10
	sphere.radius = 0.5
	sphere.height = 1.0
	var src := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 101 + variant * 17
	noise.frequency = 1.3
	noise.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + variant * 31
	var planes: Array[Plane] = []
	for k in rng.randi_range(3, 5):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		planes.append(Plane(dir, rng.randf_range(0.30, 0.42)))
	for i in verts.size():
		var d := verts[i].normalized()
		var v := d * 0.5 * (0.80 + 0.40 * noise.get_noise_3dv(d * 1.4))
		for plane in planes:
			var over := plane.normal.dot(v) - plane.d
			if over > 0.0:
				v -= plane.normal * over * 0.92
		v.y = maxf(v.y, -0.30)
		verts[i] = v
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Weld the UV seam so smooth normals have no crease there, then recompute normals.
	var st := SurfaceTool.new()
	st.create_from(raw, 0)
	st.index()
	st.generate_normals()
	var out := st.commit()
	_meshes[variant] = out
	return out


## Stratified rock material. Colours default to red desert sandstone.
static func material(base := Color(0.62, 0.40, 0.29), band := Color(0.80, 0.58, 0.42), dark := Color(0.36, 0.22, 0.16),
		top := Color(0.86, 0.74, 0.58), band_spacing := 0.9) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("band_color", band)
	m.set_shader_parameter("dark_color", dark)
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("band_spacing", band_spacing)
	return m


## Grey granite / limestone for temperate maps: weak banding, more cracks, mossy-dusty tops.
static func grey_material() -> ShaderMaterial:
	var m := material(Color(0.47, 0.46, 0.43), Color(0.58, 0.57, 0.53), Color(0.27, 0.27, 0.26), Color(0.42, 0.47, 0.33), 1.6)
	m.set_shader_parameter("band_amount", 0.25)
	m.set_shader_parameter("crack_amount", 0.9)
	m.set_shader_parameter("top_amount", 0.35)
	return m
