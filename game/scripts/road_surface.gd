extends RefCounted
## Spatially indexed road corridors. Shared by grip, road audio and particles.
const CELL := 64.0
var map_id := ""
var _buckets: Dictionary = {}
var _regions: Array = []

func configure(id: String, data: Dictionary) -> void:
	map_id = id
	_buckets.clear()
	_regions = data.get("surface_regions", [])
	for path: PackedVector3Array in data.get("map_paths", []):
		for i in path.size() - 1:
			var a := Vector2(path[i].x, path[i].z)
			var b := Vector2(path[i + 1].x, path[i + 1].z)
			for x in range(floori((minf(a.x, b.x) - 18) / CELL), floori((maxf(a.x, b.x) + 18) / CELL) + 1):
				for y in range(floori((minf(a.y, b.y) - 18) / CELL), floori((maxf(a.y, b.y) + 18) / CELL) + 1):
					var key := Vector2i(x, y)
					if not _buckets.has(key): _buckets[key] = []
					_buckets[key].append([a, b])

func at(point: Vector3) -> String:
	var p := Vector2(point.x, point.z)
	for region: Dictionary in _regions:
		if (region["rect"] as Rect2).has_point(p): return region["surface"]
	if map_id == "proving_grounds": return "asphalt"
	var distance := INF
	for edge: Array in _buckets.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), []):
		var a: Vector2 = edge[0]
		var d: Vector2 = edge[1] - a
		var t := clampf((p - a).dot(d) / maxf(0.001, d.length_squared()), 0, 1)
		distance = minf(distance, p.distance_to(a + d * t))
	match map_id:
		"offroad": return "gravel" if distance < 3.3 else "grass"
		"desert": return "gravel" if distance < 7.0 else "sand"
		"hill_roads": return "asphalt" if distance < 5.5 else "grass"
		"autobahn": return "asphalt" if distance < 15.0 else "grass"
		"city": return "asphalt" if distance < 8.0 else "pavement"
	return "asphalt"

static func grip(kind: String) -> float:
	return {"asphalt": 1.0, "pavement": 0.94, "gravel": 0.78, "sand": 0.66, "grass": 0.70}.get(kind, 1.0)
