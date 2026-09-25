class_name PoolPostFX
extends CanvasLayer

# One pass over the finished frame, under the HUD. Most of the time it only
# does the quiet things a film camera would: a warm grade, a soft vignette,
# a little grain. It is also where the drinks show, where a knock to the head
# swims, and where a big punch smears the edges of the screen.

var rect: ColorRect
var mat: ShaderMaterial

# 0..1 each, set by the game every frame
var trip := 0.0          # Blitzkraft
var wobble := 0.0        # Old Wobbly
var dizzy := 0.0         # knocked down
var zoom_blur := 0.0     # the punch going in
var flash := 0.0         # the punch landing

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float grain = 0.03;
uniform float trip = 0.0;
uniform float wobble = 0.0;
uniform float dizzy = 0.0;
uniform float zoom_blur = 0.0;
uniform float flash = 0.0;

vec3 hue_rotate(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = TIME;
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);

	// Blitzkraft: the room breathes and ripples
	if (trip > 0.0) {
		float pulse = 0.5 + 0.5 * sin(t * 4.4);
		uv += trip * 0.011 * vec2(sin(uv.y * 17.0 + t * 3.1), cos(uv.x * 13.0 + t * 2.3));
		uv = 0.5 + (uv - 0.5) * (1.0 - trip * 0.035 * pulse);
	}
	// knocked silly: the view swims round
	if (dizzy > 0.0) {
		float a = dizzy * 0.10 * sin(t * 1.9) * (1.2 - r);
		mat2 m = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		uv = 0.5 + m * (uv - 0.5);
	}

	float ca = 0.0012 + trip * 0.011 * (0.6 + 0.4 * sin(t * 5.3)) + zoom_blur * 0.01 + dizzy * 0.004;
	vec2 dir = c * ca * 2.0;
	vec3 col;
	col.r = texture(screen, uv + dir).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - dir).b;

	// seeing double
	float dv = max(wobble, dizzy * 0.8);
	if (dv > 0.0) {
		vec2 off = vec2(0.02 + 0.014 * sin(t * 0.9), 0.007 * sin(t * 1.3)) * dv;
		vec3 ghost = textureLod(screen, uv + off, 1.0).rgb;
		col = mix(col, ghost, 0.42 * dv);
		float edge = smoothstep(0.15, 0.6, r);
		col = mix(col, textureLod(screen, uv, 3.0).rgb, 0.5 * dv * edge);
	}
	// a fist going through the air: everything streaks towards the middle
	if (zoom_blur > 0.0) {
		vec3 acc = col;
		for (int i = 1; i < 8; i++) {
			float k = float(i) / 8.0 * 0.09 * zoom_blur;
			acc += texture(screen, 0.5 + (uv - 0.5) * (1.0 - k)).rgb;
		}
		col = mix(col, acc / 8.0, smoothstep(0.05, 0.35, r));
	}
	if (trip > 0.0) {
		vec3 shifted = hue_rotate(col, trip * (t * 1.7 + r * 7.0));
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		shifted = mix(vec3(l), shifted, 1.0 + trip * 0.9);
		col = mix(col, shifted, trip);
		col += trip * 0.06 * vec3(0.4 + 0.4 * sin(t * 2.0), 0.2, 0.5 + 0.5 * cos(t * 1.4)) * smoothstep(0.3, 0.8, r);
	}
	if (wobble > 0.0) {
		// a warm, boozy haze
		col = mix(col, col * vec3(1.08, 0.98, 0.85), wobble * 0.6);
	}

	// the everyday grade: a touch warm, shadows lifted a hair
	col = pow(max(col, vec3(0.0)), vec3(0.985, 1.0, 1.02));
	col = col * 0.985 + vec3(0.011, 0.009, 0.006);
	float v = smoothstep(0.95, 0.28, r * (1.0 + dizzy * 0.6));
	col *= mix(1.0 - vignette - dizzy * 0.3, 1.0, v);
	col = mix(col, vec3(1.0, 0.95, 0.9), flash * 0.5);
	col += (hash(FRAGCOORD.xy + fract(t * 7.13) * 91.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
"""


func setup() -> void:
	layer = 0
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	rect.position = Vector2.ZERO
	rect.size = vs


func _process(_delta: float) -> void:
	mat.set_shader_parameter("trip", trip)
	mat.set_shader_parameter("wobble", wobble)
	mat.set_shader_parameter("dizzy", dizzy)
	mat.set_shader_parameter("zoom_blur", zoom_blur)
	mat.set_shader_parameter("flash", flash)
	var film := PoolSettings.on("film_fx")
	mat.set_shader_parameter("grain", 0.03 if film else 0.0)
	mat.set_shader_parameter("vignette", 0.32 if film else 0.0)
