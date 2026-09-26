class_name PoolHud
extends CanvasLayer

# What sits over the table while you play. Kept to the edges and kept small:
# the two players and their balls at the top, a message when something
# happens, the power of the stroke while you are pulling it, where the tip is
# on the cue ball, and a line of hints along the bottom.

signal menu_confirmed()
signal rack_again()
signal leave_pressed()


var score: ScoreBar
var toast: Toast
var power: PowerColumn
var tip: TipBall
var result: ResultCard
var pause: PauseCard
var hints: HintBar
var root: Control
var crosshair: Crosshair
var punch_meter: PunchMeter
var ko_shade: KoShade
var bubbles: Bubbles
var cash: Cash


static func _f(weight := 400, condensed := false, spacing := 0) -> Font:
	return PoolTheme.font(weight, condensed, spacing)


# A small dot in the middle of your view, only when your eyes are choosing
# something: where the cue ball goes, or which pocket you are calling.
class Crosshair extends Control:
	var ring := false

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 4.0, Color(0.0, 0.0, 0.0, 0.45))
		draw_circle(c, 2.4, Color(1.0, 1.0, 1.0, 0.9))
		if ring:
			draw_arc(c, 13.0, 0.0, TAU, 32, Color(0.45, 0.75, 1.0, 0.85), 2.0, true)


# ---------------------------------------------------------------------------


# The score bar across the top: you on the left, the house player on the
# right, the balls each of you has left, and a bar under whoever is at the
# table. Small and plain, like the score bug on a broadcast.
class ScoreBar extends Control:
	var names := ["YOU", "HOUSE"]
	var notes := ["", ""]
	var ids: Array = [[], []]
	var active := 0
	var thinking := false
	var clock := -1.0             # shot clock, seconds left; -1 when there isn't one
	var clock_side := 0
	var _slide := 0.0
	var _t := 0.0
	var logo: Texture2D

	func _process(delta: float) -> void:
		_t += delta
		_slide = lerpf(_slide, float(active), 1.0 - exp(-10.0 * delta))
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var half := w * 0.5
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.3), 16), Rect2(Vector2(0, 5), size).grow(1))
		draw_style_box(PoolTheme.box(PoolTheme.PANEL, 14, PoolTheme.HAIR, 1), Rect2(Vector2.ZERO, size))
		# whose turn: their half lights up a little, with a gold line under it
		var bar_w := half - 34.0
		var bx := lerpf(14.0, half + 20.0, _slide)
		draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, 0.06), 10), Rect2(Vector2(bx - 8.0, 4.0), Vector2(bar_w + 16.0, h - 8.0)))
		draw_style_box(PoolTheme.box(PoolTheme.GOLD, 1), Rect2(Vector2(bx, h - 3.0), Vector2(bar_w, 2.0)))
		var nf := PoolHud._f(800, true, 1)
		var sf := PoolHud._f(700, false, 2)
		for side in 2:
			var on: bool = side == active
			var nm: String = names[side]
			var note: String = notes[side]
			if side == 1 and thinking:
				note = "thinking" + ".".repeat(int(_t * 2.5) % 4)
			var ncol := PoolTheme.WHITE if on else Color(1, 1, 1, 0.45)
			var tcol := PoolTheme.GOLD if on else PoolTheme.FAINT
			var balls: Array = ids[side]
			var step := 17.0
			if side == 0:
				draw_string(nf, Vector2(18, 25), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ncol)
				draw_string(sf, Vector2(18, 41), note.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tcol)
				for i in balls.size():
					_ball(Vector2(half - 40.0 - float(balls.size() - 1 - i) * step, h * 0.5 - 1.0), balls[i], on)
			else:
				var nw := nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
				draw_string(nf, Vector2(w - 18 - nw, 25), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ncol)
				var tw := sf.get_string_size(note.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				draw_string(sf, Vector2(w - 18 - tw, 41), note.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tcol)
				for i in balls.size():
					_ball(Vector2(half + 40.0 + float(i) * step, h * 0.5 - 1.0), balls[i], on)
		# the shot clock, under whoever's shot it is
		if clock >= 0.0:
			var secs := int(ceil(clock))
			var ccol := PoolTheme.DANGER if clock < 5.5 else PoolTheme.WHITE
			var ctext := "%d" % secs
			var cf := PoolHud._f(800, true)
			var cw := cf.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0
			var cx := half - 60.0 - cw if clock_side == 0 else half + 60.0
			var cr := Rect2(Vector2(cx, h + 8.0), Vector2(cw, 30))
			draw_style_box(PoolTheme.box(Color(PoolTheme.PANEL, 0.9), 15, Color(ccol, 0.5), 1), cr)
			draw_string(cf, Vector2(cr.position.x, cr.position.y + 23), ctext, HORIZONTAL_ALIGNMENT_CENTER, cw, 22, ccol)
		# the J in the middle
		var c := Vector2(half, h * 0.5 - 1.0)
		draw_circle(c, 17.0, Color(0.03, 0.033, 0.036), true, -1.0, true)
		draw_arc(c, 17.0, 0.0, TAU, 40, PoolTheme.HAIR, 1.0, true)
		if logo != null:
			draw_texture_rect(logo, Rect2(c - Vector2(13, 13), Vector2(26, 26)), false)

	func _ball(c: Vector2, id: int, on: bool) -> void:
		var col: Color = PoolArt.BALL_COLORS.get(id, Color.WHITE)
		var r := 7.0
		var a := 1.0 if on else 0.6
		if id >= 9:
			draw_circle(c, r, Color(PoolArt.IVORY, a))
			draw_rect(Rect2(c - Vector2(r * 0.95, r * 0.42), Vector2(r * 1.9, r * 0.84)), Color(col, a))
		else:
			draw_circle(c, r, Color(col, a))
		draw_circle(c, r * 0.45, Color(PoolArt.IVORY, a))
		var txt := "J" if id == PoolSim.EIGHT else str(id)
		var f := PoolHud._f(800)
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
		draw_string(f, c + Vector2(-sz.x * 0.5, 2.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.08, 0.07, 0.06, a))


# One short line under the score bar when something happens. Small, gone in
# a couple of seconds; a newer one simply replaces it.
class Toast extends Control:
	var text := ""
	var tone := PoolTheme.WHITE
	var life := 0.0
	const TOTAL := 2.6

	func show_text(t: String, c: Color) -> void:
		text = t
		tone = c
		life = TOTAL
		queue_redraw()

	func _process(delta: float) -> void:
		if life > 0.0:
			life -= delta
			if life <= 0.0:
				text = ""
			queue_redraw()

	func _draw() -> void:
		if text == "":
			return
		var f := PoolHud._f(600)
		var fs := 15
		var a: float = clampf(life / 0.35, 0.0, 1.0)
		var appear: float = clampf((TOTAL - life) / 0.15, 0.0, 1.0)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bw := w + 44.0
		var y := (1.0 - appear) * -6.0
		var box := Rect2(Vector2((size.x - bw) * 0.5, y), Vector2(bw, 32.0))
		draw_style_box(PoolTheme.box(Color(PoolTheme.PANEL, 0.9 * a), 16, Color(1, 1, 1, 0.08 * a), 1), box)
		draw_circle(Vector2(box.position.x + 17.0, y + 16.0), 3.5, Color(tone, a), true, -1.0, true)
		draw_string(f, Vector2(box.position.x + 29.0, y + 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.96, 0.95, 0.92, a))


# Speech bubbles, pinned over whoever is talking. They pop in, follow the
# speaker round the room, shrink with distance, and go when the line ends.
class Bubbles extends Control:
	var cam: Camera3D
	var items: Array = []    # {key, anchor: Callable -> Vector3, segs: [[t, text]], t, dur}

	func say(key: String, anchor: Callable, segs: Array, dur: float) -> void:
		for i in range(items.size() - 1, -1, -1):
			if items[i].key == key:
				items.remove_at(i)
		items.append({"key": key, "anchor": anchor, "segs": segs, "t": 0.0, "dur": dur})

	func clear() -> void:
		items.clear()

	func _process(delta: float) -> void:
		for i in range(items.size() - 1, -1, -1):
			items[i].t += delta
			if items[i].t > items[i].dur:
				items.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		if cam == null:
			return
		var f := PoolHud._f(700)
		for it in items:
			var text := ""
			for seg in it.segs:
				if float(seg[0]) <= float(it.t):
					text = str(seg[1])
			if text == "":
				continue
			var at: Vector3 = (it.anchor as Callable).call()
			if cam.is_position_behind(at):
				continue
			var p := cam.unproject_position(at)
			var dist := cam.global_position.distance_to(at)
			var sc := clampf(2.6 / maxf(dist, 0.1), 0.7, 1.25)
			var t: float = it.t
			var pop := 1.0 - pow(1.0 - clampf(t / 0.18, 0.0, 1.0), 3.0)
			pop *= 1.0 + 0.12 * sin(clampf(t / 0.3, 0.0, 1.0) * PI)
			var fade := clampf((float(it.dur) - t) / 0.25, 0.0, 1.0)
			var fs := int(round(21.0 * sc))
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pad := Vector2(15, 10) * sc
			var box := Vector2(tw, fs * 1.05) + pad * 2.0
			box *= pop
			# a speaker just out of frame keeps his bubble at the edge
			var tip := Vector2(clampf(p.x, box.x * 0.5 + 12.0, size.x - box.x * 0.5 - 12.0),
				clampf(p.y, box.y + 72.0, size.y - 60.0))
			var r := Rect2(tip - Vector2(box.x * 0.5, box.y + 12.0 * sc), box)
			var bg := Color(0.98, 0.97, 0.94, 0.96 * fade)
			var shadow := Color(0, 0, 0, 0.35 * fade)
			draw_style_box(PoolTheme.box(shadow, int(14 * sc)), Rect2(r.position + Vector2(0, 3), r.size))
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-8, -13) * sc, tip + Vector2(8, -13) * sc, tip + Vector2(0, 1)]), bg)
			draw_style_box(PoolTheme.box(bg, int(14 * sc)), r)
			if pop > 0.85:
				draw_string(f, r.position + Vector2(pad.x, pad.y + fs * 0.82), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(0.1, 0.09, 0.08, fade))


# Money in your pocket, while you're near the bar or it has just changed.
class Cash extends Control:
	var amount := 0
	var show_for := 0.0
	var near := false
	var _vis := 0.0

	func _process(delta: float) -> void:
		show_for = maxf(0.0, show_for - delta)
		_vis = move_toward(_vis, 1.0 if (near or show_for > 0.0) else 0.0, delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		if _vis <= 0.001:
			return
		var f := PoolHud._f(800, true, 1)
		var txt := "$%d" % amount
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var r := Rect2(Vector2(0, 4), Vector2(w + 50, 38))
		draw_style_box(PoolTheme.box(Color(PoolTheme.PANEL, 0.9 * _vis), 19, Color(1, 1, 1, 0.08 * _vis), 1), r)
		draw_circle(Vector2(20, 23), 10, Color(PoolTheme.GOLD, _vis), true, -1.0, true)
		draw_circle(Vector2(20, 23), 6.5, Color(0.8, 0.6, 0.2, _vis), true, -1.0, true)
		draw_string(f, Vector2(38, 31), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, _vis))


# A fist, and how long until it's ready again.
class PunchMeter extends Control:
	var cd := 0.0          # fraction of the cooldown left
	var hot := false       # your eye is on somebody you could hit
	var _vis := 0.0

	func _process(delta: float) -> void:
		var want := 1.0 if hot or cd > 0.0 else 0.0
		_vis = move_toward(_vis, want, delta * 4.0)
		if _vis > 0.0 or want > 0.0:
			queue_redraw()

	func _draw() -> void:
		if _vis <= 0.001:
			return
		var a := _vis
		var c := Vector2(22, size.y * 0.5)
		draw_circle(c, 20.0, Color(PoolTheme.PANEL, 0.9 * a), true, -1.0, true)
		draw_arc(c, 20.0, 0.0, TAU, 40, Color(1, 1, 1, 0.08 * a), 1.0, true)
		var ready := cd <= 0.0
		var col := Color(PoolTheme.GOLD, a) if ready else Color(1, 1, 1, 0.35 * a)
		if not ready:
			draw_arc(c, 17.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cd), 40, Color(PoolTheme.GOLD, 0.9 * a), 3.0, true)
		# the fist: knuckles over a palm
		draw_style_box(PoolTheme.box(col, 3), Rect2(c + Vector2(-7, -3), Vector2(14, 10)))
		for k in 4:
			draw_circle(c + Vector2(-5.2 + float(k) * 3.5, -4.0), 2.0, col)
		draw_style_box(PoolTheme.box(col, 2), Rect2(c + Vector2(-9, -1), Vector2(4, 6)))
		var f := PoolHud._f(700, false, 1)
		var label := "PUNCH" if ready else "%ds" % int(ceil(cd * 30.0))
		draw_string(f, Vector2(50, size.y * 0.5 + 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.85 * a))


# When you get decked: a red flash that fades, and the edges darken while
# you're on the floor.
class KoShade extends Control:
	var flash := 0.0
	var down := 0.0

	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 1.6)
		queue_redraw()

	func _draw() -> void:
		if flash <= 0.0 and down <= 0.0:
			return
		var w := size.x
		var h := size.y
		var edge := Color(0.45, 0.0, 0.0, 0.55 * flash + 0.35 * down)
		var clear := Color(edge, 0.0)
		var bands := 90.0
		# four soft edges, each a gradient from the side of the screen inwards
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.22), Vector2(0, h * 0.22)]),
			PackedColorArray([edge, edge, clear, clear]))
		draw_polygon(PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(w, h * 0.78), Vector2(0, h * 0.78)]),
			PackedColorArray([edge, edge, clear, clear]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.18, 0), Vector2(w * 0.18, h), Vector2(0, h)]),
			PackedColorArray([edge, clear, clear, edge]))
		draw_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w * 0.82, 0), Vector2(w * 0.82, h), Vector2(w, h)]),
			PackedColorArray([edge, clear, clear, edge]))
		if flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.05, 0.02, 0.18 * flash * bands / 90.0))

class PowerColumn extends Control:
	var value := 0.0
	var armed := false

	func _draw() -> void:
		if not armed:
			return
		var w := size.x
		var h := size.y
		draw_style_box(PoolTheme.box(PoolTheme.PANEL, 13, PoolTheme.HAIR, 1), Rect2(Vector2.ZERO, size))
		var v: float = clampf(value, 0.0, 1.0)
		var inner := Rect2(Vector2(9, 9), Vector2(w - 18, h - 18))
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.08), 4), inner)
		var fill := inner.size.y * v
		if fill > 1.0:
			var steps := int(fill)
			for i in steps:
				var f := float(i) / maxf(inner.size.y, 1.0)
				var c := PoolTheme.FELT_HI.lerp(PoolTheme.GOLD, clampf(f * 1.6, 0.0, 1.0)).lerp(PoolTheme.DANGER, clampf((f - 0.6) * 2.5, 0.0, 1.0))
				var yy := inner.end.y - float(i)
				draw_line(Vector2(inner.position.x, yy), Vector2(inner.end.x, yy), c, 1.0)
		var f2 := PoolHud._f(800, true)
		draw_string(f2, Vector2(-20, h + 30), "%d" % int(round(v * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, w + 40, 22, PoolTheme.WHITE)
		PoolTheme.caps(self, Vector2(-20, h + 46), "POWER", PoolTheme.FAINT, 9, w + 40, HORIZONTAL_ALIGNMENT_CENTER)


# Where the tip meets the cue ball. Small in the corner while you shoot; big
# while you hold the right button and move the tip about.
class TipBall extends Control:
	var spin := Vector2.ZERO
	var focus := 0.0
	var want_focus := false
	var shown := false
	const LIMIT := 0.62

	func _process(delta: float) -> void:
		focus = lerpf(focus, 1.0 if want_focus else 0.0, 1.0 - exp(-12.0 * delta))
		queue_redraw()

	func _draw() -> void:
		if not shown and focus < 0.02:
			return
		var r: float = lerpf(34.0, 92.0, focus)
		var c := Vector2(size.x - r - 8.0, size.y - r - 8.0)
		draw_circle(c + Vector2(0, 3), r + 3.0, Color(0, 0, 0, 0.45))
		var steps := 22
		for i in steps:
			var f := float(i) / float(steps)
			var rr: float = r * (1.0 - f)
			var shade: float = lerpf(0.62, 1.0, pow(f, 0.6))
			draw_circle(c + Vector2(-r + rr, -r + rr) * 0.28, rr, Color(0.96 * shade, 0.94 * shade, 0.88 * shade))
		var grid := Color(0.3, 0.28, 0.25, 0.35)
		draw_line(c - Vector2(r * 0.8, 0), c + Vector2(r * 0.8, 0), grid, 1.0)
		draw_line(c - Vector2(0, r * 0.8), c + Vector2(0, r * 0.8), grid, 1.0)
		draw_arc(c, r * (LIMIT / 0.7), 0.0, TAU, 48, Color(PoolTheme.RUST.r, PoolTheme.RUST.g, PoolTheme.RUST.b, 0.35 * focus), 1.0, true)
		var p := c + Vector2(spin.x, -spin.y) / 0.7 * r
		var tr: float = lerpf(5.5, 11.0, focus)
		draw_circle(p, tr + 1.5, Color(0.05, 0.08, 0.12, 0.7))
		draw_circle(p, tr, Color("3d6fa3"))
		if focus > 0.3:
			var f := PoolHud._f(700, false, 1)
			var label := _describe()
			var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(f, Vector2(c.x - w * 0.5, c.y - r - 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(1, 1, 1, focus))

	func _describe() -> String:
		var parts: Array[String] = []
		if spin.y > 0.12:
			parts.append("FOLLOW")
		elif spin.y < -0.12:
			parts.append("DRAW")
		if spin.x > 0.12:
			parts.append("RIGHT")
		elif spin.x < -0.12:
			parts.append("LEFT")
		if parts.is_empty():
			return "CENTRE BALL"
		return " + ".join(parts)


# Key hints along the bottom, drawn as keycaps.
class HintBar extends Control:
	var items: Array = []

	func _draw() -> void:
		if items.is_empty():
			return
		var kf := PoolHud._f(800)
		var tf := PoolHud._f(500)
		var total := 0.0
		var widths: Array = []
		for it in items:
			var kw := maxf(26.0, kf.get_string_size(str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0)
			var tw := tf.get_string_size(str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			widths.append([kw, tw])
			total += kw + 10.0 + tw + 28.0
		total -= 28.0
		var x := (size.x - total) * 0.5
		var y := size.y * 0.5
		draw_style_box(PoolTheme.box(Color(PoolTheme.PANEL, 0.82), 19, PoolTheme.HAIR, 1),
			Rect2(Vector2(x - 8.0, y - 19.0), Vector2(total + 26.0, 38.0)))
		for i in items.size():
			var kw: float = widths[i][0]
			var tw: float = widths[i][1]
			PoolTheme.keycap(self, Vector2(x, y - 13), str(items[i][0]), 26.0, 11)
			draw_string(tf, Vector2(x + kw + 10.0, y + 5), str(items[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1, 0.86))
			x += kw + 10.0 + tw + 28.0


class CardButtons extends Control:
	signal chosen(id: String)
	var buttons: Array = []       # [id, label, primary, enabled]
	var rects: Array = []
	var hover := Vector2(-100, -100)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			hover = ev.position
			queue_redraw()
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			for i in rects.size():
				if (rects[i] as Rect2).has_point(ev.position):
					if (buttons[i] as Array).size() < 4 or bool(buttons[i][3]):
						chosen.emit(str(buttons[i][0]))
					return
			_clicked_away()

	func _clicked_away() -> void:
		pass

	func _draw_buttons(y: float, w: float) -> void:
		rects.clear()
		var n := buttons.size()
		var bw := w
		var bh := 54.0
		for i in n:
			var r := Rect2(Vector2((size.x - bw) * 0.5, y + float(i) * (bh + 10.0)), Vector2(bw, bh))
			rects.append(r)
			var primary: bool = buttons[i][2]
			var enabled: bool = (buttons[i] as Array).size() < 4 or bool(buttons[i][3])
			PoolTheme.button(self, r, str(buttons[i][1]), "primary" if primary else "secondary",
				1.0 if r.has_point(hover) and enabled else 0.0, enabled, 18)


class PauseCard extends CardButtons:
	func _ready() -> void:
		super._ready()
		buttons = [["resume", "RESUME", true], ["restart", "RESTART RACK", false], ["menu", "MAIN MENU", false]]

	func _clicked_away() -> void:
		chosen.emit("resume")

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.6))
		var cw := 400.0
		var ch := 346.0
		var card := Rect2(Vector2((size.x - cw) * 0.5, (size.y - ch) * 0.5), Vector2(cw, ch))
		PoolTheme.panel(self, card, Color(0, 0, 0, 0), 18)
		draw_string(PoolHud._f(800, true, 1), Vector2(card.position.x, card.position.y + 72), "PAUSED",
			HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 42, PoolTheme.WHITE)
		PoolTheme.caps(self, Vector2(card.position.x, card.position.y + 100), "ESC TO RESUME", PoolTheme.FAINT, 11,
			card.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_buttons(card.position.y + 128.0, cw - 64.0)


class ResultCard extends CardButtons:
	var title := ""
	var sub := ""
	var won := false
	var note := ""

	func _ready() -> void:
		super._ready()
		buttons = [["again", "PLAY AGAIN", true], ["leave", "MAIN MENU", false]]

	func _draw() -> void:
		if title == "":
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
		var cw := 480.0
		var ch := 330.0
		var card := Rect2(Vector2((size.x - cw) * 0.5, (size.y - ch) * 0.5), Vector2(cw, ch))
		var tone := PoolTheme.GOLD if won else PoolTheme.DANGER
		PoolTheme.panel(self, card, tone, 18)
		PoolTheme.caps(self, Vector2(card.position.x, card.position.y + 46), "VICTORY" if won else "DEFEAT", tone, 12,
			card.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		draw_string(PoolHud._f(800, true, 1), Vector2(card.position.x, card.position.y + 98), title.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 48, PoolTheme.WHITE)
		draw_string(PoolHud._f(500), Vector2(card.position.x + 32, card.position.y + 132), sub,
			HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 64, 16, Color(1, 1, 1, 0.7))
		if note != "":
			PoolTheme.caps(self, Vector2(card.position.x, card.position.y + 162), note.to_upper(), PoolTheme.GOLD, 11,
				card.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_buttons(card.position.y + 184.0, cw - 64.0)


# ---------------------------------------------------------------------------

func setup() -> void:
	layer = 1
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	ko_shade = KoShade.new()
	ko_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ko_shade)

	score = ScoreBar.new()
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	score.logo = load("res://icon.png")
	root.add_child(score)

	toast = Toast.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)

	punch_meter = PunchMeter.new()
	punch_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(punch_meter)

	bubbles = Bubbles.new()
	bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bubbles)

	cash = Cash.new()
	cash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cash)

	power = PowerColumn.new()
	power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(power)

	tip = TipBall.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tip)

	hints = HintBar.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hints)

	crosshair = Crosshair.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.visible = false
	root.add_child(crosshair)

	pause = PauseCard.new()
	root.add_child(pause)
	pause.chosen.connect(_on_pause_choice)

	result = ResultCard.new()
	root.add_child(result)
	result.chosen.connect(_on_result_choice)

	_layout()
	get_viewport().size_changed.connect(_layout)


func _on_pause_choice(id: String) -> void:
	pause.visible = false
	if id == "restart":
		rack_again.emit()
	elif id == "menu":
		menu_confirmed.emit()


func _on_result_choice(id: String) -> void:
	if id == "again":
		rack_again.emit()
	elif id == "leave":
		leave_pressed.emit()


# Anchor presets alone leave a Control at zero size, which piles everything
# into the corner of the screen. Every panel is placed by hand instead, and
# placed again whenever the window changes shape.
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bar_w := 620.0
	_place(ko_shade, Vector2.ZERO, vs)
	_place(score, Vector2((vs.x - bar_w) * 0.5, 16), Vector2(bar_w, 54))
	_place(toast, Vector2(0, 82), Vector2(vs.x, 34))
	_place(punch_meter, Vector2(24, vs.y - 100), Vector2(160, 48))
	_place(cash, Vector2(24, vs.y - 158), Vector2(160, 48))
	_place(bubbles, Vector2.ZERO, vs)
	_place(power, Vector2(34, vs.y * 0.5 - 160.0), Vector2(26, 320))
	_place(hints, Vector2(0, vs.y - 56), Vector2(vs.x, 40))
	_place(tip, Vector2(vs.x - 320, vs.y - 300), Vector2(300, 280))
	_place(crosshair, vs * 0.5 - Vector2(20, 20), Vector2(40, 40))
	_place(pause, Vector2.ZERO, vs)
	_place(result, Vector2.ZERO, vs)
	root.position = Vector2.ZERO
	root.size = vs


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	if c == null:
		return
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y
	c.position = pos
	c.size = sz
	c.queue_redraw()


func set_shown(on: bool) -> void:
	visible = on
	if root != null:
		root.visible = on


func open_confirm() -> void:
	pause.visible = true
	pause.queue_redraw()


func confirm_open() -> bool:
	return pause != null and pause.visible


func close_confirm() -> void:
	pause.visible = false


func result_open() -> bool:
	return result != null and result.visible


func _label(parent: Control, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", PoolTheme.font(600))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func say(text: String, kind := "info") -> void:
	var c := PoolTheme.WHITE
	match kind:
		"foul":
			c = Color("ff8a6a")
		"good":
			c = Color("8fe0a0")
		"brass":
			c = PoolTheme.GOLD
		"call":
			c = Color("7cc4ff")
	toast.show_text(text, c)


func set_names(you: String, foe: String) -> void:
	score.names = [you.to_upper(), foe.to_upper()]


func set_sides(you_group: String, foe_group: String, you_ids: Array, foe_ids: Array, your_turn: bool) -> void:
	score.notes = [_group_text(you_group), _group_text(foe_group)]
	score.ids = [you_ids, foe_ids]
	score.active = 0 if your_turn else 1


func _group_text(g: String) -> String:
	match g:
		PoolRules.SOLIDS:
			return "solids"
		PoolRules.STRIPES:
			return "stripes"
	return "open table"


# Somebody says something: a bubble over `anchor` (a Callable giving a world
# point), each [seconds, text] segment replacing the last, for `dur` seconds.
func speak(key: String, anchor: Callable, segs: Array, dur: float) -> void:
	bubbles.say(key, anchor, segs, dur)


func set_cash(amount: int, near: bool) -> void:
	if amount != cash.amount:
		cash.show_for = 3.0
	cash.amount = amount
	cash.near = near


func set_punch(cd_frac: float, hot: bool) -> void:
	punch_meter.cd = cd_frac
	punch_meter.hot = hot


# 0 standing, 1 flat on the floor
func set_knocked(down: float) -> void:
	ko_shade.down = down


func knocked_flash() -> void:
	ko_shade.flash = 1.0


# [[key, what it does], ...] along the bottom of the screen
func set_hints(items: Array) -> void:
	if items == hints.items:
		return
	hints.items = items
	hints.queue_redraw()


func set_power(v: float, armed: bool) -> void:
	power.value = v
	power.armed = armed
	power.queue_redraw()


func set_spin(v: Vector2) -> void:
	tip.spin = v


func set_tip(shown: bool, focus: bool) -> void:
	tip.shown = shown
	tip.want_focus = focus


func set_crosshair(on: bool, ring := false) -> void:
	crosshair.visible = on
	if crosshair.ring != ring:
		crosshair.ring = ring
		crosshair.queue_redraw()


func set_thinking(on: bool, _who := "") -> void:
	score.thinking = on


# A line under your name: what you're on, or the call you've made.
func set_note(text: String) -> void:
	if text != "":
		score.notes[0] = text


func finish(title: String, sub: String, won: bool) -> void:
	result.title = title
	result.sub = sub
	result.won = won
	result.visible = true
	result.queue_redraw()


# Online or not: the pause card offers leaving instead of a restart, and the
# result card a rematch or the lobby.
func set_online(on: bool) -> void:
	if on:
		pause.buttons = [["resume", "RESUME", true], ["menu", "LEAVE MATCH", false]]
		result.buttons = [["again", "REMATCH", true], ["leave", "BACK TO LOBBY", false]]
	else:
		pause.buttons = [["resume", "RESUME", true], ["restart", "RESTART RACK", false], ["menu", "MAIN MENU", false]]
		result.buttons = [["again", "PLAY AGAIN", true], ["leave", "MAIN MENU", false]]
	result.note = ""
	score.clock = -1.0


func set_clock(secs: float, yours: bool) -> void:
	score.clock = secs
	score.clock_side = 0 if yours else 1


# A line on the result card ("waiting for them..."), and whether a rematch
# can still be asked for.
func set_result_note(text: String, rematch_ok: bool) -> void:
	result.note = text
	if not result.buttons.is_empty():
		var b: Array = result.buttons[0]
		result.buttons[0] = [b[0], b[1], b[2], rematch_ok]
	result.queue_redraw()


func clear_finish() -> void:
	result.note = ""
	if not result.buttons.is_empty():
		var b: Array = result.buttons[0]
		result.buttons[0] = [b[0], b[1], b[2], true]
	result.title = ""
	result.sub = ""
	result.visible = false
	result.queue_redraw()
