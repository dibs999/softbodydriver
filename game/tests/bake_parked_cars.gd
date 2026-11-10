extends SceneTree
## Bakes low-poly scenery versions of the glTF cars for parked cars (run once, results committed):
## godot --headless -s res://tests/bake_parked_cars.gd
## Each model (~290k triangles) is merged into one mesh per material, simplified to roughly
## TARGET triangles with Godot's mesh simplifier, given its own distance LODs, and saved to
## res://models/rubble/parked/<name>.res.

const TARGET := 9000
const OUT_DIR := "res://models/rubble/parked/"

func _initialize() -> void:
	var P := preload("res://scripts/maps/parked_cars.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for path: String in P.MODELS:
		var merged: Array = P._merged_full(path)
		var mesh: ArrayMesh = merged[0]
		var full := 0
		for s in mesh.get_surface_count():
			full += mesh.surface_get_array_index_len(s) / 3
		# Simplify: generate LODs, then keep the first LOD level at or below the target share.
		var im := ImporterMesh.new()
		for s in mesh.get_surface_count():
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s))
		im.generate_lods(60.0, 60.0, [])
		var reduced := ImporterMesh.new()
		var total := 0
		for s in im.get_surface_count():
			var arrays := im.get_surface_arrays(s)
			var base: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var share := float(base.size()) / float(full * 3)
			var want := int(TARGET * share * 3)
			var best := base
			for l in im.get_surface_lod_count(s):
				var idx := im.get_surface_lod_indices(s, l)
				best = idx
				if idx.size() <= want:
					break
			arrays[Mesh.ARRAY_INDEX] = best
			# Drop the vertices the simplified index list no longer uses.
			var st := SurfaceTool.new()
			st.create_from_arrays(arrays)
			st.deindex()
			st.index()
			var compact := st.commit_to_arrays()
			total += (compact[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			reduced.add_surface(Mesh.PRIMITIVE_TRIANGLES, compact, [], {}, im.get_surface_material(s))
		reduced.generate_lods(60.0, 60.0, [])
		var out := reduced.get_mesh()
		var file := OUT_DIR + path.get_file().get_basename() + ".res"
		var err := ResourceSaver.save(out, file, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d -> %d triangles, saved %s (%s)" % [path.get_file(), full, total, file, error_string(err)])
	quit()
