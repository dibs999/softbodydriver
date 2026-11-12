extends SceneTree
## Import regressions: tangent frames, wheel fit and unchanged vehicle dynamics.
var failed := false
func check(condition: bool, label: String) -> void:
 print(label, ": ", condition)
 if not condition:
  failed = true
  push_error(label)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var game = root.get_node("Game")
 var source_model = load("res://models/carconcept/CarConcept.glb").instantiate()
 var source_material: BaseMaterial3D = source_model.find_child("InteriorSeatsColor2", true, false).get_active_material(0)
 var source_ao_on_uv2 := source_material.get_flag(BaseMaterial3D.FLAG_AO_ON_UV2)
 var worlds: Array[SBWorld] = []
 var cars: Array[SBVehicle] = []
 for imported in [false, true]:
  var world := SBWorld.new()
  world.paused = true
  root.add_child(world)
  world.add_ground_plane(1)
  var car := world.spawn_car("res://cars/concept_gt.car.json", Transform3D.IDENTITY)
  if car == null:
   world.queue_free()
   for previous in worlds:
    previous.queue_free()
   await process_frame
   push_error("Concept failed to spawn; rebuild native extension before testing")
   quit(1)
   return
  if imported:
   game.apply_visual_model(car, game.car_info("res://cars/concept_gt.car.json"))
  worlds.append(world)
  cars.append(car)
 check(cars[1].has_node("BodyHood"), "Detailed Concept body is attached")
 check(source_material.get_flag(BaseMaterial3D.FLAG_AO_ON_UV2) == source_ao_on_uv2, "AO channel override preserves shared source material")
 source_model.free()
 var ao_materials := 0
 var tangent_frames := {}
 var normal_frames := {}
 for child in cars[1].get_children():
  if child is MeshInstance3D and child.mesh:
   var material = child.mesh.surface_get_material(0)
   if material is BaseMaterial3D and material.get_feature(BaseMaterial3D.FEATURE_AMBIENT_OCCLUSION):
    ao_materials += 1
    if not material.get_flag(BaseMaterial3D.FLAG_AO_ON_UV2):
     check(false, "Concept AO atlas must use its authored second UV set")
   var arrays: Array = child.mesh.surface_get_arrays(0)
   normal_frames[child] = arrays[Mesh.ARRAY_NORMAL].duplicate()
   if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
    tangent_frames[child] = arrays[Mesh.ARRAY_TANGENT].duplicate()
 check(ao_materials > 10, "Concept AO atlas materials use the authored second UV set")
 check(tangent_frames.size() > 10, "Imported tangent-bearing surfaces are exercised")
 worlds[1].sync_visuals()
 var max_normal_error := 0.0
 for child in normal_frames:
  var before: PackedVector3Array = normal_frames[child]
  var after: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
  for i in before.size():
   max_normal_error = maxf(max_normal_error, before[i].distance_to(after[i]))
 check(max_normal_error < 0.003, "Undeformed render upload preserves imported normals")
 var max_tangent_error := 0.0
 for child in tangent_frames:
  var before: PackedFloat32Array = tangent_frames[child]
  var after: PackedFloat32Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
  for i in range(0, before.size(), 4):
   var a := Vector3(before[i],before[i+1],before[i+2])
   var b := Vector3(after[i],after[i+1],after[i+2])
   max_tangent_error = maxf(max_tangent_error, a.distance_to(b))
 check(max_tangent_error < 0.003, "Undeformed render upload preserves imported tangent frames")
 await process_frame # release replaced procedural wheel meshes after the upload checks
 var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://cars/concept_gt.car.json"))
 var diameter := 2.0 * float(spec["tires"]["radius"])
 for name in ["FL", "FR", "RL", "RR"]:
  var wheel := cars[1].get_node(name)
  var bounds := AABB()
  var first := true
  for part in wheel.get_children():
   if part is MeshInstance3D and part.mesh.surface_get_material(0).resource_name.begins_with("Tire"):
    bounds = part.mesh.get_aabb() if first else bounds.merge(part.mesh.get_aabb())
    first = false
  var axle_width := 0.27 if name.begins_with("F") else 0.35  # staggered Concept GT tyres
  check(not first and absf(bounds.size.z - axle_width) < 0.002 and absf(bounds.size.x - diameter) < 0.01 and absf(bounds.size.y - diameter) < 0.01,
    "Imported wheel %s fits physics radius, width and axle" % name)
 var max_delta := 0.0
 for step in 100:
  for i in 2:
   cars[i].set_input(1, 0, 0.0 if step < 60 else 0.015, 0)
   worlds[i].step_blocking(0.1)
   worlds[i].sync_visuals()
  max_delta = maxf(max_delta, cars[0].get_position_ws().distance_to(cars[1].get_position_ws()))
 check(max_delta < 0.000001, "Imported and procedural car retain identical driving dynamics")
 check(cars[1].get_telemetry()["speed_kmh"] > 100, "Driving comparison reaches highway speed")
 for world in worlds:
  world.queue_free()
 await process_frame
 quit(1 if failed else 0)
