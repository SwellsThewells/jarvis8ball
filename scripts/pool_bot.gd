class_name PoolBot
extends RefCounted

# The house player's comings and goings: where to stand, where to look, when
# to walk round the table thinking, when to fetch the cue ball, when to get
# down on a shot. It steers a PoolCharacter. Which shot to play still comes
# from PoolAI; this is only the person playing it.

const RING_OFF := 0.62           # the walk round the table, out from the rail
const WAIT_OFF := 1.05           # where to stand and watch
const MENU_SPOT := Vector2(1.95, -1.45)
const MIN_THINK := 2.4
const STANCE_BACK := 1.12        # stance: from the cue ball back to the feet
const STANCE_SIDE := 0.16        # and out to the left of the line
const BODY_TURN := -0.42         # body turned right of the line
const STROLL := 0.6

# His voice: recordings of him, and for the ones with words in them, what
# goes up in the bubble over his head and when, in seconds into the line.
# The rest (a sigh, a laugh, singing to himself, the grunt when he's hit)
# are only heard.
const VOICE := {
	"hey_angry": [[0.0, "HEY!"]],
	"where_do_i_go": [[0.1, "Where do I even go?"]],
	"watch_it_kid": [[0.05, "Hey! Watch it, kid!"]],
	"listen_kid": [[0.0, "Listen, kid..."], [3.55, "You think you're gonna beat me?"]],
	"sigh": [],
	"laugh": [],
	"singing": [],
	"hit_by_player": [],
}
# The least time, in seconds, before he says the same thing again.
const LINE_GAP := {
	"listen_kid": 150.0, "where_do_i_go": 75.0, "watch_it_kid": 30.0, "sigh": 50.0,
	"singing": 180.0, "laugh": 40.0, "hey_angry": 25.0,
}
# How long into "listen kid" the taunt proper starts: he swings on it.
const LISTEN_SWING := 3.55
# How often he feels like decking you, and never sooner than this after the last time.
const MISCHIEF_EVERY := Vector2(50.0, 110.0)
const OWN_COOLDOWN := 30.0

var g                            # the game; untyped so the two scripts don't depend on each other
var body: PoolCharacter
var stage := ""
var t := 0.0
var ready_to_aim := false
var _last_phase := -1
var _ring := PackedVector2Array()
var _spots := PackedVector2Array()
var _spot := Vector2.INF
var _crowd_t := 0.0
var _look_t := 0.0
var _look_i := 0
var _think_t := 0.0
var _need_pick := false
var _say_cd := 0.0
var _fresh := false
var _mischief_t := randf_range(35.0, 70.0)
var _own_cd := 0.0
var _annoy := 0.0
var _mis_prev := ""
var _repath_t := 0.0
var _landed := false
var voice: AudioStreamPlayer3D
var _voice_key := ""
var _streams := {}
var _chat_t := randf_range(40.0, 80.0)
var _laugh_in := -1.0
var _walk_line_t := 0.0
var _swing_t_last := 0.0
var _said_at := {}
var _in_menu := false


func _init(game, character: PoolCharacter) -> void:
	g = game
	body = character
	_ring = _loop(RING_OFF)
	var w := _loop(WAIT_OFF)
	for i in range(0, w.size(), maxi(1, w.size() / 14)):
		_spots.append(w[i])
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 3.2
	voice.max_db = 4.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	voice.bus = &"Voice"
	body.add_child(voice)
	body.getting_up.connect(_on_getting_up)
	# loaded up front, so the first time he speaks there's no hitch
	for key in VOICE:
		_streams[key] = load("res://audio/old_man/%s.ogg" % key)


# Say one of his lines, out loud and in a bubble if it has words. Only over
# something he's already saying if `over` is set.
func say(key: String, over := false) -> bool:
	if voice.playing and not over:
		return false
	# not the same line again too soon
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_said_at.get(key, -1.0e6)) < float(LINE_GAP.get(key, 0.0)):
		return false
	_said_at[key] = now
	if not _streams.has(key):
		_streams[key] = load("res://audio/old_man/%s.ogg" % key)
	var s: AudioStream = _streams[key]
	voice.stop()
	voice.stream = s
	voice.pitch_scale = 1.0
	voice.volume_db = -4.0 if key == "singing" else 0.0
	voice.play()
	_voice_key = key
	var segs: Array = VOICE.get(key, [])
	# a wordless line ends whatever bubble was up
	g.hud.speak("bot", _bubble_at, segs, s.get_length() + 0.7 if not segs.is_empty() else 0.0)
	return true


func hush() -> void:
	voice.stop()
	_voice_key = ""
	g.hud.speak("bot", _bubble_at, [], 0.0)


func saying(key: String) -> bool:
	return voice.playing and _voice_key == key


# Where his bubble sits: just over his head, wherever it is.
func _bubble_at() -> Vector3:
	return body.head_w + Vector3.UP * 0.3


func _on_getting_up() -> void:
	say("hey_angry", true)


# Back to standing about, dropping anything in hand. Used between games.
func reset() -> void:
	stage = ""
	ready_to_aim = false
	body.stance_on = false
	body.think_on = false
	body.reach_point = null
	body.holding_ball = false
	body.clear_shot()
	g.table.cue_hand = null
	_last_phase = -1
	_laugh_in = -1.0
	_walk_line_t = 0.0
	if voice.playing and _voice_key != "hit_by_player":
		hush()


func spawn() -> void:
	body.place(MENU_SPOT, _yaw_to(MENU_SPOT, Vector2.ZERO))
	_spot = MENU_SPOT


# ---------------------------------------------------------------------------

func update(delta: float) -> void:
	t += delta
	_say_cd -= delta
	_chat_t -= delta
	voice.global_position = body.head_w
	if _laugh_in >= 0.0:
		_laugh_in -= delta
		# not over the top of himself: the laugh waits for the line to finish
		if _laugh_in < 0.0:
			if voice.playing and _voice_key == "listen_kid":
				_laugh_in = 0.25
			else:
				say("laugh", true)
	if _walk_line_t > 0.0:
		_walk_line_t -= delta
		if _walk_line_t <= 0.0 and body.vel.length() > 0.2:
			say("where_do_i_go")
	var ph: int = g.phase
	if ph != _last_phase:
		_last_phase = ph
		_entered(ph)
	body.avoid = _avoid()
	if body.holding_ball:
		g.table.cue_hand = body.ball_world()
	_mischief_t -= delta
	_own_cd -= delta
	_annoy = maxf(0.0, _annoy - delta / 12.0)
	if stage == "mischief" or stage == "swing":
		_mischief(delta)
		return
	if _mischief_t <= 0.0 and _own_cd <= 0.0 and _can_mischief():
		_mis_prev = stage
		_set_stage("mischief")
		body.think_on = false
		body.stance_on = false
		_repath_t = 0.0
		_landed = false
		_walk_line_t = 0.0
		if saying("singing"):
			hush()
		# half the time he has something to say about it first
		if randf() < 0.5:
			say("listen_kid")
		_mischief(delta)
		return
	if ph == g.Phase.MENU:
		_menu()
	elif ph == g.Phase.AI_THINK:
		_think(delta)
	elif ph == g.Phase.AI_AIM or ph == g.Phase.AI_STROKE:
		_aiming()
	elif ph == g.Phase.ROLLING:
		_rolling()
	elif ph == g.Phase.OVER:
		_over()
	else:
		_wait(delta)


func _entered(ph: int) -> void:
	if ph == g.Phase.OVER and str(g.last_result).begins_with("Lost"):
		# he won
		_laugh_in = 0.9
	if _in_menu and ph != g.Phase.MENU:
		_in_menu = false
		# a word before the break
		if randf() < 0.5:
			_laugh_in = -1.0
			say("listen_kid", true)
	if ph == g.Phase.AI_THINK:
		if saying("singing"):
			hush()
		_set_stage("survey")
		ready_to_aim = false
		_think_t = 0.0
		_need_pick = false
		body.stance_on = false
		body.clear_shot()
		# thinking out loud, now and then
		var r := randf()
		if r < 0.4:
			say("sigh")
		elif r < 0.65:
			_walk_line_t = 1.2
		if g.ball_in_hand:
			if g.sim.ball(PoolSim.CUE).on_table:
				_need_pick = true
			else:
				# he fished it out of the pocket: it's in his hand already
				body.holding_ball = true


func _set_stage(s: String) -> void:
	stage = s
	t = 0.0
	_fresh = true


func _first() -> bool:
	var f := _fresh
	_fresh = false
	return f


# ---------------------------------------------------------------------------
# His turn
# ---------------------------------------------------------------------------

# Walk round to the cue ball with a hand on his chin, looking the balls over,
# until the shot is decided. Then fetch the cue ball if he has it in hand,
# walk to where the shot is played from, and get down on it.
func _think(delta: float) -> void:
	_think_t += delta
	var cue: Vector2 = g.sim.ball(PoolSim.CUE).pos
	if body.stunned():
		# flat on the floor: once he's up, he picks it up again from wherever
		# that leaves him, walking back to where he was going
		body.think_on = false
		body.reach_point = null
		if stage == "pickup":
			stage = "fetch"
		elif stage == "place":
			stage = "to_shot"
		_fresh = true
		t = 0.0
		return
	match stage:
		"survey":
			if _first():
				var dest := _nearest_on(_ring, cue)
				if dest.distance_to(body.pos) < 1.0:
					# already there: pace a little way along the rail instead
					var i := _ring_index(dest)
					dest = _ring[(i + int(_ring.size() * 0.1)) % _ring.size()]
				body.go(_path(body.pos, dest), _yaw_to(dest, cue), STROLL)
			body.think_on = true
			_look_balls(delta)
			if g.ai_have_shot and _think_t >= MIN_THINK:
				body.think_on = false
				_set_stage("fetch" if _need_pick else "to_shot")
		"fetch":
			if _first():
				var spot := _rail_spot(cue)
				body.go(_path(body.pos, spot), _yaw_to(spot, cue))
			_look_at_table(cue)
			if body.arrived() and t > 0.3:
				_set_stage("pickup")
		"pickup":
			body.reach_point = g.table.table_to_world(cue)
			_look_at_table(cue)
			if t > 0.75 and not body.holding_ball:
				body.holding_ball = true
				body.reach_point = null
			if t > 1.1:
				_set_stage("to_shot")
		"to_shot":
			var s := _stance()
			if _first():
				body.lean_extra = s[2]
				body.go(_path(body.pos, s[0]), s[1])
			_look_at_table(_shot_cue())
			if body.arrived() and t > 0.3:
				_set_stage("place" if body.holding_ball else "bend")
		"place":
			var p: Vector2 = _shot_cue()
			body.reach_point = g.table.table_to_world(p)
			_look_at_table(p)
			if t > 0.8 and body.holding_ball:
				body.holding_ball = false
				g.table.cue_hand = null
				g.bot_placed_ball()
			if t > 1.2:
				body.reach_point = null
				_set_stage("bend")
		"bend":
			g.bot_show_stick(0.006)
			_hold_stance()
			_look_along_shot()
			if body.stance_ready():
				ready_to_aim = true


func _aiming() -> void:
	_hold_stance()
	_look_along_shot()


# Down on the shot, unless something has knocked him off the spot: then up,
# a step or two back to it, and down again.
func _hold_stance() -> void:
	var s := _stance()
	var spot: Vector2 = s[0]
	if body.stunned():
		return
	if body.pos.distance_to(spot) > 0.07:
		# up first, then walk back to it; down again once he's there
		if body.stance_on:
			body.stance_on = false
			return
		if not body.stood_up():
			return
		var gl = body.goal()
		if gl == null or (gl as Vector2).distance_to(spot) > 0.01 or body.arrived():
			body.go(_path(body.pos, spot), s[1])
		return
	if not body.stance_on and not body.arrived():
		return
	body.stance_on = true


func _rolling() -> void:
	if not g.shot_by_you:
		# stay down a moment to watch it go, then straighten up and follow it
		if t > 0.45:
			body.stance_on = false
		if body.stood_up():
			body.clear_shot()
		body.look_target = Vector3(g.watch_focus)
		return
	_wait(0.0)
	body.look_target = Vector3(g.watch_focus)


func _over() -> void:
	body.stance_on = false
	body.think_on = false
	if body.stood_up():
		body.clear_shot()
	body.stop(_yaw_to(body.pos, g.player.pos))
	body.look_target = g.player.eye()


func _look_along_shot() -> void:
	var cue := _shot_cue()
	var d: Vector2 = g.ai_shot.get("dir", Vector2.RIGHT)
	body.look_target = g.table.table_to_world(cue + d * 1.2, PoolSim.R)


func _shot_cue() -> Vector2:
	var p = g.ai_shot.get("place", null)
	if p != null and not g.bot_ball_placed:
		return p
	return g.sim.ball(PoolSim.CUE).pos


# Where to stand to play the shot, and which way to face: behind the line,
# body turned the way a right-handed player turns. Out in the table, that is
# as close as the rail allows, and the rest is leaning.
func _stance() -> Array:
	var cue := _shot_cue()
	var dir: Vector2 = (g.ai_shot.get("dir", Vector2.RIGHT) as Vector2).normalized()
	var left := Vector2(dir.y, -dir.x)
	var back := STANCE_BACK
	var box := PoolCharacter.TABLE_HALF + Vector2(0.02, 0.02)
	var root := cue - dir * back + left * STANCE_SIDE
	while absf(root.x) < box.x and absf(root.y) < box.y and back < 4.0:
		back += 0.02
		root = cue - dir * back + left * STANCE_SIDE
	var yaw := atan2(dir.x, dir.y) + BODY_TURN
	return [root, yaw, back - STANCE_BACK]


# His eyes go from one ball to another, the way you read a table.
func _look_balls(delta: float) -> void:
	_look_t -= delta
	var ids: Array = PoolRules.legal_targets(g.sim, g.foe_group)
	if ids.is_empty():
		ids = [PoolSim.CUE]
	if _look_t <= 0.0:
		_look_t = randf_range(0.9, 1.7)
		_look_i = randi() % ids.size()
	var id: int = ids[_look_i % ids.size()]
	body.look_target = g.table.ball_world(g.sim, id)


func _look_at_table(p: Vector2) -> void:
	body.look_target = g.table.table_to_world(p)


# ---------------------------------------------------------------------------
# Your turn
# ---------------------------------------------------------------------------

func _menu() -> void:
	_in_menu = true
	if stage != "menu":
		_set_stage("menu")
		reset()
		stage = "menu"
		if body.pos.distance_to(MENU_SPOT) > 0.2:
			body.go(_path(body.pos, MENU_SPOT), _yaw_to(MENU_SPOT, Vector2.ZERO))
	body.look_target = Vector3(0.0, g.TABLE_Y, 0.0)


# Somewhere to stand and watch, out of your way: not behind the shot you are
# about to play, not on top of you. If you come and crowd him, or line up a
# shot through where he is standing, he moves.
func _wait(delta: float) -> void:
	if stage != "wait":
		_set_stage("wait")
		body.stance_on = false
		body.think_on = false
		body.reach_point = null
		_pick_spot(false)
	if body.stood_up():
		body.clear_shot()
	var crowded: bool = body.pos.distance_to(g.player.pos) < 0.9 and not g.player.down
	_crowd_t = _crowd_t + delta if crowded else 0.0
	var moving: bool = body.goal() != null and not body.arrived()
	if not moving and t > 1.0 and (_crowd_t > 0.7 or _in_the_way(body.pos)):
		_pick_spot(true)
		t = 0.0
		# shooed off again
		if randf() < 0.55:
			_walk_line_t = 0.5
	# stood about waiting long enough, he sings to himself
	if not moving and _chat_t <= 0.0 and g.phase != g.Phase.ROLLING:
		_chat_t = randf_range(50.0, 100.0)
		if randf() < 0.55:
			say("singing")
	# watch the cue ball while you shoot, the balls while they run, you
	# every now and then
	if g.phase == g.Phase.ROLLING:
		body.look_target = Vector3(g.watch_focus)
	elif g.player.down or g.phase == g.Phase.PLACE:
		body.look_target = g.table.ball_world(g.sim, PoolSim.CUE)
	else:
		var glance: bool = fmod(t, 6.0) < 2.0
		body.look_target = g.player.eye() if glance else g.table.ball_world(g.sim, PoolSim.CUE)


func _pick_spot(moving_on: bool) -> void:
	var best := Vector2.INF
	var best_s := -1.0e9
	for c in _spots:
		var s := 0.0
		s -= c.distance_to(body.pos) * 0.3
		s += minf(c.distance_to(g.player.pos), 2.6)
		if _in_the_way(c):
			s -= 6.0
		if moving_on and c.distance_to(_spot) < 0.3:
			s -= 4.0
		if s > best_s:
			best_s = s
			best = c
	_spot = best
	body.go(_path(body.pos, _spot), _yaw_to(_spot, Vector2.ZERO), 0.8)


# Behind the cue ball along the line you are shooting, or about to.
func _in_the_way(p: Vector2) -> bool:
	var cue: Vector2 = g.sim.ball(PoolSim.CUE).pos
	var dir: Vector2 = g.aim_dir if g.player.down else (cue - g.player.pos)
	if dir.length_squared() < 1.0e-6:
		return false
	dir = dir.normalized()
	var rel := p - cue
	var along := rel.dot(-dir)
	var side := absf(rel.dot(Vector2(-dir.y, dir.x)))
	return along > 0.0 and along < 3.2 and side < 0.85


# While walking, step round you rather than into you.
func _avoid() -> Vector2:
	var rel: Vector2 = body.pos - g.player.pos
	var d := rel.length()
	if d > 1.1 or d < 1.0e-4 or body.vel.length() < 0.1:
		return Vector2.ZERO
	var heading := body.vel.normalized()
	if heading.dot(-rel / d) < 0.2:
		return Vector2.ZERO
	var side := Vector2(-heading.y, heading.x)
	if side.dot(rel) < 0.0:
		side = -side
	return side * 0.6 * (1.0 - d / 1.1)


# ---------------------------------------------------------------------------
# Being knocked about
# ---------------------------------------------------------------------------

# The fist has landed: the grunt, right on it.
func on_punched() -> void:
	_laugh_in = -1.0
	_walk_line_t = 0.0
	say("hit_by_player", true)
	_say_cd = 6.0
	if stage == "mischief" or stage == "swing":
		_end_mischief()
	# more often than not, he'll be back for you once he's up
	if randf() < 0.65:
		_mischief_t = minf(_mischief_t, body.ko_length() + 1.2)


func on_bumped() -> void:
	_annoy += 1.0
	var sing := saying("singing")
	if _annoy >= 3.0:
		# that's it
		_annoy = 0.0
		_mischief_t = minf(_mischief_t, 0.8)
		say("watch_it_kid", true)
		_say_cd = 6.0
		return
	if sing or (_say_cd <= 0.0 and randf() < 0.6):
		_say_cd = 7.0
		say("watch_it_kid", sing)


# ---------------------------------------------------------------------------
# Decking you
# ---------------------------------------------------------------------------

# Whenever he likes, as long as he isn't in the middle of playing a shot
# himself: while you're up, while the balls are running, or while he's still
# walking round deciding what to play.
func _can_mischief() -> bool:
	if body.stunned() or body.anchored() or body.holding_ball or g.player_knocked():
		return false
	var ph: int = g.phase
	if ph == g.Phase.MENU or ph == g.Phase.OVER or ph == g.Phase.STROKE or ph == g.Phase.AI_AIM \
			or ph == g.Phase.AI_STROKE:
		return false
	if ph == g.Phase.AI_THINK and stage != "survey":
		return false
	return body.pos.distance_to(g.player_spot()) < 7.0


func _mischief(delta: float) -> void:
	var tp: Vector2 = g.player_spot()
	var d := body.pos.distance_to(tp)
	body.look_target = g.player_head()
	if body.stunned():
		_end_mischief()
		return
	if stage == "mischief":
		if d > 0.9:
			_repath_t -= delta
			if _repath_t <= 0.0:
				_repath_t = 0.4
				var ap := tp + (body.pos - tp).normalized() * 0.68
				body.go(_path(body.pos, ap), _yaw_to(ap, tp), 0.98)
		else:
			body.stop(_yaw_to(body.pos, tp))
			# mid-speech, he lets you have it on "...beat me?"
			var waiting := saying("listen_kid") and voice.get_playback_position() < LISTEN_SWING - 0.3
			if not waiting and absf(wrapf(_yaw_to(body.pos, tp) - body.yaw, -PI, PI)) < 0.35:
				body.punch(g.player_head())
				_set_stage("swing")
		if t > 12.0 or g.player_knocked():
			_end_mischief()
	else:
		# keep the fist on you while it's drawn back
		if t < PoolCharacter.PUNCH_WINDUP:
			body.punch_at(g.player_head())
			body.face(_yaw_to(body.pos, tp))
		if t >= PoolCharacter.PUNCH_WINDUP and _swing_t_last < PoolCharacter.PUNCH_WINDUP:
			g.sound.play("whoosh", body.lhand_w, 0.8)
		if not _landed and t >= PoolCharacter.PUNCH_HIT:
			_landed = true
			if d < 1.25 and g.player_hit(body.head_w):
				if randf() < 0.7:
					_laugh_in = 1.5
				_say_cd = 6.0
		if t > PoolCharacter.PUNCH_HIT + PoolCharacter.PUNCH_RECOVER + 0.2:
			_end_mischief()
	_swing_t_last = t if stage == "swing" else 0.0


func _end_mischief() -> void:
	_own_cd = OWN_COOLDOWN
	_mischief_t = randf_range(MISCHIEF_EVERY.x, MISCHIEF_EVERY.y)
	body.stop()
	# back to whatever he was doing, from the top
	if _mis_prev == "survey" and g.phase == g.Phase.AI_THINK:
		_set_stage("survey")
	else:
		stage = ""


# ---------------------------------------------------------------------------
# Getting about the room
# ---------------------------------------------------------------------------

# A loop round the table, `off` out from the outside of the rail, with the
# corners rounded: straight sides, and quarter circles at the corners.
static func _loop(off: float) -> PackedVector2Array:
	var ox := PoolSim.HALF_LEN + PoolTableView.CUSHION_D + PoolTableView.CAP_W
	var oz := PoolSim.HALF_WID + PoolTableView.CUSHION_D + PoolTableView.CAP_W
	var corners := [Vector2(ox, -oz), Vector2(ox, oz), Vector2(-ox, oz), Vector2(-ox, -oz)]
	var out := PackedVector2Array()
	for k in 4:
		var c: Vector2 = corners[k]
		var a0 := -PI * 0.5 + PI * 0.5 * float(k)
		for j in 6:
			var a := a0 + PI * 0.5 * float(j) / 6.0
			out.append(c + Vector2(cos(a), sin(a)) * off)
		var a1 := a0 + PI * 0.5
		var start: Vector2 = c + Vector2(cos(a1), sin(a1)) * off
		var nc: Vector2 = corners[(k + 1) % 4]
		var end: Vector2 = nc + Vector2(cos(a1), sin(a1)) * off
		var steps := maxi(1, int(start.distance_to(end) / 0.25))
		for j in steps:
			out.append(start.lerp(end, float(j) / float(steps)))
	return out


func _ring_index(p: Vector2) -> int:
	var best := 0
	var bd := 1.0e9
	for i in _ring.size():
		var d := _ring[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _nearest_on(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := pts[0]
	var bd := 1.0e9
	for q in pts:
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


# Standing at the rail nearest a spot on the table, as close as a body gets.
func _rail_spot(p: Vector2) -> Vector2:
	var box := PoolCharacter.TABLE_HALF + Vector2(0.05, 0.05)
	var dx := box.x - absf(p.x)
	var dz := box.y - absf(p.y)
	if dx < dz:
		return Vector2(signf(p.x) * box.x, p.y)
	return Vector2(p.x, signf(p.y) * box.y)


# Round the table rather than through it: along the loop the shorter way,
# then pulled tight so he cuts straight wherever the way is clear.
func _path(from: Vector2, to: Vector2) -> Array:
	if not _crosses(from, to):
		return [to]
	var n := _ring.size()
	var ia := _ring_index(from)
	var ib := _ring_index(to)
	var step := 1 if (ib - ia + n) % n <= (ia - ib + n) % n else -1
	var pts: Array = []
	var i := ia
	while i != ib:
		pts.append(_ring[i])
		i = (i + step + n) % n
	pts.append(_ring[ib])
	pts.append(to)
	var out: Array = []
	var at := from
	var k := 0
	while k < pts.size():
		var far := k
		for j in range(pts.size() - 1, k - 1, -1):
			if not _crosses(at, pts[j]):
				far = j
				break
		out.append(pts[far])
		at = pts[far]
		k = far + 1
	return out


func _crosses(a: Vector2, b: Vector2) -> bool:
	# a margin beyond where the body is kept out, so a path never grazes the
	# corner; the ends themselves may sit right at the rail
	var box := PoolCharacter.TABLE_HALF + Vector2(0.1, 0.1)
	var len := a.distance_to(b)
	var n := maxi(2, int(len / 0.06))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / float(n))
		if p.distance_to(a) < 0.2 or p.distance_to(b) < 0.2:
			if absf(p.x) < box.x - 0.12 and absf(p.y) < box.y - 0.12:
				return true
			continue
		if absf(p.x) < box.x and absf(p.y) < box.y:
			return true
	return false


static func _yaw_to(from: Vector2, at: Vector2) -> float:
	var d := at - from
	return atan2(d.x, d.y)
