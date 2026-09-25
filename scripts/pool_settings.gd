class_name PoolSettings
extends RefCounted

# Everything on the settings page: how loud things are, how the mouse feels,
# what the drinks are allowed to do to you, and how the window behaves. Kept
# in the same save file as your cues, in its own [settings] section, and
# applied the moment it changes.

const DEFAULTS := {
	# audio, 0..1
	"master": 0.9,
	"sfx": 1.0,
	"voice": 1.0,
	# gameplay
	"mouse_sens": 1.0,        # multiplier, 0.25..2.5
	"fov": 52.0,              # degrees, standing
	"drink_fx": true,         # the drinks do something to your eyes and legs
	"screen_shake": true,
	# display
	"fullscreen": true,
	"vsync": true,
	"max_fps": 0,             # 0 = no cap
	"film_fx": true,          # grain and vignette
}

const SENS_RANGE := Vector2(0.25, 2.5)
const FOV_RANGE := Vector2(40.0, 80.0)
const FPS_STEPS := [0, 30, 60, 120, 144, 165, 240]

static var data: Dictionary = DEFAULTS.duplicate()


static func load_settings() -> void:
	data = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PoolCues.SAVE_PATH) != OK:
		return
	for k in DEFAULTS:
		var v: Variant = cfg.get_value("settings", k, DEFAULTS[k])
		if typeof(v) == typeof(DEFAULTS[k]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(DEFAULTS[k]) in [TYPE_INT, TYPE_FLOAT]):
			data[k] = v
	data.master = clampf(float(data.master), 0.0, 1.0)
	data.sfx = clampf(float(data.sfx), 0.0, 1.0)
	data.voice = clampf(float(data.voice), 0.0, 1.0)
	data.mouse_sens = clampf(float(data.mouse_sens), SENS_RANGE.x, SENS_RANGE.y)
	data.fov = clampf(float(data.fov), FOV_RANGE.x, FOV_RANGE.y)
	if not FPS_STEPS.has(int(data.max_fps)):
		data.max_fps = 0


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PoolCues.SAVE_PATH)          # keep the other sections as they are
	for k in data:
		cfg.set_value("settings", k, data[k])
	cfg.save(PoolCues.SAVE_PATH)


static func reset() -> void:
	data = DEFAULTS.duplicate()


static func f(key: String) -> float:
	return float(data.get(key, DEFAULTS.get(key, 0.0)))


static func on(key: String) -> bool:
	return bool(data.get(key, DEFAULTS.get(key, false)))


# Push everything out to the engine. Cheap enough to call on every change.
static func apply() -> void:
	var sfx := _ensure_bus("SFX")
	var voice := _ensure_bus("Voice")
	_set_bus(0, f("master"))
	_set_bus(sfx, f("sfx"))
	_set_bus(voice, f("voice"))

	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if on("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
	var now := DisplayServer.window_get_mode()
	var is_full := now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full != on("fullscreen"):
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(data.get("max_fps", 0))


static func _ensure_bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	return i


static func _set_bus(i: int, v: float) -> void:
	AudioServer.set_bus_mute(i, v <= 0.001)
	# squared, so the slider feels even to the ear instead of doing nothing
	# until the last quarter
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.0001)))
