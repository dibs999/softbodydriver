extends RefCounted
## A continuous rural heightfield: every driving route is an unpaved track.
const C := preload("res://scripts/maps/common.gd")
const V := preload("res://scripts/maps/vegetation.gd")
const TRACK_SHADER := preload("res://materials/surfaces/field_track.gdshader")
const COUNT := 513
const CELL := 3.0
const ORIGIN := -768.0

static func build(world: SBWorld, parent: Node3D) -> Dictionary:
	var rolling := FastNoiseLite.new()
	rolling.seed = 8041
	rolling.frequency = 0.0045
	rolling.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = 508
	detail.frequency = 0.025
	var heights := PackedFloat32Array()
	heights.resize(COUNT * COUNT)
	for ix in COUNT:
		for iz in COUNT:
			var x := ORIGIN + ix * CELL
			var z := ORIGIN + iz * CELL
			var hill := 48.0 * exp(-Vector2(x - 300, z + 240).length_squared() / 34000.0)
			var ridge := 25.0 * exp(-Vector2(x + 220, (z - 250) * 1.35).length_squared() / 47000.0)
			var edge := smoothstep(660, 760, maxf(absf(x), absf(z)))
			heights[ix * COUNT + iz] = 14 + rolling.get_noise_2d(x, z) * 13 + detail.get_noise_2d(x, z) * 0.65 + hill + ridge + edge * 65

	var loop := PackedVector3Array()
	for i in 420:
		var a := PI + TAU * i / 420.0
		var r := 525.0 + 43.0 * sin(a * 3 + 0.5) + 26.0 * cos(a * 5)
		loop.append(Vector3(cos(a) * r, 0, sin(a) * r * 0.90))
	_project(loop, heights, true, 16)
	var forward := (loop[1] - loop[0]).normalized()
	var right := Vector3(-forward.z, 0, forward.x).normalized()
	var farm := loop[0] + right * 32 + forward * 9
	farm.y = C.sample(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, farm.x, farm.z)
	# A usable dirt farmyard, smoothly merged into the surrounding pasture.
	for ix in range(maxi(0, int((farm.x - 36 - ORIGIN) / CELL)), mini(COUNT, int((farm.x + 36 - ORIGIN) / CELL) + 1)):
		for iz in range(maxi(0, int((farm.z - 36 - ORIGIN) / CELL)), mini(COUNT, int((farm.z + 36 - ORIGIN) / CELL) + 1)):
			var d := Vector2(ORIGIN + ix * CELL - farm.x, ORIGIN + iz * CELL - farm.z).length()
			heights[ix * COUNT + iz] = lerpf(farm.y, heights[ix * COUNT + iz], smoothstep(18, 34, d))
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, loop, 3.8, 9.0, 0.0)
	var forest := _curve(PackedVector3Array([loop[24], Vector3(-330,0,-110), Vector3(-240,0,25), Vector3(-90,0,100), Vector3(120,0,210), Vector3(210,0,320), loop[280]]))
	_project(forest, heights, false, 9)
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, forest, 2.9, 6.0, 0.0, false)
	var ridge_path := _curve(PackedVector3Array([loop[115], Vector3(180,0,-350), Vector3(325,0,-310), Vector3(365,0,-215), Vector3(275,0,-145), Vector3(430,0,-100), loop[200]]))
	_project(ridge_path, heights, false, 6)
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, ridge_path, 2.8, 5.5, 0.0, false)
	var access := _curve(PackedVector3Array([loop[0], farm - right * 12, farm]))
	_project(access, heights, false, 3)
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, access, 4.2, 5.0, 0.0, false)
	var rock_path := _curve(PackedVector3Array([forest[forest.size()/2], Vector3(-5,0,22), Vector3(85,0,35), forest[forest.size()*3/4]]))
	_project(rock_path, heights, false, 4)
	# Low alternating humps reward careful wheel placement on the optional trail.
	for i in range(5, rock_path.size() - 5):
		rock_path[i].y += 0.38 * sin(i * 0.85) * sin(PI * i / (rock_path.size() - 1))
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, rock_path, 2.4, 4.5, 0.0, false)
	# Side trails are carved after the main loop and used to leave kinks where they cross it (a
	# sharp crest near the ridge junction bottomed out even the 4x4 and cracked its sump).
	# Re-carving the loop last keeps its smoothed profile; the side trails blend into it.
	C.carve_path(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, loop, 3.8, 9.0, 0.0)
	var paths: Array[PackedVector3Array] = [C.closed_route(loop), forest, ridge_path, access, rock_path]
	var ground := func(x: float, z: float) -> float:
		return C.sample(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, x, z)
	# Waypoints, visuals and collision share the final terrain, including junctions.
	for path in paths:
		for i in path.size(): path[i].y = ground.call(path[i].x, path[i].z)
	for i in loop.size(): loop[i].y = ground.call(loop[i].x, loop[i].z)
	world.add_heightfield(ORIGIN, ORIGIN, CELL, COUNT, COUNT, heights, 0.94)
	var colors := PackedColorArray()
	colors.resize(heights.size())
	for ix in COUNT:
		for iz in COUNT:
			var x := ORIGIN + ix * CELL
			var z := ORIGIN + iz * CELL
			var field := _field(Vector2(x,z))
			var base := Color(0.60,0.91,0.61) if field < 0 else (Color(0.99,0.86,0.49) if field == 0 else Color(0.75,0.71,0.46))
			var row := sin(x * 1.2 + z * 0.12) * 0.04 if field >= 0 else 0.0
			var slope := absf(heights[mini(ix + 1, COUNT-1)*COUNT+iz] - heights[maxi(0,ix-1)*COUNT+iz]) / (2*CELL)
			colors[ix*COUNT+iz] = base.darkened(clampf(slope * 0.15 + row, 0, 0.2))
	C.terrain_tiles(parent, ORIGIN, ORIGIN, CELL, COUNT, COUNT, heights, C.terrain_material("grass", 3.8), colors)
	var widths := [3.2, 2.5, 2.5, 4.0, 2.15]
	for i in paths.size():
		parent.add_child(C.road_mesh(paths[i], widths[i], _track_material(widths[i] * 2, 0.75 if i != 4 else 0.25), false, 0.055, 9.0, ground))
	# A ground-following apron instead of a floating horizontal yard slab.
	var yard := PackedVector3Array([farm - forward * 15, farm + forward * 15])
	parent.add_child(C.road_mesh(yard, 15, _track_material(30, 0), false, 0.06, 9.0, ground))
	for i in paths.size():
		V.roadside_grass(parent, paths[i], false, widths[i] + 0.3, widths[i] + 12.0, 4.5, 77 + i, ground,
			func(p: Vector3) -> bool: return _near_paths(Vector2(p.x, p.z), paths, 3.2) or p.distance_to(yard[0]) < 30.0)
	_vegetation(parent, world, paths, ground, farm)
	_farm(parent, world, farm, ground)
	var timber := forest[forest.size()/3] + Vector3(-14,0,9)
	timber.y = ground.call(timber.x,timber.z)
	_logs(parent, world, timber)
	# Lookout beside the ridge trail. A fixed offset from the trail's midpoint put the fence posts
	# across the main loop, where every car drove into them; keep it clear of all trails.
	var mid := ridge_path.size() / 2
	var ridge_dir := (ridge_path[mid + 1] - ridge_path[mid - 1]).normalized()
	var ridge_side := Vector3(-ridge_dir.z, 0, ridge_dir.x)
	var summit := ridge_path[mid] + ridge_side * 14.0
	for candidate: Vector3 in [ridge_path[mid] + ridge_side * 14.0, ridge_path[mid] - ridge_side * 14.0,
			ridge_path[mid] + ridge_side * 22.0, ridge_path[mid] - ridge_side * 22.0]:
		if not _near_paths(Vector2(candidate.x, candidate.z), paths, 11.0):
			summit = candidate
			break
	summit.y = ground.call(summit.x,summit.z)
	var wood := C.mat(Color("675039"))
	for i in 4:
		var p := summit + Vector3(-6 + i * 4, 0, -2)
		p.y = ground.call(p.x,p.z)
		C.box(parent, world, p + Vector3.UP * 0.7, Vector3(0.09,0.7,0.09), Vector3.ZERO, wood)
		if i < 3: C.box(parent, world, p + Vector3(2,1.0,0), Vector3(2,0.07,0.08), Vector3.ZERO, wood, 0.8, false)
	_sign(parent, world, summit + Vector3(0,0,4), "HÖHENBLICK", ground)
	_sign(parent, world, loop[4] + right * 5.5, "FELDWEGRUNDE  /  WALD", ground)
	_sign(parent, world, ridge_path[5] + Vector3(5,0,0), "HÖHENWEG  /  LANGSAM", ground)
	_sign(parent, world, rock_path[5] + Vector3(0,0,4), "GERÖLLPFAD  /  4x4", ground)
	var stones := _rock_garden(parent, world, rock_path, ground)
	var length_m := 0.0
	for i in loop.size(): length_m += loop[i].distance_to(loop[(i+1)%loop.size()])
	return {"spawns": [C.car_xform(loop[0], loop[1]-loop[0]), C.car_xform(loop[-3], loop[-2]-loop[-3])],
		"waypoints": loop, "speeds": C.speeds_from_curvature(loop, 12.0, 6.0, 35),
		"activity_route": loop, "map_paths": paths, "ai_spawns": [],
		"map_path_color": Color("b6a27b"),
		"surface_regions": [{"rect": Rect2(farm.x-17,farm.z-17,34,34),"surface":"gravel"}],
		"map_places": [{"name":"Hof & Start", "position":farm}, {"name":"Holzlager", "position":timber},
			{"name":"Höhenblick", "position":summit}, {"name":"Geröllpfad", "position":stones},
			{"name":"Weideland", "position":loop[315]}],
		"offroad_length_m": length_m,
		"environment": {"sky_top":Color(0.27,0.47,0.73),"horizon":Color(0.70,0.79,0.84),
			"fog":Color(0.66,0.74,0.78),"fog_density":0.00065,"sun":Vector3(-36,-32,0),
			"sun_energy":1.25,"sun_color":Color(1.0,0.97,0.90)}}

static func _track_material(width: float, greenery: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TRACK_SHADER
	material.set_shader_parameter("soil", load(C.SURFACE_PATH + "gravel.jpg"))
	material.set_shader_parameter("soil_normal", load(C.SURFACE_PATH + "gravel_normal.jpg"))
	material.set_shader_parameter("grass", load(C.SURFACE_PATH + "grass.jpg"))
	material.set_shader_parameter("width", width)
	material.set_shader_parameter("greenery", greenery)
	return material

static func _project(path: PackedVector3Array, heights: PackedFloat32Array, closed: bool, passes: int) -> void:
	for i in path.size(): path[i].y = C.sample(heights, COUNT, COUNT, ORIGIN, ORIGIN, CELL, path[i].x, path[i].z)
	for _pass in passes:
		var next := path.duplicate()
		for i in range(0 if closed else 1, path.size() if closed else path.size()-1):
			next[i].y = (path[(i-1+path.size())%path.size()].y + 2*path[i].y + path[(i+1)%path.size()].y) * 0.25
		for i in path.size(): path[i].y = next[i].y

static func _curve(controls: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in controls.size()-1:
		var samples := maxi(3, ceili(controls[i].distance_to(controls[i+1])/6.0))
		for j in samples:
			result.append(controls[i].cubic_interpolate(controls[i+1], controls[maxi(0,i-1)], controls[mini(controls.size()-1,i+2)], float(j)/samples))
	result.append(controls[-1])
	return result

static func _near_paths(p: Vector2, paths: Array[PackedVector3Array], distance: float) -> bool:
	for path in paths:
		for i in path.size()-1:
			var a := Vector2(path[i].x,path[i].z)
			if p.distance_squared_to(a) > (distance+16)*(distance+16): continue
			var b := Vector2(path[i+1].x,path[i+1].z)
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,a,b)) < distance*distance: return true
	return false

static func _field(p: Vector2) -> int:
	if Rect2(-425,150,230,180).has_point(p): return 0
	if Rect2(140,300,220,130).has_point(p): return 1
	if Rect2(-400,-390,230,170).has_point(p): return 1
	return -1

static func _vegetation(parent: Node3D, world: SBWorld, paths: Array[PackedVector3Array], ground: Callable, farm: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19182
	var pines: Array[Vector3] = []
	var leafy: Array[Vector3] = []
	var bushes: Array[Vector3] = []
	var rocks: Array[Transform3D] = []
	for i in 2400:
		var p := Vector2(rng.randf_range(-690,690),rng.randf_range(-690,690))
		if p.distance_to(Vector2(farm.x,farm.z)) < 43 or _near_paths(p,paths,6.0): continue
		var y: float = ground.call(p.x,p.y)
		var forest := _field(p) < 0 and (p.y < 160 or p.x < -470 or p.x > 400)
		if forest and i % 3 != 0 and V.keep(Vector3(p.x,y,p.y)):
			if i % 4 != 0:
				pines.append(Vector3(p.x,y,p.y))
			else:
				leafy.append(Vector3(p.x,y,p.y))
			world.add_box(Vector3(p.x,y+1.8,p.y),Vector3(0.24,1.8,0.24),Vector3.ZERO,0.75)
		elif i % 2 == 0 and _field(p) < 0:
			bushes.append(Vector3(p.x,y,p.y))
		elif i % 7 == 0 and _field(p) < 0:
			var scale := rng.randf_range(0.6,2.4)
			rocks.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled_local(Vector3(scale,scale*0.7,scale)),Vector3(p.x,y+scale*0.3,p.y)))
	# A continuous forest corridor contrasts with the open fields. Keep trunks
	# outside all junctions, including the technical trail and logging clearing.
	var woodland := paths[1]
	for i in range(8,woodland.size()-8,2):
		var tangent := (woodland[i+1]-woodland[i-1]).normalized()
		var side := Vector3(-tangent.z,0,tangent.x).normalized()
		for sign: float in [-1,1]:
			for depth in 3:
				var p := woodland[i]+side*sign*(8.5+depth*9+rng.randf_range(-1.0,2.5))+tangent*rng.randf_range(-3,3)
				if _field(Vector2(p.x,p.z)) >= 0 or _near_paths(Vector2(p.x,p.z),paths,6.5): continue
				if p.distance_to(woodland[woodland.size()/3]) < 22: continue
				p.y = ground.call(p.x,p.z)
				if not V.keep(p): continue
				pines.append(p)
				world.add_box(p+Vector3.UP*1.8,Vector3(0.23,1.8,0.23),Vector3.ZERO,0.75)
	V.plant(parent,"conifer",pines,19183,0.55,0.95)
	V.plant(parent,"broadleaf",leafy,19184,0.75,1.2)
	V.plant(parent,"bush",bushes,19185,0.7,1.5,false)
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 9
	sphere.rings = 4
	C.scatter_multimesh(parent,sphere,C.surface_material("gravel",1.8,Color(0.65,0.65,0.60)),rocks,false)
	# Hay bales make the cultivated meadows readable without thousands of grass nodes.
	var bale := CylinderMesh.new()
	bale.top_radius = 0.85
	bale.bottom_radius = 0.85
	bale.height = 1.35
	bale.radial_segments = 12
	bale.rings = 0
	var hay: Array[Transform3D] = []
	for i in 70:
		var p := Vector2(rng.randf_range(-425,-195),rng.randf_range(150,330))
		if _near_paths(p,paths,7): continue
		var y: float = ground.call(p.x,p.y)
		hay.append(Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(p.x,y+0.85,p.y)))
		world.add_box(Vector3(p.x,y+0.65,p.y),Vector3(0.65,0.65,0.65),Vector3.ZERO,0.6)
	C.scatter_multimesh(parent,bale,C.surface_material("grass",0.8,Color(1.0,0.82,0.39)),hay)
	var fence := C.mat(Color("7c694d"))
	var bars: Array[Transform3D] = []
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	for z: float in [145,335]:
		for x in range(-430,-190,6):
			if _near_paths(Vector2(x,z),paths,10): continue
			var y: float = ground.call(x,z)
			bars.append(Transform3D(Basis.from_scale(Vector3(0.14,1.15,0.14)),Vector3(x,y+0.575,z)))
			if not _near_paths(Vector2(x+3,z),paths,10):
				for level: float in [0.5,0.95]:
					bars.append(Transform3D(Basis.from_scale(Vector3(5.9,0.09,0.1)),Vector3(x+3,y+level,z)))
				world.add_box(Vector3(x+3,y+0.6,z),Vector3(2.95,0.6,0.08),Vector3.ZERO,0.65)
	C.scatter_multimesh(parent,mesh,fence,bars,false)

static func _farm(parent: Node3D, world: SBWorld, p: Vector3, ground: Callable) -> void:
	var timber := C.noise_mat(Color("6c4931"),0.13,1.5)
	var roof := C.mat(Color("3e4543"),0.9)
	var h := p + Vector3(7,0,0)
	for z: float in [-10,10]: C.box(parent,world,h+Vector3(0,3.1,z),Vector3(8,3.1,0.18),Vector3.ZERO,timber)
	C.box(parent,world,h+Vector3(8,3.1,0),Vector3(0.18,3.1,10),Vector3.ZERO,timber)
	for side: float in [-1,1]: C.box(parent,world,h+Vector3(0,7.1,side*5),Vector3(8.7,0.15,5.4),Vector3(side*0.19,0,0),roof,0.8,false)
	for z: float in [-10,0,10]: C.box(parent,world,h+Vector3(-8,3.1,z),Vector3(0.18,3.1,0.18),Vector3.ZERO,timber)
	var battens: Array[Transform3D] = []
	for x in range(-7,8):
		for side: float in [-1,1]:
			battens.append(Transform3D(Basis.from_scale(Vector3(0.07,6.1,0.08)),h+Vector3(x,3.1,side*10.20)))
	for z in range(-9,10):
		battens.append(Transform3D(Basis.from_scale(Vector3(0.08,6.1,0.07)),h+Vector3(8.20,3.1,z)))
	var strip := BoxMesh.new()
	strip.size = Vector3.ONE
	C.scatter_multimesh(parent,strip,C.mat(Color("503e2c")),battens,false)
	for z: float in [-5,5]:
		C.box(parent,world,h+Vector3(2,0.55,z),Vector3(3.3,0.55,1.1),Vector3.ZERO,timber)
	_sign(parent,world,p+Vector3(-14,0,-16),"WALD & WEIDE  /  START",ground)
	_logs(parent,world,p+Vector3(9,0,18))

static func _logs(parent: Node3D, world: SBWorld, p: Vector3) -> void:
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.32
	log_mesh.bottom_radius = 0.36
	log_mesh.height = 7
	log_mesh.radial_segments = 8
	log_mesh.rings = 0
	var pile: Array[Transform3D] = []
	for row in 3:
		for j in 5-row:
			var center := p+Vector3(0,0.35+row*0.57,(j+row*0.5)*0.72-1.4)
			pile.append(Transform3D(Basis(Vector3.FORWARD,PI/2),center))
	C.scatter_multimesh(parent,log_mesh,C.mat(Color("715334")),pile)
	world.add_box(p+Vector3(0,0.8,0),Vector3(3.5,0.8,1.6),Vector3.ZERO,0.7)

static func _sign(parent: Node3D, world: SBWorld, p: Vector3, caption: String, ground: Callable) -> void:
	p.y = ground.call(p.x,p.z)
	var wood := C.mat(Color("66513a"))
	C.box(parent,world,p+Vector3.UP*1.0,Vector3(0.10,1.0,0.10),Vector3.ZERO,wood)
	C.box(parent,world,p+Vector3.UP*1.9,Vector3(2,0.33,0.10),Vector3.ZERO,wood,0.8,false)
	C.label3d(parent,caption,p+Vector3(0,1.9,0.11),0,0.32)

static func _rock_garden(parent: Node3D, world: SBWorld, path: PackedVector3Array, ground: Callable) -> Vector3:
	var rock := SphereMesh.new()
	rock.radius = 1
	rock.height = 2
	rock.radial_segments = 7
	rock.rings = 3
	var transforms: Array[Transform3D] = []
	for i in range(14,path.size()-10,4):
		var p := path[i]+Vector3(0.75 if i%8==0 else -0.75,0,0)
		p.y = ground.call(p.x,p.z)+0.06
		transforms.append(Transform3D(Basis.from_scale(Vector3(0.48,0.18,0.55)),p))
		world.add_box(p,Vector3(0.31,0.12,0.36),Vector3.ZERO,0.9)
	C.scatter_multimesh(parent,rock,C.surface_material("gravel",1.2,Color(0.68,0.68,0.62)),transforms,false)
	return path[path.size()/2]
