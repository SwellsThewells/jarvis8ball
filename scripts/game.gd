extends Node3D

# Root of the game. Owns the simulation, the scene, the camera and the turn
# flow. The physics runs in real time here and in a background thread for the
# opponent's rehearsals.
#
# The whole thing is meant to feel like standing at a real table: you walk,
# you look, you get down on the shot. There are no views you could not have
# in the room, and nothing is done with a key that you would do with your
# hands or your eyes. The keyboard walks (WASD), bends you down over the shot
# and back up (space) and pauses (Esc). Everything else is the mouse: look,
# aim, stroke, put the cue ball down, call a pocket, move the tip.

const TABLE_Y := PoolTableView.BED_Y
const MAX_SPEED := 7.6
const STROKE_TIME := 0.085

# You are a person standing at the table, not a floating lens: EYE_H is how
# tall you are, and WALK_A/WALK_B are the ellipse the title camera circles on.
const EYE_H := 1.63
const WALK_A := PoolSim.HALF_LEN + 0.95
const WALK_B := PoolSim.HALF_WID + 0.95
const PULL_RANGE := 260.0
const AIM_SENS := 0.00072
const TIP_SENS := 0.0042
# How far across the table you can lean: from the outside of the rail to the
# cue ball, along the line you are shooting.
const LEAN_MAX := 1.5
# No input for this long and Discord shows you as idle.
const IDLE_AFTER_MS := 90000

# The cue sits nearly level unless something behind the cue ball is under it,
# and then comes up only as far as it has to, CUE_MARGIN clear of it. It
# starts lifting a degree before the stick is over a ball, so it never dips
# into one while you sweep the aim across.
const CUE_MIN_ELEV := 0.05
const CUE_MAX_ELEV := 0.70
const CUE_MARGIN := 0.004
const CUE_LOOKAHEAD := deg_to_rad(1.0)
# How long you have to stand still before your eyes follow the shot.
const WATCH_AFTER := 2.0
# How high the cue ball is held while you carry it.
const HOLD_LIFT := 0.02

enum Phase { MENU, PLACE, AIM, STROKE, ROLLING, AI_THINK, AI_AIM, AI_STROKE, OVER }

var sim: PoolSim
var table: PoolTableView
var room: BarRoom
var cue_view: PoolCueView
var hud: PoolHud
var cam: Camera3D
var ai: PoolAI
var sound: PoolSound
var rng := RandomNumberGenerator.new()

var phase: int = Phase.PLACE
var your_turn := true
var you_group := PoolRules.OPEN
var foe_group := PoolRules.OPEN
var open_table := true
var broken := false
var called_pocket := -1
var ball_in_hand := true
var behind_head := true

var aim_dir := Vector2.RIGHT
var aim_yaw := 0.0
var cam_pitch := 0.30
var cam_dist := 0.80

var shot_power := 0.0
var pulling := false
var pull_px := 0.0
var english := Vector2.ZERO
var tip_adjust := false
var tip_look := 0.0               # 1 while you are looking down at the tip
var stroke_t := 0.0
var stroke_pull := 0.0
var cue_elev := CUE_MIN_ELEV
var stroke_elev := CUE_MIN_ELEV
var ai_timer := 0.0
var ai_shot: Dictionary = {}
var ai_have_shot := false        # the opponent has decided; his body still has to get there
var bot_ball_placed := true
var ai_pull := 0.0

# The house player, in the room with you.
var bot: PoolCharacter
var brain: PoolBot
const AI_AIM_TIME := 2.35
# You can put your hands on him, once in a while: one click, your arm goes
# right back, and then everything you've got.
const PUNCH_COOLDOWN := 30.0
const PUNCH_REACH := 1.5
const PUNCH_WINDUP := 0.4
const PUNCH_STRIKE := 0.1
const PUNCH_END := 1.0
var punch_cd := 0.0
var punch_t := -1.0
var punch_landed := false
var bump_cd := 0.0
var shake := 0.0
var arm: PoolFPArm
var postfx: PoolPostFX
var bar: PoolBar
var _sway_last := 0.0
# And he can put his on you: clean off your feet, flat on your back seeing
# stars, then a long wobbly struggle back up. Nothing else about the game moves.
const KO_FLY := 0.75
const KO_LAND := 0.35
const KO_LIE := 5.0
const KO_RISE := 3.6
const KO_EYE_KEYS := [
	# seconds, eye height, how far towards where your head was, pitch, roll
	[0.0, 0.2, 0.42, 0.55, 0.0],
	[0.9, 0.72, 0.12, -0.38, 0.12],
	[1.7, 1.0, -0.05, -0.52, -0.15],
	[2.4, 1.38, -0.02, -0.3, 0.1],
	[2.8, 1.16, 0.0, -0.46, 0.2],
	[3.6, 1.63, 0.0, -0.1, 0.0],
]
var ko_t := -1.0
var ko_w := 0.0
var ko_from := Vector3.ZERO      # your eyes when it landed
var ko_to := Vector2.ZERO        # where you end up lying, the middle of you
var ko_head := Vector2.ZERO      # the way your head points, lying there
var ko_yaw := 0.0
var ko_pitch0 := 0.0
var ko_look := Vector2.ZERO      # looking about from the floor
var _ko_xf := Transform3D()
var fp_stars: Node3D
var _you_got_hit: AudioStream = preload("res://audio/old_man/you_got_hit.ogg")
var _ko_dizzy := 0.0
var place_point := Vector2.ZERO
var place_ok := false
var hover_pocket := -1
var cam_time := 0.0

var menu: PoolMenu
var profile: PoolProfile
var _play_time := 0.0             # seconds in a match not yet added to your stats
var stand := 1.0          # 1 standing and walking, 0 down on the shot
var kick := 0.0
var player := PoolPlayer.new()
var look_off := Vector2.ZERO      # head turn while down, watching your shot run
var shot_speed := 0.0
var look_idle := 0.0              # how long since you last moved the mouse
var still_time := 0.0             # how long since you last moved at all
var stance_yaw := 0.0             # the line you got down on
var stance_cue := Vector2.ZERO    # where the cue ball was when you got down
var shot_by_you := false
# Once you are down you can shuffle round a good way either side of the line
# you got down on, as long as you could still reach the ball from behind the
# rail; swinging round to the far side of the table means standing up and
# walking there.
const STANCE_ARC := deg_to_rad(60.0)
const STANCE_REACH := 3.2         # how close you must be to get down at all
var watch_focus := Vector3.ZERO   # where your eyes are following the balls, eased
var roll_stand := 0.0             # how far a shot has straightened you up
var roll_reach := 0.8             # how far back your head was when you struck
var discord: PoolDiscord
var match_started := 0
var last_result := ""
var _last_input_ms := 0
var _presence_t := 0.0
var menu_angle := 2.35
var guides_allowed := true
var shot_origin := Vector3.ZERO
var _mouse_mode := -1
var save_state := {}
var held_cue: Node3D
var _held_skin := ""
var _ev_seen := 0

# The rack is generated from a seed rather than straight from the clock, and
# every shot played — yours, the opponent's — goes through _play_shot. When a
# second player arrives over a wire, they send a seed and shot dictionaries of
# exactly this shape, and nothing else here has to change.
var rack_seed := 0

var _thread: Thread
var _mutex := Mutex.new()
var _ai_ready := false
var _ai_out: Dictionary = {}


func _ready() -> void:
	# debug builds tack " (DEBUG)" onto the title, and Discord shows the title
	get_window().title = "Jarvis 8 Pool"
	rng.randomize()
	sim = PoolSim.new()
	ai = PoolAI.new()

	room = BarRoom.new()
	add_child(room)
	room.build()
	PoolCharacter.obstacles = room.obstacles
	player.obstacles = room.obstacles

	table = PoolTableView.new()
	table.position.y = TABLE_Y
	add_child(table)
	table.build(sim)

	cue_view = PoolCueView.new()
	table.add_child(cue_view)
	cue_view.build()

	# volumes, window and the rest, before anything makes a sound
	PoolSettings.load_settings()
	PoolSettings.apply()

	sound = PoolSound.new()
	add_child(sound)
	sound.setup()

	# the house player: an old hand with a beard, in shorts
	bot = PoolCharacter.new()
	bot.name = "HousePlayer"
	add_child(bot)
	# the texture baked into the .glb is the one that matches its UVs
	bot.build("res://characters/old_man/old_man.glb")
	bot.set_cue("house")
	bot.stepped.connect(func(at: Vector3, s: float): sound.play("step", at, 0.22 * s))
	bot.landed.connect(func(at: Vector3): sound.play("thud", at, 1.0))

	discord = PoolDiscord.new()
	add_child(discord)
	_last_input_ms = Time.get_ticks_msec()

	cam = Camera3D.new()
	cam.fov = 52.0
	cam.near = 0.02
	cam.far = 80.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 6.0
	attrs.dof_blur_far_transition = 4.0
	attrs.dof_blur_amount = 0.06
	cam.attributes = attrs
	add_child(cam)
	cam.current = true
	# opening position: across the room, so the first seconds glide in
	cam.global_transform = Transform3D().looking_at(Vector3(0, TABLE_Y, 0) - Vector3(2.4, 2.2, 3.4), Vector3.UP)
	cam.global_position = Vector3(2.4, 2.2, 3.4)
	# your own arm, for punching and for holding a drink
	arm = PoolFPArm.new()
	cam.add_child(arm)
	arm.build()
	# stars going round your head when you've been decked
	fp_stars = Node3D.new()
	cam.add_child(fp_stars)
	for i in 5:
		fp_stars.add_child(PoolCharacter.star(false))
	fp_stars.visible = false

	# the cue you carry round the table, at your right side
	held_cue = Node3D.new()
	held_cue.name = "HeldCue"
	add_child(held_cue)

	hud = PoolHud.new()
	add_child(hud)
	hud.setup()
	hud.bubbles.cam = cam
	postfx = PoolPostFX.new()
	add_child(postfx)
	postfx.setup()

	brain = PoolBot.new(self, bot)
	brain.spawn()

	save_state = PoolCues.load_state()
	ai.skill = int(save_state.difficulty)
	guides_allowed = bool(save_state.get("guides", true))
	_apply_skin(str(save_state.equipped))

	online = PoolOnline.new()
	online.name = "Online"
	add_child(online)
	online.lobby_event.connect(_on_lobby_event)
	online.message_received.connect(_on_message)
	online.me_changed.connect(_sync_wallet)
	online.auth_changed.connect(_sync_wallet)

	profile = PoolProfile.new()
	profile.name = "Profile"
	add_child(profile)
	profile.leveled_up.connect(func(l: int):
		if phase != Phase.MENU:
			hud.say("Level up! You're level %d" % l, "brass"))

	menu = PoolMenu.new()
	add_child(menu)
	menu.setup(save_state, profile, online)
	profile.setup(online)
	menu.start_pressed.connect(_start_match)
	menu.state_changed.connect(_on_state_changed)
	menu.quit_pressed.connect(func(): get_tree().quit())
	menu.online_start.connect(_host_start)
	menu.buy_requested.connect(_buy_cue)
	menu.code_entered.connect(_redeem_code)
	menu.ui_sound.connect(func(k): sound.ui(k))
	hud.menu_confirmed.connect(_to_menu)
	hud.rack_again.connect(_restart)
	hud.leave_pressed.connect(_to_menu)

	bar = PoolBar.new()
	bar.name = "Bar"
	add_child(bar)
	bar.setup(self)

	new_rack()
	phase = Phase.MENU
	hud.set_shown(false)
	_sync_wallet()
	menu.open()


func _on_state_changed(state: Dictionary) -> void:
	# coins and owned cues only change through buying, never from the menu
	save_state.equipped = state.equipped
	save_state.difficulty = state.difficulty
	save_state.guides = state.guides
	ai.skill = clampi(int(state.difficulty), 1, 10)
	guides_allowed = bool(state.get("guides", true))
	_apply_skin(str(state.equipped))
	PoolCues.save_state(save_state)
	_refresh_hud()


# The stick on the table and the one in your hand are both rebuilt, so what
# you picked in the shop is what you are holding the moment you walk back in.
func _apply_skin(id: String) -> void:
	cue_view.set_skin(id)
	if id == _held_skin:
		return
	_held_skin = id
	for c in held_cue.get_children():
		held_cue.remove_child(c)
		c.queue_free()
	var model := PoolCueModel.build(PoolCues.by_id(id))
	# tip up at your right shoulder, butt down by your right foot: there at
	# the edge of your eye when you look down at the table, not across it
	var tip := Vector3(0.34, 1.44, -0.16)
	var down := Vector3(0.03, -1.42, 0.22).normalized()
	var basis := Basis(Quaternion(Vector3.UP, down))
	model.transform = Transform3D(basis, tip)
	held_cue.add_child(model)
	for mi in model.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _start_match(difficulty: int) -> void:
	ai.skill = clampi(difficulty, 1, 10)
	menu.close()
	hud.set_shown(true)
	new_rack()
	cam_time = 0.0
	match_started = int(Time.get_unix_time_from_system())
	_presence_t = 0.0


# ---------------------------------------------------------------------------
# Match flow
# ---------------------------------------------------------------------------

func new_rack(seed_value := -1) -> void:
	rack_seed = seed_value if seed_value >= 0 else rng.randi() & 0x7fffffff
	var rack_rng := RandomNumberGenerator.new()
	rack_rng.seed = rack_seed
	sim.rack(rack_rng)
	table.reset_trays()
	table.clear_pocket_glows()
	for i in 16:
		table.ball_nodes[i].visible = true
	you_group = PoolRules.OPEN
	foe_group = PoolRules.OPEN
	open_table = true
	broken = false
	called_pocket = -1
	your_turn = true
	ball_in_hand = true
	behind_head = true
	last_result = ""
	english = Vector2.ZERO
	tip_adjust = false
	hud.set_spin(english)
	hud.clear_finish()
	aim_dir = Vector2.RIGHT
	aim_yaw = 0.0
	cam_time = 0.0
	place_point = Vector2(PoolSim.HEAD_X - 0.24, 0.0)
	sim.place_cue(place_point)
	table.cue_lift = HOLD_LIFT
	table.cue_hand = null
	ai_have_shot = false
	ai_shot = {}
	bot_ball_placed = true
	if brain != null:
		brain.reset()
	# you start at the head of the table, where you break from
	player.stand_at(Vector2(PoolSim.HEAD_X - 1.3, 0.35), Vector2(1.0, -0.2).normalized())
	_refresh_hud()
	hud.say("Your break", "brass")
	phase = Phase.PLACE


func _refresh_hud() -> void:
	var yl := PoolRules.remaining(sim, you_group) if you_group != PoolRules.OPEN else []
	var fl := PoolRules.remaining(sim, foe_group) if foe_group != PoolRules.OPEN else []
	if you_group != PoolRules.OPEN and yl.is_empty() and sim.ball(PoolSim.EIGHT).on_table:
		yl = [PoolSim.EIGHT]
	if foe_group != PoolRules.OPEN and fl.is_empty() and sim.ball(PoolSim.EIGHT).on_table:
		fl = [PoolSim.EIGHT]
	if mp and int(mp_rules.get("race", 1)) > 1:
		hud.set_names("You  %d" % mp_score[0], "%s  %d" % [_foe_name(), mp_score[1]])
	else:
		hud.set_names("You", _foe_name())
	hud.set_sides(you_group, foe_group, yl, fl, your_turn)
	var note := ""
	if _call_all() and your_turn and not _on_eight(you_group):
		note = ("called, %s" % PoolSim.POCKET_NAMES[called_pocket].trim_prefix("the ")) if called_pocket >= 0 else "call your pocket"
	if _on_eight(you_group) and your_turn:
		note = ("8, %s" % PoolSim.POCKET_NAMES[called_pocket].trim_prefix("the ")) if called_pocket >= 0 else "on the 8, call it"
	hud.set_note(note)


func _on_eight(g: String) -> bool:
	return g != PoolRules.OPEN and PoolRules.remaining(sim, g).is_empty()


func _shooter_group() -> String:
	return you_group if your_turn else foe_group


# You are on the 8 and it is your shot: a pocket has to be named first.
func _calling() -> bool:
	return your_turn and phase == Phase.AIM and (_on_eight(you_group) or _call_all())


# Online, with "call every shot": every shot after the break needs a pocket.
func _call_all() -> bool:
	return mp and str(mp_rules.get("call", "eight")) == "all" and broken


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	table.update_balls(sim, delta)
	if phase != Phase.MENU:
		_play_time += delta
		if _play_time >= 30.0:
			_bank_play_time()
	_update_presence(delta)
	if mp:
		_mp_update(delta)
	if hud.confirm_open() and not mp:
		# paused: the room holds still, the view settles where it is
		# (not online, though: the other player's game carries on)
		_update_mouse_mode()
		return

	match phase:
		Phase.MENU:
			cue_view.hide_stick()
			cue_view.clear_guide()
			table.cue_lift = 0.0
		Phase.PLACE:
			cue_view.hide_stick()
			if ko_t < 0.0:
				_update_placement()
		Phase.AIM:
			_update_aim(delta)
		Phase.STROKE:
			_update_stroke(delta)
		Phase.ROLLING:
			cue_view.hide_stick()
			cue_view.clear_guide()
			sim.advance(minf(delta, 0.05))
			_update_watch_focus(delta)
			_play_events()
			if not sim.is_moving():
				if mp and not shot_by_you:
					_mp_try_settle()
				else:
					_resolve_shot()
		Phase.AI_THINK:
			if mp:
				_mp_their_turn_update(delta)
			else:
				ai_timer += delta
				cue_view.hide_stick()
				cue_view.clear_guide()
				_poll_ai()
				if ai_have_shot and brain.ready_to_aim:
					_bot_begin_aim()
		Phase.AI_AIM:
			# a couple of feathering strokes, a pause at the back, and through.
			# The clock only runs while he is steady over the ball.
			cue_view.hide_stick()
			var steady := bot.stance_ready()
			if steady:
				ai_timer += delta
			var d: Vector2 = ai_shot.dir
			var ai_eng: Vector2 = ai_shot.get("english", Vector2.ZERO)
			var final_pull := 0.04 + clampf(float(ai_shot.speed) / MAX_SPEED, 0.0, 1.0) * 0.22
			var want_pull := _ai_practice_pull(ai_timer, final_pull) if steady else 0.006
			ai_pull = lerpf(ai_pull, want_pull, 1.0 - exp(-25.0 * delta))
			var cue := sim.ball(PoolSim.CUE)
			_ease_elev(_cue_clearance(cue.pos, d, 0.006, maxf(ai_pull, 0.006), ai_eng), delta)
			_bot_stick(cue.pos, d, ai_pull, cue_elev, ai_eng)
			aim_dir = d
			aim_yaw = atan2(d.y, d.x)
			if ai_timer > AI_AIM_TIME and steady:
				phase = Phase.AI_STROKE
				stroke_t = 0.0
				stroke_pull = ai_pull
				stroke_elev = maxf(cue_elev, _cue_clearance(cue.pos, d, 0.006, stroke_pull, ai_eng))
		Phase.AI_STROKE:
			_update_stroke(delta)
		Phase.OVER:
			cue_view.hide_stick()
			cue_view.clear_guide()

	# a glass only stays in your hand while the button's held
	if bar.holding() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		bar.release()
	if mp:
		_mp_drive_avatar(delta)
	else:
		brain.update(delta)
	_update_ko(delta)
	_update_walk(delta)
	_bodies(delta)
	_update_punch(delta)
	_update_watching(delta)
	cam_time += delta
	_update_camera(delta)
	bar.update(delta, phase != Phase.MENU and not player.down and ko_t < 0.0 and punch_t < 0.0)
	_update_held_cue()
	_update_mouse_mode()
	_update_hints()
	_update_postfx(delta)
	var at_bot := _can_punch()
	var at_bar := bar.look_card != "" or bar.look_glass
	hud.set_crosshair(phase == Phase.PLACE or (_calling() and not player.down) or at_bot or at_bar,
		_calling() or at_bar)
	hud.set_punch(punch_cd / PUNCH_COOLDOWN, at_bot)
	hud.set_tip(phase == Phase.AIM and player.down, tip_adjust)
	hud.set_cash(coins(), phase != Phase.MENU and player.pos.x < -2.2)


# The cue comes up quickly when it has to clear something and settles back
# more slowly, so it is never inside a ball for even a frame or two.
func _ease_elev(want: float, delta: float) -> void:
	var rate := 30.0 if want > cue_elev else 6.0
	cue_elev = lerpf(cue_elev, want, 1.0 - exp(-rate * delta))


# --- aiming -----------------------------------------------------------------

func _update_aim(delta: float) -> void:
	if not player.down:
		# on your feet: walk, look around, pick where you want to shoot from
		var cue_w := sim.ball(PoolSim.CUE)
		cue_view.hide_stick()
		cue_view.clear_guide()
		aim_yaw = (cue_w.pos - player.pos).angle()
		aim_dir = Vector2(cos(aim_yaw), sin(aim_yaw))
		_update_call_hover()
		return

	# rum in you: the line won't hold still while you're lining it up
	var sway := bar.wobble() * (0.011 * sin(cam_time * 0.7) + 0.004 * sin(cam_time * 2.3 + 1.0))
	if not pulling:
		aim_yaw += sway - _sway_last
	_sway_last = sway
	aim_dir = Vector2(cos(aim_yaw), sin(aim_yaw))
	_show_called_only()

	if pulling:
		shot_power = clampf(pull_px / PULL_RANGE, 0.0, 1.0)
	hud.set_power(shot_power, pulling)

	var cue := sim.ball(PoolSim.CUE)
	var pull := 0.035 + shot_power * 0.27
	_ease_elev(_cue_clearance(cue.pos, aim_dir, 0.006, pull, english), delta)
	cue_view.aim(cue.pos, aim_dir, pull, cue_elev, english)
	_draw_guide()


func _draw_guide() -> void:
	if guides_allowed and not tip_adjust:
		cue_view.draw_guide(sim, aim_dir, PoolTheme.CHALK)
	else:
		cue_view.clear_guide()


func _stick_radius(from_tip: float) -> float:
	return lerpf(0.0065, 0.0129, clampf(from_tip / PoolCueModel.LENGTH, 0.0, 1.0))


# How far the butt of the cue has to come up for the stick to pass over
# everything behind the cue ball: other balls, the cushion, the rail. The
# stick is a tapered rod pointed at the spot the tip will strike, and this is
# the smallest lift at which that rod clears each thing by CUE_MARGIN, checked
# for every position it takes between `pull_near` and `pull_far`. Nothing in
# the way means a nearly level cue. It is checked a degree either side of the
# line as well, so the lift has already started by the time the stick sweeps
# over a ball.
func _cue_clearance(from: Vector2, dir: Vector2, pull_near: float, pull_far: float, eng := Vector2.ZERO) -> float:
	var need := CUE_MIN_ELEV
	for turn: float in [0.0, -CUE_LOOKAHEAD, CUE_LOOKAHEAD]:
		need = maxf(need, _clearance_along(from, dir.rotated(turn), pull_near, pull_far, eng))
	return clampf(need, CUE_MIN_ELEV, CUE_MAX_ELEV)


func _clearance_along(from: Vector2, dir: Vector2, pull_near: float, pull_far: float, eng: Vector2) -> float:
	var R := PoolSim.R
	var back := -dir
	var side := Vector2(-dir.y, dir.x)
	var ox := eng.x * R
	var oy := eng.y * R
	var s0 := R + PoolCueView.TIP_GAP + pull_near
	var s1 := R + PoolCueView.TIP_GAP + pull_far + PoolCueModel.LENGTH
	var need := 0.0

	for b in sim.balls:
		if not b.on_table or b.id == PoolSim.CUE:
			continue
		var rel: Vector2 = b.pos - from
		var h := rel.dot(back)
		if h <= 0.0 or h > s1 + R:
			continue
		var wl := rel.dot(side) - ox
		var reach := R + _stick_radius(maxf(h - s0, 0.0)) + CUE_MARGIN
		if absf(wl) >= reach:
			continue
		# In the vertical plane of the shot the stick is a line through the
		# strike point, raised by angle e. Find the e at which its distance
		# from this ball's centre is exactly `reach`.
		var c := -oy
		var rho := sqrt(h * h + c * c)
		var phi := atan2(c, h)
		var k2 := rho * rho + wl * wl - reach * reach
		if k2 <= 0.0:
			need = CUE_MAX_ELEV
			continue
		var k := sqrt(k2)
		var e := phi + acos(clampf(k / rho, -1.0, 1.0))
		if k < s0:
			# the nearest part of the stick is its tip, not somewhere along it
			var ct := (rho * rho + wl * wl + s0 * s0 - reach * reach) / (2.0 * s0 * rho)
			e = phi + acos(clampf(ct, -1.0, 1.0))
		need = maxf(need, e)

	# the cushion, then the rail cap behind it: the underside of the stick
	# has to pass over each, starting from wherever it first reaches them
	var d := _dist_to_cushion(from, back)
	var bands := [[0.0, PoolTableView.CUSHION_D, PoolTableView.TOP_H],
		[PoolTableView.CUSHION_D, PoolTableView.CUSHION_D + PoolTableView.CAP_W, PoolTableView.CAP_TOP]]
	for band in bands:
		var a0: float = d + float(band[0])
		var a1: float = d + float(band[1])
		var x: float = maxf(a0, s0)
		if x > a1 or x > s1:
			continue
		var rise: float = float(band[2]) - R + CUE_MARGIN + _stick_radius(a1 - s0) - oy
		if rise > 0.0:
			need = maxf(need, atan(rise / maxf(x, 0.02)))
	return need


func _dist_to_cushion(from: Vector2, back: Vector2) -> float:
	var d := 9.0
	if absf(back.x) > 1.0e-4:
		d = minf(d, (PoolSim.HALF_LEN * signf(back.x) - from.x) / back.x)
	if absf(back.y) > 1.0e-4:
		d = minf(d, (PoolSim.HALF_WID * signf(back.y) - from.y) / back.y)
	return maxf(d, 0.0)


func _update_stroke(delta: float) -> void:
	stroke_t += delta
	var t: float = clampf(stroke_t / STROKE_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.2)
	var cue := sim.ball(PoolSim.CUE)
	# the ball has not moved yet, so this freezes at the moment of the strike
	shot_origin = Vector3(cue.pos.x, TABLE_Y + PoolSim.R, cue.pos.y)
	cue_elev = stroke_elev
	var eng: Vector2 = english if phase == Phase.STROKE else ai_shot.get("english", Vector2.ZERO)
	if phase == Phase.STROKE:
		cue_view.aim(cue.pos, aim_dir, lerpf(stroke_pull, 0.006, eased), stroke_elev, eng)
	else:
		_bot_stick(cue.pos, aim_dir, lerpf(stroke_pull, 0.006, eased), stroke_elev, eng)
	if t < 1.0:
		return

	if phase == Phase.STROKE:
		var shot := {
			"dir": aim_dir,
			"speed": 0.55 + pow(shot_power, 1.35) * MAX_SPEED,
			"english": english,
			"pocket": called_pocket,
		}
		if mp:
			mp_seq += 1
			var cb := sim.ball(PoolSim.CUE)
			online.lobby_send("shot", {"seq": mp_seq, "dir": [aim_dir.x, aim_dir.y], "speed": shot.speed,
				"english": [english.x, english.y], "pocket": called_pocket, "pull": stroke_pull,
				"place": [cb.pos.x, cb.pos.y]})
		_play_shot(shot)
		shot_by_you = true
	else:
		_play_shot(ai_shot)
		shot_by_you = false
	cue_view.hide_stick()
	# where your head was at the strike is where it stays; it only ever rises
	# from there as the shot opens up, and your eyes start on the line
	roll_reach = cam_dist + shot_power * 0.13
	roll_stand = stand
	watch_focus = shot_origin + Vector3(aim_dir.x, 0.0, aim_dir.y) * 0.48 + Vector3.UP * 0.015
	shot_power = 0.0
	pull_px = 0.0
	kick = 0.035
	look_off = Vector2.ZERO
	look_idle = 0.0
	hud.set_power(0.0, false)
	phase = Phase.ROLLING


# Every shot in the game arrives here, whoever played it.
func _play_shot(shot: Dictionary) -> void:
	if shot.get("place", null) != null:
		sim.place_cue(shot.place)
		table.ball_nodes[PoolSim.CUE].visible = true
	called_pocket = int(shot.get("pocket", -1))
	shot_speed = float(shot.speed)
	sim.strike(shot.dir, shot_speed, shot.get("english", Vector2.ZERO))
	_ev_seen = 0
	sound.play("strike", table.ball_world(sim, PoolSim.CUE), clampf(shot_speed / 5.0, 0.15, 1.0))


# Clicks, cushions and pockets, as they happen.
func _play_events() -> void:
	var evs: Array = sim.events
	while _ev_seen < evs.size():
		var ev: Dictionary = evs[_ev_seen]
		_ev_seen += 1
		match str(ev.type):
			"hit":
				sound.play("click", table.ball_world(sim, int(ev.a)), float(ev.get("speed", 1.0)) / 3.0)
			"rail":
				sound.play("rail", table.ball_world(sim, int(ev.ball)), float(ev.get("speed", 1.0)) / 2.5)
			"pot":
				var pc: Vector2 = sim.pockets[int(ev.pocket)].c
				sound.play("drop", table.table_to_world(pc, -0.05), 0.9)


# You are on your feet whenever you are not down on a shot, including while
# your opponent is shooting: WASD walks, the mouse looks.
func _update_walk(delta: float) -> void:
	look_idle += delta
	if player.down or phase == Phase.MENU or phase == Phase.OVER or hud.confirm_open() or ko_t >= 0.0:
		player.walk(delta, Vector2.ZERO)
		still_time += delta
		return
	var wish := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		wish.y += 1.0
	if Input.is_key_pressed(KEY_S):
		wish.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		wish.x += 1.0
	if Input.is_key_pressed(KEY_A):
		wish.x -= 1.0
	if wish == Vector2.ZERO:
		still_time += delta
	else:
		still_time = 0.0
	# rum in you: your feet don't quite go where you send them, and standing
	# still you sway off anyway
	var wob := bar.wobble()
	if wob > 0.0:
		if wish != Vector2.ZERO:
			wish = wish.rotated(wob * 0.6 * sin(cam_time * 0.55))
		else:
			wish = Vector2(sin(cam_time * 0.43), 0.4 * sin(cam_time * 0.31)) * 0.22 * wob
	player.walk(delta, wish, Input.is_key_pressed(KEY_SHIFT))


# You and the house player are both solid. Walk into him and you stop against
# him and he rocks, and if you came in at any pace he notices; he's the
# heavier of the two, and down over a shot he doesn't give at all.
func _bodies(delta: float) -> void:
	bump_cd = maxf(0.0, bump_cd - delta)
	if player.down or phase == Phase.MENU or ko_t >= 0.0 or bot.knocked():
		return
	var rel := player.pos - bot.pos
	var d := rel.length()
	var min_d := 0.26 + PoolCharacter.RADIUS
	if d >= min_d:
		return
	var n := rel / d if d > 1.0e-4 else Vector2(0.0, 1.0)
	var pen := min_d - d
	var share := 0.0 if bot.anchored() else 0.3
	player.pos += n * pen * (1.0 - share)
	bot.pos -= n * pen * share
	var closing := (player.vel - bot.vel).dot(-n)
	var vn := player.vel.dot(n)
	if vn < 0.0:
		player.vel -= n * vn
	if closing > 0.3 and bump_cd <= 0.0:
		bump_cd = 1.0
		bot.bump(player.eye(), clampf(closing / 0.8, 0.4, 1.3))
		sound.play("bump", bot.hips_w, 0.4)
		brain.on_bumped()


# Is your eye on him, and close enough to reach?
func _looking_at_bot() -> bool:
	if phase == Phase.MENU or player.down or hud.confirm_open() or ko_t >= 0.0 or bot.knocked():
		return false
	if bar.holding():
		return false
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var cap := bot.capsule()
	var hit := Geometry3D.get_closest_points_between_segments(from, from + dir * PUNCH_REACH, cap[0], cap[1])
	return hit[0].distance_to(hit[1]) < float(cap[2])


# Your eye is on him and a click would do nothing else.
func _can_punch() -> bool:
	return not mp and phase != Phase.PLACE and not _calling() and punch_t < 0.0 and _looking_at_bot()


# One click on him and you throw a punch: the arm drawn right back past your
# ear, a beat, then thrown. Once every half a minute: he's an old man. It
# never changes the game: knocked flat over his shot, he gets up, walks back
# to it and plays it exactly as he meant to.
func _start_punch() -> void:
	punch_t = 0.0
	punch_landed = false
	punch_cd = PUNCH_COOLDOWN


func _update_punch(delta: float) -> void:
	punch_cd = maxf(0.0, punch_cd - delta)
	if punch_t < 0.0:
		return
	var was := punch_t
	punch_t += delta
	arm.punch(punch_t, PUNCH_WINDUP, PUNCH_STRIKE)
	if was < PUNCH_WINDUP and punch_t >= PUNCH_WINDUP:
		sound.near_kind("whoosh", -3.0)
	if not punch_landed and punch_t >= PUNCH_WINDUP + PUNCH_STRIKE:
		punch_landed = true
		if _punch_connects():
			_punch_impact()
		else:
			# thin air: no harm done, and you can try again sooner
			punch_cd = minf(punch_cd, 3.0)
	if punch_t >= PUNCH_END:
		punch_t = -1.0
		arm.hide_arm()


# He's still there in front of you when the fist arrives.
func _punch_connects() -> bool:
	if bot.knocked() or ko_t >= 0.0:
		return false
	var to := Vector2(bot.pos.x - player.pos.x, bot.pos.y - player.pos.y)
	if to.length() > PUNCH_REACH + 0.3:
		return false
	var look := Vector2(-cam.global_transform.basis.z.x, -cam.global_transform.basis.z.z)
	return look.length() < 1.0e-3 or absf(look.angle_to(to)) < deg_to_rad(40.0)


# The fist lands: his grunt right on it, a frozen instant, and off he goes.
func _punch_impact() -> void:
	profile.add("punches_landed")
	bot.hit(player.eye(), 1.0)
	brain.on_punched()
	shake = 1.0
	postfx.flash = 1.0
	Engine.time_scale = 0.08
	get_tree().create_timer(0.09, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _cancel_punch() -> void:
	if punch_t >= 0.0:
		punch_t = -1.0
		arm.hide_arm()


# Where you are, for anyone coming at you: your feet, or down on a shot, your
# head over the cue.
func player_spot() -> Vector2:
	if player.down:
		return Vector2(cam.global_position.x, cam.global_position.z)
	return player.pos


func player_head() -> Vector3:
	return cam.global_position


func player_knocked() -> bool:
	return ko_t >= 0.0


# Decked, and sent flying. Whatever you were doing stops, and nothing else
# changes: the shot is still yours to play, the cue ball still in your hand,
# the call still made. You just have to get up first. Returns whether it
# landed.
func player_hit(from: Vector3) -> bool:
	if ko_t >= 0.0 or phase == Phase.MENU or phase == Phase.OVER or phase == Phase.STROKE:
		return false
	if player.down:
		_leave_stance()
	pulling = false
	tip_adjust = false
	shot_power = 0.0
	pull_px = 0.0
	hud.set_power(0.0, false)
	_cancel_punch()
	if bar.holding():
		bar.drop()
	var d := Vector2(player.pos.x - from.x, player.pos.y - from.z)
	if d.length_squared() < 1.0e-4:
		d = -player.forward()
	d = d.normalized()
	var land := PoolCharacter.landing(player.pos, d, 3.4)
	ko_head = land[1]
	ko_to = (land[0] as Vector2) + ko_head * 0.45
	ko_from = cam.global_position
	# you land looking back the way you came, at him
	ko_yaw = atan2(-ko_head.y, -ko_head.x)
	ko_pitch0 = player.pitch
	ko_look = Vector2.ZERO
	ko_t = 0.0
	ko_w = 0.0
	player.vel = Vector2.ZERO
	profile.add("knockdowns")
	shake = 1.0
	sound.near(_you_got_hit, 0.0)
	hud.knocked_flash()
	return true


# Where your eyes are and which way they face while you're off your feet: a
# backflip through the air, a bounce, flat on your back, then up by stages.
func _update_ko(delta: float) -> void:
	if ko_t < 0.0:
		ko_w = 0.0
		hud.set_knocked(0.0)
		fp_stars.visible = false
		return
	ko_t += delta
	var t := ko_t
	var eye: Vector3
	var yaw := ko_yaw
	var pitch := 0.55
	var roll := 0.0
	var dizzy := 0.0
	var lie_eye := Vector3(ko_to.x + ko_head.x * 0.42, 0.2, ko_to.y + ko_head.y * 0.42)
	if t < KO_FLY:
		var k := t / KO_FLY
		var e := 1.0 - pow(1.0 - k, 1.8)
		eye = ko_from.lerp(lie_eye, e)
		eye.y = lerpf(ko_from.y, lie_eye.y, pow(k, 1.4)) + 4.0 * 0.85 * k * (1.0 - k)
		# heels over head, all the way round
		pitch = lerpf(ko_pitch0, 0.55 + TAU, 1.0 - pow(1.0 - k, 2.2))
		roll = 0.35 * sin(k * PI)
		ko_w = minf(1.0, t / 0.06)
		player.pos = Vector2(eye.x, eye.z)
	elif t < KO_FLY + KO_LAND:
		var b := t - KO_FLY
		if b <= delta:
			sound.play("thud", lie_eye, 1.0)
			shake = 0.8
		eye = lie_eye + Vector3.UP * 0.07 * sin(PI * minf(b / 0.25, 1.0))
		pitch = 0.55 - 0.15 * sin(PI * minf(b / 0.25, 1.0))
		ko_w = 1.0
		dizzy = smoothstep(0.0, KO_LAND, b)
		player.pos = ko_to
	elif t < KO_FLY + KO_LAND + KO_LIE:
		var l := t - KO_FLY - KO_LAND
		eye = lie_eye
		# the ceiling going round
		yaw += 0.12 * sin(l * 1.1)
		pitch += 0.06 * sin(l * 1.7)
		roll = 0.12 * sin(l * 0.9)
		dizzy = 1.0
		ko_w = 1.0
	elif t < KO_FLY + KO_LAND + KO_LIE + KO_RISE:
		var r := t - KO_FLY - KO_LAND - KO_LIE
		var key := _eye_key(r)
		eye = Vector3(ko_to.x + ko_head.x * float(key[2]), float(key[1]), ko_to.y + ko_head.y * float(key[2]))
		pitch = key[3]
		roll = key[4]
		# the look you had on the floor comes back to straight ahead
		ko_look = ko_look.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
		dizzy = 1.0 - smoothstep(0.3, 3.0, r)
		ko_w = 1.0 - smoothstep(3.1, KO_RISE, r)
		if r <= delta:
			player.pos = ko_to
	else:
		ko_t = -1.0
		ko_w = 0.0
		_ko_dizzy = 0.0
		player.pos = ko_to
		player.yaw = ko_yaw
		player.pitch = -0.1
		player.vel = Vector2.ZERO
		hud.set_knocked(0.0)
		fp_stars.visible = false
		return
	# you come up where you'll stand, facing the way you'll face
	player.yaw = ko_yaw
	player.pitch = -0.1
	yaw += ko_look.x
	pitch += ko_look.y
	_ko_xf = Transform3D(_view_basis(yaw, pitch, roll), eye)
	_ko_dizzy = dizzy
	hud.set_knocked(dizzy * 0.25)
	# stars, going round at the top of your view
	fp_stars.visible = dizzy > 0.02
	var tt := Time.get_ticks_msec() * 0.001
	var i := 0
	for s in fp_stars.get_children():
		var a := tt * 2.2 + TAU * float(i) / 5.0
		(s as Node3D).position = Vector3(cos(a) * 0.17, 0.14 + sin(a) * 0.035, -0.5 + sin(a) * 0.08)
		(s as Node3D).rotation = Vector3(0.0, 0.0, tt * 3.0 + float(i))
		(s as Node3D).scale = Vector3.ONE * 0.022 * dizzy
		i += 1


func _eye_key(t: float) -> Array:
	var keys := KO_EYE_KEYS
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var k := smoothstep(0.0, 1.0, (t - float(a[0])) / (float(b[0]) - float(a[0])))
			var out := [t]
			for j in range(1, a.size()):
				out.append(lerpf(float(a[j]), float(b[j]), k))
			return out
	return keys[keys.size() - 1]


# A camera facing along `yaw` (the game's way: cos, sin on the floor),
# tipped up by `pitch` (past straight up is fine: it goes over the top) and
# rolled.
func _view_basis(yaw: float, pitch: float, roll: float) -> Basis:
	return Basis(Vector3.UP, -yaw - PI * 0.5) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)


# While the balls are running and you are on your feet, the room is yours:
# walk, look, go and stand somewhere else, and nothing turns your head for
# you. Only once you have stood still for a couple of seconds do your eyes
# drift to the shot, the way anyone's would.
func _update_watching(delta: float) -> void:
	if player.down or still_time < WATCH_AFTER or ko_t >= 0.0:
		return
	var theirs: bool = phase == Phase.AI_AIM or phase == Phase.AI_STROKE or phase == Phase.AI_THINK
	if not theirs and phase != Phase.ROLLING:
		return
	var at: Vector3
	if phase == Phase.AI_THINK:
		# him, walking round it
		at = bot.head_w + Vector3.DOWN * 0.35
	elif phase == Phase.ROLLING:
		var f := _action_focus()
		at = Vector3(f.x, TABLE_Y + PoolSim.R, f.y)
	else:
		at = table.ball_world(sim, PoolSim.CUE)
	var to := at - player.eye()
	var want_yaw := atan2(to.z, to.x)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var k := 1.0 - exp(-2.4 * delta)
	player.yaw = lerp_angle(player.yaw, want_yaw, k)
	player.pitch = lerpf(player.pitch, clampf(want_pitch, -1.15, 0.85), k)


# How far you would have to lean to shoot along `yaw`: from the outside edge
# of the rail behind the cue ball to the ball itself. Zero when the ball is
# near enough the rail that you stand behind it as normal.
func _lean_for(cue_pos: Vector2, yaw: float) -> float:
	var back := -Vector2(cos(yaw), sin(yaw))
	var ox := PoolSim.HALF_LEN + PoolTableView.CUSHION_D + PoolTableView.CAP_W
	var oz := PoolSim.HALF_WID + PoolTableView.CUSHION_D + PoolTableView.CAP_W
	var t := 9.0
	if absf(back.x) > 1.0e-4:
		t = minf(t, (ox * signf(back.x) - cue_pos.x) / back.x)
	if absf(back.y) > 1.0e-4:
		t = minf(t, (oz * signf(back.y) - cue_pos.y) / back.y)
	return maxf(t, 0.0)


# Drop into the stance, shooting along the line you are standing on. If the
# cue ball is out in the table you lean across to it from the rail.
func _take_stance() -> void:
	var cue := sim.ball(PoolSim.CUE)
	if player.pos.distance_to(cue.pos) > STANCE_REACH:
		hud.say("Too far from the cue ball")
		return
	if _lean_for(cue.pos, (cue.pos - player.pos).angle()) > LEAN_MAX:
		hud.say("Can't reach it from this side")
		return
	if _calling() and called_pocket < 0:
		hud.say("Call a pocket first", "call")
		return
	if bar.holding():
		bar.release()
	_cancel_punch()
	_sway_last = 0.0
	aim_yaw = (cue.pos - player.pos).angle()
	stance_yaw = aim_yaw
	stance_cue = cue.pos
	aim_dir = Vector2(cos(aim_yaw), sin(aim_yaw))
	cue_elev = _cue_clearance(cue.pos, aim_dir, 0.006, 0.035, english)
	player.down = true
	player.locked = false
	look_off = Vector2.ZERO
	table.clear_pocket_glows()


# Stand back up where you got down, on the line you were shooting along.
func _leave_stance() -> void:
	if player.down:
		player.stand_at(stance_cue - aim_dir * 1.15, aim_dir)
	look_off = Vector2.ZERO
	pulling = false
	tip_adjust = false
	shot_power = 0.0
	pull_px = 0.0
	hud.set_power(0.0, false)


# --- calling the 8 ---------------------------------------------------------

# Where your eyes meet a level plane `height` above the cloth: the middle of
# the view.
func _look_point(height: float) -> Variant:
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit = Plane(Vector3.UP, TABLE_Y + height).intersects_ray(from, dir)
	if hit == null:
		return null
	return Vector2(hit.x, hit.z)


# The pocket you are looking at, whether your eyes land on the cloth in front
# of it or on the rail around it.
func _pocket_under_look() -> int:
	var best := -1
	var bd := 0.19
	for h: float in [0.0, PoolTableView.CAP_TOP]:
		var p = _look_point(h)
		if p == null:
			continue
		for i in sim.pockets.size():
			var d: float = (p as Vector2).distance_to(sim.pockets[i].c)
			if d < bd:
				bd = d
				best = i
	return best


func _update_call_hover() -> void:
	table.clear_pocket_glows()
	hover_pocket = -1
	if _calling():
		hover_pocket = _pocket_under_look()
		if hover_pocket >= 0 and hover_pocket != called_pocket:
			table.set_pocket_glow(hover_pocket, 1)
	if called_pocket >= 0:
		table.set_pocket_glow(called_pocket, 2)


func _show_called_only() -> void:
	table.clear_pocket_glows()
	if called_pocket >= 0:
		table.set_pocket_glow(called_pocket, 2)


# Clicking the pocket you have called takes the call back; clicking another
# one moves it there.
func _click_pocket() -> void:
	if hover_pocket < 0:
		hud.say("Look at a pocket to call it", "call")
		return
	if hover_pocket == called_pocket:
		called_pocket = -1
		hud.say("Call cancelled", "call")
	else:
		called_pocket = hover_pocket
		var what := "8 ball" if _on_eight(you_group) else "Calling"
		hud.say("%s, %s" % [what, PoolSim.POCKET_NAMES[called_pocket].trim_prefix("the ")], "call")
	sound.ui("click")
	if mp:
		online.lobby_send("call", {"pocket": called_pocket})
	_refresh_hud()


# --- ball in hand -----------------------------------------------------------

# The cue ball is in your hand and goes wherever you look on the table. Walk
# round to reach a different spot; click to put it down. If where you are
# looking is taken, it settles just beside the ball that is in the way.
func _update_placement() -> void:
	table.cue_lift = lerpf(table.cue_lift, HOLD_LIFT, 1.0 - exp(-10.0 * get_process_delta_time()))
	var hit = _look_point(PoolSim.R)
	if hit == null:
		return
	var raw: Vector2 = hit
	var p := _clamp_to_bed(raw)
	# looking well off the table is not pointing at a spot on it: the ball
	# stays where it was until your eyes come back
	if raw.distance_to(p) > 0.5:
		cue_view.draw_place_marker(place_point, place_ok, behind_head)
		return
	p = _settle(p)
	place_point = p
	place_ok = sim.spot_is_clear(p, behind_head)
	sim.place_cue(p)
	cue_view.draw_place_marker(p, place_ok, behind_head)


func _clamp_to_bed(p: Vector2) -> Vector2:
	var m := PoolSim.R * 1.1
	p.x = clampf(p.x, -PoolSim.HALF_LEN + m, PoolSim.HALF_LEN - m)
	p.y = clampf(p.y, -PoolSim.HALF_WID + m, PoolSim.HALF_WID - m)
	if behind_head:
		p.x = minf(p.x, PoolSim.HEAD_X - PoolSim.R)
	return p


# Nudge a spot out of other balls and pocket mouths.
func _settle(p: Vector2) -> Vector2:
	for _i in 8:
		var moved := false
		for b in sim.balls:
			if b.id == PoolSim.CUE or not b.on_table:
				continue
			var d: Vector2 = p - b.pos
			var want := PoolSim.D * 1.08
			if d.length() < want:
				var n := d.normalized() if d.length() > 1.0e-5 else Vector2.UP
				p = b.pos + n * want
				moved = true
		for pk in sim.pockets:
			var dc: Vector2 = p - pk.c
			var keep: float = float(pk.r) + PoolSim.R * 1.05
			if dc.length() < keep:
				p = (pk.c as Vector2) + dc.normalized() * keep
				moved = true
		p = _clamp_to_bed(p)
		if not moved:
			break
	return p


func _confirm_placement() -> void:
	if not place_ok:
		hud.say("No room there", "foul")
		return
	sim.place_cue(place_point)
	table.cue_lift = 0.0
	sound.play("rail", table.ball_world(sim, PoolSim.CUE), 0.12)
	ball_in_hand = false
	behind_head = false
	if mp:
		online.lobby_send("place", {"p": [place_point.x, place_point.y]})
	cue_view.clear_guide()
	phase = Phase.AIM
	var target := sim.ball(1) if sim.ball(1).on_table else sim.ball(PoolSim.EIGHT)
	aim_yaw = (target.pos - place_point).angle()
	aim_dir = Vector2(cos(aim_yaw), sin(aim_yaw))
	if _on_eight(you_group):
		hud.say("You're on the 8, call a pocket", "call")


# ---------------------------------------------------------------------------
# Shot resolution
# ---------------------------------------------------------------------------

# Your side of the shot, for your profile: that you took it, every ball the
# cue ball touched, what went down, and whether it was a foul.
func _count_shot(events: Array, res: Dictionary) -> void:
	profile.add("shots")
	var pots := 0
	for ev in events:
		if ev.type == "hit" and (int(ev.a) == PoolSim.CUE or int(ev.get("b", -1)) == PoolSim.CUE):
			profile.add("balls_hit")
	for id in res.potted:
		if id != PoolSim.CUE:
			pots += 1
	profile.add("balls_potted", pots)
	if res.foul:
		profile.add("fouls")
	if pots > 0 and not res.foul:
		profile.add_xp(pots * PoolProfile.XP_PER_POT)
	profile.flush()


func _bank_play_time() -> void:
	var secs := int(_play_time)
	if secs <= 0:
		return
	_play_time -= float(secs)
	profile.add("time_played", secs)
	profile.flush()


func _resolve_shot() -> void:
	if mp and shot_by_you:
		_mp_send_settle()
	var shooter := _shooter_group()
	var on_eight := _on_eight(shooter)
	var events := sim.events.duplicate()
	var res := PoolRules.analyze(events, shooter, on_eight, called_pocket if on_eight else -1)
	if your_turn:
		_count_shot(events, res)
	if mp:
		var side := 0 if your_turn else 1
		mp_fouls[side] = int(mp_fouls[side]) + 1 if res.foul else 0
		if bool(mp_rules.get("three_fouls", false)) and int(mp_fouls[side]) >= 3 and not res.won and not res.lost:
			res.lost = true
			res.reason = "Three fouls in a row"

	var was_break := not broken
	broken = true

	# the 8 on the break is a re-rack, not a result
	if was_break and res.eight_potted and not res.cue_potted:
		phase = Phase.OVER
		hud.say("8 on the break, re-rack", "brass")
		await get_tree().create_timer(1.6).timeout
		if mp:
			if not mp_over:
				_mp_rack(_next_seed(rack_seed))
		else:
			new_rack()
		return

	for id in res.potted:
		if id == PoolSim.CUE:
			table.ball_nodes[PoolSim.CUE].visible = false
			continue
		var side := "near"
		if you_group != PoolRules.OPEN and PoolRules.group_of(id) == foe_group:
			side = "far"
		elif id == PoolSim.EIGHT and not your_turn:
			side = "far"
		table.send_to_tray(id, side)

	if res.won or res.lost:
		_finish(res, shooter)
		return

	# claim a group on the first ball legally potted after the break
	if open_table and not was_break and not res.foul and res.own > 0:
		var claim := ""
		for id in res.potted:
			var g := PoolRules.group_of(id)
			if g != "":
				claim = g
				break
		if claim != "":
			open_table = false
			if your_turn:
				you_group = claim
				foe_group = PoolRules.other_group(claim)
			else:
				foe_group = claim
				you_group = PoolRules.other_group(claim)
			hud.say("%s %s" % ["You take" if your_turn else _foe_name() + " takes", "solids" if claim == PoolRules.SOLIDS else "stripes"], "good")

	var illegal_break := false
	if was_break and not res.foul:
		var rails := {}
		for ev in events:
			if ev.type == "rail":
				rails[ev.ball] = true
		if res.potted.is_empty() and rails.size() < 4:
			illegal_break = true

	var keep: bool = res.own > 0 and not res.foul and not illegal_break
	# calling every shot: one of yours has to drop in the pocket you named
	var call_miss := false
	if keep and _call_all() and not on_eight:
		var in_call := false
		for id in res.potted:
			if id != PoolSim.CUE and (shooter == PoolRules.OPEN or PoolRules.group_of(id) == shooter) \
					and int(res.pockets.get(id, -1)) == called_pocket:
				in_call = true
		if not in_call:
			keep = false
			call_miss = true

	if res.foul:
		hud.say("Foul: %s" % str(res.reason).to_lower(), "foul")
	elif illegal_break:
		hud.say("Weak break, ball in hand", "foul")
	elif call_miss:
		hud.say("Not in the called pocket, turn over", "foul")
	elif keep:
		hud.say("Shoot again" if res.own == 1 else "%d down, shoot again" % res.own, "good")
	elif res.potted.is_empty():
		hud.say("Nothing down")

	if not keep:
		your_turn = not your_turn
		ball_in_hand = res.foul or illegal_break
	else:
		ball_in_hand = false
	behind_head = mp and ball_in_hand and str(mp_rules.get("scratch", "anywhere")) == "kitchen"
	called_pocket = -1
	table.clear_pocket_glows()
	shot_power = 0.0
	pull_px = 0.0
	_refresh_hud()
	_begin_turn()


# Whoever is up now takes it from here: you on your feet, the house player
# thinking, or the other player's machine.
func _begin_turn() -> void:
	if mp:
		mp_clock = float(mp_rules.get("clock", 0))
	if your_turn:
		# your turn starts on your feet, where you got down for the last one
		_leave_stance()
		if ball_in_hand:
			phase = Phase.PLACE
			table.cue_lift = HOLD_LIFT
			hud.say("Ball in hand", "brass")
		else:
			var cue := sim.ball(PoolSim.CUE)
			var tgt := _nearest_legal(cue.pos, you_group)
			if tgt >= 0:
				aim_yaw = (sim.ball(tgt).pos - cue.pos).angle()
			aim_dir = Vector2(cos(aim_yaw), sin(aim_yaw))
			phase = Phase.AIM
			if _on_eight(you_group):
				hud.say("You're on the 8, call a pocket", "call")
			elif _call_all():
				hud.say("Call your pocket", "call")
	elif mp:
		_mp_their_turn()
	else:
		_start_ai()


func _nearest_legal(from: Vector2, g: String) -> int:
	var best := -1
	var bd := 1e9
	for id in PoolRules.legal_targets(sim, g):
		var d := sim.ball(id).pos.distance_to(from)
		if d < bd:
			bd = d
			best = id
	return best


func _finish(res: Dictionary, _shooter: String) -> void:
	phase = Phase.OVER
	table.clear_pocket_glows()
	if player.down:
		_leave_stance()
	var shooter_won: bool = res.won
	var you_won := shooter_won if your_turn else not shooter_won
	if res.lost:
		you_won = not your_turn
	if mp:
		_mp_rack_over(you_won, str(res.reason))
		return
	last_result = ("Won against %s" if you_won else "Lost to %s") % ai.label()
	# something to spend either way
	var pay := PoolCues.WIN_CASH if you_won else PoolCues.LOSS_CASH
	if online.signed_in():
		online.bot_reward(you_won)
	else:
		save_state.cash = int(save_state.get("cash", 0)) + pay
		PoolCues.save_state(save_state)
		_sync_wallet()
	_bank_play_time()
	var xp := profile.record_bot_game(you_won, ai.skill)
	var reward := "+%d coins" % pay
	if profile.signed_in:
		reward += "  ·  +%d XP" % xp
	if you_won:
		hud.finish("You win", "%s  %s" % [res.reason if res.reason != "" else "The 8 went where you called it.", reward], true)
	else:
		hud.finish("%s wins" % ai.label(), "%s  %s" % [res.reason if res.reason != "" else "The 8 went where they called it.", reward], false)
	hud.set_thinking(false)


# ---------------------------------------------------------------------------
# Opponent
# ---------------------------------------------------------------------------

func _start_ai() -> void:
	phase = Phase.AI_THINK
	ai_timer = 0.0
	ai_have_shot = false
	ai_shot = {}
	ai_pull = 0.0
	_ai_ready = false
	_ai_out = {}
	hud.set_thinking(true, ai.label())
	if player.down:
		_leave_stance()
	var work := sim.clone_sim(PoolAI.SIM_DT)
	var g := foe_group
	var bih := ball_in_hand
	var brk := not broken
	_thread = Thread.new()
	_thread.start(_ai_worker.bind(work, g, brk, bih))


func _ai_worker(work: PoolSim, g: String, brk: bool, bih: bool) -> void:
	var shot := ai.choose(work, g, brk, bih)
	_mutex.lock()
	_ai_out = shot
	_ai_ready = true
	_mutex.unlock()


# The opponent's mind is made up once the thread comes back. His body still
# has to walk round, maybe fetch the cue ball, and get down on it; the bot
# brain says when he is there, and _bot_begin_aim takes it from there.
func _poll_ai() -> void:
	if ai_have_shot:
		return
	_mutex.lock()
	var is_ready := _ai_ready
	var shot := _ai_out
	_mutex.unlock()
	if not is_ready or ai_timer < 0.9:
		return
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	hud.set_thinking(false)
	ai_shot = shot
	ai_have_shot = true
	bot_ball_placed = ai_shot.get("place", null) == null
	# on the 8 they say which pocket, out loud, like anyone has to
	if _on_eight(foe_group) and int(ai_shot.get("pocket", -1)) >= 0:
		called_pocket = int(ai_shot.pocket)
		table.clear_pocket_glows()
		table.set_pocket_glow(called_pocket, 2)
		hud.say("%s calls the 8, %s" % [ai.label(), PoolSim.POCKET_NAMES[called_pocket].trim_prefix("the ")], "call")


# He has put the cue ball down where he wants it.
func bot_placed_ball() -> void:
	var p = ai_shot.get("place", null)
	if p == null:
		# the shot he settled on didn't need it moved: back where it was
		var cb := sim.ball(PoolSim.CUE)
		p = cb.pos if cb.on_table else Vector2(PoolSim.HEAD_X - 0.3, 0.0)
	sim.place_cue(p)
	table.cue_lift = 0.0
	table.cue_hand = null
	table.ball_nodes[PoolSim.CUE].visible = true
	bot_ball_placed = true
	ball_in_hand = false
	sound.play("rail", table.ball_world(sim, PoolSim.CUE), 0.12)


func _bot_begin_aim() -> void:
	ball_in_hand = false
	ai_timer = 0.0
	ai_pull = 0.006
	var eng: Vector2 = ai_shot.get("english", Vector2.ZERO)
	cue_elev = _cue_clearance(sim.ball(PoolSim.CUE).pos, ai_shot.dir, 0.006, 0.006, eng)
	phase = Phase.AI_AIM


# The cue in his hands, laid on the shot he has chosen, while he gets down.
func bot_show_stick(pull: float) -> void:
	if ai_shot.is_empty():
		return
	var cue_p: Vector2 = brain._shot_cue()
	var d: Vector2 = ai_shot.dir
	var eng: Vector2 = ai_shot.get("english", Vector2.ZERO)
	var elev := _cue_clearance(cue_p, d, 0.006, maxf(pull, 0.006), eng)
	_bot_stick(cue_p, d, pull, elev, eng)


func _bot_stick(cue_p: Vector2, d: Vector2, pull: float, elev: float, eng: Vector2) -> void:
	var now := table.global_transform * PoolCueView.stick_transform(cue_p, d, pull, elev, eng)
	var rest := table.global_transform * PoolCueView.stick_transform(cue_p, d, 0.0, elev, eng)
	bot.set_shot_cue(now, rest)


# Two feathering strokes, then a slow draw back to where the shot needs it,
# and a moment's pause there.
func _ai_practice_pull(t: float, final_pull: float) -> float:
	if t < 1.5:
		return 0.03 + 0.07 * (0.5 - 0.5 * cos(TAU * t / 0.75))
	var k := clampf((t - 1.5) / 0.7, 0.0, 1.0)
	return lerpf(0.03, final_pull, smoothstep(0.0, 1.0, k))


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _action_focus() -> Vector2:
	return Vector2(watch_focus.x, watch_focus.z)


# Where your eyes follow the balls: the middle of what is moving, weighted by
# how fast each ball is going, so a ball rolling to a stop fades out of it
# instead of dropping out with a jump, and eased so the eyes glide rather than
# twitch. When everything stops it stays where it was.
func _update_watch_focus(delta: float) -> void:
	var sum := Vector2.ZERO
	var wsum := 0.0
	for b in sim.balls:
		if b.on_table and not b.resting:
			var w: float = b.vel.length()
			sum += b.pos * w
			wsum += w
	if wsum < 0.02:
		return
	var p := sum / wsum
	var target := Vector3(p.x, TABLE_Y + 0.05, p.y)
	watch_focus = watch_focus.lerp(target, 1.0 - exp(-2.2 * delta))


# The camera is a pair of eyes belonging to somebody. On their feet it is the
# player's own head; down on a shot it is the stance behind the cue ball. One
# eased number, `stand`, runs between the two, so getting down and standing up
# are the same smooth motion rather than a cut.
func _update_camera(delta: float) -> void:
	var centre := Vector3(0, TABLE_Y, 0)
	var cue := sim.ball(PoolSim.CUE)
	var cue3 := Vector3(cue.pos.x, TABLE_Y + PoolSim.R, cue.pos.y)
	if phase == Phase.STROKE or phase == Phase.ROLLING or phase == Phase.AI_STROKE:
		cue3 = shot_origin
	var fwd := Vector3(aim_dir.x, 0.0, aim_dir.y)

	var eye: Vector3
	var look_target: Vector3

	if phase == Phase.MENU:
		menu_angle += delta * 0.045
		var seat := Vector3(cos(menu_angle) * WALK_A * 1.34, EYE_H + 0.32, sin(menu_angle) * WALK_B * 1.34)
		var to_c := centre - seat
		var side := Vector3(-to_c.z, 0.0, to_c.x).normalized()
		eye = seat
		look_target = centre + Vector3(0.0, 0.10, 0.0) - side * (2.2 * menu.bar_fraction())
		stand = 1.0
	else:
		var walk_eye := player.eye()
		var walk_look := walk_eye + player.look_dir() * 2.6

		tip_look = move_toward(tip_look, 1.0 if tip_adjust else 0.0, delta * 4.0)
		var tl := smoothstep(0.0, 1.0, tip_look)
		# Your head stays above the stick: when the butt has to come up to
		# clear something, so does your eye line, a hand's width over it.
		var pitch: float = maxf(cam_pitch, cue_elev + 0.12)
		var reach: float = cam_dist + shot_power * 0.13
		var rolling_down := phase == Phase.ROLLING and player.down
		if rolling_down:
			reach = roll_reach
		# looking down the cue at the tip: in close, over the cue ball
		pitch = lerpf(pitch, maxf(0.34, cue_elev + 0.20), tl)
		reach = lerpf(reach, 0.34, tl)
		var aim_eye := cue3 - fwd * (cos(pitch) * reach) + Vector3.UP * (sin(pitch) * reach)
		var aim_look := (cue3 + fwd * 0.48 + Vector3.UP * 0.015).lerp(cue3, tl)

		var target := 0.0 if player.down else 1.0
		if rolling_down and shot_by_you:
			# a tap keeps you down on the shot; a hard one straightens you up
			# far enough to see where everything went. It only ever rises
			# while the balls run, so you don't bob as they come to rest.
			var spread := 0.0
			for b in sim.balls:
				if b.on_table and not b.resting:
					spread = maxf(spread, b.pos.distance_to(Vector2(shot_origin.x, shot_origin.z)))
			var energy: float = clampf(shot_speed / 6.5, 0.0, 1.0) * 0.45
			energy += clampf(spread / 1.90, 0.0, 1.0) * 0.45
			roll_stand = maxf(roll_stand, clampf(0.08 + energy, 0.08, 1.0))
			target = roll_stand
			# your eyes are on the balls; the mouse turns your head away from
			# them, and it drifts back once you leave the mouse alone
			if look_idle > 1.0:
				look_off = look_off.lerp(Vector2.ZERO, 1.0 - exp(-0.9 * delta))
			aim_look = _gaze(aim_eye, watch_focus, look_off)
			walk_look = _gaze(walk_eye, watch_focus, look_off)
		# bending down is quicker than straightening up, as it is in life, and
		# getting down from further out takes a moment longer
		var step_in: float = clampf(player.pos.distance_to(cue.pos) * 0.22, 0.0, 0.7)
		var rate: float = (0.72 + step_in) if target < stand else 0.95
		stand = move_toward(stand, target, delta / rate)

		# the step in finishes a touch before the bend down, which is how
		# people move
		var down_xz: float = 1.0 - smoothstep(0.0, 1.0, clampf(stand * 1.22, 0.0, 1.0))
		var down_y: float = 1.0 - smoothstep(0.0, 1.0, stand)
		eye = walk_eye.lerp(aim_eye, down_xz)
		eye.y = lerpf(walk_eye.y, aim_eye.y, down_y)
		look_target = walk_look.lerp(aim_look, down_xz)
		# tipping a glass back, your head goes back with it
		var hb := bar.head_back()
		if hb > 0.0:
			look_target += Vector3.UP * hb * 2.6

	# the stroke pushes the view forward a little and it settles back
	kick = maxf(0.0, kick - delta * 3.4)
	eye += fwd * kick
	var extra_roll := 0.0
	# throwing a punch: you wind up and turn away with it, then your whole
	# head goes in behind the fist
	if punch_t >= 0.0:
		var look := -cam.global_transform.basis.z
		var flat := Vector3(look.x, 0.0, look.z).normalized()
		var side := flat.cross(Vector3.UP)
		var back := 0.0
		var turn := 0.0
		if punch_t < PUNCH_WINDUP:
			var k := smoothstep(0.0, 1.0, punch_t / PUNCH_WINDUP)
			back = -0.07 * k
			turn = 0.05 * k
			extra_roll = 0.05 * k
		elif punch_t < PUNCH_WINDUP + 0.35:
			var k := (punch_t - PUNCH_WINDUP) / 0.35
			back = lerpf(-0.07, 0.13, sin(PI * 0.5 * minf(k * 2.8, 1.0))) * (1.0 - smoothstep(0.35, 1.0, k))
			turn = lerpf(0.05, -0.04, minf(k * 3.0, 1.0)) * (1.0 - smoothstep(0.35, 1.0, k))
			extra_roll = lerpf(0.05, -0.04, minf(k * 3.0, 1.0)) * (1.0 - smoothstep(0.35, 1.0, k))
		eye += flat * back + side * turn + Vector3.DOWN * maxf(back, 0.0) * 0.25
	# drink in you
	var tr := bar.trip()
	var wob := bar.wobble()
	if wob > 0.0:
		var side := Vector3(-sin(player.yaw), 0.0, cos(player.yaw))
		eye += side * wob * 0.05 * sin(cam_time * 0.5)
		extra_roll += wob * (0.07 * sin(cam_time * 0.6) + 0.03 * sin(cam_time * 1.7))
	if tr > 0.0:
		extra_roll += tr * 0.05 * sin(cam_time * 0.8)
		eye.y += tr * 0.02 * sin(cam_time * 2.1)
	eye.y += bar.hic * 0.035
	shake = maxf(0.0, shake - delta * 2.2)
	if shake > 0.0 and PoolSettings.on("screen_shake"):
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03 * shake * shake

	# on your feet the head is yours, so the camera follows it closely; down
	# on a shot it eases
	var speed: float = lerpf(7.5, 12.0, smoothstep(0.0, 1.0, stand))
	if phase == Phase.MENU:
		speed = 1.1
	elif cam_time < 1.4:
		speed = minf(speed, 2.4)
	var k: float = 1.0 - exp(-speed * delta)
	var new_pos := cam.global_position.lerp(eye, k)
	new_pos.x = clampf(new_pos.x, -BarRoom.W + 0.4, BarRoom.W - 0.4)
	new_pos.z = clampf(new_pos.z, -BarRoom.L + 0.4, BarRoom.L - 0.4)
	new_pos.y = clampf(new_pos.y, TABLE_Y + 0.06, BarRoom.H - 0.3)
	cam.global_position = new_pos

	var to_look := look_target - new_pos
	if to_look.length() < 0.05:
		to_look = Vector3.FORWARD
	var want := Transform3D().looking_at(to_look, Vector3.UP)
	if phase != Phase.MENU:
		# the faint lean of the walk, only while you're on your feet
		var r := player.roll() * smoothstep(0.6, 1.0, stand) + extra_roll
		want.basis = want.basis.rotated(-want.basis.z.normalized(), r)
	var q := Quaternion(cam.global_transform.basis.orthonormalized()).slerp(
		Quaternion(want.basis.orthonormalized()), clampf(k * 1.2, 0.0, 1.0))
	var xf := Transform3D(Basis(q), new_pos)
	# knocked flying: the view is the fall's, not yours
	if ko_w > 0.0:
		xf = xf.interpolate_with(_ko_xf, ko_w)
	cam.global_transform = xf
	# the lens: a kick wider as the fist goes in, the room breathing on
	# Blitzkraft
	var fov := PoolSettings.f("fov")
	if punch_t >= PUNCH_WINDUP:
		fov += 8.0 * sin(PI * clampf((punch_t - PUNCH_WINDUP) / 0.45, 0.0, 1.0))
	fov += tr * (4.0 + 6.0 * sin(cam_time * 1.3))
	cam.fov = fov


# A point two metres out from `from`, towards `at`, turned by `off` (yaw,
# pitch) the way a head turns.
func _gaze(from: Vector3, at: Vector3, off: Vector2) -> Vector3:
	var to := at - from
	var yaw := atan2(to.z, to.x) + off.x
	var lp := clampf(atan2(to.y, Vector2(to.x, to.z).length()) + off.y, -1.3, 0.85)
	return from + Vector3(cos(lp) * cos(yaw), sin(lp), cos(lp) * sin(yaw)) * 2.0


# The finished frame: the everyday grade, and on top of it whatever the
# drink, the floor or the punch is doing to you.
func _update_postfx(delta: float) -> void:
	postfx.trip = bar.trip()
	postfx.wobble = bar.wobble()
	postfx.dizzy = _ko_dizzy
	var zb := 0.0
	if punch_t >= PUNCH_WINDUP - 0.03:
		zb = sin(PI * clampf((punch_t - PUNCH_WINDUP + 0.03) / 0.4, 0.0, 1.0))
	if ko_t >= 0.0 and ko_t < KO_FLY:
		zb = maxf(zb, 0.8 * sin(PI * ko_t / KO_FLY))
	postfx.zoom_blur = zb
	postfx.flash = maxf(0.0, postfx.flash - delta * 4.0)


# The cue in your hand: at your side while you walk, gone while you are down
# on a shot (it is on the table then) and while you are in the menus.
func _update_held_cue() -> void:
	var show := phase != Phase.MENU and not player.down and stand > 0.9 and ko_t < 0.0 and not arm.visible
	held_cue.visible = show
	if not show:
		return
	var bob := -(0.5 - 0.5 * cos(player.bob * 2.0)) * 0.010 * player.sway
	held_cue.position = Vector3(player.pos.x, bob, player.pos.y)
	held_cue.rotation = Vector3(0.0, -player.yaw - PI * 0.5, 0.0)


func _update_mouse_mode() -> void:
	var want := Input.MOUSE_MODE_VISIBLE
	var busy: bool = hud.confirm_open()
	var playing: bool = phase != Phase.MENU and phase != Phase.OVER
	if playing and not busy:
		want = Input.MOUSE_MODE_CAPTURED
	if int(want) != _mouse_mode:
		_mouse_mode = int(want)
		Input.mouse_mode = want


# What you can do right now, along the bottom of the screen.
func _update_hints() -> void:
	var h: Array = []
	match phase:
		Phase.PLACE:
			h = [["LMB", "Put the cue ball down"], ["W A S D", "Walk"]]
		Phase.AIM:
			if tip_adjust:
				h = [["RMB", "Let go to keep the tip here"]]
			elif player.down:
				h = [["LMB", "Hold, pull back, push through"], ["RMB", "Move the tip"], ["SPACE", "Stand up"]]
			elif _calling() and called_pocket < 0:
				h = [["LMB", "Look at a pocket and click to call the 8"], ["W A S D", "Walk"]]
			else:
				var near := player.pos.distance_to(sim.ball(PoolSim.CUE).pos) <= STANCE_REACH
				h = [["SPACE", "Get down on the shot"]] if near else [["W A S D", "Walk up to the cue ball"]]
				if _calling():
					h.append(["LMB", "Change your call"])
		Phase.ROLLING:
			if player.down:
				h = [["SPACE", "Stand up"]]
	if _can_punch():
		h = [["LMB", "Punch" if punch_cd <= 0.0 else "Punch in %ds" % int(ceil(punch_cd))]]
	if bar.look_card != "":
		var d: Dictionary = PoolBar.DRINKS[bar.look_card]
		h = [["LMB", "Order %s  $%d" % [d.name, d.price]]]
	elif bar.look_glass:
		h = [["HOLD LMB", "Pick it up"]]
	elif bar.holding():
		h = [["MOUSE UP", "Drink"], ["RELEASE", "Put it down"]]
	if ko_t >= 0.0:
		h = []
	hud.set_hints(h)


# What your friends see on Discord: where you are in the game, and whether
# you have wandered off.
func _update_presence(delta: float) -> void:
	_presence_t -= delta
	if _presence_t > 0.0:
		return
	_presence_t = 1.0
	var idle := Time.get_ticks_msec() - _last_input_ms > IDLE_AFTER_MS
	var details := "In the menu"
	var state := ""
	var since := 0
	if phase == Phase.MENU:
		match menu.screen.page:
			"shop":
				details = "In the shop"
				state = "Looking at %s" % str(PoolCues.CUES[menu.screen.picked_cue].name)
			"mode":
				state = "Choosing a game mode"
			"play":
				state = "Picking an opponent"
			"info":
				state = "Reading how to play"
			"settings":
				state = "In settings"
			"profile":
				state = "Looking at their profile"
	elif mp:
		details = "Playing online vs %s" % _foe_name()
		since = match_started
		state = "Racks %d-%d" % [mp_score[0], mp_score[1]] if not mp_over else last_result
	else:
		details = "Playing 8-ball vs %s (level %d)" % [ai.label(), ai.skill]
		since = match_started
		if phase == Phase.OVER:
			state = last_result
		elif hud.confirm_open():
			state = "Paused"
		elif your_turn:
			state = "Your shot"
			if phase == Phase.PLACE:
				state = "Ball in hand"
			elif _on_eight(you_group):
				state = "Your shot, on the 8"
			elif you_group != PoolRules.OPEN:
				state = "Your shot (%s, %d left)" % [you_group, PoolRules.remaining(sim, you_group).size()]
		else:
			state = "Opponent's shot"
	if idle:
		state = "Idle"
	discord.set_presence(details, state, since)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey or ev is InputEventMouseButton or \
			(ev is InputEventMouseMotion and (ev as InputEventMouseMotion).relative.length() > 1.0):
		_last_input_ms = Time.get_ticks_msec()


# ---------------------------------------------------------------------------
# Input
#
# Everything here is something you would do at a real table: walk (WASD),
# look (mouse), get down on the shot or stand up (space), stroke (hold left
# and pull back), move the tip on the cue ball (hold right), lean in or out
# (wheel), and step away (Esc). Clicking with your eyes on a spot puts the
# cue ball there, or calls the pocket you are looking at for the 8 — but only
# while you are standing, never while you are down over a shot.
# ---------------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if phase == Phase.MENU:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		if phase == Phase.OVER:
			return
		if hud.confirm_open():
			hud.close_confirm()
		else:
			pulling = false
			tip_adjust = false
			hud.set_power(0.0, false)
			hud.open_confirm()
		return
	if hud.confirm_open():
		return
	if ev is InputEventMouseButton and bar.holding():
		# a drink in your hand: let go of the button and you let go of it
		var hb := ev as InputEventMouseButton
		if hb.button_index == MOUSE_BUTTON_LEFT and not hb.pressed:
			bar.release()
		return
	if ev is InputEventMouseMotion and bar.holding():
		# the mouse lifts the glass rather than your head; you can still turn
		var hr: Vector2 = (ev as InputEventMouseMotion).relative
		bar.lift(hr.y)
		player.turn(Vector2(hr.x, 0.0), 0.0021 * PoolSettings.f("mouse_sens"))
		look_idle = 0.0
		return
	if ko_t >= 0.0:
		# on the floor: you can look about, and that's all
		if ev is InputEventMouseMotion:
			var kr: Vector2 = (ev as InputEventMouseMotion).relative
			var ks := 0.0015 * PoolSettings.f("mouse_sens")
			ko_look.x = clampf(ko_look.x + kr.x * ks, -0.6, 0.6)
			ko_look.y = clampf(ko_look.y - kr.y * ks, -0.4, 0.3)
		return
	if ev is InputEventMouseButton and not player.down:
		var bm := ev as InputEventMouseButton
		# the bar: a card you're looking at, a glass in reach
		if bm.button_index == MOUSE_BUTTON_LEFT and bm.pressed:
			if bar.can_grab():
				bar.grab()
				return
			if bar.look_card != "":
				bar.order(bar.look_card)
				return
	if phase == Phase.OVER:
		return

	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		# Only when the click has nothing else to do: putting the cue ball
		# down and calling the 8 always come first. It's a bit of fun, not
		# part of the game.
		if mb.button_index == MOUSE_BUTTON_LEFT and not player.down and mb.pressed and _can_punch():
			if punch_cd > 0.0:
				hud.say("Punch ready in %ds" % int(ceil(punch_cd)))
			else:
				_start_punch()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if phase == Phase.PLACE and mb.pressed:
				_confirm_placement()
			elif phase == Phase.AIM and not player.down and mb.pressed:
				if _calling():
					_click_pocket()
			elif phase == Phase.AIM and player.down and not tip_adjust:
				if mb.pressed:
					pulling = true
					pull_px = 0.0
					shot_power = 0.0
				elif pulling:
					pulling = false
					if shot_power >= 0.06:
						stroke_pull = 0.03 + shot_power * 0.27
						stroke_elev = maxf(cue_elev, _cue_clearance(sim.ball(PoolSim.CUE).pos, aim_dir, 0.006, stroke_pull, english))
						stroke_t = 0.0
						phase = Phase.STROKE
					else:
						shot_power = 0.0
						pull_px = 0.0
						hud.set_power(0.0, false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if phase == Phase.AIM and player.down and not pulling:
				tip_adjust = mb.pressed
			elif not mb.pressed:
				tip_adjust = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and player.down and mb.pressed:
			cam_dist = clampf(cam_dist - 0.06, 0.45, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and player.down and mb.pressed:
			cam_dist = clampf(cam_dist + 0.06, 0.45, 1.2)

	elif ev is InputEventMouseMotion:
		var rel: Vector2 = ev.relative
		var sens := PoolSettings.f("mouse_sens")
		look_idle = 0.0
		still_time = 0.0
		if pulling:
			# pull the mouse back towards you to load the stroke
			pull_px = clampf(pull_px + rel.y, 0.0, PULL_RANGE * 1.1)
		elif tip_adjust:
			# move the tip round the face of the cue ball
			english += Vector2(rel.x, -rel.y) * TIP_SENS
			if english.length() > PoolHud.TipBall.LIMIT:
				english = english.normalized() * PoolHud.TipBall.LIMIT
			hud.set_spin(english)
		elif not player.down:
			player.turn(rel, 0.0021 * sens)
		elif phase == Phase.ROLLING:
			look_off.x = wrapf(look_off.x + rel.x * 0.0021 * sens, -PI, PI)
			look_off.y = clampf(look_off.y - rel.y * 0.0019 * sens, -0.95, 0.75)
		elif phase == Phase.AIM:
			# small, slow movements are finer still, the way a steady hand is
			var fine: float = clampf(absf(rel.x) / 7.0, 0.2, 1.0)
			var swing: float = wrapf(aim_yaw + rel.x * AIM_SENS * sens * fine - stance_yaw, -PI, PI)
			# a good way round either side of where you got down, but only as
			# far as you could still reach the ball from behind the rail
			var want: float = stance_yaw + clampf(swing, -STANCE_ARC, STANCE_ARC)
			var cue_p := sim.ball(PoolSim.CUE).pos
			if _lean_for(cue_p, want) <= LEAN_MAX:
				aim_yaw = want
			else:
				# go as far towards it as the reach allows, rather than stopping dead
				var lo := aim_yaw
				var hi := want
				for _i in 8:
					var mid := lerp_angle(lo, hi, 0.5)
					if _lean_for(cue_p, mid) <= LEAN_MAX:
						lo = mid
					else:
						hi = mid
				aim_yaw = lo
			cam_pitch = clampf(cam_pitch - rel.y * 0.0012 * sens, 0.10, 0.75)

	elif ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_SPACE and not pulling:
			if phase == Phase.AIM:
				if player.down:
					_leave_stance()
				else:
					_take_stance()
			elif phase == Phase.ROLLING and player.down:
				_leave_stance()


func _to_menu() -> void:
	if mp:
		_mp_back_to_lobby()
		return
	_leave_table()
	menu.open()


# Everything back as it was before you walked up to the table.
func _leave_table() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	_bank_play_time()
	_reset_person()
	pulling = false
	tip_adjust = false
	player.down = false
	player.locked = false
	look_off = Vector2.ZERO
	shot_power = 0.0
	pull_px = 0.0
	hud.set_power(0.0, false)
	hud.set_hints([])
	hud.close_confirm()
	hud.clear_finish()
	hud.set_thinking(false)
	new_rack()
	phase = Phase.MENU
	stand = 1.0
	hud.set_shown(false)
	hud.set_online(false)
	_sync_wallet()


func _restart() -> void:
	if mp:
		_mp_rematch()
		return
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	_reset_person()
	pulling = false
	tip_adjust = false
	player.down = false
	player.locked = false
	shot_power = 0.0
	pull_px = 0.0
	hud.set_power(0.0, false)
	hud.set_thinking(false)
	hud.close_confirm()
	new_rack()


# ---------------------------------------------------------------------------
# Coins
#
# One purse for everything: drinks at the bar and cues in the shop. Signed in
# with Discord it's kept online (the server does the sums, so it can't be
# edited), otherwise in the local save.
# ---------------------------------------------------------------------------

func coins() -> int:
	return online.coins() if online.signed_in() else int(save_state.get("cash", 0))


# Takes coins for something at the bar. False when you can't cover it.
func try_spend(n: int) -> bool:
	if online.signed_in():
		if online.coins() < n:
			return false
		online.me["coins"] = online.coins() - n     # straight away; the server has the last word
		online.spend(n)
		_sync_wallet()
		return true
	var have := int(save_state.get("cash", 0))
	if have < n:
		return false
	save_state.cash = have - n
	PoolCues.save_state(save_state)
	_sync_wallet()
	return true


# What the menu shows: your coins and cues from wherever they're kept, the
# rest from the local save.
func _menu_state() -> Dictionary:
	var st := save_state.duplicate(true)
	if online.signed_in():
		st.owned = online.owned_cues().duplicate()
		st.cash = online.coins()
		if not (st.owned as Array).has(str(st.equipped)):
			st.equipped = "house"
	return st


func _sync_wallet() -> void:
	if menu == null:
		return
	var st := _menu_state()
	_apply_skin(str(st.equipped))
	menu.set_state(st)


func _buy_cue(id: String) -> void:
	var cue := PoolCues.by_id(id)
	var price := int(cue.price)
	if online.signed_in():
		var err := await online.buy_cue(id)
		if err != "":
			menu.screen.show_toast("You need %d more coins." % (price - online.coins()) if err.contains("coins") else err)
			return
	else:
		var have := int(save_state.get("cash", 0))
		if have < price:
			menu.screen.show_toast("You need %d more coins." % (price - have))
			return
		save_state.cash = have - price
		if not (save_state.owned as Array).has(id):
			save_state.owned.append(id)
	save_state.equipped = id
	PoolCues.save_state(save_state)
	_sync_wallet()
	sound.ui("equip")
	menu.screen.show_toast("%s is yours." % str(cue.name))


func _redeem_code(code: String) -> void:
	var id := PoolCues.redeem(code)
	var fresh := false
	if id != "":
		if online.signed_in():
			fresh = not online.owned_cues().has(id)
			id = await online.redeem_code(code)
		else:
			fresh = not (save_state.owned as Array).has(id)
			if fresh:
				save_state.owned.append(id)
		if id != "":
			save_state.equipped = id
			PoolCues.save_state(save_state)
			_sync_wallet()
	menu.screen.code_result(id, fresh)


# A message while you're at the table: a line in the corner, no more.
func _on_message(m: Dictionary) -> void:
	if phase == Phase.MENU:
		return
	var f := online.friend(str(m.get("sender", "")))
	var who := str(f.get("display_name", "A friend"))
	if str(m.get("kind", "")) == "invite":
		hud.say("%s invited you to play. Open Friends in the menu" % who, "brass")
	else:
		hud.say("%s: %s" % [who, str(m.get("body", "")).left(60)], "info")


# ---------------------------------------------------------------------------
# Online matches
#
# Both players run the whole game. Whoever's turn it is plays exactly as they
# would against the house player, and their shot goes to the other machine
# as the same numbers _play_shot takes. That machine plays it too, then waits
# for the shooter's "settle": where every ball came to rest and what happened
# on the way. It takes that as the truth before applying the rules, so both
# sides always agree, even if their physics drifted by a hair.
#
# Everything about the other player's turn is queued and only acted on once
# it's their turn here, so nothing that arrives early can land mid-shot.
# ---------------------------------------------------------------------------

var online: PoolOnline
var mp := false
var mp_match: Dictionary = {}
var mp_rules: Dictionary = {}
var mp_score := [0, 0]            # racks won: you, them
var mp_seq := 0                   # shots played this match, by both of you
var mp_inbox: Array = []          # [event, payload] for their turn
var mp_settles := {}              # shot number -> the shooter's settle
var mp_remote: Dictionary = {}    # their last pose
var mp_clock := 0.0               # shot clock, seconds left
var mp_fouls := [0, 0]            # fouls in a row: you, them
var mp_breaker_me := true
var mp_over := false
var mp_want_rematch := [false, false]
var mp_opp: Dictionary = {}
var mp_heard_ms := 0              # when anything last came from them (they send ten times a second)
var mp_opp_left := false          # gone back to the lobby, or out of it
var _mp_pose_ms := 0
var _mp_pose_last: Dictionary = {}
var _mp_result_sent := false


func _foe_name() -> String:
	if mp:
		return str(mp_opp.get("display_name", mp_opp.get("username", "Opponent")))
	return ai.label()


static func _next_seed(s: int) -> int:
	return int((s * 1103515245 + 12345) & 0x7fffffff)


# The host pressed Start in the lobby.
func _host_start() -> void:
	if not online.is_host() or mp:
		return
	var m := await online.start_match()
	if m.has("error"):
		menu.screen.show_toast(str(m.error))
		return
	online.lobby_send("start", {"match": m})
	start_online(m)


func start_online(m: Dictionary) -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	mp = true
	mp_match = m
	mp_rules = PoolMPRules.clean(m.get("rules", {}))
	mp_opp = online.opponent()
	mp_score = [0, 0]
	mp_seq = 0
	mp_inbox.clear()
	mp_settles.clear()
	mp_fouls = [0, 0]
	mp_over = false
	mp_want_rematch = [false, false]
	mp_heard_ms = Time.get_ticks_msec()
	mp_opp_left = false
	mp_remote = {}
	_mp_result_sent = false
	guides_allowed = bool(mp_rules.guides)
	_reset_person()
	pulling = false
	tip_adjust = false
	player.down = false
	player.locked = false
	shot_power = 0.0
	pull_px = 0.0
	brain.reset()
	brain.hush()
	menu.close()
	hud.close_confirm()
	hud.clear_finish()
	hud.set_online(true)
	hud.set_shown(true)
	online.set_status("playing")
	online.set_ready(false)
	match_started = int(Time.get_unix_time_from_system())
	cam_time = 0.0
	_presence_t = 0.0
	mp_breaker_me = online.is_host()
	_mp_rack(int(m.get("seed", 1)))


func _mp_rack(seed_value: int) -> void:
	new_rack(seed_value)
	mp_fouls = [0, 0]
	your_turn = mp_breaker_me
	hud.set_thinking(false)
	_refresh_hud()
	mp_clock = float(mp_rules.get("clock", 0))
	if your_turn:
		hud.say("Your break", "brass")
	else:
		hud.say("%s breaks" % _foe_name(), "brass")
		_mp_their_turn()


func _mp_their_turn() -> void:
	phase = Phase.AI_THINK
	ai_timer = 0.0
	ai_shot = {}
	hud.set_thinking(true)
	if player.down:
		_leave_stance()


func _mp_their_turn_update(delta: float) -> void:
	ai_timer += delta
	cue_view.hide_stick()
	cue_view.clear_guide()
	# their cue ball, following their hand while they have it
	var h: Variant = mp_remote.get("h", null)
	if ball_in_hand and h is Array and (h as Array).size() == 2:
		sim.place_cue(Vector2(float(h[0]), float(h[1])))
		table.cue_lift = HOLD_LIFT
	while not mp_inbox.is_empty() and phase == Phase.AI_THINK:
		var m: Array = mp_inbox.pop_front()
		_mp_apply(str(m[0]), m[1])


func _mp_apply(event: String, p: Dictionary) -> void:
	match event:
		"place":
			var at: Array = p.get("p", [0, 0])
			sim.place_cue(Vector2(float(at[0]), float(at[1])))
			table.cue_lift = 0.0
			ball_in_hand = false
			sound.play("rail", table.ball_world(sim, PoolSim.CUE), 0.12)
		"call":
			called_pocket = int(p.get("pocket", -1))
			table.clear_pocket_glows()
			if called_pocket >= 0:
				table.set_pocket_glow(called_pocket, 2)
				hud.say("%s calls %s" % [_foe_name(), PoolSim.POCKET_NAMES[called_pocket].trim_prefix("the ")], "call")
		"timeout":
			_mp_timeout(false)
		"shot":
			mp_seq = int(p.get("seq", mp_seq + 1))
			var d: Array = p.get("dir", [1, 0])
			var e: Array = p.get("english", [0, 0])
			var at: Array = p.get("place", [])
			if at.size() == 2:
				sim.place_cue(Vector2(float(at[0]), float(at[1])))
			table.cue_lift = 0.0
			table.ball_nodes[PoolSim.CUE].visible = true
			ball_in_hand = false
			called_pocket = int(p.get("pocket", -1))
			ai_shot = {
				"dir": Vector2(float(d[0]), float(d[1])).normalized(),
				"speed": float(p.get("speed", 1.0)),
				"english": Vector2(float(e[0]), float(e[1])),
				"pocket": called_pocket,
			}
			hud.set_thinking(false)
			aim_dir = ai_shot.dir
			aim_yaw = atan2(aim_dir.y, aim_dir.x)
			var cue := sim.ball(PoolSim.CUE)
			stroke_pull = clampf(float(p.get("pull", 0.15)), 0.02, 0.35)
			stroke_elev = _cue_clearance(cue.pos, aim_dir, 0.006, stroke_pull, ai_shot.english)
			cue_elev = stroke_elev
			stroke_t = 0.0
			phase = Phase.AI_STROKE


# Their shot has stopped here; take their word for where it all ended up.
func _mp_try_settle() -> void:
	if not mp_settles.has(mp_seq):
		return
	var p: Dictionary = mp_settles[mp_seq]
	mp_settles.erase(mp_seq)
	var bs: Array = p.get("balls", [])
	for i in mini(bs.size(), sim.balls.size()):
		var r: Array = bs[i]
		var b: PoolSim.Ball = sim.balls[i]
		b.pos = Vector2(float(r[0]), float(r[1]))
		b.on_table = int(r[2]) == 1
		b.pocket = int(r[3])
		b.vel = Vector2.ZERO
		b.spin = Vector3.ZERO
		b.resting = true
	var evs: Array = []
	for e in p.get("events", []):
		var d := {"type": str(e.get("type", ""))}
		for k in ["a", "b", "ball", "pocket"]:
			if (e as Dictionary).has(k):
				d[k] = int(e[k])
		evs.append(d)
	sim.events = evs
	_resolve_shot()


func _mp_send_settle() -> void:
	var bs: Array = []
	for b in sim.balls:
		bs.append([b.pos.x, b.pos.y, 1 if b.on_table else 0, b.pocket])
	var evs: Array = []
	for ev in sim.events:
		var e := {"type": ev.type}
		for k in ["a", "b", "ball", "pocket"]:
			if (ev as Dictionary).has(k):
				e[k] = ev[k]
		evs.append(e)
	online.lobby_send("settle", {"seq": mp_seq, "balls": bs, "events": evs})


func _mp_update(delta: float) -> void:
	# where you are and what you're doing: up to five times a second while it
	# changes, and every two seconds anyway so they know you're still there
	var now := Time.get_ticks_msec()
	if now - _mp_pose_ms >= 200:
		var pose := {"p": [snappedf(player.pos.x, 0.01), snappedf(player.pos.y, 0.01)], "y": snappedf(player.yaw, 0.01),
			"d": player.down}
		if ball_in_hand and phase == Phase.PLACE:
			pose["h"] = [snappedf(place_point.x, 0.005), snappedf(place_point.y, 0.005)]
		if player.down and your_turn and (phase == Phase.AIM or phase == Phase.STROKE):
			var pull := 0.035 + shot_power * 0.27
			pose["a"] = [snappedf(aim_dir.x, 0.0005), snappedf(aim_dir.y, 0.0005), snappedf(pull, 0.005),
				snappedf(cue_elev, 0.005), snappedf(english.x, 0.01), snappedf(english.y, 0.01)]
		if pose != _mp_pose_last or now - _mp_pose_ms >= 2000:
			_mp_pose_ms = now
			_mp_pose_last = pose
			online.lobby_send("pose", pose)
	# the shot clock
	if not mp_over and int(mp_rules.get("clock", 0)) > 0 and phase in [Phase.PLACE, Phase.AIM, Phase.AI_THINK]:
		mp_clock = maxf(0.0, mp_clock - delta)
		hud.set_clock(mp_clock, your_turn)
		if your_turn and mp_clock <= 0.0 and not pulling:
			_mp_timeout(true)
	else:
		hud.set_clock(-1.0, your_turn)
	# gone quiet: twenty seconds without a word (in real time, whatever the
	# frame rate) and they've dropped out
	if not mp_over and Time.get_ticks_msec() - mp_heard_ms > 20000:
		_mp_match_over(true, "%s lost connection" % _foe_name())


# The shooter ran out of time: a foul, ball in hand to the other player.
func _mp_timeout(mine: bool) -> void:
	if mine:
		online.lobby_send("timeout", {})
	if player.down:
		_leave_stance()
	pulling = false
	hud.set_power(0.0, false)
	var side := 0 if your_turn else 1
	mp_fouls[side] = int(mp_fouls[side]) + 1
	if bool(mp_rules.get("three_fouls", false)) and int(mp_fouls[side]) >= 3:
		_mp_rack_over(not your_turn, "Three fouls in a row")
		return
	hud.say("Shot clock: foul, ball in hand", "foul")
	your_turn = not your_turn
	ball_in_hand = true
	behind_head = str(mp_rules.get("scratch", "anywhere")) == "kitchen"
	called_pocket = -1
	table.clear_pocket_glows()
	_refresh_hud()
	if your_turn:
		table.cue_lift = HOLD_LIFT
	_begin_turn()


func _mp_drive_avatar(_delta: float) -> void:
	if mp_remote.is_empty():
		return
	var p: Array = mp_remote.get("p", [0, 0])
	var at := Vector2(float(p[0]), float(p[1]))
	var yaw_p := float(mp_remote.get("y", 0.0))
	var face := atan2(cos(yaw_p), sin(yaw_p))
	var d := bot.pos.distance_to(at)
	if d > 0.12:
		bot.go([at], face, clampf(d * 2.5, 0.7, 2.2))
	else:
		bot.stop(face)
	var down := bool(mp_remote.get("d", false))
	bot.stance_on = down
	var a: Variant = mp_remote.get("a", null)
	if phase == Phase.AI_STROKE:
		pass
	elif down and a is Array and (a as Array).size() == 6 and phase == Phase.AI_THINK:
		_bot_stick(sim.ball(PoolSim.CUE).pos, Vector2(float(a[0]), float(a[1])), float(a[2]), float(a[3]),
			Vector2(float(a[4]), float(a[5])))
	else:
		bot.clear_shot()
	bot.look_target = table.ball_world(sim, PoolSim.CUE) if down else null


func _mp_rack_over(you_won: bool, reason: String) -> void:
	phase = Phase.OVER
	table.clear_pocket_glows()
	if player.down:
		_leave_stance()
	mp_score[0 if you_won else 1] = int(mp_score[0 if you_won else 1]) + 1
	_refresh_hud()
	var race := int(mp_rules.get("race", 1))
	if int(mp_score[0]) >= race or int(mp_score[1]) >= race:
		_mp_match_over(you_won, reason)
		return
	if you_won:
		hud.say("You take the rack, %d-%d" % [mp_score[0], mp_score[1]], "good")
	else:
		hud.say("%s takes the rack, %d-%d" % [_foe_name(), mp_score[0], mp_score[1]], "foul")
	match str(mp_rules.get("break", "alternate")):
		"winner":
			mp_breaker_me = you_won
		"loser":
			mp_breaker_me = not you_won
		_:
			mp_breaker_me = not mp_breaker_me
	var next := _next_seed(rack_seed)
	await get_tree().create_timer(3.0).timeout
	if mp and not mp_over:
		_mp_rack(next)


func _mp_match_over(you_won: bool, reason: String) -> void:
	if mp_over:
		return
	mp_over = true
	phase = Phase.OVER
	hud.set_thinking(false)
	hud.set_clock(-1.0, true)
	if player.down:
		_leave_stance()
	_bank_play_time()
	var xp := profile.record_mp_game(you_won)
	var score := "%d-%d" % [mp_score[0], mp_score[1]]
	last_result = ("Beat %s " if you_won else "Lost to %s ") % _foe_name() + score
	var why := reason if reason != "" else ("The 8 went where you called it." if you_won else "The 8 went where they called it.")
	var reward := "+1 trophy  ·  +50 coins" if you_won else "+%d XP" % xp
	var title := "You win" if you_won else "%s wins" % _foe_name()
	hud.finish(title, "%s  %s  ·  %s" % [why, score, reward], you_won)
	if mp_opp_left:
		hud.set_result_note("%s has left" % _foe_name(), false)
	_mp_report(you_won)


# Tell the server who won. The loser's word settles it at once; the winner's
# needs the loser to agree, or a minute to pass if they've vanished.
func _mp_report(you_won: bool) -> void:
	if _mp_result_sent or mp_match.is_empty():
		return
	_mp_result_sent = true
	var match_id := str(mp_match.get("id", ""))
	var winner := online.user_id if you_won else str(mp_opp.get("id", ""))
	var r := await online.report_result(match_id, winner)
	if you_won and bool(r.get("waiting", false)):
		await get_tree().create_timer(65.0).timeout
		await online.report_result(match_id, winner)


func _mp_rematch() -> void:
	if not mp_over or mp_opp_left:
		return
	mp_want_rematch[0] = true
	online.lobby_send("rematch", {})
	hud.set_result_note("Waiting for %s..." % _foe_name(), true)
	_mp_try_rematch()


func _mp_try_rematch() -> void:
	if not (mp_want_rematch[0] and mp_want_rematch[1]) or not online.is_host():
		return
	mp_want_rematch = [false, false]
	var m := await online.start_match()
	if m.has("error"):
		hud.set_result_note(str(m.error), true)
		return
	online.lobby_send("start", {"match": m})
	start_online(m)


# Back to the lobby screen. Mid-match, that's handing them the game.
func _mp_back_to_lobby() -> void:
	if not mp_over:
		online.lobby_send("forfeit", {})
		mp_over = true
		_mp_report(false)
	else:
		online.lobby_send("to_lobby", {})
	mp = false
	mp_remote = {}
	brain.reset()
	brain.spawn()
	guides_allowed = bool(save_state.get("guides", true))
	_leave_table()
	online.set_status("lobby")
	online.refresh_lobby()
	menu.open("lobby" if not online.lobby.is_empty() else "mp")


func _on_lobby_event(event: String, p: Dictionary) -> void:
	if event != "presence":
		mp_heard_ms = Time.get_ticks_msec()
	match event:
		"start":
			if not online.is_host() and typeof(p.get("match")) == TYPE_DICTIONARY:
				start_online(p.match)
		"pose":
			if mp:
				mp_remote = p
		"settle":
			if mp:
				mp_settles[int(p.get("seq", -1))] = p
		"shot", "place", "call", "timeout":
			if mp and not mp_over:
				mp_inbox.append([event, p])
		"rematch":
			if mp and mp_over:
				mp_want_rematch[1] = true
				if not mp_want_rematch[0]:
					hud.set_result_note("%s wants a rematch" % _foe_name(), true)
				_mp_try_rematch()
		"to_lobby":
			if mp and mp_over:
				mp_opp_left = true
				hud.set_result_note("%s went back to the lobby" % _foe_name(), false)
		"forfeit":
			if mp and not mp_over:
				_mp_match_over(true, "%s left the match." % _foe_name())
		"left", "closed":
			if mp:
				mp_opp_left = true
				if not mp_over:
					_mp_match_over(true, "%s left the match." % _foe_name())
				else:
					hud.set_result_note("%s has left" % _foe_name(), false)



# Back on your feet with nothing in your hands, for a fresh game.
func _reset_person() -> void:
	_cancel_punch()
	if bar.holding():
		bar.release()
	ko_t = -1.0
	ko_w = 0.0
	_ko_dizzy = 0.0
	fp_stars.visible = false
	Engine.time_scale = 1.0
	hud.set_knocked(0.0)


func _exit_tree() -> void:
	if profile != null:
		_bank_play_time()
		profile.flush()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
