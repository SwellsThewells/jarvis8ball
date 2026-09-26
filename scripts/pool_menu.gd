class_name PoolMenu
extends CanvasLayer

# Title screen, over the table turning slowly in the room behind it. A column
# of big menu words on the left, and each page (play, shop, how to play,
# settings) slides in on the same side so the table stays in view on the
# right. Your profile sits in the top right corner: a sign-in button until
# you're signed in with Discord, then your name, level and trophies, and it
# opens out into the full profile.

signal start_pressed(difficulty: int)
signal state_changed(state: Dictionary)
signal quit_pressed()
signal ui_sound(kind: String)
signal online_start()
signal buy_requested(id: String)
signal code_entered(code: String)

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
	signal online_start()
	signal buy_requested(id: String)
	signal code_entered(code: String)

	var state := {"owned": ["house"], "equipped": "house", "difficulty": 5, "guides": true}
	var page := "main"            # main, mode, play, shop, info, settings, code, profile
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
	var online: PoolOnline

	# online pages
	var edits := {}               # name -> LineEdit, made the first time a page asks for one
	var _edits_used := {}
	var busy := false             # a request is out; buttons wait for it
	var friends_open := false
	var fr_tab := "friends"       # friends, requests, add
	var fr_chat := ""             # whose conversation is open ("" for the list)
	var fr_scroll := 0
	var fr_results: Array = []
	var fr_searched := false
	var chat_scroll := 0
	var browse: Array = []
	var browse_t := 99.0
	var browse_scroll := 0
	var browse_loaded := false
	var create_rules := {}
	var create_public := true
	var create_edit := false      # changing the lobby you're in, not making one
	var my_ready := false

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
	const SET_ROW_H := 66.0
	var slider_rects := {}
	var dragging_slider := ""

	var toast := ""
	var toast_t := 0.0

	# the secret code page, behind the little J ball in Settings
	var code_edit: LineEdit
	var code_msg := ""
	var code_shake := 0.0
	var mp_nudge := 0.0           # the multiplayer card shaking its head
	var _reveal_pick := false     # scroll the shop to the picked cue on its next draw

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
		# a real text box for typing codes; we draw its frame ourselves
		code_edit = LineEdit.new()
		code_edit.visible = false
		code_edit.max_length = 24
		code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		code_edit.placeholder_text = "TYPE A CODE"
		code_edit.context_menu_enabled = false
		code_edit.add_theme_font_override("font", PoolTheme.font(800, true, 6))
		code_edit.add_theme_font_size_override("font_size", 36)
		code_edit.add_theme_color_override("font_color", PoolTheme.WHITE)
		code_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.22))
		code_edit.add_theme_color_override("caret_color", PoolTheme.GOLD)
		for st in ["normal", "focus", "read_only"]:
			code_edit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		code_edit.text_changed.connect(func(s: String):
			var up := s.to_upper()
			if up != s:
				var c := code_edit.caret_column
				code_edit.text = up
				code_edit.caret_column = c
			code_msg = ""
		)
		code_edit.text_submitted.connect(func(_s: String): _redeem())
		add_child(code_edit)

	func _process(delta: float) -> void:
		t += delta
		page_t = minf(1.0, page_t + delta * 4.5)
		toast_t = maxf(0.0, toast_t - delta)
		code_shake = maxf(0.0, code_shake - delta * 2.5)
		mp_nudge = maxf(0.0, mp_nudge - delta * 2.5)
		if page == "profile" and (profile == null or not profile.signed_in):
			go("main")
		if online != null:
			if page == "lobby" and online.lobby.is_empty():
				go("mp")
			if page in ["mp_create", "mp_browse"] and not online.signed_in():
				go("mp")
			if friends_open and not online.signed_in():
				friends_open = false
			if page == "mp_browse" and online.signed_in():
				browse_t += delta
				if browse_t > 6.0 and not busy:
					browse_t = 0.0
					_load_browse()
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
		if code_edit != null:
			code_edit.visible = p == "code"
			code_edit.text = ""
			code_msg = ""
			if p == "code":
				code_edit.grab_focus.call_deferred()
			else:
				code_edit.release_focus()
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
			if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var step := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				if friends_open:
					if fr_chat != "":
						chat_scroll = maxi(0, chat_scroll - step)
					else:
						fr_scroll = maxi(0, fr_scroll + step)
					return
				if page == "mp_browse":
					browse_scroll = clampi(browse_scroll + step, 0, maxi(0, browse.size() - 1))
					return
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
		var content := float(PoolCues.shop_indices(state.owned).size()) * ROW_H
		scroll_to = clampf(scroll_to + dy, 0.0, maxf(0.0, content - list_rect.size.y))

	func _update_hot() -> void:
		hot = ""
		for h in hits:
			if (h[0] as Rect2).has_point(hover):
				hot = str(h[1])
		if hot != _last_hot:
			if hot != "" and not hot.begins_with("cue:") and not (hot in ["panel", "close_bg", "jball"]):
				ui_sound.emit("tick")
			_last_hot = hot

	func _press(name: String) -> void:
		if name == "play":
			go("mode")
		elif name in ["shop", "info", "settings"]:
			go(name)
		elif name == "mode_bot":
			go("play")
		elif name == "mode_mp":
			go("mp")
		elif _press_online(name):
			pass
		elif name == "chip":
			if profile != null and profile.signed_in:
				friends_open = false
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
			match page:
				"code":
					go("settings")
				"play", "mp":
					go("mode")
				"mp_create":
					go("lobby" if create_edit else "mp")
				"mp_browse":
					go("mp")
				"lobby":
					_leave_lobby()
				_:
					go("main")
		elif name == "jball":
			go("code")
		elif name == "redeem":
			_redeem()
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
			buy_requested.emit(str(cue.id))
			return
		state.equipped = cue.id
		state_changed.emit(state)
		ui_sound.emit("equip")

	func _redeem() -> void:
		if code_edit.text.strip_edges() == "":
			code_msg = "Type a code first."
			code_shake = 1.0
			ui_sound.emit("click")
			code_edit.grab_focus.call_deferred()
			return
		if busy:
			return
		busy = true
		code_entered.emit(code_edit.text)

	# What the game made of the code: the cue it unlocked, or "".
	func code_result(id: String, fresh: bool) -> void:
		busy = false
		if id == "":
			code_msg = "That code doesn't do anything."
			code_shake = 1.0
			ui_sound.emit("click")
			code_edit.grab_focus.call_deferred()
			return
		picked_cue = PoolCues.index_of(id)
		_reveal_pick = true
		go("shop")
		ui_sound.emit("start" if fresh else "equip")
		var cue := PoolCues.by_id(id)
		show_toast(("Unlocked: %s" if fresh else "You've already got %s. It's in your hand.") % str(cue.name))

	func _unhandled_key_input(ev: InputEvent) -> void:
		if not is_visible_in_tree() or not (ev is InputEventKey and ev.pressed and not ev.echo):
			return
		match ev.keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				if friends_open:
					if ev.keycode == KEY_ESCAPE:
						if fr_chat != "":
							_close_chat()
						else:
							friends_open = false
					return
				if page == "lobby":
					return
				if page == "code":
					if ev.keycode == KEY_ESCAPE:
						go("settings")
				elif page in ["play", "mp"]:
					go("mode")
				elif page in ["mp_create", "mp_browse"]:
					go("mp")
				elif page != "main":
					go("main")
			KEY_ENTER, KEY_KP_ENTER:
				if page == "code":
					_redeem()
				elif page == "play":
					_press("start")
				elif page == "mode":
					go("play")
				elif page == "main":
					go("mode")
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
		var list := PoolCues.shop_indices(state.owned)
		var at := clampi(list.find(picked_cue) + d, 0, list.size() - 1)
		_press("cue:%d" % int(list[at]))
		_scroll_to_pick()

	# scrolls the shop list just far enough to show the picked cue
	func _scroll_to_pick() -> void:
		var row := maxi(0, PoolCues.shop_indices(state.owned).find(picked_cue))
		var top := float(row) * ROW_H
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
		_edits_used.clear()
		list_view.visible = page == "shop"
		_draw_shade()
		match page:
			"main":
				_draw_main()
			"mode":
				_draw_mode()
			"play":
				_draw_play()
			"shop":
				_draw_shop()
			"info":
				_draw_info()
			"settings":
				_draw_settings()
			"code":
				_draw_code()
			"mp":
				_draw_mp()
			"mp_create":
				_draw_mp_create()
			"mp_browse":
				_draw_mp_browse()
			"lobby":
				_draw_lobby()
			"profile":
				_draw_profile()
		if page != "profile":
			_draw_chip()
		if friends_open:
			_draw_friends()
		_draw_toast()
		for k in edits:
			var le: LineEdit = edits[k]
			if not _edits_used.has(k) and le.visible:
				le.visible = false
				le.release_focus()
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
		var r := Rect2(Vector2(x - 4, y - 24), Vector2(104, 36))
		_hit(r, "back")
		var a := _a("back")
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.04 + a * 0.06), 18, Color(1, 1, 1, 0.12 + a * 0.16), 1), r)
		_text(Vector2(r.position.x, r.get_center().y + 5.0), "‹  BACK", 14, PoolTheme.MUTED.lerp(PoolTheme.WHITE, a), 700, true,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)

	func _page_title(x: float, y: float, s: String, sub: String) -> void:
		var e := _ease(page_t)
		var dx := (1.0 - e) * -30.0
		if sub != "":
			PoolTheme.caps(self, Vector2(x + dx + 2, y - 60), sub, Color(PoolTheme.GOLD, e), 13)
		_text(Vector2(x + dx, y), s, 60, Color(1, 1, 1, e), 800, true)

	func _button(r: Rect2, name: String, label: String, primary := true, enabled := true) -> void:
		if enabled:
			_hit(r, name)
		var a := _a(name) if enabled else 0.0
		PoolTheme.button(self, r, label, "primary" if primary else "secondary", a, enabled, 20 if r.size.y >= 56.0 else 15)

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
		_chip(Vector2(x + 560, by), "COINS", _num(int(state.get("cash", 0))))

	func _chip(at: Vector2, label: String, value: String) -> void:
		_text(at, label, 13, PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		_text(at + Vector2(0, 26), value, 20, PoolTheme.WHITE, 600)

	# --- mode -------------------------------------------------------------

	func _draw_mode() -> void:
		var x := 84.0
		_back_button(x, 70.0)
		_page_title(x, 170.0, "PLAY", "CHOOSE A GAME MODE")
		var cw := clampf((size.x - x * 2.0 - 24.0) * 0.5, 300.0, 400.0)
		var cards := [
			["mode_bot", "VS COMPUTER", "Eight-ball against the house player. Pick how good he is, from 1 to 10.", true],
			["mode_mp", "MULTIPLAYER", "Take on your friends or anyone online. Winners take a trophy and 50 coins.", true],
		]
		for i in 2:
			var d: Array = cards[i]
			var ei := _ease(page_t * 1.4 - float(i) * 0.15)
			var nm: String = d[0]
			var live: bool = d[3]
			var a := _a(nm)
			var shake := 0.0 if live else sin(t * 50.0) * mp_nudge * mp_nudge * 10.0
			var r := Rect2(Vector2(x + float(i) * (cw + 24.0) + (1.0 - ei) * -40.0 + shake, 236.0), Vector2(cw, 420))
			_hit(r, nm)
			var rr := Rect2(r.position - Vector2(0, a * 4.0 if live else 0.0), r.size)
			PoolTheme.panel(self, rr)
			if live and a > 0.01:
				draw_style_box(PoolTheme.box(Color(0, 0, 0, 0), 16, Color(PoolTheme.GOLD, 0.7 * a), 1), rr)
			var alpha := 1.0 if live else 0.5
			var art := Rect2(rr.position + Vector2(16, 16), Vector2(rr.size.x - 32, 200))
			draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.035 + (a * 0.02 if live else 0.0)), 12), art)
			if nm == "mode_bot":
				_icon_bot(art.get_center(), a)
			else:
				_icon_mp(art.get_center(), a)
			var ty := art.end.y + 58.0
			_text(Vector2(rr.position.x + 28, ty), str(d[1]), 34, Color(PoolTheme.WHITE, alpha), 800, true,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			draw_multiline_string(PoolTheme.font(400), Vector2(rr.position.x + 28, ty + 32), str(d[2]),
				HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 56.0, 16, 3, Color(1, 1, 1, 0.66 * alpha))
			var fy := rr.end.y - 32.0
			if live:
				_text(Vector2(rr.position.x + 28 + a * 4.0, fy), "CHOOSE OPPONENT  ›" if nm == "mode_bot" else "FIND A GAME  ›", 15,
					PoolTheme.GOLD.lerp(Color("ffd978"), a), 700, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
			else:
				_text(Vector2(rr.position.x + 28, fy), "ON ITS WAY", 15, PoolTheme.FAINT, 700, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)

	# the house player's card: the J ball with a cue lined up on it
	func _icon_bot(c: Vector2, a: float) -> void:
		if logo == null:
			logo = load("res://icon.png")
		var r := 54.0 + a * 3.0
		draw_circle(c + Vector2(0, 8), r, Color(0, 0, 0, 0.35), true, -1.0, true)
		if logo != null:
			draw_texture_rect(logo, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		var d := Vector2(-1.0, 0.42).normalized()
		var tip := c + d * (r + 14.0 - a * 6.0)
		draw_line(tip, tip + d * 96.0, Color("d9bf8c"), 6.0, true)
		draw_line(tip, tip + d * 6.0, Color("2c4a6e"), 6.0, true)

	# two people: you and a friend
	func _icon_mp(c: Vector2, a := 0.0) -> void:
		var col := Color(1, 1, 1, 0.5 + a * 0.2)
		_person(c + Vector2(-34, 0), 44.0, col)
		_person(c + Vector2(34, 0), 44.0, col)
		draw_circle(c + Vector2(0, -4), 18.0, Color(0.08, 0.085, 0.09), true, -1.0, true)
		_text(Vector2(c.x - 20, c.y + 3), "VS", 15, PoolTheme.GOLD, 800, true, HORIZONTAL_ALIGNMENT_CENTER, 40)

	# --- play against the house ------------------------------------------

	func _draw_play() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "VS COMPUTER", "EIGHT-BALL")
		var pw := clampf(bar_width() - x + 40.0, 480.0, 600.0)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(pw, 456))
		PoolTheme.panel(self, panel)
		var px := panel.position.x + 32.0
		var inner_w := panel.size.x - 64.0
		var y := panel.position.y + 46.0
		PoolTheme.caps(self, Vector2(px, y), "OPPONENT")
		var diff := clampi(int(state.difficulty), 1, 10)

		# his level, big, beside who he is
		y += 84.0
		var num := str(diff)
		_text(Vector2(px - 3, y), num, 88, PoolTheme.GOLD, 800, true)
		var nw := _text_w(num, 88, 800, true)
		var name_s: String = PoolAI.SKILL_LABELS[diff - 1]
		_text(Vector2(px + nw + 18, y - 36), name_s.to_upper(), 30, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
		PoolTheme.caps(self, Vector2(px + nw + 20, y - 10), "LEVEL %d OF 10" % diff, PoolTheme.FAINT, 11)
		for k in 2:
			var nm := "lvl_down" if k == 0 else "lvl_up"
			var c := Vector2(px + inner_w - 20.0 - (52.0 if k == 0 else 0.0), y - 32.0)
			var en := diff > 1 if k == 0 else diff < 10
			if en:
				_hit(Rect2(c - Vector2(22, 22), Vector2(44, 44)), nm)
			var a := _a(nm) if en else 0.0
			draw_circle(c, 20.0, Color(1, 1, 1, 0.05 + a * 0.08), true, -1.0, true)
			draw_arc(c, 20.0, 0.0, TAU, 48, Color(1, 1, 1, 0.14 + a * 0.22), 1.0, true)
			_chevron(c, -1.0 if k == 0 else 1.0, Color(1, 1, 1, 0.9 if en else 0.25))

		# ten steps, any of them a click away
		y += 30.0
		var gap := 4.0
		var sw := (inner_w - gap * 9.0) / 10.0
		for i in 10:
			var r := Rect2(Vector2(px + float(i) * (sw + gap), y), Vector2(sw, 6))
			var nm2 := "lvl:%d" % (i + 1)
			_hit(Rect2(r.position - Vector2(0, 12), Vector2(sw + gap, 30)), nm2)
			var a2 := _a(nm2)
			var col := PoolTheme.GOLD.lerp(Color("ff8a3d"), float(i) / 9.0) if i + 1 <= diff else Color(1, 1, 1, 0.12 + a2 * 0.2)
			draw_style_box(PoolTheme.box(col, 3), Rect2(r.position - Vector2(0, a2 * 2.0), r.size + Vector2(0, a2 * 4.0)))
		y += 46.0
		draw_multiline_string(PoolTheme.font(400), Vector2(px, y), _level_blurb(diff), HORIZONTAL_ALIGNMENT_LEFT,
			inner_w, 16, 2, Color(1, 1, 1, 0.7))

		# the aiming guide
		y += 52.0
		PoolTheme.divider(self, px, px + inner_w, y)
		var on_g := bool(state.get("guides", true))
		_hit(Rect2(Vector2(px, y + 4), Vector2(inner_w, 64)), "guides")
		_text(Vector2(px, y + 34), "Aim guide", 17, PoolTheme.WHITE, 600)
		_text(Vector2(px, y + 55), "Lines showing where the balls will go" if on_g else "No lines. Just you and the table",
			13, PoolTheme.MUTED, 400)
		PoolTheme.switch(self, Vector2(px + inner_w - 46, y + 23), on_g, _a("guides"))

		_button(Rect2(Vector2(px, panel.end.y - 32 - 60), Vector2(inner_w, 60)), "start", "START MATCH")

	func _level_blurb(d: int) -> String:
		if d <= 2:
			return "Misses plenty and never plans ahead. Good for learning the table."
		if d <= 4:
			return "Pots the easy ones, but doesn't think much about where the cue ball ends up."
		if d <= 6:
			return "A decent stick. Plays some position and knows when to play safe."
		if d <= 8:
			return "Solid. Thinks a shot or two ahead, and banks it when nothing's on."
		if d == 9:
			return "Rarely misses and leaves you nothing. Bring your best."
		return "Barely misses. Plays every shot through in his head before he takes it."

	# a small arrow, pointing left (-1) or right (1)
	func _chevron(c: Vector2, dir: float, col: Color) -> void:
		var s := 5.0
		draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5 * dir, -s), c + Vector2(s * 0.5 * dir, 0), c + Vector2(-s * 0.5 * dir, s)]),
			col, 2.0, true)

	# --- shop -------------------------------------------------------------

	func _draw_shop() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		var shop := PoolCues.shop_indices(state.owned)
		_page_title(x, 170.0, "SHOP", "%s COINS TO SPEND" % _num(int(state.get("cash", 0))))

		# the list: its frame here, its rows drawn clipped inside list_view
		var lw := 420.0
		list_rect = Rect2(Vector2(x - 12 + (1.0 - e) * -50.0, 216), Vector2(lw, size.y - 216 - 56))
		PoolTheme.panel(self, list_rect.grow(8), Color(0, 0, 0, 0), 14)
		list_view.position = list_rect.position
		list_view.size = list_rect.size
		if _reveal_pick:
			_reveal_pick = false
			_scroll_to_pick()
			scroll = scroll_to
		list_view.queue_redraw()
		for row in shop.size():
			var r := _row_rect(row)
			r.position += list_rect.position
			var vis := r.intersection(list_rect)
			if vis.size.y > 2.0:
				_hit(vis, "cue:%d" % int(shop[row]))
		# scroll bar
		var content := float(shop.size()) * ROW_H
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
		draw_style_box(PoolTheme.box(Color(0.043, 0.047, 0.051, 0.72), 16, PoolTheme.HAIR, 1), pr)
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
		var have := (state.owned as Array).has(pick.id)
		var price := int(pick.price)
		var wallet := int(state.get("cash", 0))
		var br := Rect2(Vector2(pr.end.x - 300, pr.end.y + 36), Vector2(300, 72))
		if have or price == 0:
			_button(br, "equip", "EQUIPPED" if is_on else ("EQUIP" if have else "TAKE IT"), not is_on, not is_on)
		elif wallet >= price:
			_button(br, "equip", "BUY  ·  %s" % _num(price), true, true)
		else:
			_button(br, "equip", "NEED %s MORE" % _num(price - wallet), false, false)
		_coin(Vector2(br.position.x + 16, br.end.y + 26), 8.0)
		_text(Vector2(br.position.x + 30, br.end.y + 31), "You have %s coins" % _num(wallet), 14, PoolTheme.MUTED, 500)

	# a row of the cue list, in the list's own coordinates
	func _row_rect(i: int) -> Rect2:
		return Rect2(Vector2(0.0, float(i) * ROW_H - scroll), Vector2(list_rect.size.x, ROW_H - 6))

	func _draw_list() -> void:
		var c := list_view
		var owned: Array = state.owned
		var font_b := PoolTheme.font(700)
		var font_t := PoolTheme.font(700, false, 2)
		var shop := PoolCues.shop_indices(owned)
		for row in shop.size():
			var r := _row_rect(row)
			if r.end.y < 0.0 or r.position.y > c.size.y:
				continue
			var i: int = shop[row]
			var cue: Dictionary = PoolCues.CUES[i]
			var a := _a("cue:%d" % i)
			var on := picked_cue == i
			var equipped := str(state.equipped) == str(cue.id)
			var bg := Color(1, 1, 1, 0.02 + a * 0.05)
			if on:
				bg = Color(PoolTheme.GOLD, 0.1)
			c.draw_style_box(PoolTheme.box(bg, 10, Color(PoolTheme.GOLD, 0.8) if on else Color(0, 0, 0, 0), 1 if on else 0), r)
			var cols := PoolCues.swatch(cue)
			var sw := Rect2(r.position + Vector2(12, 14), Vector2(10, r.size.y - 28))
			c.draw_style_box(PoolTheme.box(cols[0], 4), sw)
			c.draw_style_box(PoolTheme.box(cols[1], 4), Rect2(sw.position, Vector2(sw.size.x, sw.size.y * 0.5)))
			c.draw_string(font_b, r.position + Vector2(36, 32), str(cue.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, PoolTheme.WHITE)
			c.draw_string(font_t, r.position + Vector2(36, 54), str(cue.tag).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PoolTheme.MUTED)
			var badge := "EQUIPPED" if equipped else ("OWNED" if owned.has(cue.id) else ("FREE" if int(cue.price) == 0 else "%s COINS" % _num(int(cue.price))))
			var bcol := PoolTheme.FELT_HI if equipped else (PoolTheme.MUTED if owned.has(cue.id) else PoolTheme.GOLD)
			PoolTheme.badge(c, Vector2(r.end.x - 14, r.position.y + (r.size.y - 22.0) * 0.5), badge, bcol)

	# --- how to play ------------------------------------------------------

	func _draw_info() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "HOW TO PLAY", "AT THE TABLE")
		var w := minf(size.x - 2.0 * x, 1180.0)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(w, size.y - 236 - 60))
		PoolTheme.panel(self, panel)
		var px := panel.position.x + 36.0
		var y := panel.position.y + 50.0
		var col_w := (panel.size.x - 72.0 - 56.0) * 0.56
		var rules_w := panel.size.x - 72.0 - 56.0 - col_w
		PoolTheme.caps(self, Vector2(px, y), "CONTROLS", PoolTheme.GOLD)
		y += 34.0
		for row in CONTROLS:
			var kx := px
			for k in row[0]:
				kx += _keycap(Vector2(kx, y - 4), str(k)) + 6.0
			_text(Vector2(px + 160, y + 18), _fit(str(row[1]), 16, 400, col_w - 160.0), 16, PoolTheme.WHITE, 400)
			y += 50.0
		var rx := px + col_w + 56.0
		var ry := panel.position.y + 50.0
		PoolTheme.caps(self, Vector2(rx, ry), "RULES", PoolTheme.GOLD)
		ry += 34.0
		for i in RULES.size():
			draw_circle(Vector2(rx + 4, ry + 13), 3.5, PoolTheme.GOLD, true, -1.0, true)
			draw_multiline_string(PoolTheme.font(400), Vector2(rx + 20, ry + 19), str(RULES[i]),
				HORIZONTAL_ALIGNMENT_LEFT, rules_w - 20.0, 16, 3, Color(1, 1, 1, 0.82))
			ry += 76.0

	func _keycap(at: Vector2, label: String) -> float:
		return PoolTheme.keycap(self, at, label, 32.0, 13)

	# --- settings ---------------------------------------------------------

	func _draw_settings() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "SETTINGS", "SOUND, CONTROLS AND SCREEN")
		var w := minf(size.x - 2.0 * x, 1120.0)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(w, 36.0 + 2.0 * 38.0 + 22.0 + 7.0 * SET_ROW_H + 32.0))
		PoolTheme.panel(self, panel)
		var gutter := 56.0
		var col_w := (panel.size.x - 72.0 - gutter) * 0.5
		var cx := panel.position.x + 36.0
		var top := panel.position.y + 36.0
		var y := top
		slider_rects.clear()
		for i in SETTING_ROWS.size():
			var row: Array = SETTING_ROWS[i]
			if row.size() == 1:
				if row[0] == "DISPLAY":
					# the second column
					cx += col_w + gutter
					y = top
				elif y > top:
					y += 22.0
				PoolTheme.caps(self, Vector2(cx, y + 14), str(row[0]), PoolTheme.GOLD)
				y += 38.0
				continue
			var last := i + 1 >= SETTING_ROWS.size() or (SETTING_ROWS[i + 1] as Array).size() == 1
			_setting_row(Rect2(Vector2(cx, y), Vector2(col_w, SET_ROW_H)), row, last)
			y += SET_ROW_H
		var rr := Rect2(Vector2(panel.end.x - 36.0 - 220.0, panel.end.y - 32.0 - 46.0), Vector2(220, 46))
		_button(rr, "reset_settings", "Reset to defaults", false)
		# tucked in the bottom corner, barely there: the way to the code page
		var jc := panel.end - Vector2(18, 18)
		_hit(Rect2(jc - Vector2(11, 11), Vector2(22, 22)), "jball")
		_jball(jc, 7.0, 0.16 + _a("jball") * 0.3, t * 0.3)

	func _jball(c: Vector2, r: float, alpha: float, turn := 0.0) -> void:
		if logo == null:
			logo = load("res://icon.png")
		if logo == null:
			return
		draw_set_transform(c, turn, Vector2.ONE)
		draw_texture_rect(logo, Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- secret code ------------------------------------------------------

	func _draw_code() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "ENTER CODE", "YOU FOUND THE J BALL")
		var pw := minf(520.0, size.x - 2.0 * x)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(pw, 330))
		PoolTheme.panel(self, panel)
		var px := panel.position.x + 32.0
		var inner_w := panel.size.x - 64.0
		var y := panel.position.y + 46.0
		PoolTheme.caps(self, Vector2(px, y), "CODE")
		_jball(Vector2(panel.end.x - 44, panel.position.y + 40), 16.0, e, sin(t * 1.3) * 0.4)
		# the box, shaking its head at a wrong code
		var shake := sin(t * 55.0) * code_shake * code_shake * 14.0
		var box := Rect2(Vector2(px + shake, y + 22), Vector2(inner_w, 72))
		var edge := PoolTheme.DANGER if code_msg != "" else (PoolTheme.GOLD if code_edit.has_focus() else Color(1, 1, 1, 0.16))
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.35), 12, edge, 1), box)
		code_edit.position = box.position + Vector2(10, 4)
		code_edit.size = box.size - Vector2(20, 8)
		if code_msg != "":
			_text(Vector2(px, box.end.y + 32), code_msg, 14, PoolTheme.DANGER, 600)
		else:
			_text(Vector2(px, box.end.y + 32), "Some cues aren't in the shop.", 14, PoolTheme.MUTED, 400)
		_button(Rect2(Vector2(px, panel.end.y - 32 - 56), Vector2(inner_w, 56)), "redeem", "Unlock")

	func _setting_row(r: Rect2, row: Array, last := false) -> void:
		var kind: String = row[0]
		var key: String = row[1]
		if not last:
			PoolTheme.divider(self, r.position.x, r.end.x, r.end.y)
		var ctl_w := 250.0
		# a switch only needs its own width; sliders and pickers take more
		var text_w := r.size.x - (64.0 if kind == "toggle" else ctl_w + 20.0)
		_text(r.position + Vector2(0, 29), str(row[2]), 17, PoolTheme.WHITE, 600, false, HORIZONTAL_ALIGNMENT_LEFT, text_w)
		_text(r.position + Vector2(0, 49), _fit(str(row[3]), 13, 400, text_w), 13, PoolTheme.MUTED, 400, false,
			HORIZONTAL_ALIGNMENT_LEFT, text_w)
		var cy := r.position.y + r.size.y * 0.5
		match kind:
			"slider":
				var nm := "slider:" + key
				var track := Rect2(Vector2(r.end.x - ctl_w, cy - 10), Vector2(ctl_w - 64, 20))
				slider_rects[key] = track
				_hit(Rect2(Vector2(track.position.x - 12, r.position.y), Vector2(track.size.x + 24, r.size.y)), nm)
				var rng := _slider_range(key)
				var v := PoolSettings.f(key)
				var a := maxf(_a(nm), 1.0 if dragging_slider == key else 0.0)
				PoolTheme.slider(self, track, inverse_lerp(rng.x, rng.y, v), a)
				var label := "%d%%" % int(round(v * 100.0))
				if key == "mouse_sens":
					label = "%.2f×" % v
				elif key == "fov":
					label = "%d°" % int(v)
				_text(Vector2(r.end.x - 52, cy + 6), label, 15, PoolTheme.WHITE, 700, false, HORIZONTAL_ALIGNMENT_RIGHT, 52)
			"toggle":
				var nm := "tog:" + key
				_hit(Rect2(r.position, Vector2(r.size.x, r.size.y - 2)), nm)
				PoolTheme.switch(self, Vector2(r.end.x - 46, cy - 13), PoolSettings.on(key), _a(nm))
			"cycle":
				var v := int(PoolSettings.data.get(key, 0))
				var label := "NO CAP" if v == 0 else "%d FPS" % v
				var box := Rect2(Vector2(r.end.x - 176, cy - 18), Vector2(176, 36))
				draw_style_box(PoolTheme.box(PoolTheme.RAISED, 18, PoolTheme.HAIR, 1), box)
				for k in 2:
					var nm := ("cyc-:" if k == 0 else "cyc+:") + key
					var br := Rect2(Vector2(box.position.x if k == 0 else box.end.x - 40, box.position.y), Vector2(40, 36))
					_hit(br, nm)
					var a := _a(nm)
					if a > 0.01:
						draw_circle(br.get_center(), 14.0, Color(1, 1, 1, 0.08 * a), true, -1.0, true)
					_chevron(br.get_center(), -1.0 if k == 0 else 1.0, PoolTheme.MUTED.lerp(PoolTheme.WHITE, a))
				_text(Vector2(box.position.x + 40, cy + 6), label, 15, PoolTheme.WHITE, 700, true,
					HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 80, 1)

	# --- the profile corner -------------------------------------------------

	func _draw_chip() -> void:
		if profile == null:
			return
		var w := 320.0
		var h := 64.0
		var r := Rect2(Vector2(size.x - w - 40.0, 36.0), Vector2(w, h))
		_hit(r, "chip")
		var a := _a("chip")
		draw_style_box(PoolTheme.box(PoolTheme.PANEL.lerp(Color(0.1, 0.105, 0.11, 0.94), a), 14,
			Color(1, 1, 1, 0.08 + a * 0.14), 1), r)
		var p := r.position
		# coins, and your friends, to the left of it
		var fx := r.position.x - 12.0
		if online != null and online.signed_in():
			var fb := Rect2(Vector2(fx - h, r.position.y), Vector2(h, h))
			fx = fb.position.x - 12.0
			_hit(fb, "friends_btn")
			var fa := maxf(_a("friends_btn"), 1.0 if friends_open else 0.0)
			draw_style_box(PoolTheme.box(PoolTheme.PANEL.lerp(Color(0.1, 0.105, 0.11, 0.94), fa), 14,
				Color(1, 1, 1, 0.08 + fa * 0.14), 1), fb)
			var fc := fb.get_center()
			_person(fc + Vector2(-7, -2), 9.0, Color(1, 1, 1, 0.55 + fa * 0.3))
			_person(fc + Vector2(6, 0), 10.0, PoolTheme.WHITE)
			var n := online.unread_total() + online.incoming_requests()
			if n > 0:
				var bc := fb.position + Vector2(fb.size.x - 10, 10)
				draw_circle(bc, 10.0, PoolTheme.DANGER, true, -1.0, true)
				_text(Vector2(bc.x - 10, bc.y + 5), str(mini(n, 9)), 12, PoolTheme.WHITE, 800, false, HORIZONTAL_ALIGNMENT_CENTER, 20)
		var cash := _num(int(state.get("cash", 0)))
		var cwid := _text_w(cash, 18, 800, true) + 56.0
		var cr := Rect2(Vector2(fx - cwid, r.position.y + 12), Vector2(cwid, 40))
		draw_style_box(PoolTheme.box(PoolTheme.PANEL, 20, PoolTheme.HAIR, 1), cr)
		_coin(cr.position + Vector2(22, 20), 9.0)
		_text(Vector2(cr.position.x + 38, cr.position.y + 27), cash, 18, PoolTheme.WHITE, 800, true)
		if not profile.signed_in:
			var ic := p + Vector2(34, h * 0.5)
			_discord_icon(ic, 20.0)
			var waiting := online != null and online.signing_in
			_text(p + Vector2(66, 29), "Waiting for Discord..." if waiting else "Sign in with Discord", 16,
				PoolTheme.WHITE.lerp(PoolTheme.GOLD, a), 700)
			_text(p + Vector2(66, 48), "Click to cancel" if waiting else "Play online, keep your stats", 12, PoolTheme.MUTED, 400)
			_text(Vector2(r.end.x - 34, p.y + h * 0.5 + 7), "›", 22, PoolTheme.MUTED.lerp(PoolTheme.WHITE, a), 700, false,
				HORIZONTAL_ALIGNMENT_CENTER, 20)
			return
		_avatar(Rect2(p + Vector2(10, 10), Vector2(44, 44)), 10)
		var tx := p.x + 66.0
		# trophies on the right
		var cnt := _num(int(profile.stats.trophies))
		var cw := _text_w(cnt, 18, 800, true)
		var tr_x := r.end.x - 16.0 - cw
		_text(Vector2(tr_x, p.y + 39), cnt, 18, PoolTheme.WHITE, 800, true)
		_trophy(Vector2(tr_x - 16, p.y + 32), 20.0, PoolTheme.GOLD)
		var name_w := tr_x - 36.0 - tx
		_text(Vector2(tx, p.y + 28), _fit(profile.username, 16, 700, name_w), 16, PoolTheme.WHITE, 700)
		var lv := "LVL %d" % profile.level()
		PoolTheme.caps(self, Vector2(tx, p.y + 48), lv, PoolTheme.GOLD, 10)
		var bx := tx + _text_w(lv, 10, 700, false, 3) + 10.0
		var prog := profile.level_progress()
		_bar(Rect2(Vector2(bx, p.y + 43), Vector2(maxf(20.0, tr_x - 36.0 - bx), 4)), float(prog.x) / float(prog.y))

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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55 * e))
		_hit(Rect2(Vector2.ZERO, size), "close_bg")

		var pw := minf(760.0, size.x - 120.0)
		var panel := Rect2(Vector2(size.x - pw - 40.0 + (1.0 - e) * 80.0, 36.0), Vector2(pw, size.y - 72.0))
		_hit(panel, "panel")
		PoolTheme.panel(self, panel, Color(0, 0, 0, 0), 18)
		var px := panel.position.x + 40.0
		var inner := pw - 80.0
		var y := panel.position.y + 40.0
		var st: Dictionary = profile.stats

		# close: a round button in the corner
		var cc := Vector2(panel.end.x - 42, y + 8)
		_hit(Rect2(cc - Vector2(20, 20), Vector2(40, 40)), "close")
		var ca := _a("close")
		draw_circle(cc, 18.0, Color(1, 1, 1, 0.05 + ca * 0.08), true, -1.0, true)
		draw_arc(cc, 18.0, 0.0, TAU, 40, Color(1, 1, 1, 0.14 + ca * 0.2), 1.0, true)
		var xc := PoolTheme.MUTED.lerp(PoolTheme.WHITE, ca)
		draw_line(cc + Vector2(-5, -5), cc + Vector2(5, 5), xc, 2.0, true)
		draw_line(cc + Vector2(5, -5), cc + Vector2(-5, 5), xc, 2.0, true)

		# who
		_avatar(Rect2(Vector2(px, y), Vector2(96, 96)), 16)
		var nx := px + 120.0
		_text(Vector2(nx, y + 40), _fit(profile.username, 38, 800, inner - 120.0 - 70.0), 38, PoolTheme.WHITE, 800, true)
		var via := "SIGNED IN WITH DISCORD"
		PoolTheme.caps(self, Vector2(nx + 2, y + 64), via, PoolTheme.GOLD, 11)
		var so := Rect2(Vector2(nx, y + 76), Vector2(100, 28))
		_hit(so, "signout")
		var sa := _a("signout")
		draw_style_box(PoolTheme.box(Color(PoolTheme.DANGER, 0.12 * sa), 14, Color(1, 1, 1, 0.14).lerp(PoolTheme.DANGER, sa), 1), so)
		_text(Vector2(so.position.x, so.position.y + 19), "SIGN OUT", 11, PoolTheme.MUTED.lerp(PoolTheme.DANGER, sa), 700, false,
			HORIZONTAL_ALIGNMENT_CENTER, so.size.x, 2)
		y += 128.0

		# level
		var lvl_r := Rect2(Vector2(px, y), Vector2(inner, 112))
		draw_style_box(PoolTheme.box(PoolTheme.RAISED, 12, PoolTheme.HAIR, 1), lvl_r)
		var prog := profile.level_progress()
		PoolTheme.caps(self, Vector2(px + 22, y + 30), "LEVEL", PoolTheme.FAINT, 11)
		_text(Vector2(px + 22, y + 62), str(profile.level()), 34, PoolTheme.WHITE, 800, true)
		_text(Vector2(px + 22, y + 58), "%s / %s XP" % [_num(prog.x), _num(prog.y)], 14, PoolTheme.MUTED, 600, false,
			HORIZONTAL_ALIGNMENT_RIGHT, inner - 44.0)
		_bar(Rect2(Vector2(px + 22, y + 74), Vector2(inner - 44, 6)), float(prog.x) / float(prog.y))
		_text(Vector2(px + 22, y + 100), _fit("Earn XP beating the house player, more the tougher he is.", 12, 400, inner - 44.0),
			12, PoolTheme.FAINT, 400)
		y += 128.0

		# trophies
		var tr_r := Rect2(Vector2(px, y), Vector2(inner, 84))
		draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, 0.07), 12, Color(PoolTheme.GOLD, 0.3), 1), tr_r)
		_trophy(Vector2(px + 44, y + 44), 44.0, PoolTheme.GOLD)
		_text(Vector2(px + 84, y + 48), _num(int(st.trophies)), 34, PoolTheme.WHITE, 800, true)
		PoolTheme.caps(self, Vector2(px + 86, y + 68), "TROPHIES", PoolTheme.GOLD, 11)
		draw_multiline_string(PoolTheme.font(400), Vector2(px + 240, y + 38),
			"One for every online match you win, with 50 coins on top.", HORIZONTAL_ALIGNMENT_LEFT,
			inner - 262.0, 14, 2, Color(1, 1, 1, 0.66))
		y += 112.0

		# everything else
		PoolTheme.caps(self, Vector2(px, y), "STATS", PoolTheme.GOLD)
		y += 16.0
		var bot_games := int(st.bot_wins) + int(st.bot_losses)
		var cards := [
			["GAMES PLAYED", _num(profile.games_played())],
			["WINS VS HOUSE", _num(int(st.bot_wins))],
			["GAMES LOST", _num(int(st.bot_losses) + int(st.mp_losses))],
			["WIN RATE", "%d%%" % int(round(100.0 * float(st.bot_wins) / float(bot_games))) if bot_games > 0 else "—"],
			["WIN STREAK", _num(int(st.streak))],
			["BEST STREAK", _num(int(st.best_streak))],
			["TOUGHEST BEATEN", "Level %d" % int(st.best_bot_beaten) if int(st.best_bot_beaten) > 0 else "—"],
			["COINS", _num(int(state.get("cash", 0)))],
			["SHOTS TAKEN", _num(int(st.shots))],
			["BALLS HIT", _num(int(st.balls_hit))],
			["BALLS POTTED", _num(int(st.balls_potted))],
			["FOULS", _num(int(st.fouls))],
			["TIME PLAYED", _duration(int(st.time_played))],
			["DRINKS ORDERED", _num(int(st.drinks))],
			["PUNCHES LANDED", _num(int(st.punches_landed))],
		]
		var cols := 3
		var gap := 10.0
		var cw := (inner - gap * float(cols - 1)) / float(cols)
		var ch := minf(72.0, (panel.end.y - 36.0 - y - gap * 4.0) / 5.0)
		for i in cards.size():
			var c := Rect2(Vector2(px + float(i % cols) * (cw + gap), y + float(i / cols) * (ch + gap)), Vector2(cw, ch))
			draw_style_box(PoolTheme.box(PoolTheme.RAISED, 10, PoolTheme.HAIR, 1), c)
			_text(c.position + Vector2(16, ch * 0.5 + 4), str(cards[i][1]), 22, PoolTheme.WHITE, 800, true)
			PoolTheme.caps(self, c.position + Vector2(17, ch * 0.5 + 22), str(cards[i][0]), PoolTheme.FAINT, 10)

	# --- online: shared bits ------------------------------------------------

	# A text box at `r`, made the first time it's asked for and shown only on
	# the frames something draws it. `submit` runs on Enter.
	func _edit(key: String, r: Rect2, placeholder: String, max_len := 40, submit := Callable()) -> LineEdit:
		var le := _get_edit(key, placeholder, max_len, submit)
		var edge := PoolTheme.GOLD if le.has_focus() else Color(1, 1, 1, 0.16)
		draw_style_box(PoolTheme.box(Color(0, 0, 0, 0.35), 10, edge, 1), r)
		le.position = r.position + Vector2(12, 2)
		le.size = r.size - Vector2(24, 4)
		le.visible = true
		_edits_used[key] = true
		return le

	func _get_edit(key: String, placeholder := "", max_len := 40, submit := Callable()) -> LineEdit:
		var le: LineEdit = edits.get(key)
		if le == null:
			le = LineEdit.new()
			le.placeholder_text = placeholder
			le.max_length = max_len
			le.context_menu_enabled = false
			le.add_theme_font_override("font", PoolTheme.font(500))
			le.add_theme_font_size_override("font_size", 16)
			le.add_theme_color_override("font_color", PoolTheme.WHITE)
			le.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
			le.add_theme_color_override("caret_color", PoolTheme.GOLD)
			for st in ["normal", "focus", "read_only"]:
				le.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			if submit.is_valid():
				le.text_submitted.connect(func(_t: String): submit.call())
			le.visible = false
			add_child(le)
			edits[key] = le
		return le

	func _edit_text(key: String) -> String:
		return (edits[key] as LineEdit).text.strip_edges() if edits.has(key) else ""

	func _coin(c: Vector2, r: float) -> void:
		draw_circle(c, r, PoolTheme.GOLD, true, -1.0, true)
		draw_circle(c, r * 0.64, Color(0.8, 0.6, 0.2), true, -1.0, true)

	# Anyone's picture: their Discord avatar once it's loaded, their initial till then.
	func _player_pic(r: Rect2, pl: Dictionary, round := true) -> void:
		var tex: Texture2D = online.avatar(str(pl.get("avatar_url", ""))) if online != null else null
		var radius := int(r.size.y * 0.5) if round else 10
		if tex != null:
			if not round:
				draw_texture_rect(tex, r, false)
				return
			# the picture cut to a circle: a round polygon that samples it
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 40:
				var t := TAU * float(i) / 40.0
				var u := Vector2(cos(t), sin(t))
				pts.append(r.get_center() + u * r.size.y * 0.5)
				uvs.append(Vector2(0.5, 0.5) + u * 0.5)
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
			return
		draw_style_box(PoolTheme.box(PoolTheme.FELT, radius), r)
		var nm := str(pl.get("display_name", pl.get("username", "?")))
		var fs := int(r.size.y * 0.5)
		_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), nm.left(1).to_upper(), fs, PoolTheme.WHITE, 800,
			true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	static func _status_word(st: String) -> String:
		match st:
			"menu":
				return "Online"
			"lobby":
				return "In a lobby"
			"playing":
				return "Playing"
		return "Offline"

	static func _status_col(st: String) -> Color:
		match st:
			"menu":
				return PoolTheme.FELT_HI
			"lobby":
				return PoolTheme.GOLD
			"playing":
				return PoolTheme.CHALK
		return Color(1, 1, 1, 0.25)

	# The Discord mark, simplified: a rounded controller face with two eyes.
	func _discord_icon(c: Vector2, r: float, col := Color.WHITE) -> void:
		draw_circle(c, r, Color("5865f2"), true, -1.0, true)
		var w := r * 1.1
		var body := Rect2(c - Vector2(w * 0.5, w * 0.34), Vector2(w, w * 0.7))
		draw_style_box(PoolTheme.box(col, int(w * 0.3)), body)
		draw_circle(c + Vector2(-w * 0.2, -w * 0.02), w * 0.1, Color("5865f2"), true, -1.0, true)
		draw_circle(c + Vector2(w * 0.2, -w * 0.02), w * 0.1, Color("5865f2"), true, -1.0, true)

	func _press_online(name: String) -> bool:
		if online == null:
			return false
		if name == "discord_sign_in":
			ui_sound.emit("click")
			profile.sign_in()
		elif name == "mp_create":
			create_edit = false
			create_rules = PoolMPRules.defaults()
			create_public = true
			_get_edit("lobby_name", "Name your table").text = "%s's table" % online.display_name()
			go("mp_create")
		elif name == "mp_browse":
			browse_loaded = false
			browse_t = 99.0
			go("mp_browse")
		elif name == "join_code":
			_join_code()
		elif name == "to_lobby":
			go("lobby")
		elif name == "vis_public" or name == "vis_private":
			create_public = name == "vis_public"
			ui_sound.emit("click")
		elif name.begins_with("preset:"):
			create_rules = PoolMPRules.preset(int(name.substr(7)))
			ui_sound.emit("click")
		elif name.begins_with("rule-:") or name.begins_with("rule+:"):
			create_rules = PoolMPRules.cycle(create_rules, name.substr(6), -1 if name.begins_with("rule-") else 1)
			ui_sound.emit("click")
		elif name == "create_go":
			_create_or_save()
		elif name == "browse_refresh":
			browse_t = 99.0
			ui_sound.emit("click")
		elif name.begins_with("join:"):
			_join(name.substr(5))
		elif name == "lobby_start":
			if online.is_host() and online.other_here() and online.other_ready():
				ui_sound.emit("start")
				online_start.emit()
		elif name == "lobby_ready":
			my_ready = not my_ready
			online.set_ready(my_ready)
			ui_sound.emit("click")
		elif name == "lobby_edit":
			create_edit = true
			create_rules = PoolMPRules.clean(online.lobby.get("rules", {}))
			create_public = bool(online.lobby.get("is_public", true))
			_get_edit("lobby_name", "Name your table").text = str(online.lobby.get("name", ""))
			go("mp_create")
		elif name == "lobby_invite":
			friends_open = true
			fr_tab = "friends"
			_close_chat()
			ui_sound.emit("click")
		elif name == "lobby_leave":
			_leave_lobby()
		elif name == "copy_code":
			DisplayServer.clipboard_set(str(online.lobby.get("code", "")))
			show_toast("Code copied. Send it to whoever you want to play.")
			ui_sound.emit("click")
		elif name == "friends_btn":
			friends_open = not friends_open
			ui_sound.emit("click")
		elif name == "fr_bg" or name == "fr_close":
			friends_open = false
			_close_chat()
		elif name == "fr_panel":
			pass
		elif name.begins_with("fr_tab:"):
			fr_tab = name.substr(7)
			fr_scroll = 0
			ui_sound.emit("click")
		elif name.begins_with("fr_open:"):
			_open_chat(name.substr(8))
		elif name == "fr_back":
			_close_chat()
		elif name == "fr_send":
			_send_chat()
		elif name.begins_with("fr_invite:"):
			_invite(name.substr(10))
		elif name.begins_with("fr_accept:"):
			online.answer_request(name.substr(10), true)
			ui_sound.emit("equip")
		elif name.begins_with("fr_decline:"):
			online.answer_request(name.substr(11), false)
			ui_sound.emit("click")
		elif name.begins_with("fr_cancel:") or name.begins_with("fr_remove:"):
			online.remove_friend(name.substr(10))
			if fr_chat == name.substr(10):
				_close_chat()
			ui_sound.emit("click")
		elif name.begins_with("fr_add:"):
			_add_friend(name.substr(7))
		elif name == "fr_search":
			_search()
		elif name.begins_with("fr_join:"):
			_join(name.substr(8))
		else:
			return false
		return true

	func _join_code() -> void:
		var code := _edit_text("join_code")
		if code.length() < 4 or busy:
			show_toast("Type the 6-letter code from whoever made the lobby.")
			return
		busy = true
		var err := await online.join_code(code)
		busy = false
		if err != "":
			show_toast(err)
			ui_sound.emit("click")
			return
		_joined()

	func _join(id: String) -> void:
		if busy:
			return
		busy = true
		var err := await online.join_lobby(id)
		busy = false
		if err != "":
			show_toast(err)
			ui_sound.emit("click")
			browse_t = 99.0
			return
		_joined()

	func _joined() -> void:
		friends_open = false
		_close_chat()
		my_ready = false
		online.lobby_send("joined", {})
		ui_sound.emit("equip")
		go("lobby")

	func _create_or_save() -> void:
		if busy:
			return
		busy = true
		var nm := _edit_text("lobby_name")
		var err := ""
		if create_edit:
			err = await online.update_lobby(nm, create_public, create_rules)
		else:
			err = await online.create_lobby(nm, create_public, create_rules)
		busy = false
		if err != "":
			show_toast(err)
			return
		my_ready = false
		ui_sound.emit("equip")
		go("lobby")

	func _leave_lobby() -> void:
		my_ready = false
		online.leave_lobby()
		ui_sound.emit("click")
		go("mp")

	func _load_browse() -> void:
		busy = true
		browse = await online.public_lobbies()
		busy = false
		browse_loaded = true
		browse_scroll = clampi(browse_scroll, 0, maxi(0, browse.size() - 1))

	func _open_chat(id: String) -> void:
		fr_chat = id
		chat_scroll = 0
		online.open_chat = id
		ui_sound.emit("click")
		await online.load_conversation(id)

	func _close_chat() -> void:
		fr_chat = ""
		if online != null:
			online.open_chat = ""

	func _send_chat() -> void:
		var body := _edit_text("chat")
		if body == "" or fr_chat == "":
			return
		(edits["chat"] as LineEdit).text = ""
		chat_scroll = 0
		var err := await online.send_message(fr_chat, body)
		if err != "":
			show_toast(err)

	func _invite(id: String) -> void:
		var err := await online.invite(id)
		if err != "":
			show_toast(err)
		else:
			show_toast("Invite sent.")
			ui_sound.emit("equip")

	func _add_friend(id: String) -> void:
		var r := await online.add_friend(id)
		show_toast("You're friends now." if r == "friends" else ("Friend request sent." if r == "sent" else r))
		ui_sound.emit("equip")

	func _search() -> void:
		var q := _edit_text("fr_search")
		if q.length() < 2:
			show_toast("Type at least two letters of their Discord name.")
			return
		fr_results = await online.find_players(q)
		fr_searched = true

	# --- online: the hub --------------------------------------------------------

	func _draw_mp() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "MULTIPLAYER", "PLAY PEOPLE ONLINE")
		if online == null or not online.configured():
			var pr := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(560, 190))
			PoolTheme.panel(self, pr)
			_text(pr.position + Vector2(32, 64), "Online play isn't set up yet", 26, PoolTheme.WHITE, 800, true)
			draw_multiline_string(PoolTheme.font(400), pr.position + Vector2(32, 100),
				"This build hasn't been pointed at an online server. Whoever made it can follow ONLINE_SETUP.md to switch it on.",
				HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 64.0, 16, 3, Color(1, 1, 1, 0.7))
			return
		if not online.signed_in():
			var pr := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(560, 300))
			PoolTheme.panel(self, pr)
			_discord_icon(pr.position + Vector2(64, 76), 32.0)
			_text(pr.position + Vector2(112, 70), "Sign in to play online", 28, PoolTheme.WHITE, 800, true)
			_text(pr.position + Vector2(112, 96), "With your Discord account", 15, PoolTheme.MUTED, 500)
			draw_multiline_string(PoolTheme.font(400), pr.position + Vector2(32, 150),
				"Make lobbies, join other people's, add friends and chat. Every win online is a trophy and 50 coins.",
				HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 64.0, 16, 3, Color(1, 1, 1, 0.7))
			var br := Rect2(pr.position + Vector2(32, pr.size.y - 32 - 56), Vector2(pr.size.x - 64, 56))
			if online.signing_in:
				_button(br, "discord_sign_in", "Waiting for Discord...  (click to cancel)", false)
			else:
				_button(br, "discord_sign_in", "Sign in with Discord")
			return
		var y := 236.0
		if not online.lobby.is_empty():
			var bn := Rect2(Vector2(x + (1.0 - e) * -40.0, y), Vector2(824, 72))
			_hit(bn, "to_lobby")
			var a := _a("to_lobby")
			draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, 0.08 + a * 0.06), 14, Color(PoolTheme.GOLD, 0.5), 1), bn)
			PoolTheme.caps(self, bn.position + Vector2(24, 30), "YOU'RE IN A LOBBY", PoolTheme.GOLD, 11)
			_text(bn.position + Vector2(24, 54), str(online.lobby.get("name", "")), 18, PoolTheme.WHITE, 700)
			_text(Vector2(bn.end.x - 24 - 200, bn.position.y + 44), "BACK TO IT  ›", 15, PoolTheme.GOLD.lerp(Color("ffd978"), a),
				700, true, HORIZONTAL_ALIGNMENT_RIGHT, 200, 2)
			y += 96.0
		var cw := 400.0
		var cards := [
			["mp_create", "CREATE LOBBY", "Your table, your rules. Keep it public or make it private and invite your friends."],
			["mp_browse", "BROWSE LOBBIES", "Find an open table and jump in. Anyone can join a public lobby."],
		]
		for i in 2:
			var d: Array = cards[i]
			var nm: String = d[0]
			var ei := _ease(page_t * 1.4 - float(i) * 0.15)
			var a := _a(nm)
			var r := Rect2(Vector2(x + float(i) * (cw + 24.0) + (1.0 - ei) * -40.0, y - a * 4.0), Vector2(cw, 250))
			_hit(r, nm)
			PoolTheme.panel(self, r)
			if a > 0.01:
				draw_style_box(PoolTheme.box(Color(0, 0, 0, 0), 16, Color(PoolTheme.GOLD, 0.7 * a), 1), r)
			var ic := r.position + Vector2(56, 64)
			draw_circle(ic, 30.0, Color(1, 1, 1, 0.05), true, -1.0, true)
			if i == 0:
				draw_line(ic - Vector2(12, 0), ic + Vector2(12, 0), PoolTheme.GOLD, 3.0, true)
				draw_line(ic - Vector2(0, 12), ic + Vector2(0, 12), PoolTheme.GOLD, 3.0, true)
			else:
				for k in 3:
					draw_line(ic + Vector2(-12, -8 + k * 8), ic + Vector2(12, -8 + k * 8), PoolTheme.GOLD, 3.0, true)
			_text(r.position + Vector2(28, 140), str(d[1]), 30, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 1)
			draw_multiline_string(PoolTheme.font(400), r.position + Vector2(28, 170), str(d[2]), HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x - 56.0, 15, 3, Color(1, 1, 1, 0.66))
		# a private lobby's code
		y += 278.0
		var jr := Rect2(Vector2(x + (1.0 - e) * -40.0, y), Vector2(824, 88))
		PoolTheme.panel(self, jr)
		PoolTheme.caps(self, jr.position + Vector2(28, 36), "GOT A CODE?", PoolTheme.GOLD, 11)
		_text(jr.position + Vector2(28, 60), "Join a private lobby", 15, PoolTheme.MUTED, 500)
		_edit("join_code", Rect2(jr.position + Vector2(300, 20), Vector2(320, 48)), "ABC123", 6, _join_code)
		_button(Rect2(jr.position + Vector2(636, 20), Vector2(160, 48)), "join_code", "Join", true, not busy)

	# --- online: making a lobby ----------------------------------------------

	func _draw_mp_create() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "EDIT TABLE" if create_edit else "CREATE LOBBY", "YOUR TABLE, YOUR RULES")
		var w := minf(size.x - 2.0 * x, 1120.0)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(w, 36.0 + 38.0 + 7.0 * 62.0 + 36.0))
		PoolTheme.panel(self, panel)
		var gutter := 56.0
		var lw := 380.0
		var lx := panel.position.x + 36.0
		var rx := lx + lw + gutter
		var rw := panel.end.x - 36.0 - rx
		var y := panel.position.y + 50.0
		# name
		PoolTheme.caps(self, Vector2(lx, y), "NAME", PoolTheme.GOLD)
		_edit("lobby_name", Rect2(Vector2(lx, y + 14), Vector2(lw, 48)), "Name your table", 40)
		y += 96.0
		# who can join
		PoolTheme.caps(self, Vector2(lx, y), "WHO CAN JOIN", PoolTheme.GOLD)
		for k in 2:
			var nm := "vis_public" if k == 0 else "vis_private"
			var on := create_public == (k == 0)
			var r := Rect2(Vector2(lx + float(k) * (lw * 0.5 + 4.0), y + 14), Vector2(lw * 0.5 - 4.0, 48))
			_hit(r, nm)
			var a := _a(nm)
			draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, 0.14) if on else Color(1, 1, 1, 0.04 + a * 0.05), 10,
				Color(PoolTheme.GOLD, 0.8) if on else PoolTheme.HAIR, 1), r)
			_text(Vector2(r.position.x, r.position.y + 30), "Public" if k == 0 else "Private", 16,
				PoolTheme.WHITE if on else PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_text(Vector2(lx, y + 88), "Anyone can find it in Browse." if create_public else "Only people with the code, or your invite.",
			13, PoolTheme.MUTED, 400)
		y += 128.0
		# presets
		PoolTheme.caps(self, Vector2(lx, y), "QUICK RULES", PoolTheme.GOLD)
		var cur := PoolMPRules.preset_of(create_rules)
		var pw := (lw - 12.0) / 2.0
		for i in PoolMPRules.PRESETS.size():
			var nm := "preset:%d" % i
			var r := Rect2(Vector2(lx + float(i % 2) * (pw + 12.0), y + 14 + float(i / 2) * 56.0), Vector2(pw, 46))
			_hit(r, nm)
			var a := _a(nm)
			var on := cur == i
			draw_style_box(PoolTheme.box(Color(PoolTheme.GOLD, 0.14) if on else Color(1, 1, 1, 0.04 + a * 0.05), 10,
				Color(PoolTheme.GOLD, 0.8) if on else PoolTheme.HAIR, 1), r)
			_text(Vector2(r.position.x, r.position.y + 29), str(PoolMPRules.PRESETS[i].name), 15,
				PoolTheme.WHITE if on else PoolTheme.MUTED, 700, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		# the rules, one per row
		var ry := panel.position.y + 36.0
		PoolTheme.caps(self, Vector2(rx, ry + 14), "RULES", PoolTheme.GOLD)
		ry += 38.0
		for i in PoolMPRules.LIST.size():
			var spec: Dictionary = PoolMPRules.LIST[i]
			var key: String = spec.key
			var r := Rect2(Vector2(rx, ry), Vector2(rw, 62))
			if i < PoolMPRules.LIST.size() - 1:
				PoolTheme.divider(self, r.position.x, r.end.x, r.end.y)
			_text(r.position + Vector2(0, 27), str(spec.label), 17, PoolTheme.WHITE, 600)
			_text(r.position + Vector2(0, 47), str(spec.desc), 13, PoolTheme.MUTED, 400)
			var box := Rect2(Vector2(r.end.x - 196, r.position.y + 13), Vector2(196, 36))
			draw_style_box(PoolTheme.box(PoolTheme.RAISED, 18, PoolTheme.HAIR, 1), box)
			for k in 2:
				var nm := ("rule-:" if k == 0 else "rule+:") + key
				var br := Rect2(Vector2(box.position.x if k == 0 else box.end.x - 40, box.position.y), Vector2(40, 36))
				_hit(br, nm)
				var a := _a(nm)
				if a > 0.01:
					draw_circle(br.get_center(), 14.0, Color(1, 1, 1, 0.08 * a), true, -1.0, true)
				_chevron(br.get_center(), -1.0 if k == 0 else 1.0, PoolTheme.MUTED.lerp(PoolTheme.WHITE, a))
			_text(Vector2(box.position.x + 40, box.position.y + 24), PoolMPRules.name_of(create_rules, key).to_upper(), 14,
				PoolTheme.WHITE, 700, true, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 80, 1)
			ry += 62.0
		_button(Rect2(Vector2(lx, panel.end.y - 36 - 56), Vector2(lw, 56)), "create_go",
			"Save changes" if create_edit else "Create lobby", true, not busy)

	# --- online: finding a lobby ---------------------------------------------

	func _draw_mp_browse() -> void:
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, "PUBLIC LOBBIES", ("%d OPEN TABLES" % browse.size()) if browse_loaded else "LOOKING...")
		var w := minf(size.x - 2.0 * x, 1000.0)
		var panel := Rect2(Vector2(x + (1.0 - e) * -40.0, 236), Vector2(w, size.y - 236 - 60))
		PoolTheme.panel(self, panel)
		var px := panel.position.x + 28.0
		var inner := panel.size.x - 56.0
		var rb := Rect2(Vector2(panel.end.x - 28 - 130, panel.position.y + 24), Vector2(130, 40))
		_button(rb, "browse_refresh", "Refresh", false)
		PoolTheme.caps(self, Vector2(px, panel.position.y + 50), "OPEN TABLES", PoolTheme.GOLD)
		var y := panel.position.y + 84.0
		if browse_loaded and browse.is_empty():
			_text(Vector2(px, y + 60), "Nobody's waiting at a table right now.", 20, PoolTheme.WHITE, 700, false,
				HORIZONTAL_ALIGNMENT_CENTER, inner)
			_text(Vector2(px, y + 90), "Make one and your friends can join, or check back in a moment.", 15, PoolTheme.MUTED,
				400, false, HORIZONTAL_ALIGNMENT_CENTER, inner)
			var cr := Rect2(Vector2(px + inner * 0.5 - 130, y + 124), Vector2(260, 52))
			_button(cr, "mp_create", "Create lobby")
			return
		var row_h := 88.0
		var fit := int((panel.end.y - 24.0 - y) / row_h)
		for i in range(browse_scroll, mini(browse.size(), browse_scroll + fit)):
			var l: Dictionary = browse[i]
			var r := Rect2(Vector2(px, y), Vector2(inner, row_h - 10))
			var host: Dictionary = l.get("host_player", {}) if typeof(l.get("host_player")) == TYPE_DICTIONARY else {}
			var nm := "join:" + str(l.id)
			var a := _a("row:" + str(l.id))
			_hit(r, "row:" + str(l.id))
			draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.03 + a * 0.04), 12, PoolTheme.HAIR, 1), r)
			_player_pic(Rect2(r.position + Vector2(16, 15), Vector2(48, 48)), host)
			_text(r.position + Vector2(80, 32), _fit(str(l.get("name", "")), 18, 700, inner - 300.0), 18, PoolTheme.WHITE, 700)
			_text(r.position + Vector2(80, 52), "%s  ·  %d trophies" % [str(host.get("display_name", "?")), int(host.get("trophies", 0))],
				13, PoolTheme.MUTED, 500)
			_text(r.position + Vector2(80, 70), PoolMPRules.summary(l.get("rules", {})), 12, PoolTheme.FAINT, 500)
			_button(Rect2(Vector2(r.end.x - 16 - 120, r.position.y + 19), Vector2(120, 40)), nm, "Join", true, not busy)
			y += row_h
		if browse.size() > fit:
			_text(Vector2(px, panel.end.y - 16), "Scroll for more", 12, PoolTheme.FAINT, 500, false, HORIZONTAL_ALIGNMENT_CENTER, inner)

	# --- online: the lobby ------------------------------------------------------

	func _draw_lobby() -> void:
		if online == null or online.lobby.is_empty():
			return
		var l: Dictionary = online.lobby
		var x := 84.0
		var e := _ease(page_t)
		_back_button(x, 70.0)
		_page_title(x, 170.0, _fit(str(l.get("name", "Lobby")).to_upper(), 60, 800, size.x - 700.0),
			("PUBLIC LOBBY" if bool(l.get("is_public", true)) else "PRIVATE LOBBY"))
		var host: Dictionary = l.get("host_player", {}) if typeof(l.get("host_player")) == TYPE_DICTIONARY else {}
		var guest: Dictionary = l.get("guest_player", {}) if typeof(l.get("guest_player")) == TYPE_DICTIONARY else {}
		var i_host := online.is_host()
		var y := 236.0
		var cw := 300.0
		for k in 2:
			var pl: Dictionary = host if k == 0 else guest
			var r := Rect2(Vector2(x + float(k) * (cw + 24.0) + (1.0 - e) * -40.0, y), Vector2(cw, 250))
			if pl.is_empty():
				draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.02), 16, Color(1, 1, 1, 0.14), 1), r)
				var cc := r.get_center() - Vector2(0, 40)
				draw_arc(cc, 34.0, 0.0, TAU, 48, Color(1, 1, 1, 0.2), 2.0, true)
				_text(Vector2(r.position.x, cc.y + 8), "?", 30, Color(1, 1, 1, 0.3), 800, true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
				_text(Vector2(r.position.x, r.position.y + 170), "Waiting for a player", 18, PoolTheme.MUTED, 700, false,
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
				if i_host:
					_button(Rect2(Vector2(r.position.x + 40, r.end.y - 30 - 44), Vector2(r.size.x - 80, 44)), "lobby_invite",
						"Invite a friend", false)
				continue
			PoolTheme.panel(self, r)
			var pid := str(pl.get("id", ""))
			var here := pid == online.user_id or online.lobby_members.has(pid)
			_player_pic(Rect2(Vector2(r.get_center().x - 44, r.position.y + 28), Vector2(88, 88)), pl)
			_text(Vector2(r.position.x, r.position.y + 150), _fit(str(pl.get("display_name", "?")), 22, 800, r.size.x - 32.0), 22,
				PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			_trophy(Vector2(r.get_center().x - 28, r.position.y + 173), 16.0, PoolTheme.GOLD)
			_text(Vector2(r.get_center().x - 16, r.position.y + 180), "%d" % int(pl.get("trophies", 0)), 14, PoolTheme.MUTED, 700)
			var tag := "HOST" if k == 0 else "PLAYER"
			var ready := false
			if k == 1:
				ready = my_ready if pid == online.user_id else online.other_ready()
			var st := tag
			var scol := PoolTheme.FAINT
			if not here:
				st = "CONNECTING..."
			elif k == 1:
				st = "READY" if ready else "NOT READY"
				scol = PoolTheme.FELT_HI if ready else PoolTheme.FAINT
			PoolTheme.badge(self, Vector2(r.get_center().x + PoolTheme.font(800, false, 2).get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5 + 9.0,
				r.end.y - 50), st, scol if k == 1 else PoolTheme.GOLD)
		# the code and the rules
		var rx := x + 2.0 * (cw + 24.0) + (1.0 - e) * -40.0
		var rw := minf(420.0, size.x - rx - 60.0)
		var cr := Rect2(Vector2(rx, y), Vector2(rw, 82))
		_hit(cr, "copy_code")
		var ca := _a("copy_code")
		draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.04 + ca * 0.04), 14, PoolTheme.HAIR, 1), cr)
		PoolTheme.caps(self, cr.position + Vector2(22, 32), "LOBBY CODE", PoolTheme.FAINT, 11)
		_text(cr.position + Vector2(22, 66), str(l.get("code", "")), 30, PoolTheme.WHITE, 800, true, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		_text(Vector2(cr.end.x - 22 - 100, cr.position.y + 52), "COPY", 13, PoolTheme.GOLD.lerp(Color("ffd978"), ca), 700, false,
			HORIZONTAL_ALIGNMENT_RIGHT, 100, 2)
		var rr := Rect2(Vector2(rx, y + 98), Vector2(rw, 36.0 + 30.0 * float(PoolMPRules.LIST.size()) + 14.0))
		PoolTheme.panel(self, rr)
		PoolTheme.caps(self, rr.position + Vector2(22, 34), "RULES", PoolTheme.GOLD, 11)
		var rules: Dictionary = l.get("rules", {})
		var ry := rr.position.y + 66.0
		for spec in PoolMPRules.LIST:
			_text(Vector2(rr.position.x + 22, ry), str(spec.label), 14, PoolTheme.MUTED, 500)
			_text(Vector2(rr.position.x + 22, ry), PoolMPRules.name_of(rules, spec.key), 14, PoolTheme.WHITE, 700, false,
				HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 44.0)
			ry += 30.0
		# what to do next
		var by := y + 280.0
		var bw := 200.0
		var bx := x + (1.0 - e) * -40.0
		var status := ""
		if i_host:
			var can := online.other_here() and online.other_ready() and not guest.is_empty()
			_button(Rect2(Vector2(bx, by), Vector2(260, 60)), "lobby_start", "Start match", true, can)
			_button(Rect2(Vector2(bx + 276, by + 8), Vector2(bw - 40, 44)), "lobby_edit", "Edit rules", false)
			_button(Rect2(Vector2(bx + 276 + bw - 24, by + 8), Vector2(bw - 40, 44)), "lobby_invite", "Invite", false)
			if guest.is_empty():
				status = "Invite a friend, share the code, or wait for someone to join from Browse."
			elif not online.other_here():
				status = "%s is connecting..." % str(guest.get("display_name", "They"))
			elif not online.other_ready():
				status = "Waiting for %s to get ready." % str(guest.get("display_name", "them"))
			else:
				status = "%s is ready. Start when you are." % str(guest.get("display_name", "They"))
		else:
			_button(Rect2(Vector2(bx, by), Vector2(260, 60)), "lobby_ready", "Not ready" if my_ready else "Ready", not my_ready)
			status = "Waiting for %s to start." % str(host.get("display_name", "the host")) if my_ready \
				else "Hit Ready when you're set. %s starts the match." % str(host.get("display_name", "The host"))
		_button(Rect2(Vector2(bx + 276 + 2.0 * (bw - 24) + (0.0 if i_host else -2.0 * (bw - 24)), by + 8), Vector2(bw - 40, 44)),
			"lobby_leave", "Leave", false)
		_text(Vector2(bx, by + 96), status, 15, PoolTheme.MUTED, 500)

	# --- online: friends --------------------------------------------------------

	func _draw_friends() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		_hit(Rect2(Vector2.ZERO, size), "fr_bg")
		var pw := minf(470.0, size.x - 80.0)
		var panel := Rect2(Vector2(size.x - pw - 40.0, 36.0), Vector2(pw, size.y - 72.0))
		_hit(panel, "fr_panel")
		PoolTheme.panel(self, panel, Color(0, 0, 0, 0), 18)
		if fr_chat != "":
			_draw_chat(panel)
			return
		var px := panel.position.x + 28.0
		var inner := pw - 56.0
		var y := panel.position.y + 52.0
		_text(Vector2(px, y), "FRIENDS", 30, PoolTheme.WHITE, 800, true)
		_close_x(Vector2(panel.end.x - 44, y - 10), "fr_close")
		y += 28.0
		# tabs
		var req := online.incoming_requests()
		var tabs := [["friends", "Friends"], ["requests", "Requests" + (" (%d)" % req if req > 0 else "")], ["add", "Add"]]
		var tw := inner / 3.0
		draw_style_box(PoolTheme.box(PoolTheme.RAISED, 12, PoolTheme.HAIR, 1), Rect2(Vector2(px, y), Vector2(inner, 40)))
		for i in 3:
			var nm := "fr_tab:" + str(tabs[i][0])
			var r := Rect2(Vector2(px + float(i) * tw, y), Vector2(tw, 40)).grow(-3)
			_hit(r, nm)
			var on := fr_tab == str(tabs[i][0])
			if on:
				draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.1), 9), r)
			_text(Vector2(r.position.x, r.position.y + 23), str(tabs[i][1]), 14,
				PoolTheme.WHITE if on else PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a(nm)), 700, false, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		y += 60.0
		var bottom := panel.end.y - 24.0
		match fr_tab:
			"friends":
				var list: Array = []
				for f in online.friends:
					if str(f.status) == "friend":
						list.append(f)
				list.sort_custom(func(a, b):
					var oa := online.is_online(str(a.id))
					var ob := online.is_online(str(b.id))
					if oa != ob:
						return oa
					return str(a.display_name).naturalnocasecmp_to(str(b.display_name)) < 0)
				if list.is_empty():
					_text(Vector2(px, y + 30), "No friends yet.", 18, PoolTheme.WHITE, 700)
					_text(Vector2(px, y + 56), "Find people by their Discord name in Add.", 14, PoolTheme.MUTED, 400)
				var row_h := 66.0
				fr_scroll = clampi(fr_scroll, 0, maxi(0, list.size() - 1))
				for i in range(fr_scroll, list.size()):
					if y + row_h > bottom:
						break
					var f: Dictionary = list[i]
					var id := str(f.id)
					var r := Rect2(Vector2(px, y), Vector2(inner, row_h - 6))
					var nm := "fr_open:" + id
					_hit(r, nm)
					var a := _a(nm)
					draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.02 + a * 0.05), 12), r)
					_player_pic(Rect2(r.position + Vector2(10, 10), Vector2(40, 40)), f)
					var st := online.status_of(id)
					draw_circle(r.position + Vector2(46, 46), 6.0, PoolTheme.PANEL, true, -1.0, true)
					draw_circle(r.position + Vector2(46, 46), 4.5, _status_col(st), true, -1.0, true)
					_text(r.position + Vector2(64, 27), _fit(str(f.display_name), 16, 700, inner - 180.0), 16, PoolTheme.WHITE, 700)
					_text(r.position + Vector2(64, 46), _status_word(st), 12, _status_col(st) if st != "offline" else PoolTheme.FAINT, 600)
					var unread := int(f.get("unread", 0))
					if unread > 0:
						PoolTheme.badge(self, Vector2(r.end.x - 12, r.position.y + 19), "%d NEW" % unread)
					elif not online.lobby.is_empty() and online.lobby.get("guest") == null and st != "offline":
						var ib := Rect2(Vector2(r.end.x - 12 - 84, r.position.y + 14), Vector2(84, 32))
						_button(ib, "fr_invite:" + id, "Invite", false)
					y += row_h
			"requests":
				var any := false
				for f in online.friends:
					if str(f.status) == "friend" or y + 66 > bottom:
						continue
					any = true
					var id := str(f.id)
					var r := Rect2(Vector2(px, y), Vector2(inner, 60))
					draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.02), 12), r)
					_player_pic(Rect2(r.position + Vector2(10, 10), Vector2(40, 40)), f)
					_text(r.position + Vector2(64, 27), _fit(str(f.display_name), 16, 700, inner - 240.0), 16, PoolTheme.WHITE, 700)
					if str(f.status) == "incoming":
						_text(r.position + Vector2(64, 46), "Wants to be friends", 12, PoolTheme.GOLD, 600)
						_button(Rect2(Vector2(r.end.x - 12 - 76, r.position.y + 14), Vector2(76, 32)), "fr_accept:" + id, "Accept", true)
						_button(Rect2(Vector2(r.end.x - 12 - 76 - 8 - 44, r.position.y + 14), Vector2(44, 32)), "fr_decline:" + id, "✕", false)
					else:
						_text(r.position + Vector2(64, 46), "Request sent", 12, PoolTheme.FAINT, 600)
						_button(Rect2(Vector2(r.end.x - 12 - 84, r.position.y + 14), Vector2(84, 32)), "fr_cancel:" + id, "Cancel", false)
					y += 66.0
				if not any:
					_text(Vector2(px, y + 30), "No requests.", 18, PoolTheme.WHITE, 700)
					_text(Vector2(px, y + 56), "When someone adds you, it shows up here.", 14, PoolTheme.MUTED, 400)
			"add":
				PoolTheme.caps(self, Vector2(px, y), "FIND A PLAYER", PoolTheme.GOLD, 11)
				_edit("fr_search", Rect2(Vector2(px, y + 14), Vector2(inner - 108, 44)), "Discord name", 40, _search)
				_button(Rect2(Vector2(px + inner - 96, y + 14), Vector2(96, 44)), "fr_search", "Search", true)
				_text(Vector2(px, y + 84), "Your name for them to find: %s" % str(online.me.get("username", "")), 13, PoolTheme.MUTED, 500)
				y += 112.0
				if fr_searched and fr_results.is_empty():
					_text(Vector2(px, y + 20), "Nobody by that name has played yet.", 15, PoolTheme.MUTED, 500)
				for pl in fr_results:
					if y + 66 > bottom:
						break
					var id := str(pl.id)
					var r := Rect2(Vector2(px, y), Vector2(inner, 60))
					draw_style_box(PoolTheme.box(Color(1, 1, 1, 0.02), 12), r)
					_player_pic(Rect2(r.position + Vector2(10, 10), Vector2(40, 40)), pl)
					_text(r.position + Vector2(64, 27), _fit(str(pl.display_name), 16, 700, inner - 200.0), 16, PoolTheme.WHITE, 700)
					_text(r.position + Vector2(64, 46), "@%s  ·  %d trophies" % [str(pl.username), int(pl.get("trophies", 0))], 12,
						PoolTheme.FAINT, 500)
					var rel := str(online.friend(id).get("status", ""))
					if rel == "":
						_button(Rect2(Vector2(r.end.x - 12 - 76, r.position.y + 14), Vector2(76, 32)), "fr_add:" + id, "Add", true)
					else:
						var word := "Friends" if rel == "friend" else ("Sent" if rel == "outgoing" else "Asked you")
						_text(Vector2(r.end.x - 12 - 100, r.position.y + 35), word, 13, PoolTheme.MUTED, 700, false,
							HORIZONTAL_ALIGNMENT_RIGHT, 100)
					y += 66.0

	func _close_x(c: Vector2, nm: String) -> void:
		_hit(Rect2(c - Vector2(20, 20), Vector2(40, 40)), nm)
		var a := _a(nm)
		draw_circle(c, 18.0, Color(1, 1, 1, 0.05 + a * 0.08), true, -1.0, true)
		draw_arc(c, 18.0, 0.0, TAU, 40, Color(1, 1, 1, 0.14 + a * 0.2), 1.0, true)
		var xc := PoolTheme.MUTED.lerp(PoolTheme.WHITE, a)
		draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), xc, 2.0, true)
		draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), xc, 2.0, true)

	func _draw_chat(panel: Rect2) -> void:
		var f := online.friend(fr_chat)
		var px := panel.position.x + 24.0
		var inner := panel.size.x - 48.0
		var y := panel.position.y + 24.0
		# header
		var back := Rect2(Vector2(px - 6, y), Vector2(40, 52))
		_hit(back, "fr_back")
		_chevron(back.get_center(), -1.0, PoolTheme.MUTED.lerp(PoolTheme.WHITE, _a("fr_back")))
		_player_pic(Rect2(Vector2(px + 38, y + 4), Vector2(44, 44)), f)
		var st := online.status_of(fr_chat)
		_text(Vector2(px + 94, y + 24), _fit(str(f.get("display_name", "?")), 18, 700, inner - 260.0), 18, PoolTheme.WHITE, 700)
		_text(Vector2(px + 94, y + 44), _status_word(st), 12, _status_col(st) if st != "offline" else PoolTheme.FAINT, 600)
		var can_invite := not online.lobby.is_empty() and online.lobby.get("guest") == null
		if can_invite:
			_button(Rect2(Vector2(panel.end.x - 24 - 84 - 52, y + 10), Vector2(84, 34)), "fr_invite:" + fr_chat, "Invite", true)
		_close_x(Vector2(panel.end.x - 24 - 18, y + 27), "fr_close")
		y += 68.0
		PoolTheme.divider(self, panel.position.x, panel.end.x, y)
		var remove := Rect2(Vector2(px, panel.end.y - 22 - 18), Vector2(120, 18))
		# the box you type in
		var input_y := panel.end.y - 24.0 - 48.0 - 26.0
		_edit("chat", Rect2(Vector2(px, input_y), Vector2(inner - 96, 48)), "Message", 500, _send_chat)
		_button(Rect2(Vector2(px + inner - 84, input_y), Vector2(84, 48)), "fr_send", "Send", true)
		_hit(remove, "fr_remove:" + fr_chat)
		_text(Vector2(px, panel.end.y - 26), "Remove friend", 12, PoolTheme.FAINT.lerp(PoolTheme.DANGER, _a("fr_remove:" + fr_chat)), 600)
		# messages, newest at the bottom
		var msgs: Array = online.conversations.get(fr_chat, [])
		var top := y + 12.0
		var by := input_y - 14.0
		var font := PoolTheme.font(400)
		var maxw := inner * 0.72
		chat_scroll = clampi(chat_scroll, 0, maxi(0, msgs.size() - 1))
		var i := msgs.size() - 1 - chat_scroll
		if msgs.is_empty():
			_text(Vector2(px, y + 60), "Say hello.", 15, PoolTheme.MUTED, 500, false, HORIZONTAL_ALIGNMENT_CENTER, inner)
		while i >= 0:
			var m: Dictionary = msgs[i]
			var mine := str(m.sender) == online.user_id
			var body := str(m.body)
			var invite := str(m.get("kind", "")) == "invite"
			var tsz := font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, maxw - 28.0, 15)
			var bw := minf(maxw, tsz.x + 28.0)
			var bh := tsz.y + 20.0
			if invite and not mine:
				bw = maxw
				bh += 44.0
			if by - bh < top:
				break
			var bx := panel.end.x - 24.0 - bw if mine else px
			var r := Rect2(Vector2(bx, by - bh), Vector2(bw, bh))
			var bg := Color(PoolTheme.GOLD, 0.16) if mine else Color(1, 1, 1, 0.06)
			draw_style_box(PoolTheme.box(bg, 14, Color(PoolTheme.GOLD, 0.5) if invite else Color(0, 0, 0, 0), 1 if invite else 0), r)
			draw_multiline_string(font, r.position + Vector2(14, 10 + 15.0 * 0.95), body, HORIZONTAL_ALIGNMENT_LEFT, maxw - 28.0,
				15, -1, PoolTheme.WHITE)
			if invite and not mine and m.get("lobby_id") != null:
				_button(Rect2(Vector2(r.position.x + 14, r.end.y - 44), Vector2(110, 34)), "fr_join:" + str(m.lobby_id), "Join", true)
			by -= bh + 8.0
			i -= 1

	# --- little helpers ---------------------------------------------------------

	func _draw_toast() -> void:
		if toast_t <= 0.0 or toast == "":
			return
		var a := clampf(toast_t / 0.4, 0.0, 1.0) * clampf((3.5 - toast_t) / 0.2, 0.0, 1.0)
		var fs := 15
		var w := _text_w(toast, fs, 600) + 56.0
		var r := Rect2(Vector2((size.x - w) * 0.5, size.y - 140.0 + (1.0 - a) * 12.0), Vector2(w, 44))
		draw_style_box(PoolTheme.box(Color(0.06, 0.065, 0.07, 0.96 * a), 22, Color(1, 1, 1, 0.12 * a), 1), r)
		draw_circle(Vector2(r.position.x + 22, r.get_center().y), 3.5, Color(PoolTheme.GOLD, a), true, -1.0, true)
		_text(Vector2(r.position.x + 34, r.position.y + 28), toast, fs, Color(1, 1, 1, a), 600)

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

func setup(state: Dictionary, profile: PoolProfile = null, online: PoolOnline = null) -> void:
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
	screen.online = online
	if profile != null:
		profile.message.connect(screen.show_toast)
	if online != null:
		online.message_received.connect(_on_message)
		online.lobby_event.connect(_on_lobby_event)
	root.add_child(screen)
	screen.start_pressed.connect(func(d): start_pressed.emit(d))
	screen.state_changed.connect(func(st): state_changed.emit(st))
	screen.quit_pressed.connect(func(): quit_pressed.emit())
	screen.ui_sound.connect(func(k): ui_sound.emit(k))
	screen.online_start.connect(func(): online_start.emit())
	screen.buy_requested.connect(func(id): buy_requested.emit(id))
	screen.code_entered.connect(func(c): code_entered.emit(c))

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
	if screen.page != "shop" or not visible:
		screen.picked_cue = PoolCues.index_of(str(state.get("equipped", "house")))
	screen.queue_redraw()


# Something from a friend while the menu is up: a toast, unless you're
# already reading their messages.
func _on_message(m: Dictionary) -> void:
	if not visible or screen.online == null:
		return
	var from := str(m.get("sender", ""))
	if screen.friends_open and screen.fr_chat == from:
		return
	var who := str(screen.online.friend(from).get("display_name", "A friend"))
	if str(m.get("kind", "")) == "invite":
		screen.show_toast("%s invited you to play. Open Friends to join." % who)
	else:
		screen.show_toast("%s: %s" % [who, str(m.get("body", "")).left(70)])
	ui_sound.emit("tick")


func _on_lobby_event(event: String, _p: Dictionary) -> void:
	if not visible:
		return
	match event:
		"closed":
			screen.show_toast("The host closed the lobby.")
		"left":
			screen.show_toast("The other player left.")
			screen.my_ready = false


func open(page := "main") -> void:
	visible = true
	screen.visible = true
	screen.page = page
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
