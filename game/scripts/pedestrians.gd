extends Node3D
## People on the city's footways. Each walks round the footway ring of a block (map data
## "pedestrian_loops": the ring's corners), at their own pace and side of the footway, now and
## then stopping at a shop window or turning back. They step out of the way of a car that comes
## onto the footway towards them; one that is hit anyway stumbles and falls over, and gets up again
## a few seconds later. All of them are simulated (it is cheap arithmetic); the nearest `visible_max`
## are drawn from one MultiMesh whose shader swings arms and legs (pedestrian.gdshader).

const SHADER := preload("res://materials/pedestrian.gdshader")
enum { WALK, PAUSE, DODGE, FALLEN, RISE }

var game: Node
var loops: Array = []          # [{"min": Vector2, "max": Vector2, "y": float, "len": float}]
var people: Array = []         # one Dictionary per person
var visible_max := 120
var multimesh: MultiMesh
var _mm_instance: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _car_cache: Array = []
var hits := 0                  # people knocked over (tests, statistics)
var _last_sim := -1.0
var _frame := 0
var _shown: Array[int] = []
var _picked_from := Vector3(INF, INF, INF)
var _slot_person: PackedInt32Array = PackedInt32Array()
var _tiers: Array = []
var _tiered_from := Vector3(INF, INF, INF)


## loops_in: Array of PackedVector3Array rings (4 corners, the y of the footway). per_loop people
## walk round a ring in the town centre, about a third of them out at the edge of town.
func setup(game_node: Node, loops_in: Array, per_loop: int, seed_value := 31) -> void:
	game = game_node
	_rng.seed = seed_value
	for ring: PackedVector3Array in loops_in:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in ring:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		loops.append({"min": lo, "max": hi, "y": ring[0].y, "len": 2.0 * ((hi.x - lo.x) + (hi.y - lo.y))})
	for li in loops.size():
		var centre: Vector2 = (loops[li]["min"] + loops[li]["max"]) * 0.5
		var busy := 1.0 - smoothstep(120.0, 420.0, centre.length())
		for k in roundi(lerpf(per_loop * 0.35, per_loop, busy)):
			people.append(_new_person(li))
	for p: Dictionary in people:
		_step(p, 0.0, false)   # on the footway from the start
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = person_mesh()
	multimesh.instance_count = visible_max
	multimesh.visible_instance_count = 0
	# The instances move every frame: a fixed box round the whole town instead of a bound that
	# lags behind them (the crowd was culled when the camera jumped).
	multimesh.custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 200, 4000))
	_mm_instance = MultiMeshInstance3D.new()
	_mm_instance.name = "People"
	_mm_instance.multimesh = multimesh
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_mm_instance.material_override = m
	add_child(_mm_instance)


func _new_person(li: int) -> Dictionary:
	var loop: Dictionary = loops[li]
	return {
		"loop": li, "s": _rng.randf() * float(loop["len"]), "dir": 1.0 if _rng.randf() < 0.5 else -1.0,
		"speed": _rng.randf_range(1.05, 1.55), "lane": _rng.randf_range(-0.9, 0.9), "offset": 0.0,
		"phase": _rng.randf(), "amp": 1.0, "state": WALK, "timer": _rng.randf_range(4.0, 30.0),
		"height": _rng.randf_range(0.9, 1.08), "clothing": _rng.randf(), "skin": pow(_rng.randf(), 1.8),
		"pos": Vector3.ZERO, "heading": Vector3.FORWARD, "fall_dir": Vector3.FORWARD, "fall": 0.0,
		"night_home": _rng.randf() < 0.7,   # off the streets late at night
	}


## Point of the ring at arc length s and the walking direction there (ring runs min.x->max.x along
## min.y, then up max.x, back along max.y, down min.x), and the outward normal (towards the kerb).
func _ring_point(loop: Dictionary, s: float) -> Array:
	var lo: Vector2 = loop["min"]
	var hi: Vector2 = loop["max"]
	var w := hi.x - lo.x
	var d := hi.y - lo.y
	s = fposmod(s, float(loop["len"]))
	if s < w: return [Vector2(lo.x + s, lo.y), Vector2(1, 0), Vector2(0, -1)]
	s -= w
	if s < d: return [Vector2(hi.x, lo.y + s), Vector2(0, 1), Vector2(1, 0)]
	s -= d
	if s < w: return [Vector2(hi.x - s, hi.y), Vector2(-1, 0), Vector2(0, 1)]
	s -= w
	return [Vector2(lo.x, hi.y - s), Vector2(0, -1), Vector2(-1, 0)]


func _process(delta: float) -> void:
	if game == null or people.is_empty():
		return
	# Simulated time, as the cars: slow motion and a physics thread that falls behind slow the
	# people down with them.
	var sim := float(game.world.get_stats()["sim_time"])
	var dt := clampf(sim - _last_sim, 0.0, 0.1) if _last_sim >= 0.0 else 0.0
	_last_sim = sim
	var daylight := float(game.weather.daylight) if game.get("weather") else 1.0
	var late := daylight < 0.15
	_cache_cars()
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	# Away from the camera a person only needs updating now and then, with the time gathered
	# meanwhile: every frame within 30 m, every third out to 90 m, every 8th to 200 m, then every
	# 30th (a few centimetres per update at that distance). The
	# tiers are sorted out every 30 frames (and when the camera jumps), so a frame only touches
	# the people due in it.
	if _frame % 30 == 1 or _tiers.is_empty() or eye.distance_squared_to(_tiered_from) > 400.0:
		_sort_tiers(eye)
	for t in 4:
		var every: int = [1, 3, 8, 30][t]
		var list: PackedInt32Array = _tiers[t]
		for j in range(_frame % every, list.size(), every):
			var p: Dictionary = people[list[j]]
			var acc := float(p.get("acc", 0.0))
			_step(p, dt * every + acc, late)
			p["acc"] = 0.0
			p["dirty"] = true
	# Every tenth frame, and at once when the camera jumps (camera switch, recovery).
	if _frame % 10 == 1 or _shown.is_empty() or eye.distance_squared_to(_picked_from) > 225.0:
		_pick_nearest(late, eye)
		_picked_from = eye
	_draw_shown()


func _cache_cars() -> void:
	_car_cache.clear()
	for v in game.vehicles:
		if not is_instance_valid(v): continue
		var info: Dictionary = v.get_meta("ped_dims") if v.has_meta("ped_dims") else {}
		if info.is_empty():
			var i: Dictionary = v.get_info()
			info = {"half_l": float(i.get("length", 4.4)) * 0.5 + 0.15, "half_w": float(i.get("width", 1.8)) * 0.5 + 0.15}
			v.set_meta("ped_dims", info)
		var f: Vector3 = v.get_forward()
		f.y = 0.0
		f = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
		_car_cache.append({"pos": v.get_position_ws(), "vel": v.get_velocity(), "fwd": f, "half_l": info["half_l"], "half_w": info["half_w"]})


func _step(p: Dictionary, dt: float, late: bool) -> void:
	if p.get("frozen", false):
		return
	var loop: Dictionary = loops[p["loop"]]
	var state: int = p["state"]
	p["timer"] = float(p["timer"]) - dt
	if dt <= 0.0:
		# Paused (or the first frame): stay where they are, but be somewhere on the footway.
		var rp0 := _ring_point(loop, float(p["s"]))
		var c0: Vector2 = rp0[0] + (rp0[2] as Vector2) * (float(p["lane"]) + float(p["offset"]))
		p["pos"] = Vector3(c0.x, float(loop["y"]), c0.y)
		if state != FALLEN and state != RISE:
			p["heading"] = Vector3((rp0[1] as Vector2).x, 0.0, (rp0[1] as Vector2).y) * float(p["dir"])
		return
	match state:
		WALK, DODGE:
			var pace := float(p["speed"]) * (1.9 if state == DODGE else 1.0)
			p["s"] = float(p["s"]) + float(p["dir"]) * pace * dt
			p["phase"] = fposmod(float(p["phase"]) + pace * dt / 1.45, 1.0)
			p["amp"] = move_toward(float(p["amp"]), 1.0, dt * 3.0)
			if state == DODGE and float(p["timer"]) <= 0.0:
				p["state"] = WALK
				p["timer"] = _rng.randf_range(6.0, 25.0)
			elif state == WALK and float(p["timer"]) <= 0.0:
				# Stop at a shop window, or turn back.
				if _rng.randf() < 0.25:
					p["dir"] = -float(p["dir"])
					p["timer"] = _rng.randf_range(6.0, 25.0)
				else:
					p["state"] = PAUSE
					p["timer"] = _rng.randf_range(2.0, 7.0)
		PAUSE:
			p["amp"] = move_toward(float(p["amp"]), 0.0, dt * 3.0)
			if float(p["timer"]) <= 0.0:
				p["state"] = WALK
				p["timer"] = _rng.randf_range(6.0, 25.0)
		FALLEN:
			p["amp"] = 0.0
			p["fall"] = move_toward(float(p["fall"]), 1.0, dt * 5.0)
			if float(p["timer"]) <= 0.0:
				p["state"] = RISE
				p["timer"] = 1.2
		RISE:
			p["fall"] = move_toward(float(p["fall"]), 0.0, dt * 1.0)
			if float(p["fall"]) <= 0.0:
				p["state"] = WALK
				p["timer"] = _rng.randf_range(6.0, 25.0)
	var rp := _ring_point(loop, float(p["s"]))
	var along: Vector2 = rp[1] * float(p["dir"])
	var outward: Vector2 = rp[2]
	p["offset"] = move_toward(float(p["offset"]), 0.0, dt * 0.4)
	var lateral := float(p["lane"]) + float(p["offset"])
	var c: Vector2 = rp[0] + outward * lateral
	var pos := Vector3(c.x, float(loop["y"]), c.y)
	if state != FALLEN and state != RISE:
		p["heading"] = Vector3(along.x, 0.0, along.y)
	p["pos"] = pos
	if state == FALLEN or state == RISE or (late and p["night_home"]):
		return
	# Cars: dodge one that heads for this spot within ~1.5 s; fall over if one is already here.
	for car: Dictionary in _car_cache:
		var rel: Vector3 = pos - car["pos"]
		rel.y = 0.0
		if rel.length_squared() > 100.0:
			continue
		var fwd: Vector3 = car["fwd"]
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var vel: Vector3 = car["vel"]
		vel.y = 0.0
		var speed := vel.length()
		if absf(rel.dot(fwd)) < float(car["half_l"]) and absf(rel.dot(right)) < float(car["half_w"]) and speed > 2.0:
			p["state"] = FALLEN
			p["timer"] = _rng.randf_range(4.0, 7.0)
			p["fall_dir"] = vel / speed
			hits += 1
			return
		if speed > 1.5 and state != DODGE:
			# Time until the car is closest (it moves towards rel) and how close it then is.
			var t := clampf(rel.dot(vel) / (speed * speed), 0.0, 1.5)
			var closest := rel - vel * t
			if t > 0.0 and closest.length() < 2.4:
				# Step away from the car's path, towards the buildings or the kerb, whichever is clear.
				var side := signf(closest.dot(Vector3(outward.x, 0.0, outward.y)))
				if side == 0.0: side = -1.0
				p["offset"] = clampf(float(p["offset"]) + side * 1.4, -1.6, 1.6)
				p["state"] = DODGE
				p["timer"] = 1.2
				p["heading"] = (Vector3(outward.x, 0.0, outward.y) * side + p["heading"] * 0.3).normalized()


func _sort_tiers(eye: Vector3) -> void:
	# Packed arrays are values: fill locals, then store them.
	var near := PackedInt32Array()
	var mid := PackedInt32Array()
	var far := PackedInt32Array()
	var remote := PackedInt32Array()
	for i in people.size():
		var d2 := (people[i]["pos"] as Vector3).distance_squared_to(eye)
		if d2 < 900.0: near.append(i)
		elif d2 < 8100.0: mid.append(i)
		elif d2 < 40000.0: far.append(i)
		else: remote.append(i)
	_tiers = [near, mid, far, remote]
	_tiered_from = eye


## The people drawn: the nearest visible_max within 160 m (chosen every tenth frame).
func _pick_nearest(late: bool, eye: Vector3) -> void:
	var order: Array = []
	for i in people.size():
		var p: Dictionary = people[i]
		if late and p["night_home"]: continue
		var d := (p["pos"] as Vector3).distance_squared_to(eye)
		if d < 160.0 * 160.0:
			order.append([d, i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	_shown.clear()
	for k in mini(order.size(), visible_max):
		_shown.append(order[k][1])


func _draw_shown() -> void:
	var n := _shown.size()
	multimesh.visible_instance_count = n
	_slot_person.resize(n)
	for k in n:
		var p: Dictionary = people[_shown[k]]
		# Only what changed: a person not updated this frame keeps their slot as it was.
		if _slot_person[k] == _shown[k] and not p.get("dirty", true):
			continue
		_slot_person[k] = _shown[k]
		p["dirty"] = false
		var h: Vector3 = p["heading"]
		var basis := Basis.looking_at(h if h.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
		var fall := float(p["fall"])
		if fall > 0.0:
			# Tip over forwards along the car's travel, about the feet.
			var axis: Vector3 = Vector3.UP.cross(p["fall_dir"]).normalized()
			if axis.length() > 0.5:
				basis = Basis(axis, fall * PI * 0.47) * basis
		basis = basis.scaled(Vector3.ONE * float(p["height"]))
		var origin: Vector3 = p["pos"] + Vector3.UP * (0.12 * fall)
		multimesh.set_instance_transform(k, Transform3D(basis, origin))
		multimesh.set_instance_custom_data(k, Color(float(p["phase"]), float(p["amp"]), float(p["clothing"]), float(p["skin"])))


# ------------------------------------------------------------------------------ the mesh

static var _mesh: ArrayMesh

## A person 1.75 m tall facing -Z, feet at the origin. Vertex colour: r = part / 8 (0 body,
## 1/2 left/right leg, 3/4 left/right arm), g = material / 8 (0 skin, 1 top, 2 trousers, 3 shoes,
## 4 hair).
static func person_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body: hips, torso, neck, head with hair.
	_capsule(st, Vector3(-0.06, 0.95, 0), Vector3(0.06, 0.95, 0), 0.10, 0.10, 0, 2, Vector2(1.0, 0.8))
	_capsule(st, Vector3(0, 1.00, 0), Vector3(0, 1.36, 0), 0.165, 0.105, 0, 1, Vector2(1.0, 0.62))
	_capsule(st, Vector3(0, 1.40, 0), Vector3(0, 1.43, 0), 0.19, 0.08, 0, 1, Vector2(1.0, 0.6))   # shoulders
	_capsule(st, Vector3(0, 1.46, 0), Vector3(0, 1.55, 0), 0.05, 0.05, 0, 0)
	_sphere(st, Vector3(0, 1.655, -0.005), Vector3(0.095, 0.115, 0.105), 0, 0, false)
	_sphere(st, Vector3(0, 1.675, 0.012), Vector3(0.104, 0.11, 0.112), 0, 4, true)
	for side in [-1.0, 1.0]:
		var leg := 1 if side < 0.0 else 2
		var arm := 3 if side < 0.0 else 4
		_capsule(st, Vector3(side * 0.09, 0.93, 0), Vector3(side * 0.095, 0.48, 0.01), 0.075, 0.062, leg, 2)
		_capsule(st, Vector3(side * 0.095, 0.48, 0.01), Vector3(side * 0.095, 0.09, 0.02), 0.06, 0.05, leg, 2)
		_capsule(st, Vector3(side * 0.095, 0.045, 0.04), Vector3(side * 0.095, 0.045, -0.12), 0.05, 0.048, leg, 3)
		_capsule(st, Vector3(side * 0.225, 1.39, 0), Vector3(side * 0.245, 1.11, 0.0), 0.055, 0.048, arm, 1)
		_capsule(st, Vector3(side * 0.245, 1.11, 0.0), Vector3(side * 0.25, 0.86, -0.02), 0.045, 0.04, arm, 1)
		_sphere(st, Vector3(side * 0.25, 0.81, -0.02), Vector3(0.042, 0.055, 0.035), arm, 0, false)
	st.index()
	_mesh = st.commit()
	return _mesh


static func _col(part: int, material: int) -> Color:
	return Color(part / 8.0, material / 8.0, 0.0, 1.0)


## Tapered capsule from a (radius ra) to b (radius rb); `squash` scales the cross-section (x, z).
static func _capsule(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, part: int, material: int, squash := Vector2.ONE) -> void:
	const SEG := 10
	const CAP := 3
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	# Rings: hemisphere at a, the barrel, hemisphere at b.
	var rings: Array = []   # [centre, radius scale (lateral), axial offset]
	for k in range(CAP, 0, -1):
		var t := float(k) / CAP * PI * 0.5
		rings.append([a - axis * ra * sin(t), ra * cos(t)])
	rings.append([a, ra])
	rings.append([b, rb])
	for k in range(1, CAP + 1):
		var t := float(k) / CAP * PI * 0.5
		rings.append([b + axis * rb * sin(t), rb * cos(t)])
	var col := _col(part, material)
	var pts: Array = []
	var nrm: Array = []
	for r: Array in rings:
		var row: Array = []
		var nrow: Array = []
		var centre: Vector3 = r[0]
		var rad: float = r[1]
		for s in SEG:
			var ang := TAU * s / SEG
			var dir := u * cos(ang) * squash.x + v * sin(ang) * squash.y
			row.append(centre + dir * rad)
			var along_axis := (centre - (a + b) * 0.5).dot(axis)
			var n := (u * cos(ang) / squash.x + v * sin(ang) / squash.y).normalized()
			if rad < maxf(ra, rb) * 0.999:
				n = (n * rad + axis * signf(along_axis) * sqrt(maxf(0.0, maxf(ra, rb) * maxf(ra, rb) - rad * rad))).normalized()
			nrow.append(n)
		pts.append(row)
		nrm.append(nrow)
	for i in pts.size() - 1:
		for s in SEG:
			var s2 := (s + 1) % SEG
			for tri in [[i, s], [i + 1, s], [i + 1, s2], [i, s], [i + 1, s2], [i, s2]]:
				st.set_color(col)
				st.set_normal(nrm[tri[0]][tri[1]])
				st.add_vertex(pts[tri[0]][tri[1]])
	# Close the ends (the outermost rings have radius ~0 already).


## Ellipsoid at c with radii r; `dome` keeps the upper half and the back (hair).
static func _sphere(st: SurfaceTool, c: Vector3, r: Vector3, part: int, material: int, dome: bool) -> void:
	const LAT := 7
	const LON := 12
	var col := _col(part, material)
	for i in LAT:
		for j in LON:
			var quad: Array = []
			for k: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var th := PI * float(k.x) / LAT
				var ph := TAU * float(k.y) / LON
				var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				quad.append(n)
			if dome:
				# Hair: the crown and the back of the head, not the face (-Z) below the brow.
				var mid: Vector3 = (quad[0] + quad[2]) * 0.5
				if mid.y < -0.1 or (mid.z < -0.2 and mid.y < 0.45):
					continue
			for t in [0, 1, 2, 0, 2, 3]:
				var n: Vector3 = quad[t]
				st.set_color(col)
				st.set_normal(Vector3(n.x / r.x, n.y / r.y, n.z / r.z).normalized())
				st.add_vertex(c + Vector3(n.x * r.x, n.y * r.y, n.z * r.z))
