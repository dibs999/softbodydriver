extends Node3D
## A small set of service/pit lights, switched by the same clock as the sky.
var lamps: Array[OmniLight3D] = []
var luminous: Array[MeshInstance3D] = []
var _timer := 0.0

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0: return
	_timer = 0.25
	var scene := get_tree().current_scene
	if scene == null: return
	var weather: Node = scene.get("weather")
	if weather == null: return
	var hour := float(weather.get("hour"))
	var daylight := smoothstep(-0.12, 0.35, sin((hour - 6.0) * TAU / 24.0))
	for lamp in lamps:
		lamp.light_energy = lerpf(3.0, 0.0, daylight)
		lamp.visible = daylight < 0.99
	for lens in luminous:
		lens.visible = daylight < 0.99
