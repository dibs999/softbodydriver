extends Node
## Freeroam discovery of the named places already shown on the minimap. Discoveries are persistent
## profile progress, independent of timed activities; water labels are map annotation, not targets.

var player: SBVehicle
var hud: Control
var map_id := ""
var entries: Array[Dictionary] = []
var _timer := 0.0
var _triggered := {}

const DISCOVER_RADIUS := 24.0
const VERTICAL_RANGE := 10.0

static func _targetable(place_name: String, pos: Variant) -> bool:
	if place_name.is_empty() or not pos is Vector3:
		return false
	var v: Vector3 = pos
	if not v.is_finite():
		return false
	return not (place_name.contains("See") or place_name.contains("Weiher") or place_name.contains("Teich"))

func configure(id: String, places: Array, player_vehicle: SBVehicle, hud_control: Control) -> void:
	map_id = id
	player = player_vehicle
	hud = hud_control
	entries.clear()
	_triggered.clear()
	var seen := {}
	for entry: Dictionary in places:
		var place_name := String(entry.get("name", ""))
		var pos: Variant = entry.get("position", Vector3.INF)
		if not _targetable(place_name, pos) or seen.has(place_name):
			continue
		seen[place_name] = true
		entries.append({"name": place_name, "position": pos})
	_timer = 1.0

func total() -> int:
	return entries.size()

func found_count() -> int:
	return Game.progress.landmark_count(map_id)

func status() -> String:
	return "Orte %d/%d" % [found_count(), total()] if total() > 0 else ""

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	if entries.is_empty() or not is_instance_valid(player):
		return
	var at := player.get_position_ws()
	for entry in entries:
		var place_name := String(entry["name"])
		if _triggered.has(place_name) or Game.progress.landmark_known(map_id, place_name):
			continue
		var target: Vector3 = entry["position"]
		var flat := Vector2(at.x - target.x, at.z - target.z).length()
		if flat < DISCOVER_RADIUS and absf(at.y - target.y) < VERTICAL_RANGE:
			_triggered[place_name] = true
			if Game.progress.discover_landmark(map_id, place_name) and hud:
				hud.toast("Ort entdeckt: %s · %d/%d" % [place_name, found_count(), total()])
