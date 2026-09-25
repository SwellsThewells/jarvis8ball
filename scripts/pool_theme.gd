class_name PoolTheme
extends RefCounted

# One palette for the whole game: aged brass, cream chalk-dust, tavern rust.
const BRASS := Color("c9973f")
const CREAM := Color("ece2cf")
const CHALK := Color("6f9ab5")
const RUST := Color("c25a33")
const MOSS := Color("8fbf6a")
const INK := Color(0.055, 0.043, 0.031, 0.80)
const DIM := Color(0.92, 0.89, 0.82, 0.45)
const TIP := Color("2c4a6e")

# Menus and signage
const GOLD := Color("f2c14e")
const FELT := Color("1f8a4c")
const FELT_HI := Color("2fb265")
const WHITE := Color("f7f3ea")
const MUTED := Color(0.97, 0.95, 0.90, 0.58)
const SHADE := Color(0.035, 0.04, 0.038, 0.86)
const LINE := Color(1.0, 1.0, 1.0, 0.10)
const DANGER := Color("d9534f")

# The flat, glassy look every panel and control shares: a dark sheet with a
# hairline edge, flat buttons, slim switches and sliders.
const PANEL := Color(0.043, 0.047, 0.051, 0.9)
const RAISED := Color(1.0, 1.0, 1.0, 0.04)
const HAIR := Color(1.0, 1.0, 1.0, 0.08)
const FAINT := Color(0.97, 0.95, 0.90, 0.36)
const ON_GOLD := Color(0.09, 0.07, 0.03)     # text on a gold button

static var _fonts: Dictionary = {}


# Bahnschrift ships with Windows 10 and later and is the sort of hard-edged
# sign lettering you see over a pool hall; anywhere it is missing the next
# face on the list stands in.
static func font(weight := 400, condensed := false, spacing := 0) -> Font:
	var key := "%d:%s:%d" % [weight, condensed, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Helvetica Neue", "Arial"])
	sf.font_weight = weight
	sf.font_stretch = 75 if condensed else 100
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var f: Font = sf
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = sf
		fv.spacing_glyph = spacing
		f = fv
	_fonts[key] = f
	return f


static func box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), border_w := 0,
		shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.4)
	return sb


# ---------------------------------------------------------------------------
# Drawing the shared pieces. Each takes the CanvasItem to draw on, so menus
# and the in-game overlay look like one thing.
# ---------------------------------------------------------------------------

# A sheet: soft shadow under a dark, faintly see-through panel with a hairline
# edge. `accent` draws a thin coloured line along the top.
static func panel(ci: CanvasItem, r: Rect2, accent := Color(0, 0, 0, 0), radius := 16) -> void:
	ci.draw_style_box(box(Color(0, 0, 0, 0.32), radius + 4), Rect2(r.position + Vector2(0, 10), r.size).grow(2))
	ci.draw_style_box(box(PANEL, radius, HAIR, 1), r)
	if accent.a > 0.0:
		ci.draw_rect(Rect2(r.position + Vector2(radius, 0), Vector2(r.size.x - radius * 2.0, 2)), accent)


# Small spaced capitals over a group of things.
static func caps(ci: CanvasItem, pos: Vector2, s: String, col := FAINT, sz := 12, width := -1.0,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	ci.draw_string(font(700, false, 3), pos, s, align, width, sz, col)


static func divider(ci: CanvasItem, x0: float, x1: float, y: float) -> void:
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), HAIR, 1.0)


# A flat button. kind: "primary" (gold, dark text), "secondary" (outlined),
# "ghost" (text only until you're over it). `a` is hover, 0..1.
static func button(ci: CanvasItem, r: Rect2, label: String, kind := "primary", a := 0.0, enabled := true,
		fs := 18) -> void:
	var bg: Color
	var edge := Color(0, 0, 0, 0)
	var txt: Color
	match kind:
		"primary":
			bg = GOLD.lerp(Color("ffd978"), a * 0.6)
			txt = ON_GOLD
		"secondary":
			bg = Color(1, 1, 1, 0.05 + a * 0.06)
			edge = Color(1, 1, 1, 0.14 + a * 0.2)
			txt = WHITE
		_:
			bg = Color(1, 1, 1, a * 0.07)
			txt = MUTED.lerp(WHITE, a)
	if not enabled:
		bg = Color(1, 1, 1, 0.04)
		edge = HAIR
		txt = FAINT
	var radius := int(minf(12.0, r.size.y * 0.5))
	ci.draw_style_box(box(bg, radius, edge, 1 if edge.a > 0.0 else 0), r)
	var f := font(700, true, 3)
	ci.draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), label.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, txt)


# An on/off switch, 46 by 26.
static func switch(ci: CanvasItem, at: Vector2, on: bool, a := 0.0) -> void:
	var r := Rect2(at, Vector2(46, 26))
	var bg := GOLD if on else Color(1, 1, 1, 0.14 + a * 0.08)
	ci.draw_style_box(box(bg, 13), r)
	var kx := r.end.x - 13.0 if on else r.position.x + 13.0
	ci.draw_circle(Vector2(kx, r.position.y + 13.0), 9.5, ON_GOLD if on else WHITE, true, -1.0, true)


# A slim slider along `track` (its height is ignored), filled to k.
static func slider(ci: CanvasItem, track: Rect2, k: float, a := 0.0) -> void:
	var t := Rect2(Vector2(track.position.x, track.get_center().y - 2.0), Vector2(track.size.x, 4))
	ci.draw_style_box(box(Color(1, 1, 1, 0.12), 2), t)
	k = clampf(k, 0.0, 1.0)
	if k > 0.0:
		ci.draw_style_box(box(GOLD, 2), Rect2(t.position, Vector2(maxf(4.0, t.size.x * k), 4)))
	var knob := Vector2(t.position.x + t.size.x * k, t.get_center().y)
	ci.draw_circle(knob + Vector2(0, 1.5), 9.0 + a * 1.5, Color(0, 0, 0, 0.35), true, -1.0, true)
	ci.draw_circle(knob, 8.0 + a * 1.5, WHITE, true, -1.0, true)


# A pill with a word in it: "SECRET", "COMING SOON", "EQUIPPED".
static func badge(ci: CanvasItem, right_top: Vector2, s: String, col := GOLD) -> float:
	var f := font(800, false, 2)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0
	var r := Rect2(right_top - Vector2(w, 0), Vector2(w, 22))
	ci.draw_style_box(box(Color(col.r, col.g, col.b, 0.14), 11, Color(col.r, col.g, col.b, 0.55), 1), r)
	ci.draw_string(f, Vector2(r.position.x, r.position.y + 15.5), s, HORIZONTAL_ALIGNMENT_CENTER, w, 11, col)
	return w


# A key, the way the controls are shown: outlined, not a white block.
static func keycap(ci: CanvasItem, at: Vector2, label: String, h := 28.0, fs := 12) -> float:
	var f := font(800)
	var w := maxf(h, f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0)
	var r := Rect2(at, Vector2(w, h))
	ci.draw_style_box(box(Color(1, 1, 1, 0.08), 6, Color(1, 1, 1, 0.28), 1), r)
	ci.draw_string(f, Vector2(r.position.x, r.position.y + h * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER,
		w, fs, WHITE)
	return w
