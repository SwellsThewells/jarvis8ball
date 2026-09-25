class_name PoolPlayer
extends RefCounted

# One person in the room: where they are standing, where they are looking,
# and whether they are down on a shot. Everything about a player lives in
# here and nothing else reads the keyboard, so when a second player arrives
# over a wire they are simply another one of these, fed from the network
# instead of from input, and drawn with the same body.

const EYE := 1.63                 # standing eye height
const SPEED := 1.02               # a slow, unhurried walk
const SPRINT := 1.6               # holding shift
const ACCEL := 4.5
const DAMP := 7.0
const MARGIN := 0.55              # how far out from a wall the slowdown starts
const TABLE_MARGIN := 0.22        # and from the table: you can walk right up to it

var pos := Vector2(0.0, 2.6)      # on the floor, (x, z)
var vel := Vector2.ZERO
var yaw := -PI * 0.5              # facing, radians
var pitch := -0.12
var down := false                 # down on the shot rather than standing
var locked := false               # holding the stance, head free
var bob := 0.0                    # walking cycle: one full turn is two steps
var stride := 0.0
var sway := 0.0                   # how much the walk shows in your head, eased
var breath := 0.0

# The room and the table, as far as walking is concerned. The table box is
# where your body stops: hips against the rail, not a pace back from it.
var room := Vector2(5.2, 3.8)
var table := Vector2(PoolSim.HALF_LEN + 0.36, PoolSim.HALF_WID + 0.36)
var bar_x := BarRoom.BAR_FRONT_X + 0.3
var obstacles: Array = []         # stools and the like: [centre, radius]


# Your eyes, with a calm walk in them: the head dips a little as each foot
# lands, drifts a touch towards the foot you are standing on, and when you
# stop it settles to nothing more than breathing.
func eye() -> Vector3:
	var dip := -(0.5 - 0.5 * cos(bob * 2.0)) * 0.011 * sway
	var side := sin(bob) * 0.0055 * sway
	var h := EYE + dip + sin(breath) * 0.0016
	var r := right()
	return Vector3(pos.x + r.x * side, h, pos.y + r.y * side)


# A trace of roll with each step, in radians.
func roll() -> float:
	return sin(bob) * 0.0035 * sway


func look_dir() -> Vector3:
	return Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))


func forward() -> Vector2:
	return Vector2(cos(yaw), sin(yaw))


func right() -> Vector2:
	return Vector2(-sin(yaw), cos(yaw))


# `wish` is in local terms: x is strafe, y is forward.
func walk(delta: float, wish: Vector2, sprint := false) -> void:
	var want := (right() * wish.x + forward() * wish.y)
	if want.length() > 1.0:
		want = want.normalized()
	var target := _confine(want * SPEED * (SPRINT if sprint else 1.0))
	vel = vel.lerp(target, 1.0 - exp(-(ACCEL if target.length() > 0.01 else DAMP) * delta))
	pos += vel * delta
	stride = vel.length() / SPEED
	# about two steps a second walking, a little quicker when you hurry
	bob += delta * (6.2 * minf(stride, 1.0) + 3.0 * maxf(stride - 1.0, 0.0))
	sway = lerpf(sway, clampf(stride, 0.0, 1.35), 1.0 - exp(-4.0 * delta))
	breath += delta * 1.35


# Nothing is a hard wall. Walking towards an edge just gets slower and slower
# until you are barely creeping; turn round and you are back to full pace
# immediately, because only the part of the motion heading further out is
# damped.
func _confine(v: Vector2) -> Vector2:
	var out := v
	out = _slow(out, Vector2(-1.0, 0.0), room.x - pos.x)
	out = _slow(out, Vector2(1.0, 0.0), pos.x + room.x)
	out = _slow(out, Vector2(0.0, -1.0), room.y - pos.y)
	out = _slow(out, Vector2(0.0, 1.0), pos.y + room.y)
	out = _slow(out, Vector2(1.0, 0.0), pos.x - bar_x)
	# the table itself, as a rounded box you cannot walk through
	var q := Vector2(absf(pos.x) - table.x, absf(pos.y) - table.y)
	var dist: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	var away := Vector2(signf(pos.x) * maxf(q.x, 0.0), signf(pos.y) * maxf(q.y, 0.0))
	if away.length_squared() < 1.0e-6:
		# inside the footprint: push out along whichever edge is nearest
		away = Vector2(signf(pos.x), 0.0) if q.x > q.y else Vector2(0.0, signf(pos.y))
	out = _slow(out, away.normalized(), dist, TABLE_MARGIN)
	for o in obstacles:
		var off: Vector2 = pos - (o[0] as Vector2)
		var r: float = float(o[1]) + 0.2
		if off.length() < r + 0.3 and off.length() > 1.0e-4:
			out = _slow(out, off.normalized(), off.length() - r, 0.3)
	return out


func _slow(v: Vector2, inward: Vector2, dist: float, margin := MARGIN) -> Vector2:
	if dist > margin:
		return v
	var into := v.dot(-inward)          # how much of this heads further out
	if into <= 0.0:
		return v                        # heading back in: full speed
	var scale: float = clampf(dist / margin, 0.0, 1.0)
	scale = scale * scale               # creeps, rather than stopping dead
	return v + inward * into * (1.0 - scale)


func turn(rel: Vector2, sens: float) -> void:
	yaw = wrapf(yaw + rel.x * sens, -PI, PI)
	pitch = clampf(pitch - rel.y * sens * 0.9, -1.15, 0.85)


# Stand up out of a stance at a sensible spot: behind the shot, on the line,
# and never inside the table.
func stand_at(point: Vector2, facing: Vector2) -> void:
	pos = point
	yaw = atan2(facing.y, facing.x)
	pitch = -0.14
	vel = Vector2.ZERO
	down = false
	locked = false
	for _i in 24:
		var q := Vector2(absf(pos.x) - table.x, absf(pos.y) - table.y)
		if maxf(q.x, q.y) > 0.02:
			break
		pos -= facing * 0.06
