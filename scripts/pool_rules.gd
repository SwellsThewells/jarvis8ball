class_name PoolRules
extends RefCounted

# World-standardised 8-ball, trimmed to what a bar game actually enforces.
# Groups are "solids" (1-7), "stripes" (9-15) or "open" before they're claimed.

const SOLIDS := "solids"
const STRIPES := "stripes"
const OPEN := "open"


static func group_of(id: int) -> String:
	if id >= 1 and id <= 7:
		return SOLIDS
	if id >= 9 and id <= 15:
		return STRIPES
	return ""


static func other_group(g: String) -> String:
	if g == SOLIDS:
		return STRIPES
	if g == STRIPES:
		return SOLIDS
	return OPEN


static func group_ids(g: String) -> Array:
	if g == SOLIDS:
		return [1, 2, 3, 4, 5, 6, 7]
	if g == STRIPES:
		return [9, 10, 11, 12, 13, 14, 15]
	return [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]


static func remaining(sim: PoolSim, g: String) -> Array:
	var out: Array = []
	for id in group_ids(g):
		if sim.ball(id).on_table:
			out.append(id)
	return out


# Which balls may this shooter legally strike first?
static func legal_targets(sim: PoolSim, g: String) -> Array:
	if g == OPEN:
		var open_set: Array = []
		for id in group_ids(OPEN):
			if sim.ball(id).on_table:
				open_set.append(id)
		return open_set
	var left := remaining(sim, g)
	if left.is_empty():
		return [PoolSim.EIGHT] if sim.ball(PoolSim.EIGHT).on_table else []
	return left


# Break down a completed shot. `group` is the shooter's group before the shot,
# `called` is the pocket nominated for the 8 (-1 when it doesn't matter).
static func analyze(events: Array, group: String, on_eight: bool, called: int) -> Dictionary:
	var first := -1
	var potted: Array = []
	var pot_pockets: Dictionary = {}
	var rail_after := false
	var pot_after := false
	var eight_pocket := -1

	for ev in events:
		match ev.type:
			"hit":
				if first < 0 and (ev.a == PoolSim.CUE or ev.b == PoolSim.CUE):
					first = ev.b if ev.a == PoolSim.CUE else ev.a
			"rail":
				if first >= 0:
					rail_after = true
			"pot":
				potted.append(ev.ball)
				pot_pockets[ev.ball] = ev.pocket
				if ev.ball == PoolSim.EIGHT:
					eight_pocket = ev.pocket
				if first >= 0 and ev.ball != PoolSim.CUE:
					pot_after = true

	var res := {
		"first": first,
		"potted": potted,
		"pockets": pot_pockets,
		"cue_potted": potted.has(PoolSim.CUE),
		"eight_potted": potted.has(PoolSim.EIGHT),
		"eight_pocket": eight_pocket,
		"foul": false,
		"reason": "",
		"own": 0,
		"opp": 0,
		"lost": false,
		"won": false,
	}

	for id in potted:
		if id == PoolSim.CUE or id == PoolSim.EIGHT:
			continue
		if group == OPEN or group_of(id) == group:
			res.own += 1
		else:
			res.opp += 1

	if res.cue_potted:
		res.foul = true
		res.reason = "Cue ball pocketed"
	elif first < 0:
		res.foul = true
		res.reason = "No contact"
	elif on_eight and first != PoolSim.EIGHT:
		res.foul = true
		res.reason = "Hit the wrong ball first"
	elif not on_eight and first == PoolSim.EIGHT:
		res.foul = true
		res.reason = "Hit the 8 first"
	elif group != OPEN and not on_eight and group_of(first) != group:
		res.foul = true
		res.reason = "Hit the wrong group first"
	elif not rail_after and not pot_after:
		res.foul = true
		res.reason = "No ball reached a cushion"

	if res.eight_potted:
		if not on_eight:
			res.lost = true
			res.reason = "The 8 went down early"
		elif res.cue_potted:
			res.lost = true
			res.reason = "Scratched on the 8"
		elif called >= 0 and eight_pocket != called:
			res.lost = true
			res.reason = "The 8 went in the wrong pocket"
		else:
			res.won = true

	return res
