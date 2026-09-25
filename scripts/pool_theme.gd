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
