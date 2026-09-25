class_name PoolSim
extends RefCounted

# ---------------------------------------------------------------------------
# Rigid-body pool physics.
#
# Balls live on a 2D plane (x, z) with a full 3D angular velocity vector, so
# side spin (english), follow and draw are all real quantities rather than
# cosmetic effects. Cloth friction switches between a sliding regime and a
# rolling regime exactly like a real ball does, which is what produces the
# familiar behaviour: a hard stun shot skids, then bites and rolls forward.
#
# Units are SI. Everything is tuned to a 9-foot table with a fast cloth.
# ---------------------------------------------------------------------------

const R := 0.028575                       # ball radius (2.25" diameter)
const D := 0.05715                        # ball diameter
const M := 0.17                           # ball mass (kg)
const G := 9.81
const INV_I := 5.0 / (2.0 * M * R * R)    # 1 / moment of inertia

const MU_SLIDE := 0.21                    # cloth, sliding
const MU_ROLL := 0.0105                   # cloth, rolling resistance
const MU_SPIN := 0.022                    # cloth, spin about vertical axis
const E_BALL := 0.96                      # ball-ball restitution
const MU_BALL := 0.06                     # ball-ball friction (produces throw)
const E_RAIL := 0.82                      # cushion restitution
const MU_RAIL := 0.15                     # cushion friction
const E_JAW := 0.68                       # pocket jaw rubber (rattles)
const RAIL_UP := 0.27 * R                 # cushion contact height above centre
const RAIL_OUT := 0.9628 * R              # horizontal part of contact offset
const RAIL_SPIN_GAIN := 0.6               # how much rail impulse re-spins ball

const SLIDE_EPS := 0.0015
const STOP_V := 0.0035
const STOP_W := 0.25

# Playing surface: 100" x 50"
const HALF_LEN := 1.27
const HALF_WID := 0.635
# Pocket sizes follow the WPA/BCA equipment spec for a nine-foot table:
# corner mouth 4.5"-4.625" measured between the cushion noses, side mouth
# 5"-5.125". The gap along each rail is the mouth over root two at a corner.
const CORNER_MOUTH := 0.1156              # 4.55" between the noses
const SIDE_MOUTH := 0.1285                # 5.06"
const CORNER_GAP := CORNER_MOUTH / sqrt(2.0)
const SIDE_GAP := SIDE_MOUTH * 0.5
# Cushion ends are cut flat and angled, not rounded: 142 degrees between the
# two facings at a corner, 103 at a side pocket, facings about 1.7" long.
const CORNER_FACE_ANGLE := 142.0
const SIDE_FACE_ANGLE := 103.0
const CORNER_FACE_LEN := 0.043
const SIDE_FACE_LEN := 0.032
# The shelf: how far past the mouth a ball must get before it drops. The spec
# allows 1.625"-1.875" at a corner and almost none at a side.
const CORNER_SHELF := 0.030
const SIDE_SHELF := 0.004
const FOOT_X := 0.635                     # foot spot
const HEAD_X := -0.635                    # head string

const CUE := 0
const EIGHT := 8

class Ball:
	var id := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var spin := Vector3.ZERO
	var on_table := true
	var pocket := -1
	var resting := true

var sub_dt := 1.0 / 720.0

# Shot tracking. The opponent uses this to ask "how exactly did that miss?":
# after a rehearsal, track_miss is the signed distance by which the tracked
# ball passed the target, which is enough to correct the aim and shoot again.
var track_id := -1
var track_point := Vector2.ZERO
var track_miss := 0.0
var _track_best := 1.0e9
var _track_done := false
var balls: Array[Ball] = []
var cushions: Array = []
var facings: Array = []
var pockets: Array = []
var events: Array = []
var record_events := true

# Pockets are named as they look when you are shooting up the table, i.e.
# from the head end towards the foot end.
const POCKET_NAMES := [
	"the near left corner", "the near right corner",
	"the left side pocket", "the right side pocket",
	"the far left corner", "the far right corner",
]


func _init() -> void:
	_build_geometry()
	for i in 16:
		var b := Ball.new()
		b.id = i
		balls.append(b)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func _add_cushion(a: Vector2, b: Vector2, n: Vector2) -> void:
	cushions.append({"p1": a, "p2": b, "n": n})


# A pocket facing: the flat, angled cut on the end of a cushion. Balls bounce
# off these exactly as they do off a cushion, which is what makes a pocket
# rattle instead of swallowing everything that reaches the mouth.
func _add_facing(tip: Vector2, towards: Vector2, length: float, pocket_side: Vector2) -> void:
	var d := towards.normalized()
	var far := tip + d * length
	var n := Vector2(d.y, -d.x)
	if n.dot(pocket_side) < 0.0:
		n = -n
	cushions.append({"p1": tip, "p2": far, "n": n, "facing": true})
	facings.append({"p1": tip, "p2": far, "n": n})


# The cut on the end of every cushion, angled away from the mouth so the
# pocket opens as it goes back.
func _build_facings() -> void:
	var hl := HALF_LEN
	var hw := HALF_WID
	var half_corner := deg_to_rad(CORNER_FACE_ANGLE * 0.5)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var bis := Vector2(sx, sz).normalized()
			var t1 := Vector2((hl - CORNER_GAP) * sx, hw * sz)   # long rail tip
			var t2 := Vector2(hl * sx, (hw - CORNER_GAP) * sz)   # short rail tip
			var pocket_c := (t1 + t2) * 0.5 + bis * 0.05
			var c1 := bis.rotated(half_corner)
			var c2 := bis.rotated(-half_corner)
			# the one that leans along the long rail's outward normal belongs
			# to the long rail; the other to the short rail
			var long_out := Vector2(0.0, sz)
			if absf(c1.dot(long_out)) < absf(c2.dot(long_out)):
				var swap := c1
				c1 = c2
				c2 = swap
			_add_facing(t1, c1, CORNER_FACE_LEN, pocket_c - t1)
			_add_facing(t2, c2, CORNER_FACE_LEN, pocket_c - t2)

	var half_side := deg_to_rad(SIDE_FACE_ANGLE * 0.5)
	for sz: float in [-1.0, 1.0]:
		var out := Vector2(0.0, sz)
		var pc := Vector2(0.0, (hw + 0.05) * sz)
		for sx: float in [-1.0, 1.0]:
			var tip := Vector2(SIDE_GAP * sx, hw * sz)
			var d := out.rotated(half_side * sx * sz)
			_add_facing(tip, d, SIDE_FACE_LEN, pc - tip)


func _build_geometry() -> void:
	var hl := HALF_LEN
	var hw := HALF_WID

	# long rails (broken by the side pockets)
	for s: float in [1.0, -1.0]:
		var n := Vector2(0.0, -s)
		_add_cushion(Vector2(-hl + CORNER_GAP, hw * s), Vector2(-SIDE_GAP, hw * s), n)
		_add_cushion(Vector2(SIDE_GAP, hw * s), Vector2(hl - CORNER_GAP, hw * s), n)

	# short rails
	for s: float in [1.0, -1.0]:
		var n := Vector2(-s, 0.0)
		_add_cushion(Vector2(hl * s, -hw + CORNER_GAP), Vector2(hl * s, hw - CORNER_GAP), n)

	_build_facings()

	# A pocket is a gap in the slate, not a circle in space: a ball drops once
	# its centre crosses the mouth line and gets onto the shelf. Modelling
	# it that way means nothing can wedge past a jaw and leave the table, and
	# balls vanish at the lip instead of a few centimetres early.
	pockets = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var a := Vector2((hl - CORNER_GAP) * sx, hw * sz)
			var b := Vector2(hl * sx, (hw - CORNER_GAP) * sz)
			var mid := (a + b) * 0.5
			var n := Vector2(sx, sz).normalized()
			pockets.append({
				"kind": "corner", "mid": mid, "n": n, "t": Vector2(-n.y, n.x),
				"half": (b - a).length() * 0.5 + R * 0.9 + CORNER_SHELF * 0.5,
				"shelf": CORNER_SHELF,
				"c": mid + n * (0.030 + CORNER_SHELF), "r": 0.072,
			})
	for sz: float in [-1.0, 1.0]:
		var n := Vector2(0.0, sz)
		pockets.append({
			"kind": "side", "mid": Vector2(0.0, (hw - R * 0.45) * sz), "n": n, "t": Vector2(1.0, 0.0),
			"half": SIDE_GAP + 0.004, "shelf": SIDE_SHELF,
			"c": Vector2(0.0, (hw + 0.026) * sz), "r": 0.070,
		})
	# order them: near corners, side pockets, far corners
	var ordered := [pockets[0], pockets[1], pockets[4], pockets[5], pockets[2], pockets[3]]
	pockets = ordered


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func ball(id: int) -> Ball:
	return balls[id]


static func copy_ball(src: Ball) -> Ball:
	var b := Ball.new()
	b.id = src.id
	b.pos = src.pos
	b.vel = src.vel
	b.spin = src.spin
	b.on_table = src.on_table
	b.pocket = src.pocket
	b.resting = src.resting
	return b


func snapshot() -> Array:
	var out: Array = []
	for b in balls:
		out.append(copy_ball(b))
	return out


func restore(snap: Array) -> void:
	for i in snap.size():
		balls[i] = copy_ball(snap[i])


func clone_sim(dt: float) -> PoolSim:
	var s := PoolSim.new()
	s.sub_dt = dt
	s.restore(snapshot())
	return s


func is_moving() -> bool:
	for b in balls:
		if b.on_table and not b.resting:
			return true
	return false


func balls_on_table() -> Array:
	var out: Array = []
	for b in balls:
		if b.on_table:
			out.append(b)
	return out


func rack(rng: RandomNumberGenerator) -> void:
	for b in balls:
		b.pos = Vector2.ZERO
		b.vel = Vector2.ZERO
		b.spin = Vector3.ZERO
		b.on_table = true
		b.pocket = -1
		b.resting = true

	var slots: Array = []
	var d := D * 1.004
	for row in 5:
		for j in row + 1:
			slots.append(Vector2(FOOT_X + float(row) * d * 0.8660254, (float(j) - float(row) * 0.5) * d))

	var solids := [2, 3, 4, 5, 6, 7]
	var stripes := [9, 10, 11, 12, 13, 14, 15]
	_shuffle(solids, rng)
	_shuffle(stripes, rng)

	var order: Array = []
	order.resize(15)
	order[0] = 1                                  # apex ball on the spot
	order[4] = EIGHT                              # centre of the third row
	if rng.randf() < 0.5:
		order[10] = solids.pop_back()
		order[14] = stripes.pop_back()
	else:
		order[10] = stripes.pop_back()
		order[14] = solids.pop_back()

	var rest := solids + stripes
	_shuffle(rest, rng)
	for i in 15:
		if order[i] == null:
			order[i] = rest.pop_back()

	for i in 15:
		var b := ball(order[i])
		b.pos = slots[i] + Vector2(rng.randfn(0.0, 0.0002), rng.randfn(0.0, 0.0002))

	ball(CUE).pos = Vector2(HEAD_X - 0.22, rng.randfn(0.0, 0.05))


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func place_cue(p: Vector2) -> void:
	var b := ball(CUE)
	b.pos = p
	b.vel = Vector2.ZERO
	b.spin = Vector3.ZERO
	b.on_table = true
	b.pocket = -1
	b.resting = true


# Is this a legal spot to drop the cue ball?
func spot_is_clear(p: Vector2, head_only: bool = false) -> bool:
	if absf(p.x) > HALF_LEN - R * 1.05 or absf(p.y) > HALF_WID - R * 1.05:
		return false
	if head_only and p.x > HEAD_X - R:
		return false
	for pk in pockets:
		if p.distance_to(pk.c) < pk.r + R:
			return false
	for b in balls:
		if b.id == CUE or not b.on_table:
			continue
		if p.distance_to(b.pos) < D * 1.06:
			return false
	return true


# ---------------------------------------------------------------------------
# Striking
# ---------------------------------------------------------------------------

# english.x = tip offset right of centre, english.y = above centre,
# both in units of ball radius. |english| beyond ~0.6 is a miscue.
func strike(dir: Vector2, speed: float, english: Vector2) -> void:
	var b := ball(CUE)
	var e := english
	if e.length() > 0.62:
		e = e.normalized() * 0.62
	var a := e.x * R
	var v := e.y * R
	var d := dir.normalized()
	b.vel = d * speed
	var f := Vector3(d.x, 0.0, d.y)
	var right := Vector3(-f.z, 0.0, f.x)
	var k := 5.0 * speed / (2.0 * R * R)
	b.spin = (Vector3.UP * a - right * v) * k
	b.resting = false
	if record_events:
		events.clear()


# ---------------------------------------------------------------------------
# Integration
# ---------------------------------------------------------------------------

func advance(dt: float) -> void:
	var steps := int(ceil(dt / sub_dt))
	steps = clampi(steps, 1, 400)
	var h := dt / float(steps)
	for _i in steps:
		_substep(h)


func run_to_rest(max_time := 14.0) -> Array:
	var t := 0.0
	while t < max_time and is_moving():
		_substep(sub_dt)
		t += sub_dt
	for b in balls:
		b.vel = Vector2.ZERO
		b.spin = Vector3.ZERO
		b.resting = true
	return events


func track(id: int, point: Vector2) -> void:
	track_id = id
	track_point = point
	track_miss = 0.0
	_track_best = 1.0e9
	_track_done = false


# Once the ball has touched a cushion its line means nothing for this
# measurement, so the reading stops there.
func _track_stop(id: int) -> void:
	if id == track_id:
		_track_done = true


func _track_step() -> void:
	if track_id < 0 or _track_done:
		return
	var b := ball(track_id)
	if not b.on_table:
		# it went in: no miss to correct
		track_miss = 0.0
		_track_done = true
		return
	if b.vel.length_squared() < 1.0e-4:
		return
	var d := b.pos.distance_to(track_point)
	if d < _track_best:
		_track_best = d
		track_miss = b.vel.normalized().cross(track_point - b.pos)
	elif _track_best < 0.35 and d > _track_best + 0.03:
		# past the pocket and moving away; whatever happens later is a rebound
		_track_done = true


func _substep(h: float) -> void:
	for b in balls:
		if not b.on_table or b.resting:
			continue
		_cloth(b, h)
		b.pos += b.vel * h
	_track_step()

	var n := balls.size()
	for i in n:
		var a: Ball = balls[i]
		if not a.on_table:
			continue
		for j in range(i + 1, n):
			var b: Ball = balls[j]
			if not b.on_table:
				continue
			if a.resting and b.resting:
				continue
			var dv := b.pos - a.pos
			var dsq := dv.length_squared()
			if dsq < D * D and dsq > 1e-12:
				_collide_balls(a, b, dv, sqrt(dsq))

	for b in balls:
		if not b.on_table or b.resting:
			continue
		if _pocket_check(b):
			continue
		_rails(b)


static func _planar(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _cloth(b: Ball, h: float) -> void:
	# velocity of the contact patch: v + w x (0, -R, 0)
	var u := Vector2(b.vel.x + R * b.spin.z, b.vel.y - R * b.spin.x)
	var ul := u.length()
	if ul > SLIDE_EPS:
		# sliding: friction opposes the contact patch, not the ball's path
		var uh := u / ul
		var need := MU_SLIDE * G * h
		var f := 1.0
		var budget := ul * 2.0 / 7.0
		if need > budget and need > 0.0:
			f = budget / need
		b.vel -= uh * (need * f)
		var k := 2.5 * MU_SLIDE * G * h * f / R
		b.spin.x += k * uh.y
		b.spin.z -= k * uh.x
	else:
		# rolling: light resistance, and the roll constraint is enforced
		var sp := b.vel.length()
		if sp > 0.0:
			var dec := MU_ROLL * G * h
			if dec >= sp:
				b.vel = Vector2.ZERO
			else:
				b.vel -= b.vel * (dec / sp)
		b.spin.x = b.vel.y / R
		b.spin.z = -b.vel.x / R

	var sd := 2.5 * MU_SPIN * G * h / R
	if absf(b.spin.y) <= sd:
		b.spin.y = 0.0
	else:
		b.spin.y -= signf(b.spin.y) * sd

	if b.vel.length() < STOP_V and absf(b.spin.y) < STOP_W:
		var u2 := Vector2(b.vel.x + R * b.spin.z, b.vel.y - R * b.spin.x)
		if u2.length() < SLIDE_EPS * 2.0:
			b.vel = Vector2.ZERO
			b.spin = Vector3.ZERO
			b.resting = true


func _collide_balls(a: Ball, b: Ball, dv: Vector2, dist: float) -> void:
	var n := dv / dist
	var overlap := D - dist
	if overlap > 0.0:
		a.pos -= n * (overlap * 0.5)
		b.pos += n * (overlap * 0.5)

	var rel := b.vel - a.vel
	var vn := rel.dot(n)
	if vn > 0.0:
		return

	var t := Vector2(-n.y, n.x)
	var ra := Vector3(n.x * R, 0.0, n.y * R)
	var rb := -ra
	var va_c := a.vel + _planar(a.spin.cross(ra))
	var vb_c := b.vel + _planar(b.spin.cross(rb))
	var vt := (vb_c - va_c).dot(t)

	var jn := -(1.0 + E_BALL) * vn * M * 0.5
	a.vel -= n * (jn / M)
	b.vel += n * (jn / M)

	# tangential impulse: collision-induced throw and spin transfer
	var jt := clampf(-vt * M / 7.0, -MU_BALL * jn, MU_BALL * jn)
	a.vel -= t * (jt / M)
	b.vel += t * (jt / M)
	var ft := Vector3(t.x, 0.0, t.y) * jt
	a.spin -= ra.cross(ft) * INV_I
	b.spin += rb.cross(ft) * INV_I

	a.resting = false
	b.resting = false
	if record_events:
		events.append({"type": "hit", "a": a.id, "b": b.id, "speed": absf(vn)})


func _rails(b: Ball) -> void:
	for c in cushions:
		var p1: Vector2 = c.p1
		var p2: Vector2 = c.p2
		var seg := p2 - p1
		var l2 := seg.length_squared()
		var t := (b.pos - p1).dot(seg) / l2
		if t <= 0.0 or t >= 1.0:
			continue
		var cp := p1 + seg * t
		var off := b.pos - cp
		if off.length() >= R:
			continue
		var n: Vector2 = c.n
		b.pos = cp + n * R
		if b.vel.dot(n) < 0.0:
			var hit_speed := -b.vel.dot(n)
			_rail_impulse(b, n, E_RAIL)
			_track_stop(b.id)
			if record_events:
				events.append({"type": "rail", "ball": b.id, "speed": hit_speed})


func _rail_impulse(b: Ball, n: Vector2, e: float) -> void:
	var t := Vector2(-n.y, n.x)
	var r3 := Vector3(-n.x * RAIL_OUT, RAIL_UP, -n.y * RAIL_OUT)
	var vc := b.vel + _planar(b.spin.cross(r3))
	var vn := b.vel.dot(n)
	var jn := -(1.0 + e) * M * vn
	var vt := vc.dot(t)
	var jt := clampf(-vt * M * 2.0 / 7.0, -MU_RAIL * jn, MU_RAIL * jn)
	b.vel += n * (jn / M) + t * (jt / M)
	var imp := Vector3(t.x, 0.0, t.y) * jt + Vector3(n.x, 0.0, n.y) * (jn * RAIL_SPIN_GAIN)
	b.spin += r3.cross(imp) * INV_I
	b.resting = false


func _pocket_check(b: Ball) -> bool:
	for i in pockets.size():
		var pk = pockets[i]
		var d: Vector2 = b.pos - pk.mid
		var n: Vector2 = pk.n
		var t: Vector2 = pk.t
		var caught := d.dot(n) > float(pk.shelf) and absf(d.dot(t)) < float(pk.half)
		if not caught:
			# safety net: a ball shoved clean off the slate in a pile-up is
			# treated as pocketed rather than left rolling across the bar
			if absf(b.pos.x) > HALF_LEN + 0.05 or absf(b.pos.y) > HALF_WID + 0.05:
				caught = _nearest_pocket(b.pos) == i
		if caught:
			b.on_table = false
			b.pocket = i
			b.vel = Vector2.ZERO
			b.spin = Vector3.ZERO
			b.resting = true
			if record_events:
				events.append({"type": "pot", "ball": b.id, "pocket": i})
			return true
	return false


# ---------------------------------------------------------------------------
# Queries used by aiming, the AI and the HUD
# ---------------------------------------------------------------------------

# Where does the cue ball first make contact along this line?
func trace(from: Vector2, dir: Vector2, ignore_id := -1) -> Dictionary:
	var best := 1e9
	var hit_ball := -1
	for b in balls:
		if not b.on_table or b.id == CUE or b.id == ignore_id:
			continue
		var rel := b.pos - from
		var proj := rel.dot(dir)
		if proj <= 0.0:
			continue
		var perp2 := rel.length_squared() - proj * proj
		var rr := D * D
		if perp2 >= rr:
			continue
		var t := proj - sqrt(rr - perp2)
		if t < best:
			best = t
			hit_ball = b.id

	var rail_t := 1e9
	var rail_n := Vector2.ZERO
	for c in cushions:
		var n: Vector2 = c.n
		var p1: Vector2 = c.p1
		var p2: Vector2 = c.p2
		var denom := dir.dot(n)
		if denom >= -1e-6:
			continue
		var t := ((p1 - from).dot(n) + R) / denom
		if t <= 0.0 or t >= rail_t:
			continue
		var p := from + dir * t
		var seg := p2 - p1
		var u := (p - p1).dot(seg) / seg.length_squared()
		if u < 0.0 or u > 1.0:
			continue
		rail_t = t
		rail_n = n

	if hit_ball >= 0 and best < rail_t:
		return {"kind": "ball", "t": best, "point": from + dir * best, "ball": hit_ball}
	if rail_t < 1e8:
		return {"kind": "rail", "t": rail_t, "point": from + dir * rail_t, "normal": rail_n}
	return {"kind": "none", "t": 0.0, "point": from}


# Is the straight path from a to b free of other balls?
func path_clear(a: Vector2, b: Vector2, ignore: Array, slack := 0.0) -> bool:
	var seg := b - a
	var len2 := seg.length_squared()
	if len2 < 1e-9:
		return true
	for ob in balls:
		if not ob.on_table or ignore.has(ob.id):
			continue
		var t := clampf((ob.pos - a).dot(seg) / len2, 0.0, 1.0)
		var d := (a + seg * t).distance_to(ob.pos)
		if d < D - slack:
			return false
	return true


func _nearest_pocket(p: Vector2) -> int:
	var best := 0
	var bd := 1e9
	for i in pockets.size():
		var c: Vector2 = pockets[i].c
		var d := p.distance_squared_to(c)
		if d < bd:
			bd = d
			best = i
	return best


func pocket_aim(index: int) -> Vector2:
	var pk = pockets[index]
	var c: Vector2 = pk.c
	# aim a little inside the mouth so the ball is swallowed rather than jawed
	var inward := (Vector2.ZERO - c).normalized()
	return c + inward * 0.024
