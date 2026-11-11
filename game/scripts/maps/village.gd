extends RefCounted
## Detached rural houses for the countryside maps: plastered walls with gable ends, a two-slope
## tiled roof with overhang, framed windows with sills (some with shutters), a front door with a
## step and a chimney. Houses are collected first and drawn as MultiMeshes per material.
## var v := Village.new(); v.house(...); ...; v.build(parent)

const C := preload("res://scripts/maps/common.gd")

const WALLS := [Color(0.88, 0.84, 0.74), Color(0.80, 0.76, 0.68), Color(0.86, 0.79, 0.64), Color(0.76, 0.80, 0.78), Color(0.84, 0.70, 0.58)]
const ROOFS := [Color(0.50, 0.20, 0.13), Color(0.36, 0.17, 0.12), Color(0.28, 0.27, 0.29)]
const SHUTTERS := [Color(0.20, 0.33, 0.22), Color(0.36, 0.24, 0.15), Color(0.62, 0.62, 0.60)]

var _walls: Array = []        # per wall colour: Array[Transform3D] (boxes)
var _gables: Array = []       # per wall colour: Array[Transform3D] (prisms)
var _roofs: Array = []        # per roof colour
var _shutters: Array = []     # per shutter colour
var _glass: Array[Transform3D] = []
var _glass_lit: Array[Transform3D] = []   # lit from inside at night
var _lit_rng := RandomNumberGenerator.new()
var _trim: Array[Transform3D] = []
var _doors: Array[Transform3D] = []
var _stone: Array[Transform3D] = []
var _chimneys: Array[Transform3D] = []
var _gutters: Array[Transform3D] = []
var _barn_walls: Array[Transform3D] = []
var _barn_gables: Array[Transform3D] = []
var _barn_doors: Array[Transform3D] = []


func _init() -> void:
	for list in [_walls, _gables]:
		for i in WALLS.size():
			var a: Array[Transform3D] = []
			list.append(a)
	for i in ROOFS.size():
		var a: Array[Transform3D] = []
		_roofs.append(a)
	for i in SHUTTERS.size():
		var a: Array[Transform3D] = []
		_shutters.append(a)


## One house standing on `ground` (floor level), long axis along `yaw`. Returns its footprint
## radius for spacing checks.
func house(world: SBWorld, ground: Vector3, yaw: float, length: float, width: float, storeys: int, rng: RandomNumberGenerator,
		barn := false) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var h := storeys * 2.8 + 0.4
	var wall := rng.randi() % WALLS.size()
	var roof := rng.randi() % ROOFS.size()
	var shutter := rng.randi() % SHUTTERS.size() if rng.randf() < 0.55 else -1
	var at := func(local: Vector3) -> Vector3: return ground + basis * local
	# Plinth, walls (with a collider) and gable ends.
	_stone.append(Transform3D(basis.scaled_local(Vector3(length + 0.12, 0.5, width + 0.12)), at.call(Vector3(0, 0.25, 0))))
	(_barn_walls if barn else _walls[wall]).append(Transform3D(basis.scaled_local(Vector3(length, h, width)), at.call(Vector3(0, h * 0.5, 0))))
	if world:
		world.add_box(at.call(Vector3(0, h * 0.5, 0)), Vector3(length, h, width) * 0.5, Vector3(0, yaw, 0), 0.8)
	var pitch := deg_to_rad(rng.randf_range(36.0, 46.0))
	var rise := width * 0.5 * tan(pitch)
	var gable_basis := Basis(Vector3.UP, yaw + PI * 0.5)
	for end: float in [-1.0, 1.0]:
		(_barn_gables if barn else _gables[wall]).append(Transform3D(gable_basis.scaled_local(Vector3(width, rise, 0.24)), at.call(Vector3(end * (length * 0.5 - 0.12), h + rise * 0.5, 0))))
	# Roof: two slabs with eaves and verge overhang.
	var slope := width * 0.5 / cos(pitch) + 0.45
	for sgn: float in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, sgn * pitch)
		var centre := Vector3(0, h + rise * 0.5, sgn * width * 0.25) + tilt * Vector3(0, 0.12, sgn * 0.22)
		_roofs[roof].append(Transform3D((basis * tilt).scaled_local(Vector3(length + 0.7, 0.16, slope)), at.call(centre)))
	# Zinc gutters along both eaves, downpipes at the ends of the front.
	var eave := width * 0.5 / cos(pitch) + 0.45
	for sgn: float in [-1.0, 1.0]:
		var tilt := Basis(Vector3.RIGHT, sgn * pitch)
		var centre := Vector3(0, h + rise * 0.5, sgn * width * 0.25) + tilt * Vector3(0, 0.12, sgn * 0.22)
		var edge: Vector3 = centre + tilt * Vector3(0, -0.02, sgn * eave * 0.5)
		_gutters.append(Transform3D(basis.scaled_local(Vector3(length + 0.6, 0.12, 0.13)), at.call(edge + Vector3(0, -0.12, sgn * 0.02))))
		if not barn:
			for end: float in [-1.0, 1.0]:
				var top_y: float = edge.y - 0.12
				var x := end * (length * 0.5 - 0.25)
				var z := sgn * (width * 0.5 + 0.12)
				_gutters.append(Transform3D(basis.scaled_local(Vector3(0.09, top_y, 0.09)), at.call(Vector3(x, top_y * 0.5, z))))
				_gutters.append(Transform3D(basis.scaled_local(Vector3(0.09, 0.09, absf(edge.z - z) + 0.05)), at.call(Vector3(x, top_y, (edge.z + z) * 0.5))))
	if barn:
		# Big doors on both long sides, nothing else.
		for sgn: float in [-1.0, 1.0]:
			_barn_doors.append(Transform3D(basis.scaled_local(Vector3(3.6, 3.4, 0.10)), at.call(Vector3(0, 1.9, sgn * (width * 0.5 + 0.03)))))
		return maxf(length, width) * 0.6
	_chimneys.append(Transform3D(basis.scaled_local(Vector3(0.6, rise + 0.9, 0.6)), at.call(Vector3(length * rng.randf_range(-0.3, 0.3), h + rise * 0.6, width * 0.18))))
	# Windows on both long sides (door on the front ground floor), one per storey on the gables.
	var per_side := maxi(2, int(length / 2.7))
	var door_slot := per_side / 2
	for storey in storeys:
		var wy := 0.4 + storey * 2.8 + 1.55
		for sgn: float in [-1.0, 1.0]:
			for k in per_side:
				var x := -length * 0.5 + (k + 0.5) * length / per_side
				if storey == 0 and sgn > 0.0 and k == door_slot:
					_doors.append(Transform3D(basis.scaled_local(Vector3(1.05, 2.1, 0.08)), at.call(Vector3(x, 1.45, sgn * (width * 0.5 + 0.02)))))
					_stone.append(Transform3D(basis.scaled_local(Vector3(1.6, 0.18, 0.9)), at.call(Vector3(x, 0.09, sgn * (width * 0.5 + 0.45)))))
					_trim.append(Transform3D(basis.scaled_local(Vector3(1.3, 0.12, 0.10)), at.call(Vector3(x, 2.58, sgn * (width * 0.5 + 0.04)))))
					continue
				_window(basis, at.call(Vector3(x, wy, sgn * (width * 0.5))), Vector3(0, 0, sgn), shutter)
		for end: float in [-1.0, 1.0]:
			_window(gable_basis, at.call(Vector3(end * length * 0.5, wy, 0)), Vector3(0, 0, end), shutter)
	return maxf(length, width) * 0.6


func _window(basis: Basis, centre: Vector3, outward_local: Vector3, shutter: int) -> void:
	var out := basis * outward_local
	var across := basis * Vector3(1, 0, 0)
	(_glass_lit if _lit_rng.randf() < 0.35 else _glass).append(Transform3D(basis.scaled_local(Vector3(1.0, 1.25, 0.06)), centre + out * 0.01))
	_trim.append(Transform3D(basis.scaled_local(Vector3(1.24, 0.08, 0.24)), centre + out * 0.07 - Vector3.UP * 0.68))
	for fy: float in [-0.62, 0.62]:
		_trim.append(Transform3D(basis.scaled_local(Vector3(1.12, 0.07, 0.06)), centre + out * 0.05 + Vector3.UP * fy))
	for fx: float in [-0.53, 0.0, 0.53]:
		_trim.append(Transform3D(basis.scaled_local(Vector3(0.06 if fx == 0.0 else 0.07, 1.25, 0.06)), centre + out * 0.05 + across * fx))
	if shutter >= 0:
		for fx: float in [-0.85, 0.85]:
			_shutters[shutter].append(Transform3D(basis.scaled_local(Vector3(0.5, 1.3, 0.05)), centre + out * 0.06 + across * fx))


func build(parent: Node3D) -> void:
	var unit := BoxMesh.new()
	var prism := PrismMesh.new()
	prism.size = Vector3.ONE
	for i in WALLS.size():
		var plaster := C.noise_mat(WALLS[i], 0.05, 2.5, 0.92)
		C.scatter_multimesh(parent, unit, plaster, _walls[i])
		C.scatter_multimesh(parent, prism, plaster, _gables[i])
	for i in ROOFS.size():
		var tiles := ShaderMaterial.new()
		tiles.shader = preload("res://materials/roof_tiles.gdshader")
		tiles.set_shader_parameter("base_color", ROOFS[i])
		C.scatter_multimesh(parent, unit, tiles, _roofs[i])
	C.scatter_multimesh(parent, unit, C.mat(Color(0.58, 0.60, 0.61), 0.45, 0.55), _gutters, false)
	for i in SHUTTERS.size():
		C.scatter_multimesh(parent, unit, C.mat(SHUTTERS[i], 0.7), _shutters[i], false)
	C.scatter_multimesh(parent, unit, C.mat(Color(0.10, 0.14, 0.17), 0.08, 0.4), _glass, false)
	var lit := ShaderMaterial.new()
	lit.shader = preload("res://materials/village_window.gdshader")
	C.scatter_multimesh(parent, unit, lit, _glass_lit, false)
	C.scatter_multimesh(parent, unit, C.mat(Color(0.90, 0.89, 0.85), 0.7), _trim, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.33, 0.20, 0.12), 0.1, 6.0, 0.7), _doors, false)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.52, 0.50, 0.47), 0.1, 2.0), _stone)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.45, 0.24, 0.17), 0.1, 6.0), _chimneys)
	var boards := C.noise_mat(Color(0.36, 0.25, 0.16), 0.14, 6.0, 0.9)
	C.scatter_multimesh(parent, unit, boards, _barn_walls)
	C.scatter_multimesh(parent, prism, boards, _barn_gables)
	C.scatter_multimesh(parent, unit, C.noise_mat(Color(0.22, 0.15, 0.10), 0.12, 5.0, 0.85), _barn_doors, false)
