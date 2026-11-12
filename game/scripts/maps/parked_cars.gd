extends RefCounted
## Parked cars as static scenery: each glTF vehicle model is merged into one mesh (one surface
## per material) and drawn with a MultiMesh, the paint taking a per-instance colour. A box
## collider per car makes them solid. Cheap enough for whole streets of them.

const C := preload("res://scripts/maps/common.gd")
const MODELS := ["res://models/rubble/sedan.glb", "res://models/rubble/wagon.glb", "res://models/rubble/suv_4x4.glb",
	"res://models/rubble/mach1_1969.glb", "res://models/rubble/police_sedan.glb"]
const SKIP := ["seat_H_point", "wheel_center_", "light_bar", "antenna"]
const PAINTS := [Color(0.85, 0.85, 0.86), Color(0.06, 0.06, 0.07), Color(0.42, 0.44, 0.47), Color(0.62, 0.63, 0.65),
	Color(0.10, 0.18, 0.38), Color(0.45, 0.04, 0.04), Color(0.18, 0.26, 0.20), Color(0.55, 0.50, 0.42),
	Color(0.80, 0.78, 0.70), Color(0.25, 0.30, 0.36)]

static var _cache := {}


## Baked low-poly scenery mesh of a model (tests/bake_parked_cars.gd) and its bounds.
static func _merged(path: String) -> Array:
	if _cache.has(path):
		return _cache[path]
	var baked := "res://models/rubble/parked/" + path.get_file().get_basename() + ".res"
	if ResourceLoader.exists(baked):
		var mesh: ArrayMesh = load(baked)
		_cache[path] = [mesh, mesh.get_aabb()]
		return _cache[path]
	push_warning("parked car %s not baked; run tests/bake_parked_cars.gd" % path)
	_cache[path] = []
	return []


## Full-detail merge of a model's parts (one surface per material), used by the bake tool.
static func _merged_full(path: String) -> Array:
	var scene: PackedScene = load(path)
	if scene == null:
		return []
	var root := scene.instantiate()
	var tools := {}
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		var skip := false
		for s: String in SKIP:
			if s in String(node.name): skip = true
		if skip: continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var mi := node as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(si)
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mat] = st
				(tools[mat] as SurfaceTool).append_from(mi.mesh, si, xf)
		for child in node.get_children():
			stack.append([child, xf])
	root.free()
	var mesh := ArrayMesh.new()
	for mat: Material in tools.keys():
		var st: SurfaceTool = tools[mat]
		st.commit(mesh)
		var m := mat
		if mat is StandardMaterial3D and "paint" in String((mat as StandardMaterial3D).resource_name).to_lower():
			var paint := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			paint.albedo_color = Color.WHITE
			paint.vertex_color_use_as_albedo = true   # MultiMesh instance colour
			m = paint
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	return [mesh, mesh.get_aabb()]


## Places parked cars at the given ground transforms (basis yaw: car faces local +z of xf).
## `paints` overrides the paint colours (e.g. rust for wrecks).
static func place(parent: Node3D, world: SBWorld, xforms: Array[Transform3D], seed := 5, paints: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var groups: Array = []
	for m in MODELS: groups.append([])
	for xf in xforms:
		groups[rng.randi() % MODELS.size()].append(xf)
	for k in MODELS.size():
		var list: Array = groups[k]
		if list.is_empty(): continue
		var merged := _merged(MODELS[k])
		if merged.is_empty(): continue
		var mesh: ArrayMesh = merged[0]
		var aabb: AABB = merged[1]
		var offset := Vector3(-(aabb.position.x + aabb.size.x * 0.5), -aabb.position.y, -(aabb.position.z + aabb.size.z * 0.5))
		var half := Vector3(aabb.size.x * 0.5, aabb.size.y * 0.42, aabb.size.z * 0.5)
		# Spatial chunks: a MultiMesh picks one LOD and one visibility test for all its instances.
		var chunks := {}
		for xf: Transform3D in list:
			var key := Vector2i(floori(xf.origin.x / 120.0), floori(xf.origin.z / 120.0))
			if not chunks.has(key): chunks[key] = []
			chunks[key].append(xf)
			world.add_box(xf.origin + Vector3.UP * half.y, half, Vector3(0, xf.basis.get_euler().y, 0), 0.6)
		for chunk: Array in chunks.values():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = chunk.size()
			for i in chunk.size():
				var xf: Transform3D = chunk[i]
				mm.set_instance_transform(i, xf * Transform3D(Basis.IDENTITY, offset))
				var palette: Array = paints if not paints.is_empty() else PAINTS
				mm.set_instance_color(i, palette[rng.randi() % palette.size()])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 180.0
			mmi.visibility_range_end_margin = 20.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
