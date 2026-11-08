extends MultiMeshInstance3D
## Fixed ring buffer of road-aligned strips; no new nodes during a drift.
var world: SBWorld
var clock := 0.0
var _cursor := 0
var _count := 0
var _last: Dictionary = {}
const CAPACITY := 1024

func _ready() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	multimesh.mesh = mesh
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float clock = 0.0;
varying vec4 data;
void vertex() { data = INSTANCE_CUSTOM; }
void fragment() {
 float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.12, 1.0-UV.x);
 float tread = 0.73 + 0.27 * sin(UV.x * 83.0);
 ALBEDO = vec3(0.035, 0.031, 0.027);
 ALPHA = edge * tread * data.y * (1.0-smoothstep(25.0, 45.0, clock-data.x));
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	if world: clock = float(world.get_stats()["sim_time"])
	(material_override as ShaderMaterial).set_shader_parameter("clock", clock)

func trace(key: String, point: Vector3, normal: Vector3, strength: float) -> void:
	if strength < 0.12:
		_last.erase(key)
		return
	if not _last.has(key):
		_last[key] = point
		return
	var previous: Vector3 = _last[key]
	var delta := point - previous
	if delta.length() < 0.16: return
	_last[key] = point
	if delta.length() > 3.5: return
	var tangent := delta.normalized()
	var across := normal.cross(tangent).normalized()
	if across.length_squared() < 0.5: return
	var basis := Basis(across * 0.21, tangent.cross(across).normalized(), tangent * (delta.length() + 0.04))
	multimesh.set_instance_transform(_cursor, Transform3D(basis, (point + previous) * 0.5 + normal * 0.018))
	multimesh.set_instance_custom_data(_cursor, Color(clock, clampf(strength * 0.65, 0, 0.65), 0, 0))
	_cursor = (_cursor + 1) % CAPACITY
	_count = mini(CAPACITY, _count + 1)
	multimesh.visible_instance_count = _count
