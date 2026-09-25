class_name PoolProfile
extends Node

# Who you are and what you've done at the table.
#
# Signing in goes through Steam, using the GodotSteam extension
# (https://godotsteam.com). Nothing here names it directly: the Steam object
# is looked up at run time, so the game still opens and plays without it, and
# the profile corner just offers to sign in. Once the extension is in the
# project and the game has its own Steam app ID, signing in picks up whoever
# is logged in to the Steam client: their name, their avatar, and the stats
# below, which are stored as Steam stats (set up under Stats & Achievements
# in Steamworks, one INT stat per name in STATS).
#
# Every stat is also kept in the local save, per Steam account, so the
# numbers are there straight away and nothing is lost if Steam is slow or
# offline; the two are merged by taking the larger of each.

signal changed()
signal message(text: String)
signal leveled_up(level: int)

# 480 is Spacewar, Valve's public test app, so sign-in can be tried before the
# game has an app of its own. Replace it with the real app ID, or put the ID
# in steam_appid.txt next to the exe.
const APP_ID := 480

const STATS := [
	"xp", "trophies", "mp_losses",
	"bot_wins", "bot_losses", "streak", "best_streak", "best_bot_beaten",
	"shots", "balls_hit", "balls_potted", "fouls", "time_played",
	"drinks", "punches_landed", "knockdowns",
]

# What levels you up. The house player pays more the better he is.
const XP_BOT_WIN := 60
const XP_BOT_WIN_PER_LEVEL := 12
const XP_BOT_LOSS := 15
const XP_BOT_LOSS_PER_LEVEL := 3
const XP_PER_POT := 3
# Ready for when matches go online.
const XP_MP_WIN := 200
const XP_MP_LOSS := 50

var signed_in := false
var test_profile := false         # an editor build with no Steam: a stand-in so the UI can be worked on
var steam_id := 0
var username := ""
var avatar: Texture2D
var stats := {}

var _steam: Object
var _steam_up := false
var _dirty := false


func setup() -> void:
	stats = _blank()
	_load_local("guest")
	var cfg := ConfigFile.new()
	if cfg.load(PoolCues.SAVE_PATH) == OK and bool(cfg.get_value("profile", "auto_sign_in", false)):
		sign_in(true)


func _process(_delta: float) -> void:
	if _steam_up and _steam != null:
		_steam.call("run_callbacks")


# ---------------------------------------------------------------------------
# Signing in
# ---------------------------------------------------------------------------

func sign_in(silent := false) -> void:
	if signed_in:
		return
	if not Engine.has_singleton("Steam"):
		if OS.is_debug_build():
			_sign_in_test()
		elif not silent:
			message.emit("Steam sign-in arrives with the Steam release.")
		return
	_steam = Engine.get_singleton("Steam")
	if not _steam_up:
		var id := _app_id()
		OS.set_environment("SteamAppId", str(id))
		OS.set_environment("SteamGameId", str(id))
		var r: Variant = _steam.call("steamInitEx")
		var ok := true
		if typeof(r) == TYPE_DICTIONARY:
			ok = int((r as Dictionary).get("status", 1)) == 0
		elif typeof(r) == TYPE_BOOL:
			ok = r
		_steam_up = ok
		if ok:
			if _steam.has_signal("avatar_loaded"):
				_steam.connect("avatar_loaded", _on_avatar_loaded)
			for sig in ["current_stats_received", "user_stats_received"]:
				if _steam.has_signal(sig):
					_steam.connect(sig, func(_a = null, _b = null, _c = null): _pull_steam_stats())
	if not _steam_up or not bool(_steam.call("loggedOn")):
		if not silent:
			message.emit("Couldn't reach Steam. Open Steam, sign in there, and try again.")
			OS.shell_open("steam://open/main")
		return

	steam_id = int(_steam.call("getSteamID"))
	username = str(_steam.call("getPersonaName"))
	avatar = null
	_steam.call("getPlayerAvatar", 3, steam_id)   # 3 = large; arrives on avatar_loaded
	_become(str(steam_id))
	if _steam.has_method("requestCurrentStats"):
		_steam.call("requestCurrentStats")
	_pull_steam_stats()
	if not silent:
		message.emit("Signed in as %s" % username)


func _sign_in_test() -> void:
	test_profile = true
	steam_id = 0
	username = "Test Player"
	avatar = null
	_become("test")
	message.emit("No Steam in this build, so here's a test profile (editor builds only).")


# Takes on an account's saved numbers. The first account to sign in on this
# machine also picks up anything you did before signing in.
func _become(key: String) -> void:
	var guest := stats.duplicate()
	stats = _blank()
	var had := _load_local(key)
	if not had and not _is_blank(guest):
		for k in STATS:
			stats[k] = maxi(int(stats[k]), int(guest[k]))
		_clear_local("guest")
	signed_in = true
	var cfg := ConfigFile.new()
	cfg.load(PoolCues.SAVE_PATH)
	cfg.set_value("profile", "auto_sign_in", true)
	cfg.save(PoolCues.SAVE_PATH)
	_dirty = true
	flush()
	changed.emit()


# Unlinks the account from the game on this machine. Steam itself stays
# signed in; this only stops the game using it until you sign in again.
func sign_out() -> void:
	if not signed_in:
		return
	flush()
	signed_in = false
	test_profile = false
	steam_id = 0
	username = ""
	avatar = null
	stats = _blank()
	_load_local("guest")
	var cfg := ConfigFile.new()
	cfg.load(PoolCues.SAVE_PATH)
	cfg.set_value("profile", "auto_sign_in", false)
	cfg.save(PoolCues.SAVE_PATH)
	changed.emit()


func _app_id() -> int:
	var f := FileAccess.open(OS.get_executable_path().get_base_dir().path_join("steam_appid.txt"), FileAccess.READ)
	if f != null:
		var s := f.get_as_text().strip_edges()
		if s.is_valid_int():
			return int(s)
	return APP_ID


func _on_avatar_loaded(id: int, size: int, data: PackedByteArray) -> void:
	if id != steam_id or size <= 0 or data.size() < size * size * 4:
		return
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	avatar = ImageTexture.create_from_image(img)
	changed.emit()


func _pull_steam_stats() -> void:
	if not _steam_up or not signed_in or test_profile:
		return
	var pushed := false
	for k in STATS:
		var v := int(_steam.call("getStatInt", k))
		if v > int(stats[k]):
			stats[k] = v
		elif v < int(stats[k]):
			pushed = true
	if pushed:
		_dirty = true
		flush()
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


# For online matches, once they exist: a win is a trophy.
func record_mp_game(won: bool) -> int:
	if won:
		add("trophies")
	else:
		add("mp_losses")
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


# Writes the numbers down: always to the local save, and to Steam when signed in.
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var key := "guest"
	if signed_in:
		key = "test" if test_profile else str(steam_id)
	var cfg := ConfigFile.new()
	cfg.load(PoolCues.SAVE_PATH)
	for k in STATS:
		cfg.set_value("stats_" + key, k, int(stats[k]))
	cfg.save(PoolCues.SAVE_PATH)
	if signed_in and _steam_up and not test_profile:
		for k in STATS:
			_steam.call("setStatInt", k, int(stats[k]))
		_steam.call("storeStats")
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
