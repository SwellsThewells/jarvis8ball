extends Node

# The first thing that runs. Godot's own splash shows the J ball while the
# engine starts; this picks it up in the same place, draws it back with a
# gold swoosh round it, and shows the game loading underneath with a bar.
# The game scene loads on a background thread, then is built and swapped in,
# and this fades out over the top of it.

const GAME := "res://main.tscn"

var _layer: CanvasLayer
var _view: LoadView
var _state := "loading"      # loading, building, fading
var _fade := 1.0


class LoadView extends Control:
	var t := 0.0
	var progress := 0.0      # what the bar shows, eased
	var target := 0.0        # how far the loading has really got
	var alpha := 1.0
	var logo: Texture2D

	func _process(delta: float) -> void:
		t += delta
		progress = move_toward(progress, target, delta * 1.6)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 - Vector2(0, 40)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.018, 0.015, alpha))
		# the ball: starts as big as the start-up splash had it, settles smaller
		var k := 1.0 - pow(1.0 - clampf(t / 0.9, 0.0, 1.0), 3.0)
		var r := lerpf(256.0, 96.0, k)
		var spin := sin(t * 1.6) * 0.08 * k
		# the swoosh: a gold arc chasing round the ball, fading at its tail
		var head := -PI * 0.5 + t * 5.2
		var ring := r + 26.0
		var segs := 36
		for i in segs:
			var f := float(i) / float(segs)
			var a0 := head - f * 2.4
			var a1 := head - (f + 1.0 / float(segs)) * 2.4
			var w := lerpf(7.0, 0.5, f)
			var col := Color(PoolTheme.GOLD, (1.0 - f) * 0.95 * alpha * k)
			draw_line(c + Vector2(cos(a0), sin(a0)) * ring, c + Vector2(cos(a1), sin(a1)) * ring, col, w, true)
		# a faint second streak on the far side
		for i in segs:
			var f := float(i) / float(segs)
			var a0 := head + PI - f * 1.4
			var a1 := head + PI - (f + 1.0 / float(segs)) * 1.4
			draw_line(c + Vector2(cos(a0), sin(a0)) * (ring + 10.0), c + Vector2(cos(a1), sin(a1)) * (ring + 10.0),
				Color(1, 1, 1, (1.0 - f) * 0.25 * alpha * k), lerpf(3.0, 0.5, f), true)
		draw_circle(c + Vector2(0, r * 0.08), r * 0.98, Color(0, 0, 0, 0.45 * alpha), true, -1.0, true)
		if logo != null:
			draw_set_transform(c, spin, Vector2.ONE)
			draw_texture_rect(logo, Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, alpha))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# LOADING... and the bar, coming up once the ball has settled
		var ui := clampf((t - 0.5) / 0.4, 0.0, 1.0) * alpha
		var dots := ".".repeat(int(t * 2.5) % 4)
		var f := PoolTheme.font(700, false, 6)
		var y := c.y + 96.0 + 70.0
		var label := "LOADING"
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2(c.x - lw * 0.5, y), label + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(PoolTheme.WHITE, ui))
		var bw := 360.0
		var bar := Rect2(Vector2(c.x - bw * 0.5, y + 22.0), Vector2(bw, 4))
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.12 * ui), 2), bar)
		if progress > 0.0:
			draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, ui), 2), Rect2(bar.position, Vector2(maxf(4.0, bw * progress), 4)))
		var pct := "%d%%" % int(round(progress * 100.0))
		var pf := PoolTheme.font(600)
		var pw := pf.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(pf, Vector2(c.x - pw * 0.5, y + 48.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5 * ui))


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_view = LoadView.new()
	_view.logo = load("res://icon.png")
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_view)
	_fit()
	get_viewport().size_changed.connect(_fit)
	ResourceLoader.load_threaded_request(GAME)


func _fit() -> void:
	_view.position = Vector2.ZERO
	_view.size = get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	match _state:
		"loading":
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(GAME, prog)
			if not prog.is_empty():
				_view.target = 0.7 * float(prog[0])
			# let the swoosh play a moment even when loading is quick
			if st == ResourceLoader.THREAD_LOAD_LOADED and _view.t > 1.2 and _view.progress >= 0.69:
				_view.target = 0.9
				_state = "building"
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("Couldn't load the game scene")
				set_process(false)
		"building":
			if _view.progress < 0.89:
				return
			# building the room takes a moment and holds the screen still;
			# the bar sits at 90% while it does
			var scene: PackedScene = ResourceLoader.load_threaded_get(GAME)
			var game := scene.instantiate()
			get_tree().root.add_child(game)
			get_tree().current_scene = game
			_view.target = 1.0
			_state = "fading"
		"fading":
			if _view.progress < 0.999:
				return
			_fade = maxf(0.0, _fade - delta * 2.5)
			_view.alpha = _fade
			if _fade <= 0.0:
				queue_free()
