class_name PoolMenu
extends CanvasLayer

# Title screen, over the table turning slowly in the room behind it. A column
# of big menu words on the left, and each page (play, shop, how to play,
# settings) slides in on the same side so the table stays in view on the
# right. Your profile sits in the top right corner: a sign-in button until
# you're signed in through Steam, then your name, level and trophies, and it
# opens out into the full profile.

signal start_pressed(difficulty: int)
signal state_changed(state: Dictionary)
signal quit_pressed()
signal ui_sound(kind: String)

const CONTROLS := [
	[["W", "A", "S", "D"], "Walk around the table"],
	[["SHIFT"], "Hold to walk faster"],
	[["MOUSE"], "Look around. Down on a shot, it aims"],
	[["SPACE"], "Get down on the shot, or stand back up"],
	[["LMB"], "Hold, pull the mouse back, push through to shoot"],
	[["RMB"], "Hold and move to put spin on the ball"],
	[["WHEEL"], "Lean in closer or ease back while down"],
	[["LMB"], "On your feet: put the cue ball down, or call the 8"],
	[["LMB"], "On him: wind up and punch (every 30 s)"],
	[["LMB"], "At the bar: click a card on the counter to order"],
	[["HOLD LMB"], "Pick up your drink. Mouse up to drink it"],
	[["ESC"], "Pause"],
]

const RULES := [
	"Eight-ball. Break, then the first ball you pot after the break gives you your group.",
	"Clear your solids or stripes, then pot the 8 in the pocket you called.",
	"To call the 8, look at a pocket while you're standing and click it. Click it again to cancel.",
	"Foul, and your opponent gets the cue ball in hand anywhere on the table.",
	"The 8 on the break is a re-rack. The 8 early, in the wrong pocket, or with a scratch loses.",
	"Every game pays out for the bar: $15 for a win, $5 for a loss. The drinks do nothing for your game.",
]

var screen: Screen
var root: Control
var preview: CuePreview


# ---------------------------------------------------------------------------
# The 3D cue on the shop page: its own little world, rendered to a texture.
# ---------------------------------------------------------------------------

class CuePreview extends SubViewport:
	const PREVIEW_YAW := 58.0
	const PREVIEW_TILT := 7.0
	const PREVIEW_PIVOT := 1.08       # how far from the tip the cue turns about
	const PREVIEW_CAM := Vector3(-0.06, 0.035, 0.66)
	const PREVIEW_AT := Vector3(-0.10, -0.02, -0.25)
	var holder: Node3D
	var spin: Node3D
	var cam: Camera3D
	var shown_id := ""
	var roll := 0.0
	var drag_v := 0.0
	var dragging := false
	var intro := 0.0

	func build() -> void:
		own_world_3d = true
		transparent_bg = true
		msaa_3d = Viewport.MSAA_4X
		size = Vector2i(1280, 640)
		render_target_update_mode = SubViewport.UPDATE_DISABLED

		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("3a3440")
		env.ambient_light_energy = 0.9
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
		env.glow_enabled = true
		env.glow_intensity = 0.55
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.0
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)

		# a warm key from above and in front, a cool rim from behind to pick
		# out the outline, and a soft fill from below so nothing goes black
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-50, 10, 0)
		key.light_energy = 1.9
		key.light_color = Color("fff1dc")
		add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-15, 165, 0)
		rim.light_energy = 1.6
		rim.light_color = Color("a8c8ff")
		add_child(rim)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(35, -40, 0)
		fill.light_energy = 0.55
		fill.light_color = Color("ffd9a8")
		add_child(fill)

		# The butt close to you and the shaft running away into the distance,
		# so the whole stick is in view but the part a cue is decorated on is
		# the part you see biggest.
		holder = Node3D.new()
		holder.rotation_degrees = Vector3(0, PREVIEW_YAW, PREVIEW_TILT)
		add_child(holder)
		spin = Node3D.new()
		holder.add_child(spin)

		cam = Camera3D.new()
		cam.fov = 30.0
		cam.position = PREVIEW_CAM
		add_child(cam)
		cam.look_at(PREVIEW_AT, Vector3.UP)
		cam.current = true

	func show_cue(id: String) -> void:
		if id == shown_id:
			return
		shown_id = id
		for c in spin.get_children():
			spin.remove_child(c)
			c.queue_free()
		var model := PoolCueModel.build(PoolCues.by_id(id))
		# the cue runs along +Y from the tip; lay it along X, turning about
		# a point on the butt
		model.rotation_degrees = Vector3(0, 0, 90)
		model.position = Vector3(PREVIEW_PIVOT, 0.0, 0.0)
		spin.add_child(model)
		intro = 1.0

	func set_live(on: bool) -> void:
		render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

	func _process(delta: float) -> void:
		if render_target_update_mode == SubViewport.UPDATE_DISABLED:
			return
		if not dragging:
			drag_v = lerpf(drag_v, 0.0, 1.0 - exp(-3.0 * delta))
			roll += (0.55 + drag_v) * delta
		intro = maxf(0.0, intro - delta * 2.2)
		spin.rotation = Vector3(roll, 0.0, 0.0)
		spin.position = Vector3(0.0, -0.05 * intro * intro, 0.0)

	func drag(dx: float) -> void:
		roll += dx * 0.012
		drag_v = clampf(dx * 0.6, -6.0, 6.0)


# ---------------------------------------------------------------------------

class Screen extends Control:
	signal start_pressed(difficulty: int)
	signal state_changed(state: Dictionary)
	signal quit_pressed()
	signal ui_sound(kind: String)

	var state := {"owned": ["house"], "equipped": "house", "difficulty": 5, "guides": true}
	var page := "main"            # main, play, shop, info
	var page_t := 1.0             # slide-in for the current page
	var t := 0.0
	var hover := Vector2(-100, -100)
	var hot := ""                 # what the mouse is over, by name
	var _last_hot := ""
	var anim: Dictionary = {}     # per-item hover easing
	var hits: Array = []          # [rect, name] rebuilt every draw
	var picked_cue := 0
	var scroll := 0.0
	var scroll_to := 0.0
	var list_rect := Rect2()
	var preview_rect := Rect2()
	var preview: CuePreview
	var dragging_preview := false

	const MAIN_ITEMS := [["play", "PLAY"], ["shop", "SHOP"], ["info", "HOW TO PLAY"], ["settings", "SETTINGS"], ["quit", "QUIT"]]
	const ROW_H := 74.0

	var list_view: Control
	var logo: Texture2D
	var profile: PoolProfile

	# settings page
	const SETTING_ROWS := [
		["AUDIO"],
		["slider", "master", "All sounds", "Everything the game plays"],
		["slider", "sfx", "Sound effects", "Balls, cushions, footsteps, the bar"],
		["slider", "voice", "Voices", "The house player talking"],
		["GAMEPLAY"],
		["slider", "mouse_sens", "Mouse sensitivity", "Looking round and aiming"],
		["slider", "fov", "Field of view", "How much of the room you see"],
		["toggle", "drink_fx", "Drink effects", "What the bar's drinks do to your eyes and legs"],
		["toggle", "screen_shake", "Screen shake", "When a punch lands, yours or his"],
		["DISPLAY"],
		["toggle", "fullscreen", "Fullscreen", "Off plays in a window"],
		["toggle", "vsync", "VSync", "Stops tearing. Can add a little input lag"],
		["cycle", "max_fps", "Frame rate cap", "Lower saves power and heat"],
		["toggle", "film_fx", "Film grain and vignette", "The soft, dark-edged look over the picture"],
	]
	const SET_ROW_H := 70.0
	var slider_rects := {}
	var dragging_slider := ""

	var toast := ""
	var toast_t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# the cue list scrolls, so it draws into its own clipped box
		list_view = Control.new()
		list_view.clip_contents = true
		list_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list_view.visible = false
		add_child(list_view)
		list_view.draw.connect(_draw_list)

	func _process(delta: float) -> void:
		t += delta
		page_t = minf(1.0, page_t + delta * 4.5)
		toast_t = maxf(0.0, toast_t - delta)
		if page == "profile" and (profile == null or not profile.signed_in):
			go("main")
		scroll = lerpf(scroll, scroll_to, 1.0 - exp(-14.0 * delta))
		for k in anim.keys():
			var target := 1.0 if k == hot else 0.0
			anim[k] = lerpf(float(anim[k]), target, 1.0 - exp(-16.0 * delta))
		queue_redraw()

	func bar_width() -> float:
		return clampf(size.x * 0.36, 460.0, 640.0)

	func go(p: String) -> void:
		if p == page:
			return
		page = p
		page_t = 0.0
		hot = ""
		if preview != null:
			preview.set_live(p == "shop")
			if p == "shop":
				preview.show_cue(str(PoolCues.CUES[picked_cue].id))
		ui_sound.emit("click")

	# -----------------------------------------------------------------------

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			hover = ev.position
			if dragging_preview and preview != null:
				preview.drag(ev.relative.x)
			if dragging_slider != "":
				_slide_to(ev.position.x)
				return
			_update_hot()
		elif ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if page == "shop" and list_rect.has_point(mb.position) and mb.pressed:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					_scroll_by(-ROW_H * 1.5)
					return
				if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_scroll_by(ROW_H * 1.5)
					return
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if not mb.pressed:
				if dragging_preview and preview != null:
					preview.dragging = false
				dragging_preview = false
				if dragging_slider != "":
					dragging_slider = ""
					PoolSettings.save_settings()
					ui_sound.emit("click")      # at the new volume, so you hear it
				return
			if page == "shop" and preview_rect.has_point(mb.position) and preview != null:
				dragging_preview = true
				preview.dragging = true
				return
			hover = mb.position
			_update_hot()
			if hot.begins_with("slider:"):
				dragging_slider = hot.substr(7)
				_slide_to(mb.position.x)
				return
			if hot != "":
				_press(hot)

	func _scroll_by(dy: float) -> void:
		var content := float(PoolCues.CUES.size()) * ROW_H
		scroll_to = clampf(scroll_to + dy, 0.0, maxf(0.0, content - list_rect.size.y))

	func _update_hot() -> void:
		hot = ""
		for h in hits:
			if (h[0] as Rect2).has_point(hover):
				hot = str(h[1])
		if hot != _last_hot:
			if hot != "" and not hot.begins_with("cue:") and not (hot in ["panel", "close_bg"]):
				ui_sound.emit("tick")
			_last_hot = hot

	func _press(name: String) -> void:
		if name in ["play", "shop", "info", "settings"]:
			go(name)
		elif name == "chip":
			if profile != null and profile.signed_in:
				go("profile")
			elif profile != null:
				ui_sound.emit("click")
				profile.sign_in()
		elif name == "close_bg" or name == "close":
			go("main")
		elif name == "signout":
			if profile != null:
				profile.sign_out()
				show_toast("Signed out. Your stats are kept for next time.")
			go("main")
		elif name.begins_with("tog:"):
			var k := name.substr(4)
			PoolSettings.data[k] = not PoolSettings.on(k)
			PoolSettings.apply()
			PoolSettings.save_settings()
			ui_sound.emit("click")
		elif name.begins_with("cyc-:") or name.begins_with("cyc+:"):
			var k := name.substr(5)
			var steps: Array = PoolSettings.FPS_STEPS
			var i := steps.find(int(PoolSettings.data.get(k, 0)))
			i = wrapi(i + (1 if name.begins_with("cyc+") else -1), 0, steps.size())
			PoolSettings.data[k] = steps[i]
			PoolSettings.apply()
			PoolSettings.save_settings()
			ui_sound.emit("click")
		elif name == "reset_settings":
			PoolSettings.reset()
			PoolSettings.apply()
			PoolSettings.save_settings()
			ui_sound.emit("equip")
			show_toast("Settings back to how they started.")
		elif name == "quit":
			ui_sound.emit("click")
			quit_pressed.emit()
		elif name == "back":
			go("main")
		elif name == "start":
			ui_sound.emit("start")
			start_pressed.emit(int(state.difficulty))
		elif name.begins_with("lvl:"):
			state.difficulty = int(name.substr(4))
			state_changed.emit(state)
			ui_sound.emit("click")
		elif name == "lvl_down":
			state.difficulty = maxi(1, int(state.difficulty) - 1)
			state_changed.emit(state)
			ui_sound.emit("click")
		elif name == "lvl_up":
			state.difficulty = mini(10, int(state.difficulty) + 1)
			state_changed.emit(state)
			ui_sound.emit("click")
		elif name == "guides":
			state.guides = not bool(state.get("guides", true))
			state_changed.emit(state)
			ui_sound.emit("click")
		elif name.begins_with("cue:"):
			picked_cue = int(name.substr(4))
			if preview != null:
				preview.show_cue(str(PoolCues.CUES[picked_cue].id))
			ui_sound.emit("tick")
		elif name == "equip":
			_take_or_equip()

	func _take_or_equip() -> void:
		var cue: Dictionary = PoolCues.CUES[picked_cue]
		var owned: Array = state.owned
		if str(state.equipped) == str(cue.id):
			return
		if not owned.has(cue.id):
			if int(cue.price) > 0:
				return                      # nothing to pay with yet
			owned.append(cue.id)
		state.equipped = cue.id
		state_changed.emit(state)
		ui_sound.emit("equip")

	func _unhandled_key_input(ev: InputEvent) -> void:
		if not is_visible_in_tree() or not (ev is InputEventKey and ev.pressed and not ev.echo):
			return
		match ev.keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				if page != "main":
					go("main")
			KEY_ENTER, KEY_KP_ENTER:
				if page == "play":
					_press("start")
				elif page == "main":
					go("play")
			KEY_LEFT:
				if page == "play":
					_press("lvl_down")
			KEY_RIGHT:
				if page == "play":
					_press("lvl_up")
			KEY_UP:
				if page == "shop":
					_pick_step(-1)
			KEY_DOWN:
				if page == "shop":
					_pick_step(1)

	func show_toast(text: String) -> void:
		toast = text
		toast_t = 3.5

	# A slider follows the mouse along its track while the button is down.
	func _slide_to(px: float) -> void:
		if not slider_rects.has(dragging_slider):
			return
		var r: Rect2 = slider_rects[dragging_slider]
		var k := clampf((px - r.position.x) / r.size.x, 0.0, 1.0)
		var rng := _slider_range(dragging_slider)
		var v := lerpf(rng.x, rng.y, k)
		match dragging_slider:
			"fov":
				v = roundf(v)
			"mouse_sens":
				v = snappedf(v, 0.05)
			_:
				v = snappedf(v, 0.01)
		PoolSettings.data[dragging_slider] = v
		if dragging_slider in ["master", "sfx", "voice"]:
			PoolSettings.apply()

	func _slider_range(k: String) -> Vector2:
		match k:
			"mouse_sens":
				return PoolSettings.SENS_RANGE
			"fov":
				return PoolSettings.FOV_RANGE
		return Vector2(0.0, 1.0)

	func _pick_step(d: int) -> void:
		picked_cue = clampi(picked_cue + d, 0, PoolCues.CUES.size() - 1)
		_press("cue:%d" % picked_cue)
		var top := float(picked_cue) * ROW_H
		if top < scroll_to:
			scroll_to = top
		elif top + ROW_H > scroll_to + list_rect.size.y:
			scroll_to = top + ROW_H - list_rect.size.y

	# -----------------------------------------------------------------------
	# Drawing
	# -----------------------------------------------------------------------

	func _a(name: String) -> float:
		if not anim.has(name):
			anim[name] = 0.0
		return float(anim[name])

	func _hit(r: Rect2, name: String) -> void:
		hits.append([r, name])

	func _text(pos: Vector2, s: String, sz: int, col: Color, weight := 400, condensed := false,
			align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, spacing := 0) -> void:
		draw_string(PoolTheme.font(weight, condensed, spacing), pos, s, align, width, sz, col)

	func _text_w(s: String, sz: int, weight := 400, condensed := false, spacing := 0) -> float:
		return PoolTheme.font(weight, condensed, spacing).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x

	func _ease(x: float) -> float:
		return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

	func _draw() -> void:
		hits.clear()
		list_view.visible = page == "shop"
		_draw_shade()
		match page:
			"main":
				_draw_main()
			"play":
				_draw_play()
			"shop":
				_draw_shop()
			"info":
				_draw_info()
			"settings":
				_draw_settings()
			"profile":
				_draw_profile()
		if page != "profile":
			_draw_chip()
		_draw_toast()
		# a hover can change as things animate in under a still mouse
		_update_hot()

	# darkens the left of the screen so the words read over the room
	func _draw_shade() -> void:
		var w := size.x
		var h := size.y
		var reach := w * (0.62 if page in ["main", "play", "profile"] else 0.92)
		var strength := 0.88
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(reach, 0), Vector2(reach, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, strength), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, strength)]))
		draw_polygon(PackedVector2Array([Vector2(0, h - 220), Vector2(w, h - 220), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.7)]))

	func _logo(at: Vector2, scale := 1.0) -> void:
		var r := 42.0 * scale
		var c := at + Vector2(r, r)
		# the J ball, the game's badge
		draw_circle(c + Vector2(0, 4), r * 0.98, Color(0, 0, 0, 0.45))
		if logo == null:
			logo = load("res://icon.png")
		if logo != null:
			draw_texture_rect(logo, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		# name beside it
		var x := at.x + r * 2.0 + 22.0 * scale
		_text(Vector2(x, at.y + 50.0 * scale), "JARVIS", int(66.0 * scale), PoolTheme.WHITE, 800, true)
		_text(Vector2(x + 3.0, at.y + 80.0 * scale), "8 BALL POOL", int(20.0 * scale), PoolTheme.GOLD, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)

	func _back_button(x: float, y: float) -> void:
		var r := Rect2(Vector2(x - 8, y - 26), Vector2(118, 40))
		_hit(r, "back")
		var a := _a("back")
		var col := PoolTheme.MUTED.lerp(PoolTheme.WHITE, a)
		_text(Vector2(x + a * -4.0, y), "‹  BACK", 18, col, 700, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)

	func _page_title(x: float, y: float, s: String, sub: String) -> void:
		var e := _ease(page_t)
		var dx := (1.0 - e) * -40.0
		_text(Vector2(x + dx, y), s, 64, Color(1, 1, 1, e), 800, true)
		if sub != "":
			_text(Vector2(x + dx + 3, y + 30), sub, 16, Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, e),
				600, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

	func _button(r: Rect2, name: String, label: String, primary := true, enabled := true) -> void:
		if enabled:
			_hit(r, name)
		var a := _a(name) if enabled else 0.0
		var lift := a * 2.0
		var rr := Rect2(r.position - Vector2(0, lift), r.size)
		var base := PoolTheme.FELT if primary else Color(0.16, 0.17, 0.17, 0.95)
		var top := PoolTheme.FELT_HI if primary else Color(0.24, 0.25, 0.25, 0.95)
		if not enabled:
			base = Color(0.12, 0.13, 0.13, 0.8)
			top = base
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.45), 12), Rect2(r.position + Vector2(0, 4), r.size))
		draw_style_box(PoolTheme.box(base.lerp(top, a * 0.6), 12, Color(1, 1, 1, 0.12 + a * 0.2), 1), rr)
		# a lighter band over the top half, like a lacquered button
		var band := Rect2(rr.position + Vector2(3, 3), Vector2(rr.size.x - 6, rr.size.y * 0.45))
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.07 + a * 0.05), 9), band)
		var fs := 26
		var col := PoolTheme.WHITE if enabled else PoolTheme.MUTED
		_text(Vector2(rr.position.x, rr.position.y + rr.size.y * 0.5 + fs * 0.36), label, fs, col, 800, true,
			HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 2)

	# --- main -------------------------------------------------------------

	func _draw_main() -> void:
		var x := 84.0
		_logo(Vector2(x, 70.0))
		var y := 300.0
		for i in MAIN_ITEMS.size():
			var id: String = MAIN_ITEMS[i][0]
			var label: String = MAIN_ITEMS[i][1]
			var e := _ease(page_t * 1.6 - float(i) * 0.12)
			var a := _a(id)
			var fs := 52
			var w := _text_w(label, fs, 800, true, 1)
			var r := Rect2(Vector2(x - 12, y - 48), Vector2(w + 60, 62))
			_hit(r, id)
			var px := x + a * 16.0 + (1.0 - e) * -60.0
			if a > 0.01:
				draw_rect(Rect2(Vector2(x - 12, y - 38), Vector2(6, 40)), Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, a * e))
			var col := Color(0.92, 0.9, 0.86, 0.72).lerp(PoolTheme.WHITE, a)
			if id == "play":
				col = Color(0.97, 0.95, 0.9, 0.92).lerp(PoolTheme.GOLD, a)
			col.a *= e
			_text(Vector2(px + 2, y + 3), label, fs, Color(0, 0, 0, 0.4 * e), 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			_text(Vector2(px, y), label, fs, col, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			y += 78.0

		# what you are taking to the table
		var by := size.y - 64.0
		var cue: Dictionary = PoolCues.by_id(str(state.equipped))
		_chip(Vector2(x, by), "OPPONENT", "Level %d  %s" % [int(state.difficulty), PoolAI.SKILL_LABELS[clampi(int(state.difficulty), 1, 10) - 1]])
		_chip(Vector2(x + 300, by), "CUE", str(cue.name))

	func _chip(at: Vector2, label: String, value: String) -> void:
		_text(at, label, 13, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		_text(at + Vector2(0, 26), value, 20, PoolTheme.WHITE, 600)

	# --- play -------------------------------------------------------------

	func _draw_play() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "PLAY", "EIGHT-BALL  VS  COMPUTER")

		var pw := bar_width() - x
		var panel := Rect2(Vector2(x - 24 + (1.0 - e) * -50.0, 240), Vector2(pw + 24, 470))
		draw_style_box(PoolTheme.box(PoolTheme.SHADE, 16, PoolTheme.LINE, 1, 18), panel)
		var px := panel.position.x + 28.0
		var inner_w := panel.size.x - 56.0
		var y := panel.position.y + 44.0

		_text(Vector2(px, y), "OPPONENT", 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		var diff := clampi(int(state.difficulty), 1, 10)
		# level, big, with arrows either side
		y += 58.0
		var name_s: String = PoolAI.SKILL_LABELS[diff - 1]
		var ar := Rect2(Vector2(px, y - 40), Vector2(44, 50))
		var br := Rect2(Vector2(px + inner_w - 44, y - 40), Vector2(44, 50))
		_hit(ar, "lvl_down")
		_hit(br, "lvl_up")
		_text(Vector2(ar.position.x, y), "‹", 46, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("lvl_down")), 700, false,
			HORIZONTAL_ALIGNMENT_CENTER, ar.size.x)
		_text(Vector2(br.position.x, y), "›", 46, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("lvl_up")), 700, false,
			HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
		_text(Vector2(px, y), name_s.to_upper(), 40, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_CENTER, inner_w, 1)
		_text(Vector2(px, y + 30), "LEVEL %d" % diff, 16, PoolTheme.GOLD, 700, false, HORIZONTAL_ALIGNMENT_CENTER, inner_w, 3)

		# ten steps you can click straight to
		y += 62.0
		var gap := 6.0
		var cw := (inner_w - gap * 9.0) / 10.0
		for i in 10:
			var r := Rect2(Vector2(px + float(i) * (cw + gap), y), Vector2(cw, 30))
			var nm := "lvl:%d" % (i + 1)
			_hit(r, nm)
			var on := i + 1 <= diff
			var a := _a(nm)
			var col := Color(0.2, 0.21, 0.21, 0.9)
			if on:
				col = PoolTheme.GOLD.lerp(Color("ff8a3d"), float(i) / 9.0)
			col = col.lerp(Color(1, 1, 1, col.a), a * 0.25)
			draw_style_box(PoolTheme.box(col, 5), r)
			if i + 1 == diff:
				draw_style_box(PoolTheme.box(Color(0, 0, 0, 0), 6, PoolTheme.WHITE, 2), r.grow(3))

		# aiming guide
		y += 84.0
		draw_line(Vector2(px, y - 34), Vector2(px + inner_w, y - 34), PoolTheme.LINE, 1.0)
		_text(Vector2(px, y), "AIM GUIDE", 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		var on_g := bool(state.get("guides", true))
		_text(Vector2(px, y + 26), "Lines showing where the balls will go" if on_g else "No lines. Just you and the table",
			16, PoolTheme.WHITE, 400)
		var sw := Rect2(Vector2(px + inner_w - 86, y - 16), Vector2(86, 40))
		_hit(Rect2(Vector2(px, y - 26), Vector2(inner_w, 60)), "guides")
		var ga := _a("guides")
		draw_style_box(PoolTheme.box((PoolTheme.FELT if on_g else Color(0.25, 0.26, 0.26)).lerp(Color.WHITE, ga * 0.08), 20), sw)
		var knob_x := sw.position.x + (sw.size.x - 22.0 if on_g else 22.0)
		draw_circle(Vector2(knob_x, sw.position.y + 20), 15.0, PoolTheme.WHITE)
		_text(Vector2(sw.position.x + (12.0 if on_g else 40.0), sw.position.y + 26), "ON" if on_g else "OFF",
			13, Color(1, 1, 1, 0.85), 800)

		_button(Rect2(Vector2(px, panel.position.y + panel.size.y - 104), Vector2(inner_w, 72)), "start", "START MATCH")

	# --- shop -------------------------------------------------------------

	func _draw_shop() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "SHOP", "%d CUES, ALL FREE" % PoolCues.CUES.size())

		# the list: its frame here, its rows drawn clipped inside list_view
		var lw := 420.0
		list_rect = Rect2(Vector2(x - 12 + (1.0 - e) * -50.0, 216), Vector2(lw, size.y - 216 - 56))
		draw_style_box(PoolTheme.box(PoolTheme.SHADE, 14, PoolTheme.LINE, 1, 12), list_rect.grow(8))
		list_view.position = list_rect.position
		list_view.size = list_rect.size
		list_view.queue_redraw()
		for i in PoolCues.CUES.size():
			var r := _row_rect(i)
			r.position += list_rect.position
			var vis := r.intersection(list_rect)
			if vis.size.y > 2.0:
				_hit(vis, "cue:%d" % i)
		# scroll bar
		var content := float(PoolCues.CUES.size()) * ROW_H
		if content > list_rect.size.y:
			var frac := list_rect.size.y / content
			var bar_h := list_rect.size.y * frac
			var bar_y := list_rect.position.y + (scroll / content) * list_rect.size.y
			draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.18), 3), Rect2(Vector2(list_rect.end.x + 2, bar_y), Vector2(4, bar_h)))

		# the preview
		var rx := list_rect.end.x + 48.0
		var rw := size.x - rx - 60.0
		var pick: Dictionary = PoolCues.CUES[clampi(picked_cue, 0, PoolCues.CUES.size() - 1)]
		preview_rect = Rect2(Vector2(rx, 150), Vector2(rw, minf(rw * 0.5, size.y - 150 - 300)))
		var pr := preview_rect
		draw_style_box(PoolTheme.box(Color(0.06, 0.065, 0.07, 0.72), 18, PoolTheme.LINE, 1, 16), pr)
		# a soft pool of light behind the cue, in fine steps so it doesn't band
		var glow_c := pr.get_center() + Vector2(0, pr.size.y * 0.12)
		for i in 48:
			var f := float(i) / 48.0
			draw_circle(glow_c, pr.size.y * 0.5 * (1.0 - f), Color(1, 0.85, 0.6, 0.0035))
		if preview != null:
			var tex := preview.get_texture()
			var ts := Vector2(preview.size)
			var fit := minf(pr.size.x / ts.x, pr.size.y / ts.y)
			var dsz := ts * fit
			draw_texture_rect(tex, Rect2(pr.get_center() - dsz * 0.5, dsz), false)
		_text(Vector2(pr.position.x + 22, pr.end.y - 18), "drag to turn", 13, Color(1, 1, 1, 0.35), 600)

		var iy := pr.end.y + 64.0
		_text(Vector2(rx, iy), str(pick.name).to_upper(), 48, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
		_text(Vector2(rx + 2, iy + 30), str(pick.tag).to_upper(), 15, PoolTheme.GOLD, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		draw_multiline_string(PoolTheme.font(400), Vector2(rx, iy + 66), str(pick.blurb), HORIZONTAL_ALIGNMENT_LEFT,
			minf(rw - 320.0, 620.0), 18, 3, Color(1, 1, 1, 0.78))
		var is_on := str(state.equipped) == str(pick.id)
		var br := Rect2(Vector2(pr.end.x - 280, pr.end.y + 36), Vector2(280, 72))
		_button(br, "equip", "EQUIPPED" if is_on else "EQUIP", not is_on, not is_on)

	# a row of the cue list, in the list's own coordinates
	func _row_rect(i: int) -> Rect2:
		return Rect2(Vector2(0.0, float(i) * ROW_H - scroll), Vector2(list_rect.size.x, ROW_H - 6))

	func _draw_list() -> void:
		var c := list_view
		var owned: Array = state.owned
		var font_b := PoolTheme.font(700)
		var font_t := PoolTheme.font(700, false, 2)
		var font_k := PoolTheme.font(800, false, 2)
		for i in PoolCues.CUES.size():
			var r := _row_rect(i)
			if r.end.y < 0.0 or r.position.y > c.size.y:
				continue
			var cue: Dictionary = PoolCues.CUES[i]
			var a := _a("cue:%d" % i)
			var on := picked_cue == i
			var equipped := str(state.equipped) == str(cue.id)
			var bg := Color(1, 1, 1, 0.03 + a * 0.05)
			if on:
				bg = Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, 0.16)
			c.draw_style_box(PoolTheme.box(bg, 10, PoolTheme.GOLD if on else Color(0, 0, 0, 0), 2 if on else 0), r)
			var cols := PoolCues.swatch(cue)
			var sw := Rect2(r.position + Vector2(12, 14), Vector2(10, r.size.y - 28))
			c.draw_style_box(PoolTheme.box(cols[0], 4), sw)
			c.draw_style_box(PoolTheme.box(cols[1], 4), Rect2(sw.position, Vector2(sw.size.x, sw.size.y * 0.5)))
			c.draw_string(font_b, r.position + Vector2(36, 32), str(cue.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, PoolTheme.WHITE)
			c.draw_string(font_t, r.position + Vector2(36, 54), str(cue.tag).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PoolTheme.MUTED)
			var badge := "EQUIPPED" if equipped else ("OWNED" if owned.has(cue.id) else "FREE")
			var bcol := PoolTheme.FELT_HI if equipped else (PoolTheme.MUTED if owned.has(cue.id) else PoolTheme.GOLD)
			var bw := font_k.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18.0
			var brr := Rect2(Vector2(r.end.x - bw - 14, r.position.y + 22), Vector2(bw, 24))
			c.draw_style_box(PoolTheme.box(Color(bcol.r, bcol.g, bcol.b, 0.16), 12, Color(bcol.r, bcol.g, bcol.b, 0.7), 1), brr)
			c.draw_string(font_k, Vector2(brr.position.x, brr.position.y + 17), badge, HORIZONTAL_ALIGNMENT_CENTER,
				brr.size.x, 12, bcol)

	# --- how to play ------------------------------------------------------

	func _draw_info() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "HOW TO PLAY", "AT THE TABLE")
		var w := minf(size.x - 2.0 * x, 1180.0)
		var panel := Rect2(Vector2(x - 24 + (1.0 - e) * -50.0, 230), Vector2(w + 24, size.y - 230 - 60))
		draw_style_box(PoolTheme.box(PoolTheme.SHADE, 16, PoolTheme.LINE, 1, 18), panel)
		var px := panel.position.x + 32.0
		var y := panel.position.y + 50.0
		var col_w := (panel.size.x - 96.0) * 0.5
		_text(Vector2(px, y), "CONTROLS", 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		y += 34.0
		for row in CONTROLS:
			var kx := px
			for k in row[0]:
				kx += _keycap(Vector2(kx, y - 4), str(k)) + 6.0
			_text(Vector2(px + 170, y + 20), str(row[1]), 17, PoolTheme.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, col_w - 170.0)
			y += 50.0
		var rx := px + col_w + 32.0
		var ry := panel.position.y + 50.0
		_text(Vector2(rx, ry), "RULES", 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		ry += 34.0
		for i in RULES.size():
			draw_circle(Vector2(rx + 6, ry + 13), 4.0, PoolTheme.GOLD)
			draw_multiline_string(PoolTheme.font(400), Vector2(rx + 24, ry + 20), str(RULES[i]),
				HORIZONTAL_ALIGNMENT_LEFT, col_w - 30.0, 17, 3, Color(1, 1, 1, 0.85))
			ry += 76.0

	func _keycap(at: Vector2, label: String) -> float:
		var fs := 14
		var w := maxf(34.0, _text_w(label, fs, 800) + 20.0)
		var r := Rect2(at, Vector2(w, 34))
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.5), 7), Rect2(r.position + Vector2(0, 3), r.size))
		draw_style_box(PoolTheme.box(Color(0.93, 0.91, 0.86), 7), r)
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.5), 5), Rect2(r.position + Vector2(3, 2), Vector2(r.size.x - 6, 12)))
		_text(Vector2(r.position.x, r.position.y + 23), label, fs, Color(0.1, 0.1, 0.1), 800, false,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return w


	# --- settings ---------------------------------------------------------

	func _draw_settings() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "SETTINGS", "SOUND, CONTROLS AND SCREEN")
		var w := minf(size.x - 2.0 * x, 1180.0)
		var panel := Rect2(Vector2(x - 24 + (1.0 - e) * -50.0, 230), Vector2(w + 24, 2.0 * 44.0 + 7.0 * SET_ROW_H + 110.0))
		draw_style_box(PoolTheme.box(PoolTheme.SHADE, 16, PoolTheme.LINE, 1, 18), panel)
		var col_w := (panel.size.x - 96.0) * 0.5
		var cx := panel.position.x + 32.0
		var y := panel.position.y + 50.0
		slider_rects.clear()
		for row in SETTING_ROWS:
			if row.size() == 1:
				if row[0] == "DISPLAY":
					# the second column
					cx += col_w + 32.0
					y = panel.position.y + 50.0
				elif y > panel.position.y + 60.0:
					y += 34.0
				_text(Vector2(cx, y), str(row[0]), 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
				y += 30.0
				continue
			_setting_row(Rect2(Vector2(cx, y), Vector2(col_w, SET_ROW_H)), row)
			y += SET_ROW_H
		var rr := Rect2(Vector2(cx, panel.end.y - 104.0), Vector2(col_w, 64))
		_button(rr, "reset_settings", "RESET TO DEFAULTS", false)

	func _setting_row(r: Rect2, row: Array) -> void:
		var kind: String = row[0]
		var key: String = row[1]
		draw_line(Vector2(r.position.x, r.end.y - 4), Vector2(r.end.x, r.end.y - 4), PoolTheme.LINE, 1.0)
		var ctl_w := 280.0
		# a switch only needs its own width; sliders and pickers take more
		var text_w := r.size.x - (100.0 if kind == "toggle" else ctl_w + 10.0)
		_text(r.position + Vector2(0, 26), str(row[2]), 19, PoolTheme.WHITE, 600, false, HORIZONTAL_ALIGNMENT_LEFT, text_w)
		_text(r.position + Vector2(0, 50), _fit(str(row[3]), 14, 400, text_w), 14, PoolTheme.MUTED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, text_w)
		var cr := Rect2(Vector2(r.end.x - ctl_w, r.position.y + 8), Vector2(ctl_w, 44))
		match kind:
			"slider":
				_slider(cr, key)
			"toggle":
				var nm := "tog:" + key
				_hit(Rect2(r.position, Vector2(r.size.x, r.size.y - 6)), nm)
				_switch(Vector2(cr.end.x - 86, cr.position.y + 2), PoolSettings.on(key), _a(nm))
			"cycle":
				var v := int(PoolSettings.data.get(key, 0))
				var label := "NO CAP" if v == 0 else "%d FPS" % v
				var lr := Rect2(Vector2(cr.end.x - 190, cr.position.y), Vector2(44, 44))
				var rr := Rect2(Vector2(cr.end.x - 44, cr.position.y), Vector2(44, 44))
				_hit(lr, "cyc-:" + key)
				_hit(rr, "cyc+:" + key)
				_text(Vector2(lr.position.x, lr.position.y + 36), "‹", 38, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("cyc-:" + key)), 700, false,
					HORIZONTAL_ALIGNMENT_CENTER, 44)
				_text(Vector2(rr.position.x, rr.position.y + 36), "›", 38, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("cyc+:" + key)), 700, false,
					HORIZONTAL_ALIGNMENT_CENTER, 44)
				_text(Vector2(lr.end.x, cr.position.y + 29), label, 18, PoolTheme.WHITE, 700, true,
					HORIZONTAL_ALIGNMENT_CENTER, rr.position.x - lr.end.x, 1)

	func _slider(cr: Rect2, key: String) -> void:
		var nm := "slider:" + key
		var track := Rect2(Vector2(cr.position.x + 4, cr.position.y + 20), Vector2(cr.size.x - 84, 6))
		slider_rects[key] = track
		_hit(Rect2(Vector2(track.position.x - 12, cr.position.y), Vector2(track.size.x + 24, cr.size.y)), nm)
		var rng := _slider_range(key)
		var v := PoolSettings.f(key)
		var k := clampf(inverse_lerp(rng.x, rng.y, v), 0.0, 1.0)
		var a := maxf(_a(nm), 1.0 if dragging_slider == key else 0.0)
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.14), 3), track)
		draw_style_box(PoolTheme.box(PoolTheme.GOLD, 3), Rect2(track.position, Vector2(track.size.x * k, track.size.y)))
		var knob := Vector2(track.position.x + track.size.x * k, track.position.y + 3)
		draw_circle(knob + Vector2(0, 2), 11.0 + a * 2.0, Color(0, 0, 0, 0.4))
		draw_circle(knob, 10.0 + a * 2.0, PoolTheme.WHITE)
		var label := "%d%%" % int(round(v * 100.0))
		if key == "mouse_sens":
			label = "%.2f×" % v
		elif key == "fov":
			label = "%d°" % int(v)
		_text(Vector2(track.end.x + 14, cr.position.y + 29), label, 18, PoolTheme.WHITE, 700, false, HORIZONTAL_ALIGNMENT_RIGHT, 66)

	func _switch(at: Vector2, on: bool, a: float) -> void:
		var sw := Rect2(at, Vector2(86, 40))
		draw_style_box(PoolTheme.box((PoolTheme.FELT if on else Color(0.25, 0.26, 0.26)).lerp(Color.WHITE, a * 0.08), 20), sw)
		var knob_x := sw.position.x + (sw.size.x - 22.0 if on else 22.0)
		draw_circle(Vector2(knob_x, sw.position.y + 20), 15.0, PoolTheme.WHITE)
		_text(Vector2(sw.position.x + (12.0 if on else 40.0), sw.position.y + 26), "ON" if on else "OFF",
			13, Color(1, 1, 1, 0.85), 800)

	# --- the profile corner -------------------------------------------------

	func _draw_chip() -> void:
		if profile == null:
			return
		var w := 340.0
		var h := 78.0
		var r := Rect2(Vector2(size.x - w - 40.0, 34.0), Vector2(w, h))
		_hit(r, "chip")
		var a := _a("chip")
		var rr := Rect2(r.position - Vector2(0, a * 2.0), r.size)
		draw_style_box(PoolTheme.box(Color(0.045, 0.05, 0.05, 0.84).lerp(Color(0.09, 0.1, 0.1, 0.92), a), 16,
			Color(1, 1, 1, 0.10 + a * 0.2), 1, 10), rr)
		var p := rr.position
		if not profile.signed_in:
			var ic := p + Vector2(40, h * 0.5)
			draw_circle(ic, 24.0, Color("1b2838"))
			draw_arc(ic, 24.0, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 1.5, true)
			_person(ic, 13.0, PoolTheme.WHITE)
			_text(p + Vector2(78, 35), "SIGN IN THROUGH STEAM", 19, PoolTheme.WHITE.lerp(PoolTheme.GOLD, a), 800, true,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			_text(p + Vector2(78, 57), "Keep your level, stats and trophies", 13, PoolTheme.MUTED, 500)
			return
		_avatar(Rect2(p + Vector2(11, 11), Vector2(56, 56)), 10)
		var tx := p.x + 80.0
		# trophies on the right
		var cnt := _num(int(profile.stats.trophies))
		var cw := _text_w(cnt, 22, 800, true)
		var tr_x := rr.end.x - 18.0 - cw
		_text(Vector2(tr_x, p.y + 49), cnt, 22, PoolTheme.WHITE, 800, true)
		_trophy(Vector2(tr_x - 20, p.y + 40), 26.0, PoolTheme.GOLD)
		var name_w := tr_x - 46.0 - tx
		_text(Vector2(tx, p.y + 34), _fit(profile.username, 19, 700, name_w), 19, PoolTheme.WHITE, 700)
		var lv := "LVL %d" % profile.level()
		_text(Vector2(tx, p.y + 60), lv, 13, PoolTheme.GOLD, 800, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		var bx := tx + _text_w(lv, 13, 800, false, 2) + 10.0
		var prog := profile.level_progress()
		_bar(Rect2(Vector2(bx, p.y + 52), Vector2(maxf(20.0, tr_x - 46.0 - bx), 6)), float(prog.x) / float(prog.y))

	func _bar(r: Rect2, k: float) -> void:
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.12), int(r.size.y * 0.5)), r)
		if k > 0.0:
			draw_style_box(PoolTheme.box(PoolTheme.GOLD, int(r.size.y * 0.5)),
				Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * clampf(k, 0.0, 1.0)), r.size.y)))

	func _avatar(r: Rect2, radius: int) -> void:
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.4), radius + 2), Rect2(r.position + Vector2(0, 3), r.size))
		if profile.avatar != null:
			draw_texture_rect(profile.avatar, r, false)
			draw_style_box(PoolTheme.box(Color(0, 0, 0, 0), radius, Color(1, 1, 1, 0.25), 2), r)
			return
		draw_style_box(PoolTheme.box(PoolTheme.FELT, radius, Color(1, 1, 1, 0.2), 1), r)
		var initial := profile.username.left(1).to_upper() if profile.username != "" else "?"
		var fs := int(r.size.y * 0.52)
		_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), initial, fs, PoolTheme.WHITE, 800, true,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	# a head and shoulders
	func _person(c: Vector2, s: float, col: Color) -> void:
		draw_circle(c + Vector2(0, -s * 0.38), s * 0.42, col)
		var pts := PackedVector2Array()
		for i in 17:
			var t := PI + PI * float(i) / 16.0
			pts.append(c + Vector2(cos(t) * s * 0.82, s * 0.95 + sin(t) * s * 0.78))
		draw_colored_polygon(pts, col)

	func _trophy(c: Vector2, s: float, col: Color) -> void:
		var cup := PackedVector2Array([
			c + Vector2(-0.42, -0.5) * s, c + Vector2(0.42, -0.5) * s, c + Vector2(0.36, -0.08) * s,
			c + Vector2(0.14, 0.14) * s, c + Vector2(-0.14, 0.14) * s, c + Vector2(-0.36, -0.08) * s])
		draw_colored_polygon(cup, col)
		draw_arc(c + Vector2(-0.4, -0.3) * s, 0.16 * s, PI * 0.5, PI * 1.5, 12, col, maxf(1.5, 0.07 * s), true)
		draw_arc(c + Vector2(0.4, -0.3) * s, 0.16 * s, -PI * 0.5, PI * 0.5, 12, col, maxf(1.5, 0.07 * s), true)
		draw_rect(Rect2(c + Vector2(-0.05, 0.12) * s, Vector2(0.1, 0.2) * s), col)
		draw_rect(Rect2(c + Vector2(-0.26, 0.3) * s, Vector2(0.52, 0.12) * s), col)

	# --- the full profile -----------------------------------------------------

	func _draw_profile() -> void:
		if profile == null or not profile.signed_in:
			return
		# the menu stays behind, dimmed; a click out there closes this
		var pt := page_t
		page_t = 1.0
		_draw_main()
		page_t = pt
		hits.clear()
		var e := _ease(page_t)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5 * e))
		_hit(Rect2(Vector2.ZERO, size), "close_bg")

		var pw := minf(780.0, size.x - 120.0)
		var panel := Rect2(Vector2(size.x - pw - 40.0 + (1.0 - e) * 90.0, 34.0), Vector2(pw, size.y - 68.0))
		_hit(panel, "panel")
		draw_style_box(PoolTheme.box(Color(0.04, 0.045, 0.045, 0.95), 20, PoolTheme.LINE, 1, 26), panel)
		var px := panel.position.x + 40.0
		var inner := pw - 80.0
		var y := panel.position.y + 40.0
		var st: Dictionary = profile.stats

		# close
		var cr := Rect2(Vector2(panel.end.x - 140, y - 8), Vector2(110, 40))
		_hit(cr, "close")
		_text(Vector2(cr.position.x, y + 20), "CLOSE  ✕", 16, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("close")),
			700, true, HORIZONTAL_ALIGNMENT_RIGHT, cr.size.x, 2)

		# who
		_avatar(Rect2(Vector2(px, y + 8), Vector2(116, 116)), 18)
		var nx := px + 144.0
		_text(Vector2(nx, y + 58), _fit(profile.username, 44, 800, inner - 144.0 - 120.0), 44, PoolTheme.WHITE, 800, true)
		var via := "TEST PROFILE  ·  NO STEAM IN THIS BUILD" if profile.test_profile else "SIGNED IN THROUGH STEAM"
		_text(Vector2(nx + 2, y + 86), via, 13, PoolTheme.GOLD, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		var so := Rect2(Vector2(nx - 4, y + 98), Vector2(110, 32))
		_hit(so, "signout")
		_text(Vector2(nx + 2, y + 120), "SIGN OUT", 14, PoolTheme.MUTED.lerp(PoolTheme.DANGER, _a("signout")), 700, false,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		y += 150.0

		# level
		var lvl_r := Rect2(Vector2(px, y), Vector2(inner, 104))
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.04), 14, PoolTheme.LINE, 1), lvl_r)
		var prog := profile.level_progress()
		_text(Vector2(px + 22, y + 44), "LEVEL %d" % profile.level(), 32, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
		_text(Vector2(px + 22, y + 44), "%s / %s XP" % [_num(prog.x), _num(prog.y)], 16, PoolTheme.MUTED, 600, false,
			HORIZONTAL_ALIGNMENT_RIGHT, inner - 44.0)
		_bar(Rect2(Vector2(px + 22, y + 58), Vector2(inner - 44, 10)), float(prog.x) / float(prog.y))
		_text(Vector2(px + 22, y + 90), "Earn XP beating the house player (more the tougher he is). Online matches are coming soon.",
			14, PoolTheme.MUTED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, inner - 44.0)
		y += 122.0

		# trophies
		var tr_r := Rect2(Vector2(px, y), Vector2(inner, 96))
		draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, 0.08), 14,
			Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, 0.35), 1), tr_r)
		_trophy(Vector2(px + 52, y + 50), 58.0, PoolTheme.GOLD)
		_text(Vector2(px + 100, y + 56), _num(int(st.trophies)), 44, PoolTheme.WHITE, 800, true)
		_text(Vector2(px + 102, y + 80), "TROPHIES", 13, PoolTheme.GOLD, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		draw_multiline_string(PoolTheme.font(400), Vector2(px + 250, y + 42),
			"One for every online match you win. Multiplayer is on its way.", HORIZONTAL_ALIGNMENT_LEFT,
			inner - 272.0, 15, 2, Color(1, 1, 1, 0.72))
		y += 124.0

		# everything else
		_text(Vector2(px, y), "STATS", 14, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		y += 18.0
		var bot_games := int(st.bot_wins) + int(st.bot_losses)
		var cards := [
			["GAMES PLAYED", _num(profile.games_played())],
			["WINS VS HOUSE", _num(int(st.bot_wins))],
			["GAMES LOST", _num(int(st.bot_losses) + int(st.mp_losses))],
			["WIN RATE", "%d%%" % int(round(100.0 * float(st.bot_wins) / float(bot_games))) if bot_games > 0 else "—"],
			["WIN STREAK", _num(int(st.streak))],
			["BEST STREAK", _num(int(st.best_streak))],
			["TOUGHEST BEATEN", "Level %d" % int(st.best_bot_beaten) if int(st.best_bot_beaten) > 0 else "—"],
			["SHOTS TAKEN", _num(int(st.shots))],
			["BALLS HIT", _num(int(st.balls_hit))],
			["BALLS POTTED", _num(int(st.balls_potted))],
			["FOULS", _num(int(st.fouls))],
			["TIME PLAYED", _duration(int(st.time_played))],
			["DRINKS ORDERED", _num(int(st.drinks))],
			["PUNCHES LANDED", _num(int(st.punches_landed))],
			["TIMES DECKED", _num(int(st.knockdowns))],
		]
		var cols := 3
		var gap := 12.0
		var cw := (inner - gap * float(cols - 1)) / float(cols)
		var ch := 70.0
		for i in cards.size():
			var c := Rect2(Vector2(px + float(i % cols) * (cw + gap), y + float(i / cols) * (ch + gap)), Vector2(cw, ch))
			draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.045), 12), c)
			_text(c.position + Vector2(16, 36), str(cards[i][1]), 26, PoolTheme.WHITE, 800, true)
			_text(c.position + Vector2(17, 57), str(cards[i][0]), 11, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)

	# --- little helpers ---------------------------------------------------------

	func _draw_toast() -> void:
		if toast_t <= 0.0 or toast == "":
			return
		var a := clampf(toast_t / 0.4, 0.0, 1.0) * clampf((3.5 - toast_t) / 0.2, 0.0, 1.0)
		var fs := 17
		var w := _text_w(toast, fs, 600) + 48.0
		var r := Rect2(Vector2((size.x - w) * 0.5, size.y - 150.0 + (1.0 - a) * 12.0), Vector2(w, 50))
		draw_style_box(PoolTheme.box(Color(0.05, 0.055, 0.055, 0.94 * a), 25, Color(PoolTheme.GOLD.r, PoolTheme.GOLD.g, PoolTheme.GOLD.b, 0.5 * a), 1, 10), r)
		_text(Vector2(r.position.x, r.position.y + 31), toast, fs, Color(1, 1, 1, a), 600, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	func _fit(s: String, fs: int, weight: int, max_w: float) -> String:
		if _text_w(s, fs, weight) <= max_w:
			return s
		while s.length() > 1 and _text_w(s + "…", fs, weight) > max_w:
			s = s.left(-1)
		return s + "…"

	func _num(n: int) -> String:
		var s := str(absi(n))
		var out := ""
		while s.length() > 3:
			out = "," + s.right(3) + out
			s = s.left(-3)
		return ("-" if n < 0 else "") + s + out

	func _duration(secs: int) -> String:
		if secs < 60:
			return "%ds" % secs
		var m := secs / 60
		if m < 60:
			return "%dm" % m
		return "%dh %dm" % [m / 60, m % 60]

# ---------------------------------------------------------------------------

func setup(state: Dictionary, profile: PoolProfile = null) -> void:
	layer = 5
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	preview = CuePreview.new()
	add_child(preview)
	preview.build()

	screen = Screen.new()
	screen.state = state
	screen.preview = preview
	screen.picked_cue = PoolCues.index_of(str(state.get("equipped", "house")))
	screen.profile = profile
	if profile != null:
		profile.message.connect(screen.show_toast)
	root.add_child(screen)
	screen.start_pressed.connect(func(d): start_pressed.emit(d))
	screen.state_changed.connect(func(st): state_changed.emit(st))
	screen.quit_pressed.connect(func(): quit_pressed.emit())
	screen.ui_sound.connect(func(k): ui_sound.emit(k))

	_layout()
	get_viewport().size_changed.connect(_layout)


# Sized by hand: an anchor preset on its own leaves the panel at zero size and
# everything on it lands in the corner.
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	for c: Control in [root, screen]:
		c.anchor_left = 0.0
		c.anchor_top = 0.0
		c.anchor_right = 0.0
		c.anchor_bottom = 0.0
		c.offset_left = 0.0
		c.offset_top = 0.0
		c.offset_right = vs.x
		c.offset_bottom = vs.y
		c.position = Vector2.ZERO
		c.size = vs
	screen.queue_redraw()


func bar_fraction() -> float:
	if screen == null or screen.size.x < 1.0:
		return 0.36
	return screen.bar_width() / screen.size.x


func set_state(state: Dictionary) -> void:
	screen.state = state
	screen.picked_cue = PoolCues.index_of(str(state.get("equipped", "house")))
	screen.queue_redraw()


func open() -> void:
	visible = true
	screen.visible = true
	screen.page = "main"
	screen.page_t = 0.0
	screen.set_process_unhandled_key_input(true)
	preview.set_live(false)
	_layout()


# Hiding a CanvasLayer does not hide its children as far as input is
# concerned, which is how the space bar was still starting a new match
# halfway through a game.
func close() -> void:
	visible = false
	screen.visible = false
	screen.set_process_unhandled_key_input(false)
	preview.set_live(false)
