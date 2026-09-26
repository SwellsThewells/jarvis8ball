class_name PoolBar
extends Node3D

# The bar as something you use. Two little cards stand on the counter in front
# of the bartender; look at one and click to order. He pours it and slides it
# down to you. Then it's yours to deal with: hold the button to pick it up,
# lift it (mouse up) to your mouth and tip it back, let go to put it down, or
# to drop it if you've wandered off with it. For the best part of a minute
# afterwards the room isn't quite the room. None of it changes the game.

const DRINKS := {
	"blitz": {"name": "Blitzkraft", "price": 6, "liquid": Color(0.1, 0.75, 0.95), "glow": 0.45,
		"line": "One Blitzkraft. Zum Wohl!"},
	"wobbly": {"name": "Old Wobbly", "price": 4, "liquid": Color(0.4, 0.17, 0.05), "glow": 0.12,
		"line": "Old Wobbly. Steady as she goes."},
}
const EFFECT_LEN := 45.0
const EFFECT_IN := 3.0
const EFFECT_OUT := 10.0
const REACH := 1.5
const TOP := BarRoom.BAR_TOP_Y + 0.02
const SERVE_X := BarRoom.BAR_FRONT_X - 0.15
const POUR_X := BarRoom.BAR_FRONT_X - 0.5
const DRINK_TIME := 2.4          # seconds of tipping it back to empty a glass

var g                            # the game
var cam: Camera3D
var arm: PoolFPArm
var barkeep: PoolBartender
var _cards := {}                 # kind -> where its face is, world space

var glass: Node3D
var _liquid: MeshInstance3D
var _liquid_top := 0.1
var kind := ""
var state := ""                  # "", pouring, sliding, counter, held, setting, falling, clearing
var st_t := 0.0
var fill := 1.0
var raise := 0.0
var tilt := 0.0
var _from := Transform3D()
var _to := Transform3D()
var _fall_v := Vector3.ZERO
var _gulp_t := 0.0

var effect := ""
var effect_t := 0.0
var _hic_t := 5.0
var hic := 0.0                   # a hiccup's jolt, 1 fading to 0
var _greeted := 0
var _near_bar := false

var look_card := ""              # what your eyes are on this frame
var look_glass := false


func setup(game) -> void:
	g = game
	cam = g.cam
	arm = g.arm
	barkeep = PoolBartender.new()
	barkeep.name = "Bartender"
	add_child(barkeep)
	barkeep.build()
	barkeep.position = BarRoom.BARTENDER_AT
	barkeep.rotation.y = PI * 0.5
	_card("blitz", 0.02, _paint_card_blitz)
	_card("wobbly", 0.7, _paint_card_wobbly)


# A folded card standing on the counter, printed both sides.
func _card(k: String, z: float, draw: Callable) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("e8dcc4")
	m.roughness = 0.7
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.14)
	var x := BarRoom.BAR_FRONT_X - 0.2
	for side: float in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.transform = Transform3D(Basis(Vector3(0, 0, 1), 0.2 * side) * Basis(Vector3.UP, PI * 0.5 * side),
			Vector3(x + 0.014 * side, TOP + 0.067, z))
		add_child(mi)
	PoolPaint.into(self, Vector2i(220, 280), draw, m)
	_cards[k] = Vector3(x + 0.014, TOP + 0.067, z)


# ---------------------------------------------------------------------------
# Ordering
# ---------------------------------------------------------------------------

func order(k: String) -> void:
	if state != "":
		_barkeep_says("Finish that one first.", 2.0)
		return
	var d: Dictionary = DRINKS[k]
	if g.try_spend(int(d.price)):
		g.sound.play("till", Vector3(BarRoom.BAR_FRONT_X - 0.38, TOP + 0.1, BarRoom.BAR_Z0 + 0.45), 0.5)
		_barkeep_says(str(d.line), 2.6)
	else:
		_barkeep_says("Skint? Go on, this one's on the house.", 3.0)
	g.profile.add("drinks")
	kind = k
	state = "pouring"
	st_t = 0.0
	g.sound.ui("click")


func _barkeep_says(text: String, dur: float) -> void:
	g.hud.speak("barkeep", func(): return barkeep.head_w() + Vector3.UP * 0.28, [[0.0, text]], dur)


# The glass and what's in it, standing on its base at the origin.
func _make_glass(k: String) -> void:
	glass = Node3D.new()
	glass.name = "Drink"
	add_child(glass)
	var tall := k == "blitz"
	var r := 0.029 if tall else 0.039
	var h := 0.135 if tall else 0.085
	var rt := r * (1.1 if tall else 1.04)
	var prof := [[0.0, 0.0], [r * 0.93, 0.0], [r, 0.01], [rt, h], [rt - 0.003, h], [r - 0.004, 0.016], [0.0, 0.016]]
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.9, 0.95, 0.12)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.04
	gm.metallic_specular = 0.8
	gm.rim_enabled = true
	gm.rim = 0.25
	gm.cull_mode = BaseMaterial3D.CULL_BACK
	var gmi := MeshInstance3D.new()
	gmi.mesh = BarRoom._lathe(prof, 22)
	gmi.material_override = gm
	glass.add_child(gmi)

	var d: Dictionary = DRINKS[k]
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(d.liquid, 0.88)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.roughness = 0.08
	lm.emission_enabled = true
	lm.emission = d.liquid
	lm.emission_energy_multiplier = float(d.glow)
	var cm := CylinderMesh.new()
	cm.top_radius = (rt - 0.004) * 0.97
	cm.bottom_radius = (r - 0.005) * 0.97
	cm.height = 1.0
	cm.radial_segments = 18
	_liquid = MeshInstance3D.new()
	_liquid.mesh = cm
	_liquid.material_override = lm
	glass.add_child(_liquid)
	_liquid_top = h - 0.02
	if not tall:
		# a lump of ice in the rum
		var ice := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.028, 0.026, 0.028)
		ice.mesh = bm
		var im := StandardMaterial3D.new()
		im.albedo_color = Color(0.85, 0.92, 1.0, 0.45)
		im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		im.roughness = 0.1
		ice.material_override = im
		ice.position = Vector3(0.004, 0.05, 0.0)
		ice.rotation = Vector3(0.3, 0.5, 0.2)
		glass.add_child(ice)
	else:
		# a slice of lime on the rim
		var lime := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.02
		lc.bottom_radius = 0.02
		lc.height = 0.005
		lime.mesh = lc
		var lmm := StandardMaterial3D.new()
		lmm.albedo_color = Color("9ad24a")
		lmm.roughness = 0.5
		lime.material_override = lmm
		lime.position = Vector3(rt, h - 0.004, 0.0)
		lime.rotation = Vector3(0.0, 0.0, PI * 0.5)
		glass.add_child(lime)
	for mi in glass.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill = 1.0
	_set_fill()


func _set_fill() -> void:
	var hh := maxf(_liquid_top * fill, 0.0005)
	_liquid.scale = Vector3(1.0, hh, 1.0)
	_liquid.position = Vector3(0.0, 0.016 + hh * 0.5, 0.0)
	_liquid.visible = fill > 0.01


# The spot on the counter in front of wherever you're standing.
func _serve_spot() -> Vector3:
	var z := clampf(g.player.pos.y, BarRoom.BAR_Z0 + 0.7, 1.05)
	return Vector3(SERVE_X, TOP, z)


# ---------------------------------------------------------------------------
# In your hand
# ---------------------------------------------------------------------------

func holding() -> bool:
	return state == "held"


func can_grab() -> bool:
	return look_glass and state == "counter"


func grab() -> void:
	state = "held"
	st_t = 0.0
	raise = 0.0
	tilt = 0.0
	g.sound.play("clink", glass.global_position, 0.25)


# Mouse up lifts it, mouse down lowers it.
func lift(dy: float) -> void:
	raise = clampf(raise - dy * 0.0032, 0.0, 1.0)


# Let go: back on the bar if you're at it, on the floor if you're not.
func release() -> void:
	if state != "held":
		return
	arm.hide_arm()
	_from = glass.global_transform
	if _near_bar:
		state = "setting"
		st_t = 0.0
		var spot := Vector3(SERVE_X, TOP, clampf(_from.origin.z, BarRoom.BAR_Z0 + 0.5, 1.05))
		_to = Transform3D(Basis.IDENTITY, spot)
	else:
		drop()


func drop() -> void:
	if state != "held" and state != "setting":
		return
	arm.hide_arm()
	state = "falling"
	st_t = 0.0
	var fwd := -cam.global_transform.basis.z
	_fall_v = Vector3(fwd.x, 0.6, fwd.z) * 0.8


func _drunk() -> void:
	effect = kind
	effect_t = 0.0
	_hic_t = 3.0


# ---------------------------------------------------------------------------
# Each frame
# ---------------------------------------------------------------------------

func update(delta: float, can_look: bool) -> void:
	var eye: Vector3 = cam.global_position
	_near_bar = g.player.pos.x < BarRoom.BAR_FRONT_X + 0.95 and g.player.pos.y > BarRoom.BAR_Z0 - 0.2 \
		and g.player.pos.y < BarRoom.BAR_Z1 + 0.2
	# what you're looking at, if it's in reach
	look_card = ""
	look_glass = false
	if can_look and state != "held":
		for k in _cards:
			if _ray_hits(_cards[k], 0.075, REACH + 0.2):
				look_card = k
		if state == "counter" and _ray_hits(glass.global_position + Vector3.UP * 0.05, 0.075, REACH):
			look_glass = true
			look_card = ""

	# the bartender keeps an eye on you when you're about, on the drink while
	# he sends it down
	if state == "sliding":
		barkeep.look_at_w = glass.global_position
	elif eye.x < -1.0:
		barkeep.look_at_w = eye
	else:
		barkeep.look_at_w = null
	var at_counter := Vector2(g.player.pos.x - BarRoom.BAR_FRONT_X, g.player.pos.y - BarRoom.BARTENDER_AT.z).length() < 1.8
	if at_counter and _greeted == 0 and g.phase != g.Phase.MENU:
		_greeted = 1
		_barkeep_says("Evening. What'll it be?", 2.6)
	elif not at_counter and g.player.pos.x > -1.2:
		_greeted = 0

	st_t += delta
	match state:
		"pouring":
			if st_t > 1.2:
				_make_glass(kind)
				state = "sliding"
				st_t = 0.0
				_from = Transform3D(Basis.IDENTITY, Vector3(POUR_X, TOP, BarRoom.BARTENDER_AT.z))
				_to = Transform3D(Basis.IDENTITY, _serve_spot())
				glass.global_transform = _from
				g.sound.play("slide", _from.origin, 0.5)
		"sliding":
			var k := 1.0 - pow(1.0 - clampf(st_t / 0.8, 0.0, 1.0), 2.4)
			glass.global_transform = _from.interpolate_with(_to, k)
			if st_t >= 0.8:
				state = "counter"
				st_t = 0.0
		"counter":
			# empty and left standing: he clears it away
			if fill <= 0.0 and st_t > 2.2:
				state = "clearing"
				st_t = 0.0
				_from = glass.global_transform
				_to = Transform3D(Basis.IDENTITY, Vector3(POUR_X, TOP, BarRoom.BARTENDER_AT.z))
				if randf() < 0.5:
					_barkeep_says("Another?", 1.6)
		"clearing":
			var k := smoothstep(0.0, 1.0, st_t / 0.7)
			glass.global_transform = _from.interpolate_with(_to, k)
			if st_t >= 0.7:
				_clear()
		"held":
			tilt = move_toward(tilt, smoothstep(0.72, 1.0, raise) if fill > 0.0 else 0.0, delta * 2.6)
			arm.hold(raise, tilt)
			glass.global_transform = cam.global_transform * arm.glass_xf()
			if tilt > 0.55 and fill > 0.0:
				fill = maxf(0.0, fill - delta / DRINK_TIME)
				_gulp_t -= delta
				if _gulp_t <= 0.0:
					_gulp_t = 0.42
					g.sound.near_kind("gulp", -3.0)
				_set_fill()
				if fill <= 0.0:
					_drunk()
		"setting":
			var k := smoothstep(0.0, 1.0, st_t / 0.22)
			glass.global_transform = _from.interpolate_with(_to, k)
			if st_t >= 0.22:
				state = "counter"
				st_t = 0.0
				g.sound.play("clink", glass.global_position, 0.45)
		"falling":
			_fall_v.y -= 9.8 * delta
			var xf := glass.global_transform
			xf.origin += _fall_v * delta
			xf.basis = xf.basis.rotated(Vector3(1, 0, 0.3).normalized(), 7.0 * delta)
			glass.global_transform = xf
			if xf.origin.y <= 0.02:
				g.sound.play("smash", xf.origin, 1.0)
				_barkeep_says("Oi! Mind the glasses!", 2.0)
				_clear()

	# the drink working on you
	if effect != "":
		effect_t += delta
		if effect_t >= EFFECT_LEN:
			effect = ""
		elif effect == "wobbly" and PoolSettings.on("drink_fx"):
			_hic_t -= delta
			if _hic_t <= 0.0:
				_hic_t = randf_range(4.0, 9.0)
				hic = 1.0
				g.sound.near_kind("hic", -5.0)
	hic = move_toward(hic, 0.0, delta * 4.0)


func _clear() -> void:
	if glass != null:
		glass.queue_free()
	glass = null
	state = ""
	st_t = 0.0


func _ray_hits(p: Vector3, r: float, reach: float) -> bool:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var t := (p - from).dot(dir)
	if t < 0.05 or t > reach:
		return false
	return (from + dir * t).distance_to(p) < r


# How strongly the drink has hold of you right now, 0..1: coming on over a
# few seconds, a good while at full, then wearing off completely.
func amount() -> float:
	if effect == "" or not PoolSettings.on("drink_fx"):
		return 0.0
	var a := smoothstep(0.0, EFFECT_IN, effect_t)
	return a * (1.0 - smoothstep(EFFECT_LEN - EFFECT_OUT, EFFECT_LEN, effect_t))


func trip() -> float:
	return amount() if effect == "blitz" else 0.0


func wobble() -> float:
	return amount() if effect == "wobbly" else 0.0


# How far your head goes back as you tip the glass up.
func head_back() -> float:
	return tilt * 0.3 if state == "held" else 0.0


# ---------------------------------------------------------------------------
# The cards
# ---------------------------------------------------------------------------

func _card_base(c: PoolPaint.Canvas, ink: Color) -> void:
	var s := c.size
	c.draw_rect(Rect2(Vector2.ZERO, s), Color("efe5cf"))
	c.draw_rect(Rect2(Vector2(10, 10), s - Vector2(20, 20)), Color(ink, 0.9), false, 3.0)


func _paint_card_blitz(c: PoolPaint.Canvas) -> void:
	var s := c.size
	var ink := Color("12203a")
	_card_base(c, ink)
	c.draw_rect(Rect2(Vector2(10, 10), Vector2(s.x - 20, 96)), Color("12203a"))
	var f := c.font(PoolPaint.poster(), 800)
	c.draw_string(f, Vector2(0, 60), "BLITZ", HORIZONTAL_ALIGNMENT_CENTER, s.x, 44, Color("9fe8ff"))
	c.draw_string(f, Vector2(0, 94), "KRAFT", HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color("ffe14a"))
	var ctr := Vector2(s.x * 0.5, 165)
	var bolt := PackedVector2Array([Vector2(-10, -44), Vector2(18, -44), Vector2(4, -8), Vector2(22, -8),
		Vector2(-14, 48), Vector2(-2, 4), Vector2(-20, 4)])
	for i in bolt.size():
		bolt[i] += ctr
	c.draw_colored_polygon(bolt, Color("f2b01e"))
	c.draw_string(f, Vector2(0, s.y - 26), "$6", HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, ink)


func _paint_card_wobbly(c: PoolPaint.Canvas) -> void:
	var s := c.size
	var ink := Color("3a1a0a")
	_card_base(c, ink)
	c.draw_rect(Rect2(Vector2(10, 10), Vector2(s.x - 20, 96)), Color("5a2a10"))
	var f := c.font(PoolPaint.poster(), 800)
	c.draw_string(f, Vector2(0, 58), "OLD", HORIZONTAL_ALIGNMENT_CENTER, s.x, 36, Color("f2dcb0"))
	c.draw_string(f, Vector2(0, 94), "WOBBLY", HORIZONTAL_ALIGNMENT_CENTER, s.x, 32, Color("f2dcb0"))
	# a tumbler of rum, leaning
	var ctr := Vector2(s.x * 0.5, 168)
	var cup := PackedVector2Array([Vector2(-26, -30), Vector2(26, -30), Vector2(20, 34), Vector2(-20, 34)])
	var rum := PackedVector2Array([Vector2(-23, -4), Vector2(23, -4), Vector2(20, 34), Vector2(-20, 34)])
	for i in 4:
		cup[i] = ctr + cup[i].rotated(0.15)
		rum[i] = ctr + rum[i].rotated(0.15)
	c.draw_colored_polygon(rum, Color("7a3a12"))
	c.draw_polyline(PackedVector2Array([cup[0], cup[3], cup[2], cup[1]]), ink, 3.0, true)
	c.draw_string(f, Vector2(0, s.y - 26), "$4", HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, ink)
