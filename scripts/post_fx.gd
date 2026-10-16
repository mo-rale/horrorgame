extends CanvasLayer
# Full-screen film look: vignette, grain, chromatic aberration. Anxiety makes
# the edges close in and the colour drain.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float anxiety : hint_range(0.0, 1.0) = 0.0;
uniform float grain_strength = 0.06;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float dist = length(centered);
	float aberration = (0.0015 + anxiety * 0.004) * dist * 2.0;
	vec3 col;
	col.r = texture(screen_tex, uv + centered * aberration).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - centered * aberration).b;

	float vignette = smoothstep(0.85 - anxiety * 0.35, 0.25, dist);
	col *= mix(0.35, 1.0, vignette);

	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), 0.15 + anxiety * 0.45);
	col = mix(col, col * vec3(1.0, 0.82, 0.82), anxiety * 0.6);

	float noise = hash(uv * vec2(1920.0, 1080.0) + vec2(TIME * 37.0, TIME * 91.0)) - 0.5;
	col += noise * (grain_strength + anxiety * 0.05);
	COLOR = vec4(col, 1.0);
}
"""

var _material := ShaderMaterial.new()
var _anxiety := 0.0
var _target_anxiety := 0.0


func _ready() -> void:
	layer = 1
	add_to_group("post_fx")
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	var rect := ColorRect.new()
	rect.material = _material
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)


func set_anxiety(value: float) -> void:
	_target_anxiety = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	_anxiety = lerpf(_anxiety, _target_anxiety, minf(delta * 3.0, 1.0))
	_material.set_shader_parameter("anxiety", _anxiety)
