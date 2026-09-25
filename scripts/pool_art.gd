class_name PoolArt
extends RefCounted

# Every texture in the game is generated at load time. Nothing is imported,
# so the project stays a pure source tree and the palette stays consistent.

const BALL_COLORS := {
	1: Color("e8b42c"), 2: Color("1c4f9c"), 3: Color("c02127"), 4: Color("54308a"),
	5: Color("e2701f"), 6: Color("15693c"), 7: Color("6d2320"), 8: Color("141414"),
	9: Color("e8b42c"), 10: Color("1c4f9c"), 11: Color("c02127"), 12: Color("54308a"),
	13: Color("e2701f"), 14: Color("15693c"), 15: Color("6d2320"),
}

const IVORY := Color("f4efe2")

# 3x5 digit glyphs, one string of 15 chars per digit, row major.
const GLYPHS := [
	"111101101101111", "010010010010010", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
	"011001001101111",                  # J, for the 8
]


static func ball_texture(num: int) -> ImageTexture:
	var w := 256
	var h := 128
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var base: Color = BALL_COLORS.get(num, Color.WHITE) if num > 0 else IVORY
	var striped := num >= 9

	for y in h:
		var v := (float(y) + 0.5) / float(h)
		for x in w:
			var c := base
			if num == 0:
				c = IVORY
			elif striped:
				c = base if absf(v - 0.5) < 0.215 else IVORY
			img.set_pixel(x, y, c)

	if num == 0:
		# measle-style spots so spin is readable in play
		var spots := [Vector2(0.12, 0.5), Vector2(0.37, 0.5), Vector2(0.62, 0.5),
			Vector2(0.87, 0.5), Vector2(0.25, 0.22), Vector2(0.75, 0.78)]
		for s in spots:
			_disc(img, s.x * w, s.y * h, 7.0, Color("9c2f26"))
	else:
		for cx: float in [0.25, 0.75]:
			_disc(img, cx * w, 0.5 * h, 21.0, IVORY)
			_number(img, cx * w, 0.5 * h, num, base if num != 8 else Color("161616"))

	grain(img, num)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var x0 := int(floor(cx - r)) - 1
	var x1 := int(ceil(cx + r)) + 1
	var y0 := maxi(int(floor(cy - r)) - 1, 0)
	var y1 := mini(int(ceil(cy + r)) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length()
			if d > r + 1.0:
				continue
			var a := clampf(r + 0.5 - d, 0.0, 1.0)
			var xi := wrapi(x, 0, img.get_width())
			var dst := img.get_pixel(xi, y)
			img.set_pixel(xi, y, dst.lerp(col, a))


static func _number(img: Image, cx: float, cy: float, num: int, col: Color) -> void:
	var digits: Array = []
	if num >= 10:
		digits.append(num / 10)
	digits.append(num % 10)
	if num == 8:
		digits = [10]                  # the 8 carries a J
	var px := 3.0
	var gw := (digits.size() * 3 + (digits.size() - 1)) * px
	var gh := 5.0 * px
	var ox := cx - gw * 0.5
	var oy := cy - gh * 0.5
	for gi in digits.size():
		var glyph: String = GLYPHS[digits[gi]]
		for row in 5:
			for col_i in 3:
				if glyph[row * 3 + col_i] != "1":
					continue
				var bx := ox + float(gi) * 4.0 * px + float(col_i) * px
				var by := oy + float(row) * px
				for y in range(int(by), int(by + px)):
					for x in range(int(bx), int(bx + px)):
						if y < 0 or y >= img.get_height():
							continue
						img.set_pixel(wrapi(x, 0, img.get_width()), y, col)


static func grain(img: Image, seed_val: int, count := 900) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9171 + seed_val * 37
	var w := img.get_width()
	var h := img.get_height()
	for _i in count:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var c := img.get_pixel(x, y)
		img.set_pixel(x, y, c.lerp(Color(0.5, 0.5, 0.5), rng.randf() * 0.06))


# ---------------------------------------------------------------------------
# Surfaces
# ---------------------------------------------------------------------------

static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Procedural surface shaders
#
# Wood, brick and floorboards are computed per pixel from world position
# rather than read out of a small tiled image. There is no texture to run out
# of resolution up close, no tile seam, and no stretching on box faces, which
# is what made the walls and the table cabinet look smeared and glitchy.
# ---------------------------------------------------------------------------

const _NOISE := """
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.3);
		a *= 0.5;
	}
	return s / 0.9375;
}
"""

const _WOOD := """
uniform vec3 tint : source_color = vec3(0.2, 0.12, 0.07);
uniform float contrast = 0.26;
uniform float ring_freq = 40.0;
uniform vec3 axis = vec3(1.0, 0.0, 0.0);
uniform float rough = 0.4;
uniform float cc = 0.0;
uniform float cc_rough = 0.3;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 u = normalize(axis);
	vec3 v = normalize(cross(u, abs(u.y) > 0.9 ? vec3(1, 0, 0) : vec3(0, 1, 0)));
	vec3 w = cross(u, v);
	vec3 q = vec3(dot(wp, u), dot(wp, v), dot(wp, w));
	// growth rings round a heart well off to one side: flat-sawn figure
	float r = length(q.yz + vec2(0.37, 0.91));
	r += (fbm(vec3(q.x * 0.9, q.y * 5.0, q.z * 5.0)) - 0.5) * 0.05;
	float g = sin(r * ring_freq);
	g = sign(g) * pow(abs(g), 0.45);
	// fine pores running along the grain, faded out before they alias
	float fw = length(fwidth(q.yz)) * 300.0;
	float pores = (fbm(vec3(q.x * 5.0, q.y * 300.0, q.z * 300.0)) - 0.5) * clamp(1.4 - fw, 0.0, 1.0);
	float figure = (fbm(q * vec3(0.6, 2.0, 2.0)) - 0.5) * 0.25;
	float val = g * contrast * 0.5 + pores * 0.22 + figure;
	ALBEDO = clamp(tint * (1.0 + val * vec3(1.0, 0.92, 0.8)), 0.0, 1.0);
	ROUGHNESS = clamp(rough * (1.0 + pores * 0.5), 0.02, 1.0);
	SPECULAR = 0.5;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = cc_rough;
}
"""

const _BRICK := """
uniform float course_h = 0.075;
uniform float brick_w = 0.225;
uniform float joint = 0.011;
uniform vec3 mortar_col : source_color = vec3(0.17, 0.155, 0.14);
uniform vec3 tint_a : source_color = vec3(0.29, 0.17, 0.135);
uniform vec3 tint_b : source_color = vec3(0.36, 0.20, 0.15);
uniform vec3 tint_c : source_color = vec3(0.24, 0.14, 0.115);
varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// distance from the nearest joint, and which brick this is
vec3 brick_at(vec2 uv) {
	float row = floor(uv.y / course_h);
	float x = uv.x / brick_w + mod(row, 2.0) * 0.5;
	float col = floor(x);
	vec2 l = vec2(fract(x) * brick_w, fract(uv.y / course_h) * course_h);
	float d = min(min(l.x, brick_w - l.x), min(l.y, course_h - l.y));
	return vec3(d, row, col);
}

float height_at(vec2 uv) {
	vec3 b = brick_at(uv);
	float face = smoothstep(joint * 0.5, joint * 0.5 + 0.005, b.x);
	return face + (vnoise(vec3(uv * 90.0, b.y)) - 0.5) * 0.25 * face;
}

void fragment() {
	vec3 an = abs(wn);
	vec2 uv;
	vec3 t1;
	vec3 t2;
	if (an.y > an.x && an.y > an.z) {
		uv = wp.xz; t1 = vec3(1, 0, 0); t2 = vec3(0, 0, 1);
	} else if (an.x > an.z) {
		uv = wp.zy; t1 = vec3(0, 0, 1); t2 = vec3(0, 1, 0);
	} else {
		uv = wp.xy; t1 = vec3(1, 0, 0); t2 = vec3(0, 1, 0);
	}
	vec3 b = brick_at(uv);
	float fw = max(length(fwidth(uv)), 0.0005);
	float m = 1.0 - smoothstep(joint * 0.5 - fw, joint * 0.5 + fw, b.x);
	float h = hash12(b.yz);
	vec3 brick = h < 0.33 ? mix(tint_a, tint_b, h * 3.0) : (h < 0.66 ? mix(tint_b, tint_c, h * 3.0 - 1.0) : mix(tint_c, tint_a, h * 3.0 - 2.0));
	brick *= 0.88 + 0.24 * hash12(b.yz + 7.0);
	float grit = fbm(vec3(uv * 45.0, b.y * 3.0));
	brick *= 0.82 + 0.36 * grit;
	vec3 mortar = mortar_col * (0.8 + 0.4 * vnoise(vec3(uv * 120.0, 1.0)));
	ALBEDO = mix(brick, mortar, m);
	ROUGHNESS = mix(0.82, 0.96, m);
	SPECULAR = 0.3;
	AO = mix(1.0, 0.55, m);
	AO_LIGHT_AFFECT = 0.3;

	// bump from the joint profile, fading with distance so it never shimmers
	float e = 0.0025;
	float h0 = height_at(uv);
	float dx = (height_at(uv + vec2(e, 0.0)) - h0) / e;
	float dy = (height_at(uv + vec2(0.0, e)) - h0) / e;
	float fade = clamp(1.0 - fw * 60.0, 0.0, 1.0);
	vec3 n = normalize(wn - (t1 * dx + t2 * dy) * 0.004 * fade);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
"""

const _PLANK := """
uniform vec3 tint : source_color = vec3(0.23, 0.145, 0.09);
uniform float board_w = 0.13;
uniform float board_l = 1.85;
uniform float rough = 0.5;
uniform float cc = 0.35;
uniform float cc_rough = 0.25;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(wp.z / board_w);
	float x = wp.x + hash12(vec2(row, 3.0)) * board_l;
	float col = floor(x / board_l);
	vec2 l = vec2(x - col * board_l, wp.z - row * board_w);
	float d = min(min(l.x, board_l - l.x), min(l.y, board_w - l.y));
	float fw = max(length(fwidth(wp.xz)), 0.0005);
	float gap = 1.0 - smoothstep(0.0012 - fw, 0.0012 + fw, d);
	float shade = mix(0.80, 1.18, hash12(vec2(row, col)));
	float warp = fbm(vec3(x * 1.3, wp.z * 18.0, row)) * 5.0;
	float lines = sin(wp.z * 260.0 + warp + row * 3.1);
	float fine = fbm(vec3(x * 6.0, wp.z * 320.0, row)) - 0.5;
	fine *= clamp(1.4 - fw * 300.0, 0.0, 1.0);
	lines *= clamp(1.4 - fw * 260.0, 0.0, 1.0);
	float v = lines * 0.07 + fine * 0.22 + (fbm(vec3(x * 0.8, wp.z * 4.0, row)) - 0.5) * 0.3;
	vec3 c = tint * shade * (1.0 + v * vec3(1.0, 0.95, 0.88));
	ALBEDO = mix(c, vec3(0.02, 0.015, 0.01), gap);
	ROUGHNESS = mix(rough, 0.95, gap);
	CLEARCOAT = cc * (1.0 - gap);
	CLEARCOAT_ROUGHNESS = cc_rough;
	AO = 1.0 - gap * 0.6;
}
"""


# Billiard cloth is a tight worsted weave you cannot see from standing height.
# What you do see is a flat, even colour with a soft velvet sheen where the
# light grazes it, faint drifts of shade from the nap, and chalk dust. So the
# weave is only suggested up close and fades out long before it could turn
# into a pattern, and everything is computed in world space: no tile, no seam.
const _CLOTH := """
uniform vec3 tint : source_color = vec3(0.07, 0.30, 0.20);
uniform float sheen = 0.55;
// the felt itself: a photograph of real cloth with its lighting taken out,
// 0.5 grey meaning "as it is", tiled in world space
uniform sampler2D felt : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float felt_size = 0.16;      // metres of cloth one tile covers
uniform float felt_strength = 0.85;
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// height folded in so the faces of the cushions do not streak
	vec2 p = wp.xz + wp.yy * vec2(0.83, 0.57);
	// broad, very gentle variation in the nap
	float broad = fbm(vec3(p * 1.6, 3.0)) - 0.5;
	float mid = fbm(vec3(p * 9.0, 7.0)) - 0.5;
	// two readings of the felt at different sizes and angles, so the repeat
	// of either one is lost in the other
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	float f1 = texture(felt, p / felt_size).r * 2.0;
	float f2 = texture(felt, q / (felt_size * 1.37) + vec2(0.37, 0.71)).r * 2.0;
	float fibre = mix(f1, f2, 0.4);
	fibre = pow(max(fibre, 0.0), felt_strength);
	float shade = (1.0 + broad * 0.10 + mid * 0.05) * fibre;
	// the odd pale smudge of chalk
	float chalk = smoothstep(0.78, 0.9, fbm(vec3(p * 3.1, 11.0))) * 0.05;
	ALBEDO = clamp(tint * shade + vec3(chalk * 0.6), 0.0, 1.0);
	ROUGHNESS = clamp(0.93 + (fibre - 1.0) * 0.08, 0.8, 1.0);
	SPECULAR = 0.15;
	RIM = sheen;
	RIM_TINT = 0.4;
}
"""


static func cloth_mat(tint: Color, sheen := 0.3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("cloth", _CLOTH, true)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sheen", sheen)
	m.set_shader_parameter("felt", felt_texture())
	return m


# The felt detail map, made from a photo of real cloth (see README).
static func felt_texture() -> Texture2D:
	if not _cache.has("felt"):
		var tex: Texture2D = load("res://textures/cloth_detail.png")
		if tex == null:
			# a flat grey, so the cloth still draws if the file is missing
			var img := Image.create(4, 4, false, Image.FORMAT_L8)
			img.fill(Color(0.5, 0.5, 0.5))
			tex = ImageTexture.create_from_image(img)
		_cache.felt = tex
	return _cache.felt


static func _shader(key: String, body: String, two_sided := false) -> Shader:
	var k := key + ("_2s" if two_sided else "")
	if _cache.has(k):
		return _cache[k]
	var sh := Shader.new()
	var modes := "cull_disabled" if two_sided else "cull_back"
	sh.code = "shader_type spatial;\nrender_mode %s;\n%s\n%s" % [modes, _NOISE, body]
	_cache[k] = sh
	return sh


# Wood in world space. `rings` keeps the scale the old texture generator used;
# `axis` is the direction the grain runs.
static func wood_mat(base: Color, rough := 0.4, contrast := 0.24, rings := 0.07,
		axis := Vector3.RIGHT, two_sided := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("wood", _WOOD, two_sided)
	m.set_shader_parameter("tint", base)
	m.set_shader_parameter("contrast", contrast)
	m.set_shader_parameter("ring_freq", rings * 700.0)
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("rough", rough)
	return m


static func set_clearcoat(m: ShaderMaterial, amount: float, rough: float) -> void:
	m.set_shader_parameter("cc", amount)
	m.set_shader_parameter("cc_rough", rough)


static func brick_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("brick", _BRICK)
	return m


static func plank_mat(base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("plank", _PLANK)
	m.set_shader_parameter("tint", base)
	return m


static func wood_texture(base: Color, contrast := 0.24, rings := 0.085) -> ImageTexture:
	var s := 512
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 3301
	n.frequency = 0.012
	var fine := FastNoiseLite.new()
	fine.seed = 77
	fine.frequency = 0.35
	for y in s:
		for x in s:
			var warp := n.get_noise_2d(float(x), float(y)) * 26.0
			var g := sin((float(y) + warp) * rings)
			g = pow(absf(g), 0.45) * signf(g)
			var v := g * contrast * 0.5 + fine.get_noise_2d(float(x) * 3.0, float(y)) * 0.05
			var c := base
			c.r = clampf(c.r * (1.0 + v), 0.0, 1.0)
			c.g = clampf(c.g * (1.0 + v * 0.92), 0.0, 1.0)
			c.b = clampf(c.b * (1.0 + v * 0.8), 0.0, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Material helpers
# ---------------------------------------------------------------------------

static func mat(col: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	return m


static func glow_mat(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func textured(tex: Texture2D, rough := 0.7, uv := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_scale = uv
	return m
