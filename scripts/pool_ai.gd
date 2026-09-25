class_name PoolAI
extends RefCounted

# The opponent plays by actually rehearsing shots. It finds candidate pots
# geometrically, then runs each one through the same physics the player's
# shots use, scores where the cue ball ends up, and re-runs the front-runners
# with its own aim error injected to see whether they survive a wobble. That
# is why it prefers a routine pot with good shape over a spectacular thin cut,
# and why it will play safe when there's nothing on.

# Difficulty runs 1 to 10. Every dial below is interpolated from it, so the
# opponent gets steadier hands, better shape, more patience for safeties and
# more shots to think about as the number climbs.
const SKILL_LABELS := [
	"Barfly", "Weekend player", "Regular", "League night", "Hustler",
	"House pro", "Money player", "Road shark", "Tour player", "Machine",
]

const SIM_DT := 1.0 / 280.0        # coarse pass, used to sift candidates
const FINE_DT := 1.0 / 720.0       # what the game actually runs at

var skill := 5  # 1..10
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func label() -> String:
	return SKILL_LABELS[clampi(skill, 1, 10) - 1]


# 0.0 at difficulty 1, 1.0 at difficulty 10
func _t() -> float:
	return clampf((float(skill) - 1.0) / 9.0, 0.0, 1.0)


func aim_sigma() -> float:
	# degrees of aim error, falling off geometrically
	return 2.40 * pow(0.055 / 2.40, _t())


func speed_sigma() -> float:
	return lerpf(0.175, 0.016, _t())


func position_weight() -> float:
	return lerpf(0.10, 1.55, _t())


func safety_nerve() -> float:
	return lerpf(0.05, 1.0, _t())


func variant_budget() -> int:
	return int(round(lerpf(7.0, 22.0, _t())))


func robust_checks() -> int:
	return int(round(lerpf(1.0, 4.0, _t())))


# How many times it will correct its aim and shoot again in its head. A weak
# player fires at the geometric line and gets thrown off it; a strong one
# keeps adjusting until the ball is going where they want.
func aim_passes() -> int:
	if skill <= 3:
		return 0
	if skill <= 6:
		return 1
	return 3


# Strong players rehearse at the same step the table actually runs at, so what
# they practise is what happens. Weak ones work off a rougher picture.
func fine_dt() -> float:
	return FINE_DT if skill >= 7 else SIM_DT


func considers_banks() -> bool:
	return skill >= 5


# A weak player does not always pick the shot they judged best.
func _pick(scored: Array) -> int:
	var slop := int(round(lerpf(3.0, 0.0, _t())))
	if slop <= 0 or scored.size() <= 1:
		return 0
	return rng.randi_range(0, mini(slop, scored.size() - 1))


# ---------------------------------------------------------------------------
# Entry point. Returns the shot to play, including a cue placement if it has
# ball in hand.
# ---------------------------------------------------------------------------

func choose(base: PoolSim, group: String, is_break: bool, ball_in_hand: bool) -> Dictionary:
	if is_break:
		return _break_shot(base, ball_in_hand)

	var on_eight := group != PoolRules.OPEN and PoolRules.remaining(base, group).is_empty()
	var variants := _variants(base, group, ball_in_hand)

	# first pass: a rough look at everything, to find what is worth studying
	var scored: Array = []
	for v in variants:
		v["score"] = _rehearse(base, v, group, on_eight, 0.0, SIM_DT)
		scored.append(v)
	scored.sort_custom(func(a, b): return a.score > b.score)

	var best: Dictionary = {}
	var best_score := -1e12
	# a weaker player often takes the second or third best thing on the table
	var off := _pick(scored)
	for i in range(off, mini(off + robust_checks(), scored.size())):
		var v: Dictionary = scored[i]
		_solve_aim(base, v, group, on_eight)
		var dt := fine_dt()
		# does it still work if the stroke is a fraction off?
		var sigma: float = _sigma(v)
		var total: float = _rehearse(base, v, group, on_eight, 0.0, dt)
		total += _rehearse(base, v, group, on_eight, sigma, dt)
		total += _rehearse(base, v, group, on_eight, -sigma, dt)
		total /= 3.0
		v["score"] = total
		if total > best_score:
			best_score = total
			best = v

	# A clean pot with decent shape is worth more than any safety, so don't
	# even bother rehearsing safeties in that case.
	if not best.is_empty() and best_score > 1200.0:
		return _with_error(best)

	var safe := _safety(base, group, on_eight)
	var safe_score: float = safe.get("score", -1.0e12)
	if best.is_empty():
		if not safe.is_empty():
			return _with_error(safe)
		return _with_error(_desperate(base, group))
	if not safe.is_empty() and safe_score > best_score and rng.randf() < safety_nerve():
		return _with_error(safe)
	return _with_error(best)


# ---------------------------------------------------------------------------
# Candidate generation
# ---------------------------------------------------------------------------

func _variants(sim: PoolSim, group: String, ball_in_hand: bool) -> Array:
	var cue := sim.ball(PoolSim.CUE)
	var targets := PoolRules.legal_targets(sim, group)
	var shots: Array = []

	for id in targets:
		var obj := sim.ball(id)
		for p in 6:
			var aim := sim.pocket_aim(p)
			var to_pocket := aim - obj.pos
			var d2 := to_pocket.length()
			if d2 < 0.02:
				continue
			var dir_obj := to_pocket / d2
			if not sim.path_clear(obj.pos, aim, [id, PoolSim.CUE], 0.004):
				continue
			var ghost := obj.pos - dir_obj * PoolSim.D

			var starts: Array = []
			if ball_in_hand:
				# put the cue ball where the shot is simplest
				for dist: float in [0.42, 0.85]:
					var spot: Vector2 = ghost - dir_obj * float(dist)
					if sim.spot_is_clear(spot):
						starts.append(spot)
				var ang := deg_to_rad(22.0)
				for s: float in [1.0, -1.0]:
					var spot2 := ghost - dir_obj.rotated(ang * s) * 0.55
					if sim.spot_is_clear(spot2):
						starts.append(spot2)
			if starts.is_empty():
				starts.append(cue.pos)

			for start in starts:
				var to_ghost: Vector2 = ghost - start
				var d1 := to_ghost.length()
				if d1 < 0.03:
					continue
				var dir_cue := to_ghost / d1
				var cosc := dir_cue.dot(dir_obj)
				if cosc < 0.20:
					continue
				if not sim.path_clear(start, ghost, [PoolSim.CUE, id], 0.004):
					continue
				var geo := pow(cosc, 1.7) / (1.0 + 0.30 * d1 + 0.55 * d2)
				if p == 2 or p == 3:
					geo *= 0.9                      # side pockets are meaner
				if absf(obj.pos.y) > PoolSim.HALF_WID - PoolSim.D:
					geo *= 0.82                     # frozen on the rail
				shots.append({
					"target": id, "pocket": p, "place": start if ball_in_hand else null,
					"dir": dir_cue, "cut": cosc, "d1": d1, "d2": d2, "geo": geo,
					"intent": "pot",
				})

	if considers_banks() and shots.size() < variant_budget():
		shots.append_array(_bank_shots(sim, targets, cue))

	shots.sort_custom(func(a, b): return a.geo > b.geo)
	var out: Array = []
	for s in shots:
		if out.size() >= variant_budget():
			break
		var reach: float = clampf(0.9 + 0.55 * (s.d1 + s.d2) / maxf(s.cut, 0.25), 0.9, 3.4)
		var speeds := [reach * 1.05, reach * 1.7]
		var spins := [Vector2.ZERO, Vector2(0.0, 0.32)]
		if s.d1 < 0.7:
			spins[1] = Vector2(0.0, -0.32)          # draw back off a close ball
		for si in speeds.size():
			for ei in spins.size():
				if out.size() >= variant_budget():
					break
				var v: Dictionary = s.duplicate()
				v["speed"] = clampf(speeds[si], 0.8, 5.2)
				v["english"] = spins[ei]
				out.append(v)
	return out


# One off the rail. The pocket is mirrored through the cushion line the ball
# would bounce off, and the object ball is sent at the mirror image: the angle
# it comes off at takes it to the real pocket. Only bothered with when there
# is nothing straightforward on, and only by players good enough to see it.
func _bank_shots(sim: PoolSim, targets: Array, cue: PoolSim.Ball) -> Array:
	var out: Array = []
	var hl := PoolSim.HALF_LEN - PoolSim.R
	var hw := PoolSim.HALF_WID - PoolSim.R
	var rails := [
		{"axis": "x", "at": hl}, {"axis": "x", "at": -hl},
		{"axis": "y", "at": hw}, {"axis": "y", "at": -hw},
	]
	for id in targets:
		var obj := sim.ball(id)
		for p in 6:
			var pocket := sim.pocket_aim(p)
			for rail in rails:
				var mirror: Vector2 = pocket
				if rail.axis == "x":
					mirror = Vector2(2.0 * float(rail.at) - pocket.x, pocket.y)
				else:
					mirror = Vector2(pocket.x, 2.0 * float(rail.at) - pocket.y)
				var leg := mirror - obj.pos
				if leg.length() < 0.25:
					continue
				var dir_obj := leg.normalized()
				# where it meets the cushion
				var t := 0.0
				if rail.axis == "x":
					if is_zero_approx(dir_obj.x):
						continue
					t = (float(rail.at) - obj.pos.x) / dir_obj.x
				else:
					if is_zero_approx(dir_obj.y):
						continue
					t = (float(rail.at) - obj.pos.y) / dir_obj.y
				if t <= 0.06:
					continue
				var contact := obj.pos + dir_obj * t
				if not _on_cushion(contact, rail):
					continue
				if not sim.path_clear(obj.pos, contact, [id, PoolSim.CUE], 0.004):
					continue
				if not sim.path_clear(contact, pocket, [id, PoolSim.CUE], 0.004):
					continue

				var ghost := obj.pos - dir_obj * PoolSim.D
				var to_ghost := ghost - cue.pos
				var d1 := to_ghost.length()
				if d1 < 0.05:
					continue
				var dir_cue := to_ghost / d1
				var cosc := dir_cue.dot(dir_obj)
				if cosc < 0.55:
					continue                        # thin cuts do not bank well
				if not sim.path_clear(cue.pos, ghost, [PoolSim.CUE, id], 0.004):
					continue
				var d2: float = t + contact.distance_to(pocket)
				out.append({
					"target": id, "pocket": p, "place": null, "dir": dir_cue,
					"cut": cosc, "d1": d1, "d2": d2,
					"geo": pow(cosc, 2.0) / (1.0 + 0.30 * d1 + 0.75 * d2) * 0.55,
					"intent": "pot", "bank": true,
				})
	return out


func _on_cushion(p: Vector2, rail: Dictionary) -> bool:
	# keep off the pocket mouths, where there is no cushion to bounce from
	if rail.axis == "x":
		return absf(p.y) < PoolSim.HALF_WID - PoolSim.CORNER_GAP - 0.03
	if absf(p.x) > PoolSim.HALF_LEN - PoolSim.CORNER_GAP - 0.03:
		return false
	return absf(p.x) > PoolSim.SIDE_GAP + 0.03


# ---------------------------------------------------------------------------
# Aim solving
#
# The ghost-ball line is only a first guess: friction between the two balls
# throws the object ball off it, by a couple of degrees on a thick cut, and a
# couple of degrees is a miss from the length of the table. So the shot is
# played in the head, the miss is measured, the aim is corrected by the amount
# that miss implies, and it is played again. Two or three passes and the ball
# is going where it was sent.
# ---------------------------------------------------------------------------

func _solve_aim(base: PoolSim, v: Dictionary, group: String, on_eight: bool) -> void:
	var passes := aim_passes()
	if passes <= 0 or v.intent != "pot" or int(v.pocket) < 0:
		return
	var target := int(v.target)
	var point := base.pocket_aim(int(v.pocket))
	var d1: float = maxf(float(v.d1), 0.05)
	var d2: float = maxf(float(v.d2), 0.05)
	# moving the aim by one radian moves the object ball's line by this much,
	# because the contact point slides around the ball as the cue line turns
	var gearing: float = d1 * d2 / PoolSim.D

	var angle := 0.0
	var prev_angle := 0.0
	var prev_miss := 0.0
	var have_prev := false
	for pass_i in passes:
		var miss := _measure(base, v, target, point, angle)
		if is_zero_approx(miss):
			break                                   # it went in
		var next: float
		if have_prev and absf(miss - prev_miss) > 1.0e-6:
			# secant step: two misses tell us the slope directly
			next = angle - miss * (angle - prev_angle) / (miss - prev_miss)
		else:
			# one radian of aim swings the object ball's line by roughly
			# `gearing` metres at the target, and in the opposite sense: the
			# cue ball passing above the object ball cuts it downward
			next = angle - miss / gearing
		next = clampf(next, angle - 0.06, angle + 0.06)
		prev_angle = angle
		prev_miss = miss
		have_prev = true
		angle = next
	if not is_zero_approx(angle):
		v["dir"] = (v.dir as Vector2).rotated(angle)
		v["aim_fix"] = angle


# Plays the shot in the head and reports how far off the target the object
# ball passed, signed, in metres. Zero means it dropped.
func _measure(base: PoolSim, v: Dictionary, target: int, point: Vector2, extra_angle: float) -> float:
	var sim := base.clone_sim(fine_dt())
	if v.place != null:
		sim.place_cue(v.place)
	sim.track(target, point)
	sim.events.clear()
	sim.strike((v.dir as Vector2).rotated(extra_angle), v.speed, v.english)
	sim.run_to_rest(7.0)
	return sim.track_miss


# ---------------------------------------------------------------------------
# Rehearsal
# ---------------------------------------------------------------------------

func _rehearse(base: PoolSim, v: Dictionary, group: String, on_eight: bool, wobble_deg: float, dt := SIM_DT) -> float:
	var sim := base.clone_sim(dt)
	if v.place != null:
		sim.place_cue(v.place)
	var dir: Vector2 = v.dir
	if not is_zero_approx(wobble_deg):
		dir = dir.rotated(deg_to_rad(wobble_deg))
	sim.events.clear()
	sim.strike(dir, v.speed, v.english)
	var events := sim.run_to_rest(7.0)
	var called: int = v.pocket if on_eight else -1
	var res := PoolRules.analyze(events, group, on_eight, called)

	var score := 0.0
	if res.won:
		return 1.0e6
	if res.lost:
		return -1.0e6
	score += 1500.0 * float(res.own) - 450.0 * float(res.opp)
	if res.foul:
		score -= 2000.0
	if v.intent == "safe":
		score += 250.0

	var keeps_table: bool = res.own > 0 and not res.foul
	var w: float = position_weight()
	if keeps_table:
		score += 700.0 * w * _shape(sim, group)
	else:
		var foe := PoolRules.other_group(group)
		var foe_on_eight := foe != PoolRules.OPEN and PoolRules.remaining(sim, foe).is_empty()
		score -= 600.0 * w * _shape(sim, foe, foe_on_eight)
		if res.foul:
			score -= 400.0 * w      # they get ball in hand as well
	return score


# How good is the best available shot from this layout? 0 = nothing on.
func _shape(sim: PoolSim, group: String, on_eight := false) -> float:
	var cue := sim.ball(PoolSim.CUE)
	if not cue.on_table:
		return 1.0
	var targets := PoolRules.legal_targets(sim, group)
	if on_eight:
		targets = [PoolSim.EIGHT] if sim.ball(PoolSim.EIGHT).on_table else []
	var best := 0.0
	for id in targets:
		var obj := sim.ball(id)
		if not obj.on_table:
			continue
		for p in 6:
			var aim := sim.pocket_aim(p)
			var to_pocket := aim - obj.pos
			var d2 := to_pocket.length()
			if d2 < 0.02:
				continue
			var dir_obj := to_pocket / d2
			var ghost := obj.pos - dir_obj * PoolSim.D
			var to_ghost := ghost - cue.pos
			var d1 := to_ghost.length()
			if d1 < 0.02:
				continue
			var cosc := (to_ghost / d1).dot(dir_obj)
			if cosc < 0.25:
				continue
			if not sim.path_clear(obj.pos, aim, [id, PoolSim.CUE], 0.004):
				continue
			if not sim.path_clear(cue.pos, ghost, [PoolSim.CUE, id], 0.004):
				continue
			var q := pow(cosc, 1.7) / (1.0 + 0.30 * d1 + 0.55 * d2)
			best = maxf(best, q)
	return clampf(best * 1.45, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Safety play
# ---------------------------------------------------------------------------

func _safety(base: PoolSim, group: String, on_eight: bool) -> Dictionary:
	var cue := base.ball(PoolSim.CUE)
	var targets := PoolRules.legal_targets(base, group)
	if targets.is_empty():
		return {}
	var cands: Array = []
	for id in targets:
		var obj := base.ball(id)
		var to_obj := obj.pos - cue.pos
		var d := to_obj.length()
		if d < 0.04:
			continue
		var base_dir := to_obj / d
		for off: float in [-0.55, -0.28, 0.0, 0.28, 0.55]:
			var ghost := obj.pos - base_dir.rotated(off) * PoolSim.D
			var dir := (ghost - cue.pos).normalized()
			if not base.path_clear(cue.pos, ghost, [PoolSim.CUE, id], 0.004):
				continue
			for sp: float in [1.1, 2.0]:
				cands.append({
					"target": id, "pocket": -1, "place": null, "dir": dir,
					"speed": sp, "english": Vector2.ZERO, "cut": 1.0 - absf(off),
					"d1": d, "d2": 0.5, "geo": 0.0, "intent": "safe",
				})
	if cands.is_empty():
		return {}
	if cands.size() > 14:
		cands = cands.slice(0, 14)

	var best: Dictionary = {}
	var best_score := -1e12
	for c in cands:
		var s := _rehearse(base, c, group, on_eight, 0.0, SIM_DT)
		if s > best_score:
			best_score = s
			best = c
	best["score"] = best_score
	return best


# Nothing legal found by search: hit the nearest legal ball and hope.
func _desperate(base: PoolSim, group: String) -> Dictionary:
	var cue := base.ball(PoolSim.CUE)
	var targets := PoolRules.legal_targets(base, group)
	var pick := -1
	var best := 1e9
	for id in targets:
		var d := base.ball(id).pos.distance_to(cue.pos)
		if d < best:
			best = d
			pick = id
	var dir := Vector2.RIGHT
	if pick >= 0:
		dir = (base.ball(pick).pos - cue.pos).normalized()
	return {
		"target": pick, "pocket": -1, "place": null, "dir": dir, "speed": 2.0,
		"english": Vector2.ZERO, "cut": 1.0, "d1": best, "d2": 0.5,
		"intent": "contact",
	}


# ---------------------------------------------------------------------------

func _break_shot(base: PoolSim, ball_in_hand: bool) -> Dictionary:
	var z := rng.randf_range(0.14, 0.30) * (1.0 if rng.randf() < 0.5 else -1.0)
	var place := Vector2(PoolSim.HEAD_X - 0.24, z)
	var apex := base.ball(1)
	if not apex.on_table:
		apex = base.ball(PoolSim.EIGHT)
	var from: Vector2 = place if ball_in_hand else base.ball(PoolSim.CUE).pos
	var dir := (apex.pos - from).normalized().rotated(deg_to_rad(rng.randf_range(-0.5, 0.5)))
	return {
		"target": 1, "pocket": -1, "place": place if ball_in_hand else null,
		"dir": dir, "speed": rng.randf_range(6.5, 7.4),
		"english": Vector2(rng.randf_range(-0.1, 0.1), 0.12),
		"cut": 1.0, "d1": 1.0, "d2": 0.5, "intent": "break",
	}


func _sigma(v: Dictionary) -> float:
	var base: float = aim_sigma()
	var hard: float = 1.0 + 0.5 * (float(v.d1) + float(v.d2)) + 1.1 * (1.0 - float(v.cut))
	return base * hard


# Execute with a human-sized error. The AI never sees this: it commits to the
# shot it rehearsed and then plays it slightly wrong, like everybody does.
func _with_error(v: Dictionary) -> Dictionary:
	var out := v.duplicate()
	if v.get("intent", "") == "break":
		return out
	var sigma := _sigma(v)
	var d: Vector2 = v.dir
	out["dir"] = d.rotated(deg_to_rad(rng.randfn(0.0, sigma)))
	var sp: float = float(v.speed) * (1.0 + rng.randfn(0.0, speed_sigma()))
	out["speed"] = clampf(sp, 0.6, 6.5)
	var e: Vector2 = v.english
	out["english"] = e + Vector2(rng.randfn(0.0, 0.04), rng.randfn(0.0, 0.04))
	return out
