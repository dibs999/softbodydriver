extends Node3D
## German number plates (520 x 110 mm, blue EU band with "D") on a vehicle's front and rear plate
## anchors. The anchors are skinned to the body, so the plates move with a crumpling bumper.

var vehicle: SBVehicle
var text := ""
var _plates: Array[Node3D] = []

const CODES := ["M", "HH", "K", "S", "SB", "F", "B", "HD", "KA", "DU", "N", "LB", "GÖ", "WÜ"]
const LETTERS := "ABCDEFGHJKLMNPRSTUVWXYZ"


## Deterministic plate text for a seed, e.g. "SB·KM 214" (the dot stands for the seal stickers).
static func plate_text(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var code: String = CODES[rng.randi() % CODES.size()]
	var letters := ""
	for i in (1 if rng.randf() < 0.3 else 2):
		letters += LETTERS[rng.randi() % LETTERS.length()]
	var digits := str(rng.randi_range(1, 9999 if code.length() + letters.length() < 4 else 999))
	return "%s·%s %s" % [code, letters, digits]


var _rear_white: StandardMaterial3D

func _ready() -> void:
	if not _plates.is_empty():
		return
	top_level = true   # placed in world space from the anchors
	if text.is_empty():
		text = plate_text(int(vehicle.get_instance_id()) if vehicle else 0)
	var white := _mat(Color(0.93, 0.93, 0.91), 0.45)
	var border := _mat(Color(0.05, 0.05, 0.05), 0.6)
	var blue := _mat(Color(0.0, 0.2, 0.62), 0.5)
	# The rear plate has its own white: the plate lamp above it lights it with the lights on.
	_rear_white = white.duplicate()
	_rear_white.emission = Color(0.96, 0.96, 0.93)
	for i in 2:
		var plate := Node3D.new()
		plate.name = "FrontPlate" if i == 0 else "RearPlate"
		add_child(plate)
		_box(plate, Vector3(0.48, 0.108, 0.003), Vector3(0, 0, 0.0015), border)
		_box(plate, Vector3(0.47, 0.098, 0.003), Vector3(0, 0, 0.0035), white if i == 0 else _rear_white)
		_box(plate, Vector3(0.042, 0.098, 0.002), Vector3(-0.214, 0, 0.0055), blue)
		var d := _label("D", 0.032, Color(0.95, 0.95, 0.95))
		d.position = Vector3(-0.214, -0.024, 0.0068)
		plate.add_child(d)
		var stars := _label("✶", 0.02, Color(0.98, 0.85, 0.1))
		stars.position = Vector3(-0.214, 0.02, 0.0068)
		plate.add_child(stars)
		# Fit the lettering into the 0.40 m beside the band (FE-Schrift is narrow: ~0.55 x height).
		var height := minf(0.064, 0.38 / maxf(1.0, text.length() * 0.68))
		var t := _label(text, height, Color(0.03, 0.03, 0.03))
		t.position = Vector3(0.024, -0.002, 0.0062)
		plate.add_child(t)
		_plates.append(plate)
	visible = false


## Plate lamp: lights the rear plate evenly (vehicle_equipment.gd switches it with the lights).
func set_lamp(on: bool) -> void:
	if _rear_white:
		_rear_white.emission_enabled = on
		_rear_white.emission_energy_multiplier = 0.3


func _process(_delta: float) -> void:
	if not is_instance_valid(vehicle) or _plates.is_empty():
		return
	var xf: Array = vehicle.get_plate_transforms()
	visible = xf.size() == 2
	if not visible:
		return
	for i in 2:
		_plates[i].global_transform = xf[i]


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


static func _label(s: String, height: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font_size = 64
	l.pixel_size = height / 64.0 * 1.35   # cap height ~ the requested size
	l.modulate = colour
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
