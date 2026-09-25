class_name PoolSound
extends Node3D

# Every sound is synthesised at load, the same way the textures are: the
# click of ball on ball, the thump of a cushion, the tip on the cue ball, and
# a ball dropping into a pocket and rattling down the bag. Played from where
# they happen in the room, so you hear the far corner from the far corner.

const RATE := 22050

var _clicks: Array = []
var _rail: AudioStreamWAV
var _drop: AudioStreamWAV
var _strike: AudioStreamWAV
var _players: Array = []
var _next := 0
var _rng := RandomNumberGenerator.new()
var _ui: Array = []
var _ui_next := 0
var _tick: AudioStreamWAV
var _bump: AudioStreamWAV
var _whoosh: AudioStreamWAV
var _thud: AudioStreamWAV
var _gulp: AudioStreamWAV
var _clink: AudioStreamWAV
var _slide: AudioStreamWAV
var _hic: AudioStreamWAV
var _till: AudioStreamWAV
var _steps: Array = []
var _near: AudioStreamPlayer


func setup() -> void:
	_rng.seed = 5150
	for i in 3:
		_clicks.append(_make_click(i))
	_rail = _make_rail()
	_drop = _make_drop()
	_strike = _make_strike()
	_tick = _make_tick()
	_bump = _make_bump()
	_whoosh = _make_whoosh()
	_thud = _make_thud()
	_gulp = _make_gulp()
	_clink = _make_clink()
	_slide = _make_slide()
	_hic = _make_hic()
	_till = _make_till()
	_near = AudioStreamPlayer.new()
	_near.bus = &"SFX"
	add_child(_near)
	for i in 3:
		_steps.append(_make_step(i))
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 2.2
		p.max_db = 2.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	for i in 4:
		var u := AudioStreamPlayer.new()
		u.bus = &"SFX"
		add_child(u)
		_ui.append(u)


# Menu sounds, from the same table: a light tick as you move over something,
# two balls kissing when you pick it, the cue on the ball to start.
func ui(kind: String) -> void:
	var s: AudioStream
	var vol := -10.0
	var pitch := 1.0
	match kind:
		"tick":
			s = _tick
			vol = -20.0
			pitch = _rng.randf_range(0.97, 1.03)
		"click":
			s = _clicks[0]
			vol = -9.0
			pitch = 1.08
		"equip":
			s = _clicks[1]
			vol = -6.0
			pitch = 0.92
		"start":
			s = _strike
			vol = -4.0
		_:
			return
	var rec := _take("ui_" + kind)
	if rec != null:
		s = rec
	var p: AudioStreamPlayer = _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	p.stop()
	p.stream = s
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


func _make_tick() -> AudioStreamWAV:
	var n := int(RATE * 0.02)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = exp(-t / 0.0025) * sin(TAU * 3400.0 * t) * 0.7
	return _wav(out)


# Something heard right at your own head rather than somewhere in the room:
# being hit, a gulp, a hiccup.
func near(s: AudioStream, vol_db := 0.0, pitch := 1.0) -> void:
	_near.stop()
	_near.stream = s
	_near.volume_db = vol_db
	_near.pitch_scale = pitch
	_near.play()


func near_kind(kind: String, vol_db := 0.0) -> void:
	var rec := _take(kind)
	if rec != null:
		near(rec, vol_db, _rng.randf_range(0.97, 1.03))
		return
	match kind:
		"whoosh":
			near(_whoosh, vol_db, _rng.randf_range(0.9, 1.05))
		"gulp":
			near(_gulp, vol_db, _rng.randf_range(0.9, 1.1))
		"hic":
			near(_hic, vol_db, _rng.randf_range(0.95, 1.12))


# A fist going through the air: a band of noise sweeping up and away.
func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.36)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / 0.36
		var env := pow(sin(PI * pow(k, 0.55)), 2.0)
		var a := lerpf(0.04, 0.32, sin(PI * k))
		lp = lerpf(lp, _noise(), a)
		lp2 = lerpf(lp2, lp, a * 0.5)
		out[i] = (lp - lp2 * 0.7) * env * 2.6
	return _wav(out)


# A body landing on floorboards: heavy and low, a rattle of the boards.
func _make_thud() -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.05)
		var boom := sin(TAU * (62.0 - 20.0 * minf(t / 0.1, 1.0)) * t) * exp(-t / 0.09)
		var boards := lp * exp(-t / 0.05) * 2.6
		var creak := sin(TAU * 190.0 * t + sin(TAU * 7.0 * t) * 2.0) * exp(-pow((t - 0.14) / 0.05, 2.0)) * 0.12
		out[i] = clampf((boom * 1.1 + boards + creak) * 0.85, -1.0, 1.0)
	return _wav(out)


# A swallow: a throaty glug that drops in pitch.
func _make_gulp() -> AudioStreamWAV:
	var n := int(RATE * 0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 140.0 + 300.0 * exp(-t / 0.028) - 40.0 * t / 0.26
		ph += TAU * f / RATE
		var env := minf(t / 0.008, 1.0) * exp(-t / 0.075)
		lp = lerpf(lp, _noise(), 0.06)
		var v := sin(ph) * env + sin(ph * 2.03) * env * 0.35 + lp * env * 1.1
		out[i] = v * 0.75
	return _wav(out)


# A glass set down on the bar.
func _make_clink() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ring := 0.5 * sin(TAU * 2350.0 * t) * exp(-t / 0.07) + 0.3 * sin(TAU * 3720.0 * t + 0.4) * exp(-t / 0.045) \
			+ 0.15 * sin(TAU * 5810.0 * t) * exp(-t / 0.025)
		var knock := sin(TAU * 180.0 * t) * exp(-t / 0.012) * 0.5
		out[i] = (ring + knock + _noise() * exp(-t / 0.002) * 0.3) * 0.8
	return _wav(out)


# A glass sliding down lacquered wood.
func _make_slide() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.3)
		lp2 = lerpf(lp2, lp, 0.3)
		var env := minf(t / 0.05, 1.0) * (1.0 - smoothstep(0.45, 0.7, t))
		out[i] = (lp - lp2) * env * 1.6 * (0.8 + 0.2 * sin(TAU * 31.0 * t))
	return _wav(out)


# A hiccup: a little closed-throat squeak.
func _make_hic() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 330.0 + 420.0 * minf(t / 0.05, 1.0)
		ph += TAU * f / RATE
		var env := minf(t / 0.006, 1.0) * exp(-t / 0.035)
		lp = lerpf(lp, _noise(), 0.25)
		var v := (sin(ph) + 0.5 * sin(ph * 2.0) + 0.25 * sin(ph * 3.0)) * env * 0.6 + lp * exp(-t / 0.01) * 0.6
		out[i] = v * 0.8
	return _wav(out)


# The till: a bell and the drawer.
func _make_till() -> AudioStreamWAV:
	var n := int(RATE * 0.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var bell := (0.5 * sin(TAU * 1568.0 * t) + 0.3 * sin(TAU * 2352.0 * t) + 0.12 * sin(TAU * 3920.0 * t)) * exp(-t / 0.25)
		var dt := t - 0.12
		lp = lerpf(lp, _noise(), 0.1)
		var drawer := 0.0
		if dt > 0.0:
			drawer = lp * exp(-dt / 0.06) * 1.2 + sin(TAU * 110.0 * dt) * exp(-dt / 0.04) * 0.5
		out[i] = (bell + drawer) * 0.7
	return _wav(out)


# Shoulder into a belly: soft, low, cloth.
func _make_bump() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.06)
		out[i] = (lp * 2.5 * exp(-t / 0.035) + sin(TAU * 70.0 * t) * 0.5 * exp(-t / 0.05)) * 0.8
	return _wav(out)


# A shoe on floorboards: a dull heel, a little scuff.
func _make_step(variant: int) -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var f := 120.0 + 18.0 * variant
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.12 + 0.04 * variant)
		var heel := sin(TAU * f * t) * exp(-t / 0.018)
		var scuff := lp * exp(-t / 0.03) * 0.9
		out[i] = (heel * 0.7 + scuff) * 0.7
	return _wav(out)


# A recorded sound, if there is one: audio/sfx/<kind>.ogg (or .wav, .mp3),
# and any numbered takes of it, <kind>_1, <kind>_2..., picked from at random.
# Anything recorded replaces the one made up in code.
var _recorded := {}

func _take(kind: String) -> AudioStream:
	if not _recorded.has(kind):
		var takes: Array = []
		for suffix in ["", "_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8"]:
			for ext in [".ogg", ".wav", ".mp3"]:
				var path := "res://audio/sfx/%s%s%s" % [kind, suffix, ext]
				if ResourceLoader.exists(path):
					takes.append(load(path))
		_recorded[kind] = takes
	var t: Array = _recorded[kind]
	return t[_rng.randi_range(0, t.size() - 1)] if not t.is_empty() else null


# `strength` is 0..1, roughly how hard the contact was.
func play(kind: String, at: Vector3, strength: float) -> void:
	var s: AudioStream = _take(kind)
	if s != null:
		_play_at(s, at, strength)
		return
	match kind:
		"click":
			s = _clicks[_rng.randi_range(0, _clicks.size() - 1)]
		"rail":
			s = _rail
		"drop":
			s = _drop
		"strike":
			s = _strike
		"bump":
			s = _bump
		"whoosh":
			s = _whoosh
		"thud":
			s = _thud
		"clink", "smash":
			s = _clink
		"slide":
			s = _slide
		"till":
			s = _till
		"step":
			s = _steps[_rng.randi_range(0, _steps.size() - 1)]
		_:
			return
	_play_at(s, at, strength)


func _play_at(s: AudioStream, at: Vector3, strength: float) -> void:
	var p: AudioStreamPlayer3D = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stop()
	p.stream = s
	p.global_position = at
	p.volume_db = linear_to_db(clampf(strength, 0.03, 1.0)) - 2.0
	p.pitch_scale = _rng.randf_range(0.95, 1.05)
	p.play()


# ---------------------------------------------------------------------------

func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _make_click(variant: int) -> AudioStreamWAV:
	var n := int(RATE * 0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	var f1 := 2900.0 + 180.0 * variant
	var f2 := 4600.0 - 150.0 * variant
	for i in n:
		var t := float(i) / RATE
		var ring := exp(-t / 0.0045) * (0.6 * sin(TAU * f1 * t) + 0.35 * sin(TAU * f2 * t + 1.0)
			+ 0.18 * sin(TAU * 7100.0 * t))
		var snap := _noise() * exp(-t / 0.0007) * 0.55
		out[i] = (ring + snap) * 0.9
	return _wav(out)


func _make_rail() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.08)
		var body := exp(-t / 0.04) * (0.7 * sin(TAU * 118.0 * t) + 0.3 * sin(TAU * 196.0 * t))
		var slap := lp * exp(-t / 0.012) * 1.4
		out[i] = (body + slap) * 0.85
	return _wav(out)


func _make_strike() -> AudioStreamWAV:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var tock := exp(-t / 0.006) * (0.6 * sin(TAU * 1020.0 * t) + 0.35 * sin(TAU * 1870.0 * t))
		out[i] = (tock + _noise() * exp(-t / 0.0015) * 0.35) * 0.9
	return _wav(out)


# Into the leather: a dull thunk, then the ball knocking its way down the bag.
func _make_drop() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var knocks := [0.07, 0.15, 0.21, 0.26, 0.30, 0.33]
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.12)
		var v := exp(-t / 0.05) * (0.8 * sin(TAU * 82.0 * t) + 0.3 * sin(TAU * 140.0 * t))
		v += lp * exp(-t / 0.02) * 0.6
		for k in knocks.size():
			var dt: float = t - float(knocks[k])
			if dt >= 0.0 and dt < 0.05:
				var amp := 0.5 * pow(0.72, float(k))
				v += amp * exp(-dt / 0.006) * sin(TAU * (1500.0 - 120.0 * k) * dt)
				v += amp * 0.6 * exp(-dt / 0.02) * sin(TAU * 95.0 * dt)
		out[i] = v * 0.8
	return _wav(out)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
