class_name PoolMPRules
extends RefCounted

# The house rules a lobby can be set up with. Each rule is one row on the
# create-lobby page: a few choices, the first one the default.

const LIST := [
	{"key": "race", "label": "Race to", "desc": "Racks you need to win the match",
		"options": [1, 2, 3, 5], "names": ["1 rack", "2 racks", "3 racks", "5 racks"]},
	{"key": "clock", "label": "Shot clock", "desc": "Time for each shot. Run out and it's a foul",
		"options": [0, 60, 30, 15], "names": ["Off", "60 s", "30 s", "15 s"]},
	{"key": "scratch", "label": "After a foul", "desc": "Where the other player puts the cue ball",
		"options": ["anywhere", "kitchen"], "names": ["Anywhere", "Behind the line"]},
	{"key": "call", "label": "Call shots", "desc": "Which shots need a pocket named first",
		"options": ["eight", "all"], "names": ["Just the 8", "Every shot"]},
	{"key": "break", "label": "Next break", "desc": "Who breaks the next rack",
		"options": ["alternate", "winner", "loser"], "names": ["Take turns", "Winner", "Loser"]},
	{"key": "three_fouls", "label": "Three fouls", "desc": "Three fouls in a row loses the rack",
		"options": [false, true], "names": ["Off", "On"]},
	{"key": "guides", "label": "Aim guide", "desc": "Lines showing where the balls will go",
		"options": [true, false], "names": ["On", "Off"]},
]

# Ready-made sets, as buttons above the rules.
const PRESETS := [
	{"name": "Classic", "rules": {}},
	{"name": "Casual", "rules": {"race": 1, "clock": 0, "guides": true}},
	{"name": "Speed", "rules": {"race": 3, "clock": 15, "break": "alternate"}},
	{"name": "Pro", "rules": {"race": 3, "clock": 30, "scratch": "kitchen", "call": "all",
		"three_fouls": true, "guides": false, "break": "winner"}},
]


static func spec(key: String) -> Dictionary:
	for r in LIST:
		if r.key == key:
			return r
	return {}


static func defaults() -> Dictionary:
	var d := {}
	for r in LIST:
		d[r.key] = r.options[0]
	return d


# Anything from the network or the database, made safe: unknown keys dropped,
# bad values back to the default. Numbers come back from JSON as floats.
static func clean(src: Variant) -> Dictionary:
	var d := defaults()
	if typeof(src) != TYPE_DICTIONARY:
		return d
	for r in LIST:
		if not (src as Dictionary).has(r.key):
			continue
		var v: Variant = src[r.key]
		for o in r.options:
			if typeof(o) == TYPE_INT and typeof(v) in [TYPE_INT, TYPE_FLOAT] and int(v) == o:
				d[r.key] = o
			elif typeof(o) == typeof(v) and o == v:
				d[r.key] = o
	return d


static func preset(i: int) -> Dictionary:
	var d := defaults()
	var p: Dictionary = PRESETS[clampi(i, 0, PRESETS.size() - 1)].rules
	for k in p:
		d[k] = p[k]
	return d


# Which preset these rules are exactly, or -1.
static func preset_of(rules: Dictionary) -> int:
	for i in PRESETS.size():
		if preset(i) == clean(rules):
			return i
	return -1


static func index_of(rules: Dictionary, key: String) -> int:
	var r := spec(key)
	var v: Variant = clean(rules)[key]
	return maxi(0, (r.options as Array).find(v))


static func name_of(rules: Dictionary, key: String) -> String:
	var r := spec(key)
	return str(r.names[index_of(rules, key)])


static func cycle(rules: Dictionary, key: String, dir: int) -> Dictionary:
	var d := clean(rules)
	var r := spec(key)
	d[key] = r.options[wrapi(index_of(d, key) + dir, 0, (r.options as Array).size())]
	return d


# One line for lobby lists: only what differs from a plain game.
static func summary(rules: Dictionary) -> String:
	var d := clean(rules)
	var parts: Array[String] = []
	parts.append("Race to %d" % int(d.race))
	if int(d.clock) > 0:
		parts.append("%ds clock" % int(d.clock))
	if d.call == "all":
		parts.append("call every shot")
	if d.scratch == "kitchen":
		parts.append("behind the line")
	if d.three_fouls:
		parts.append("three fouls")
	if not d.guides:
		parts.append("no guides")
	return "  ·  ".join(parts)
