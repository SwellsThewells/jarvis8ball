class_name PoolProfile
extends Node

# Who you are and what you've done at the table.
#
# Signing in is with Discord, through PoolOnline: your Discord name and
# picture, and your numbers kept in the online profile so they follow you to
# any computer. Every stat is also kept in the local save, per account, so
# they're there straight away and nothing is lost if the connection is slow;
# the two are merged by taking the larger of each.
#
# Trophies (online wins) and online losses are counted by the server when a
# match ends, not by the game, so they can't be made up.

signal changed()
signal message(text: String)
signal leveled_up(level: int)

const STATS := [
	"xp", "trophies", "mp_losses",
	"bot_wins", "bot_losses", "streak", "best_streak", "best_bot_beaten",
	"shots", "balls_hit", "balls_potted", "fouls", "time_played",
	"drinks", "punches_landed", "knockdowns",
]
# Kept by the server; the game only reads them.
const SERVER_STATS := ["trophies", "mp_losses"]

# What levels you up. The house player pays more the better he is.
const XP_BOT_WIN := 60
const XP_BOT_WIN_PER_LEVEL := 12
const XP_BOT_LOSS := 15
const XP_BOT_LOSS_PER_LEVEL := 3
const XP_PER_POT := 3
const XP_MP_WIN := 200
const XP_MP_LOSS := 50

var online: PoolOnline
var signed_in: bool:
	get:
		return online != null and online.signed_in()
var test_profile := false         # kept so older menus still compile; always false now
var username: String:
	get:
		return online.display_name() if signed_in else ""
var avatar: Texture2D:
	get:
		return online.avatar(str(online.me.get("avatar_url", ""))) if signed_in else null
var stats := {}

var _key := "guest"
var _dirty := false


func setup(o: PoolOnline) -> void:
	online = o
	stats = _blank()
	_load_local("guest")
	online.auth_changed.connect(_on_auth)
	online.me_changed.connect(_on_me)
	online.avatar_loaded.connect(func(_u): changed.emit())
	online.notice.connect(func(t): message.emit(t))


# ---------------------------------------------------------------------------
# Signing in
# ---------------------------------------------------------------------------

func sign_in(_silent := false) -> void:
	if online.signing_in:
		online.cancel_sign_in()
		message.emit("Sign-in cancelled.")
		return
	if not online.configured():
		message.emit("Discord sign-in isn't set up in this build yet (see ONLINE_SETUP.md).")
		return
	online.sign_in_discord()
	if online.signing_in:
		message.emit("Finish signing in with Discord in your browser.")


func sign_out() -> void:
	flush()
	online.sign_out()


func _on_auth() -> void:
	var key := online.user_id if signed_in else "guest"
	if key == _key:
		changed.emit()
		return
	flush()
	var guest := stats.duplicate()
	stats = _blank()
	_key = key
	var had := _load_local(key)
	# the first account to sign in on this computer picks up what you did before
	if key != "guest" and not had and not _is_blank(guest):
		for k in STATS:
			if not SERVER_STATS.has(k):
				stats[k] = maxi(int(stats[k]), int(guest[k]))
		_clear_local("guest")
	_on_me()
	_dirty = key != "guest"
	flush()
	changed.emit()


# The server's numbers: merged in, larger wins.
func _on_me() -> void:
	if not signed_in:
		return
	var server: Dictionary = online.me.get("stats", {})
	var pushed := false
	for k in STATS:
		if SERVER_STATS.has(k):
			continue
		var v := int(server.get(k, 0))
		if v > int(stats[k]):
			stats[k] = v
		elif v < int(stats[k]):
			pushed = true
	stats.trophies = int(online.me.get("trophies", 0))
	stats.mp_losses = int(online.me.get("mp_losses", 0))
	if pushed:
		_dirty = true
	changed.emit()


# ---------------------------------------------------------------------------
# Numbers
# ---------------------------------------------------------------------------

func add(key: String, n := 1) -> void:
	if n == 0:
		return
	stats[key] = int(stats.get(key, 0)) + n
	_dirty = true


func set_max(key: String, v: int) -> void:
	if v > int(stats.get(key, 0)):
		stats[key] = v
		_dirty = true


func add_xp(n: int) -> void:
	var before := level()
	add("xp", n)
	var after := level()
	if after > before:
		leveled_up.emit(after)


# A game against the house player, just finished.
func record_bot_game(won: bool, difficulty: int) -> int:
	var xp := 0
	if won:
		add("bot_wins")
		add("streak")
		set_max("best_streak", int(stats.streak))
		set_max("best_bot_beaten", difficulty)
		xp = XP_BOT_WIN + XP_BOT_WIN_PER_LEVEL * difficulty
	else:
		add("bot_losses")
		stats.streak = 0
		xp = XP_BOT_LOSS + XP_BOT_LOSS_PER_LEVEL * difficulty
	add_xp(xp)
	flush()
	return xp


# An online match, just finished. The trophy itself is the server's to give.
func record_mp_game(won: bool) -> int:
	var xp := XP_MP_WIN if won else XP_MP_LOSS
	add_xp(xp)
	flush()
	return xp


# XP needed to get from level `l` to the next one: a little more each time.
static func xp_to_next(l: int) -> int:
	return 100 + 40 * (l - 1)


func level() -> int:
	var l := 1
	var xp := int(stats.get("xp", 0))
	while xp >= xp_to_next(l):
		xp -= xp_to_next(l)
		l += 1
	return l


# How far into the current level, and how much it takes: [have, need].
func level_progress() -> Vector2i:
	var l := 1
	var xp := int(stats.get("xp", 0))
	while xp >= xp_to_next(l):
		xp -= xp_to_next(l)
		l += 1
	return Vector2i(xp, xp_to_next(l))


func games_played() -> int:
	return int(stats.bot_wins) + int(stats.bot_losses) + int(stats.trophies) + int(stats.mp_losses)


# Writes the numbers down: always to the local save, and online when signed in.
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var cfg := ConfigFile.new()
	cfg.load(PoolCues.SAVE_PATH)
	for k in STATS:
		cfg.set_value("stats_" + _key, k, int(stats[k]))
	cfg.save(PoolCues.SAVE_PATH)
	if signed_in:
		var out := {}
		for k in STATS:
			if not SERVER_STATS.has(k):
				out[k] = int(stats[k])
		online.save_stats(out)
	changed.emit()


func _blank() -> Dictionary:
	var d := {}
	for k in STATS:
		d[k] = 0
	return d


func _is_blank(d: Dictionary) -> bool:
	for k in STATS:
		if int(d.get(k, 0)) != 0:
			return false
	return true


func _load_local(key: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PoolCues.SAVE_PATH) != OK or not cfg.has_section("stats_" + key):
		return false
	for k in STATS:
		stats[k] = maxi(0, int(cfg.get_value("stats_" + key, k, 0)))
	return true


func _clear_local(key: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PoolCues.SAVE_PATH) == OK and cfg.has_section("stats_" + key):
		cfg.erase_section("stats_" + key)
		cfg.save(PoolCues.SAVE_PATH)
