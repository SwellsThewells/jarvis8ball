class_name PoolTableView
extends Node3D

# Visual table. Local origin sits on the cloth, so a ball centre is at y = R.
# Cushions and pocket facings are placed from the same numbers the physics
# uses, so what you see is what you hit.

const HL := PoolSim.HALF_LEN
const HW := PoolSim.HALF_WID
const R := PoolSim.R

const CUSHION_H := 0.034
const CUSHION_D := 0.055
const CAP_W := 0.118
const CAP_H := 0.026
const CAP_TOP := 0.058

# WPA equipment spec: 29.25"-31" from the floor to the top of the rail.
# 30.5" here, so the cloth sits CAP_TOP below that.
const RAIL_HEIGHT := 0.7747
const BED_Y := RAIL_HEIGHT - CAP_TOP
# WPA: sights centred 3-11/16" from the cushion nose.
const SIGHT_FROM_NOSE := 0.0937

# matched to the photographed felt the cloth is made from
const CLOTH := Color("0d3b22")
const RAIL_WOOD := Color("2a1c15")
const CUSHION_COL := Color("0b341e")
const LEATHER := Color("140e0a")

var ball_nodes: Array = []
var ball_spin: Array = []
# the cue ball is held just off the cloth while it is in your hand
var cue_lift := 0.0
# or, while somebody else is carrying it, in the room where their hand is
var cue_hand: Variant = null
var pockets_ref: Array = []
var _tray_count := {"near": 0, "far": 0}
var _trayed: Dictionary = {}
var _mouth_arcs: Array = []


func build(sim: PoolSim) -> void:
	pockets_ref = sim.pockets
	_build_bed(sim)
	_build_cushions(sim)
	_build_rail_ring(sim)
	_build_sights()
	_build_pockets(sim)
	_build_frame()
	_build_balls()
	_build_pocket_glows(sim)
	_bake_ball_faces()


# ---------------------------------------------------------------------------
# Calling the 8: a blue ring of light round the pocket you nominate, and a
# fainter one round the pocket you are looking at.
# ---------------------------------------------------------------------------

var _glow_rings: Array = []
var _glow_lights: Array = []
var _glow_level: Array = [0, 0, 0, 0, 0, 0]
var _glow_t := 0.0
const GLOW_BLUE := Color(0.25, 0.62, 1.0)


func _build_pocket_glows(sim: PoolSim) -> void:
	for i in sim.pockets.size():
		var pk = sim.pockets[i]
		var r := mouth_radius(pk)
		var t := TorusMesh.new()
		t.inner_radius = r - 0.006
		t.outer_radius = r + 0.004
		t.rings = 48
		t.ring_segments = 10
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = GLOW_BLUE
		m.emission_enabled = true
		m.emission = GLOW_BLUE
		var ring := MeshInstance3D.new()
		ring.mesh = t
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(pk.c.x, 0.004, pk.c.y)
		ring.scale = Vector3(1.0, 0.35, 1.0)
		ring.visible = false
		add_child(ring)
		_glow_rings.append(ring)
		var light := OmniLight3D.new()
		light.light_color = GLOW_BLUE
		light.omni_range = 0.34
		light.position = Vector3(pk.c.x, 0.03, pk.c.y)
		light.visible = false
		add_child(light)
		_glow_lights.append(light)


# 0 off, 1 looked at, 2 called
func set_pocket_glow(index: int, level: int) -> void:
	if index < 0 or index >= _glow_level.size():
		return
	_glow_level[index] = level


func clear_pocket_glows() -> void:
	for i in _glow_level.size():
		_glow_level[i] = 0


func _process(delta: float) -> void:
	_glow_t += delta
	for i in _glow_rings.size():
		var lvl: int = _glow_level[i]
		var ring: MeshInstance3D = _glow_rings[i]
		var light: OmniLight3D = _glow_lights[i]
		ring.visible = lvl > 0
		light.visible = lvl > 1
		if lvl == 0:
			continue
		var m: StandardMaterial3D = ring.material_override
		if lvl == 1:
			m.albedo_color = Color(GLOW_BLUE.r, GLOW_BLUE.g, GLOW_BLUE.b, 0.35)
			m.emission_energy_multiplier = 0.8
		else:
			var pulse := 0.75 + 0.25 * sin(_glow_t * 4.0)
			m.albedo_color = Color(GLOW_BLUE.r, GLOW_BLUE.g, GLOW_BLUE.b, 1.0)
			m.emission_energy_multiplier = 3.5 * pulse
			light.light_energy = 1.6 * pulse


# ---------------------------------------------------------------------------

func _box(size: Vector3, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	add_child(mi)
	return mi


func _cyl(rt: float, rb: float, h: float, pos: Vector3, m: Material, segs := 20) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = rt
	mesh.bottom_radius = rb
	mesh.height = h
	mesh.radial_segments = segs
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	add_child(mi)
	return mi


# The bed is a polygon with the pockets cut out of it, not a box with dark
# discs laid on top. That is the difference between a hole and a sticker.
func _build_bed(sim: PoolSim) -> void:
	# the cloth shader is two-sided: triangulation winding is not guaranteed,
	# and an invisible bed is worse than a few extra triangles
	var m := PoolArt.cloth_mat(CLOTH)

	# the cloth stops under the cushions, where the rail covers its edge; the
	# pocket circles have to breach that edge or clipping leaves a floating hole
	var ex := HL + CUSHION_D
	var ez := HW + CUSHION_D
	var polys: Array = [PackedVector2Array([
		Vector2(-ex, -ez), Vector2(ex, -ez), Vector2(ex, ez), Vector2(-ex, ez)])]
	for pk in sim.pockets:
		var hole := _circle_poly(pk.c, mouth_radius(pk), 30)
		var next_polys: Array = []
		for poly: PackedVector2Array in polys:
			next_polys.append_array(Geometry2D.clip_polygons(poly, hole))
		polys = next_polys

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly: PackedVector2Array in polys:
		var tri := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tri.size(), 3):
			var q0: Vector2 = poly[tri[i]]
			var q1: Vector2 = poly[tri[i + 1]]
			var q2: Vector2 = poly[tri[i + 2]]
			_tri(st, Vector3(q0.x, 0.0, q0.y), Vector3(q1.x, 0.0, q1.y), Vector3(q2.x, 0.0, q2.y),
				Vector3.UP, Vector3.UP, Vector3.UP, q0 * 1.55, q1 * 1.55, q2 * 1.55)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.name = "Cloth"
	add_child(mi)

	# the slate carries the same holes, or it would cap every pocket from below
	var slate := PoolArt.mat(Color("4c4842"), 0.95)
	slate.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly: PackedVector2Array in polys:
		var tri := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tri.size(), 3):
			var q0: Vector2 = poly[tri[i]]
			var q1: Vector2 = poly[tri[i + 1]]
			var q2: Vector2 = poly[tri[i + 2]]
			_tri(sst, Vector3(q0.x, -0.026, q0.y), Vector3(q1.x, -0.026, q1.y), Vector3(q2.x, -0.026, q2.y),
				Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, q0 * 1.2, q1 * 1.2, q2 * 1.2)
	# and an edge band so the slate reads as a slab, not a sheet. The outward
	# side of each edge depends on which way round the clipper returned it.
	for poly: PackedVector2Array in polys:
		var ccw := _signed_area(poly) > 0.0
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var e := (b - a).normalized()
			var nrm := Vector3(e.y, 0.0, -e.x) * (1.0 if ccw else -1.0)
			_quad(sst, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y),
				Vector3(b.x, -0.026, b.y), Vector3(a.x, -0.026, a.y), nrm)
	var smi := MeshInstance3D.new()
	smi.mesh = sst.commit()
	smi.material_override = slate
	smi.name = "Slate"
	add_child(smi)

	# foot spot
	var chalk := PoolArt.mat(Color("0d332f"), 0.9)
	_cyl(0.009, 0.009, 0.001, Vector3(PoolSim.FOOT_X, 0.0012, 0.0), chalk, 16)


func mouth_radius(pk) -> float:
	return float(pk.r) + 0.004


func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# Every custom triangle goes through here. Godot treats clockwise (seen from
# the front) as the front face; the builders below were written without
# caring which way round they went, which left parts of the table inside out
# and lit from the wrong side. This turns each triangle to face its normal.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)


func _circle_poly(c: Vector2, r: float, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# A real cushion is not a box: it noses out over the cloth at about the height
# of the ball's equator and slopes back down behind it, and it is wrapped in
# the same cloth as the bed. Each run of cushion is one solid with its two
# jaws, mitred where the cushion turns into the angled cut at a pocket. Built
# as a straight prism with a separate block for each jaw, the two overlapped
# and their tops fought each other at every pocket.
const NOSE_H := 0.0363       # 63.5% of a ball diameter
const TOP_H := 0.0415
const TOP_IN := 0.006        # the flat top starts just behind the nose
const FOOT_IN := 0.026       # where the slope under the nose meets the cloth


func _build_cushions(sim: PoolSim) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in sim.cushions:
		if c.get("facing", false):
			continue
		_cushion_run(st, sim, c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = PoolArt.cloth_mat(CUSHION_COL, 0.4)
	mi.name = "Cushions"
	add_child(mi)


func _facing_at(sim: PoolSim, tip: Vector2) -> Dictionary:
	for fc in sim.facings:
		if (fc.p1 as Vector2).distance_to(tip) < 1.0e-5:
			return fc
	return {}


func _pocket_near(sim: PoolSim, p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1.0e9
	for pk in sim.pockets:
		var d: float = (pk.c as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = pk
	return best


# Where a jaw ends, and which way its end is cut. A corner jaw runs back until
# it reaches the rail, and is cut along the rail. A side jaw closes in on its
# partner, so it stops at the length of the real facing and is cut straight
# back to the rail, leaving the mouth open between the two.
func _jaw_end(sim: PoolSim, tip: Vector2, fc: Dictionary, n: Vector2, body: Vector2) -> Array:
	if fc.is_empty():
		return [tip, -n]
	var d: Vector2 = ((fc.p2 as Vector2) - tip).normalized()
	var t_back := 1.0e9
	var dn := d.dot(n)
	if dn < -1.0e-3:
		t_back = CUSHION_D / -dn
	var t_axis := 1.0e9
	var pk := _pocket_near(sim, tip)
	var ta: Vector2 = pk.t
	var along := d.dot(ta)
	if absf(along) > 1.0e-3:
		var ax: float = -(tip - (pk.c as Vector2)).dot(ta) / along
		if ax > 0.0:
			t_axis = ax
	if t_back <= t_axis:
		# along the rail, towards the body of the cushion
		var u := Vector2(-n.y, n.x)
		if u.dot(body - tip) < 0.0:
			u = -u
		return [tip + d * t_back, u]
	var length := minf((fc.p2 as Vector2).distance_to(tip), t_axis * 0.8)
	return [tip + d * length, -n]


# How far a vertex moves, per metre of depth, to stay that deep behind both
# of the faces that meet at it.
func _miter(a: Vector2, b: Vector2) -> Vector2:
	var m := (a + b).normalized()
	return -m / maxf(m.dot(a), 0.25)


func _cushion_run(st: SurfaceTool, sim: PoolSim, c: Dictionary) -> void:
	var p1: Vector2 = c.p1
	var p2: Vector2 = c.p2
	var n: Vector2 = c.n
	var fa := _facing_at(sim, p1)
	var fb := _facing_at(sim, p2)
	var fna: Vector2 = fa.n if not fa.is_empty() else (p1 - p2).normalized()
	var fnb: Vector2 = fb.n if not fb.is_empty() else (p2 - p1).normalized()
	var body := (p1 + p2) * 0.5 - n * (CUSHION_D * 0.5)
	var end_a := _jaw_end(sim, p1, fa, n, body)
	var end_b := _jaw_end(sim, p2, fb, n, body)
	var far_a: Vector2 = end_a[0]
	var far_b: Vector2 = end_b[0]
	var cut_a: Vector2 = end_a[1]
	var cut_b: Vector2 = end_b[1]

	var line: Array[Vector2] = [far_a, p1, p2, far_b]
	var seg_n: Array[Vector2] = [fna, n, fnb]
	# at the jaw ends, depth is measured along the cut rather than square to
	# the facing, so the whole end lies in one flat plane
	var dirs: Array[Vector2] = [cut_a / maxf(cut_a.dot(-fna), 0.2), _miter(fna, n),
		_miter(n, fnb), cut_b / maxf(cut_b.dot(-fnb), 0.2)]

	# nothing may reach behind the rail line
	var behind := func(p: Vector2) -> Vector2:
		var depth := -(p - p1).dot(n)
		if depth > CUSHION_D:
			return p + n * (depth - CUSHION_D)
		return p
	var back := func(p: Vector2) -> Vector2:
		return p - n * ((p - p1).dot(n) + CUSHION_D)

	var nose: Array[Vector3] = []
	var top: Array[Vector3] = []
	var foot: Array[Vector3] = []
	for i in line.size():
		var v: Vector2 = line[i]
		var t2: Vector2 = behind.call(v + dirs[i] * TOP_IN)
		var f2: Vector2 = behind.call(v + dirs[i] * FOOT_IN)
		nose.append(Vector3(v.x, NOSE_H, v.y))
		top.append(Vector3(t2.x, TOP_H, t2.y))
		foot.append(Vector3(f2.x, 0.0, f2.y))

	# the rounded nose and the undercut beneath it, along the run and both jaws
	var up_a := Vector2(-(NOSE_H - TOP_H), TOP_IN).normalized()   # (out, up) in profile terms
	var up_b := Vector2(NOSE_H, FOOT_IN).normalized()
	for i in seg_n.size():
		if line[i].distance_to(line[i + 1]) < 1.0e-4:
			continue
		var sn: Vector2 = seg_n[i]
		var na := Vector3(sn.x * up_a.x, up_a.y, sn.y * up_a.x).normalized()
		var nb := Vector3(sn.x * up_b.x, -up_b.y, sn.y * up_b.x).normalized()
		_quad_n(st, top[i], top[i + 1], nose[i + 1], nose[i], na)
		_quad_n(st, nose[i], nose[i + 1], foot[i + 1], foot[i], nb)

	# flat top, from just behind the nose back to the rail
	var last := line.size() - 1
	var ba: Vector2 = back.call(Vector2(top[0].x, top[0].z))
	var bb: Vector2 = back.call(Vector2(top[last].x, top[last].z))
	var outline := PackedVector2Array()
	for p in top:
		outline.append(Vector2(p.x, p.z))
	outline.append(bb)
	outline.append(ba)
	_fill(st, _dedupe(outline), TOP_H, Vector3.UP)

	# back wall and the two ends, so nothing is hollow from any angle
	var ba_top := Vector3(ba.x, TOP_H, ba.y)
	var bb_top := Vector3(bb.x, TOP_H, bb.y)
	var ba_bot := Vector3(ba.x, 0.0, ba.y)
	var bb_bot := Vector3(bb.x, 0.0, bb.y)
	var nb3 := Vector3(-n.x, 0.0, -n.y)
	_quad_n(st, ba_top, bb_top, bb_bot, ba_bot, nb3)
	var cap_a := Vector2(-cut_a.y, cut_a.x)
	if cap_a.dot(far_a - body) < 0.0:
		cap_a = -cap_a
	var cap_b := Vector2(-cut_b.y, cut_b.x)
	if cap_b.dot(far_b - body) < 0.0:
		cap_b = -cap_b
	_fan(st, [nose[0], top[0], ba_top, ba_bot, foot[0]], Vector3(cap_a.x, 0.0, cap_a.y))
	_fan(st, [nose[last], top[last], bb_top, bb_bot, foot[last]], Vector3(cap_b.x, 0.0, cap_b.y))


func _dedupe(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 1.0e-5:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 1.0e-5:
		out.remove_at(out.size() - 1)
	return out


func _quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	_tri(st, a, b, c, nrm, nrm, nrm)
	_tri(st, a, c, d, nrm, nrm, nrm)


func _fan(st: SurfaceTool, pts: Array, nrm: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		_tri(st, pts[0], pts[i], pts[i + 1], nrm, nrm, nrm)


# A flat polygon at height y. Falls back to a fan if the outline is too
# degenerate for the triangulator, rather than leaving a hole.
func _fill(st: SurfaceTool, poly: PackedVector2Array, y: float, nrm: Vector3) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		for i in range(1, poly.size() - 1):
			_tri(st, Vector3(poly[0].x, y, poly[0].y), Vector3(poly[i].x, y, poly[i].y),
				Vector3(poly[i + 1].x, y, poly[i + 1].y), nrm, nrm, nrm)
		return
	for i in range(0, tri.size(), 3):
		var a: Vector2 = poly[tri[i]]
		var b: Vector2 = poly[tri[i + 1]]
		var c: Vector2 = poly[tri[i + 2]]
		_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), nrm, nrm, nrm,
			a * 1.4, b * 1.4, c * 1.4)


func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, na, nb, nb, ua, ub, uc)
	_tri(st, a, c, d, na, nb, na, ua, uc, ud)


# The rail is one continuous ring of wood with the pockets cut out of it, so
# the corners mitre cleanly into the pocket mouths. Where it meets the playing
# area, the cloth comes up over the cushion to the edge of the wood; round the
# pockets the cut is lined with leather, the way a real pocket is.
func _build_rail_ring(sim: PoolSim) -> void:
	var wood := PoolArt.wood_mat(RAIL_WOOD, 0.42, 0.26, 0.05, Vector3.RIGHT, true)
	PoolArt.set_clearcoat(wood, 0.32, 0.28)

	var zi := HW + CUSHION_D - 0.002
	var xi := HL + CUSHION_D - 0.002

	var order := [1, 3, 5, 4, 2, 0]
	var inner := PackedVector2Array()
	var arc_edge: Array[bool] = []
	_mouth_arcs.resize(6)
	for i in order.size():
		var pk = sim.pockets[order[i]]
		var prev = sim.pockets[order[(i + order.size() - 1) % order.size()]]
		var nxt = sim.pockets[order[(i + 1) % order.size()]]
		var rr: float = mouth_radius(pk)
		var a_in := _meet(pk.c, rr, prev.c, xi, zi)
		var a_out := _meet(pk.c, rr, nxt.c, xi, zi)
		var arc := _arc(pk.c, rr, a_in, a_out)
		_mouth_arcs[order[i]] = arc
		for k in arc.size():
			inner.append(arc[k])
			arc_edge.append(k < arc.size() - 1)

	_ring_mesh(inner, arc_edge, CAP_TOP, -0.03, wood)


# Where the circle around a pocket meets the straight rail line running
# towards the neighbouring pocket, as an angle on that circle.
func _meet(c: Vector2, r: float, other: Vector2, xi: float, zi: float) -> float:
	var vertical: bool = absf(c.x - other.x) < absf(c.y - other.y)
	if vertical:
		var line_x: float = xi * signf(c.x)
		var dz: float = sqrt(maxf(r * r - pow(line_x - c.x, 2.0), 0.0))
		var z: float = c.y + (dz if other.y > c.y else -dz)
		return (Vector2(line_x, z) - c).angle()
	var line_z: float = zi * signf(c.y)
	var dx: float = sqrt(maxf(r * r - pow(line_z - c.y, 2.0), 0.0))
	var x: float = c.x + (dx if other.x > c.x else -dx)
	return (Vector2(x, line_z) - c).angle()


# The arc that bulges away from the table, i.e. the one that bites the pocket
# opening out of the rail rather than the one that would cover it.
func _arc(c: Vector2, r: float, a0: float, a1: float) -> Array[Vector2]:
	var sweep := wrapf(a1 - a0, -TAU, 0.0)
	var mid_out := c + Vector2(cos(a0 + sweep * 0.5), sin(a0 + sweep * 0.5)) * r
	var alt := wrapf(a1 - a0, 0.0, TAU)
	var mid_alt := c + Vector2(cos(a0 + alt * 0.5), sin(a0 + alt * 0.5)) * r
	if mid_alt.length() > mid_out.length():
		sweep = alt
	var steps := maxi(6, int(absf(sweep) / 0.09))
	var out: Array[Vector2] = []
	for i in steps + 1:
		var a: float = a0 + sweep * (float(i) / float(steps))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _rail_outline() -> PackedVector2Array:
	var ox := HL + CUSHION_D + CAP_W
	var oz := HW + CUSHION_D + CAP_W
	var k := 0.15
	return PackedVector2Array([
		Vector2(ox, -oz + k), Vector2(ox, oz - k), Vector2(ox - k, oz), Vector2(-ox + k, oz),
		Vector2(-ox, oz - k), Vector2(-ox, -oz + k), Vector2(-ox + k, -oz), Vector2(ox - k, -oz),
	])


# The flat of the rail: the outline with the playing area cut out of it. The
# ring is cut into quarters first so each piece is a plain polygon the
# triangulator can take; mapping the inner edge straight out to the outer one
# instead folded the top back on itself behind every corner pocket.
func _ring_fill(st: SurfaceTool, outer: PackedVector2Array, hole: PackedVector2Array,
		y: float, nrm: Vector3) -> void:
	var big := 9.0
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			var quad := PackedVector2Array([Vector2(0, 0), Vector2(big * sx, 0),
				Vector2(big * sx, big * sz), Vector2(0, big * sz)])
			# the hole always crosses the cut lines, so no piece has a hole in it
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(quad, outer):
				for part: PackedVector2Array in Geometry2D.clip_polygons(piece, hole):
					_fill(st, part, y, nrm)


func _ring_mesh(inner: PackedVector2Array, arc_edge: Array[bool], top: float, bottom: float,
		wood: Material) -> void:
	var n := inner.size()
	var ccw := _signed_area(inner) > 0.0
	# edge normals, facing out of the wood into the table and the pockets
	var en: Array[Vector2] = []
	for i in n:
		var e := (inner[(i + 1) % n] - inner[i]).normalized()
		var left := Vector2(-e.y, e.x)
		en.append(left if ccw else -left)
	var vn: Array[Vector2] = []
	for i in n:
		vn.append((en[i] + en[(i + n - 1) % n]).normalized())

	var bevel := 0.007
	var chamfer := PackedVector2Array()
	for i in n:
		chamfer.append(inner[i] - vn[i] * (bevel / maxf(vn[i].dot(en[i]), 0.5)))

	var st_wood := SurfaceTool.new()
	st_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_cloth := SurfaceTool.new()
	st_cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_leather := SurfaceTool.new()
	st_leather.begin(Mesh.PRIMITIVE_TRIANGLES)

	var outer := _rail_outline()
	_ring_fill(st_wood, outer, chamfer, top, Vector3.UP)
	_ring_fill(st_wood, outer, inner, bottom, Vector3.DOWN)
	for i in outer.size():
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[(i + 1) % outer.size()]
		var e := (b - a).normalized()
		var no := Vector3(e.y, 0.0, -e.x)
		if no.dot(Vector3(a.x + b.x, 0.0, a.y + b.y)) < 0.0:
			no = -no
		_quad(st_wood, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y),
			Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y), no)

	# the inside edge: a small rounded-over chamfer, then the wall down
	for i in n:
		var j := (i + 1) % n
		var st: SurfaceTool = st_leather if arc_edge[i] else st_cloth
		# smooth round a pocket, crisp where an arc meets a straight run
		var sa: Vector2 = vn[i] if en[i].dot(en[(i + n - 1) % n]) > 0.8 else en[i]
		var sb: Vector2 = vn[j] if en[i].dot(en[j]) > 0.8 else en[i]
		var wa := Vector3(sa.x, 0.0, sa.y)
		var wb := Vector3(sb.x, 0.0, sb.y)
		var ba := (wa + Vector3.UP).normalized()
		var bb := (wb + Vector3.UP).normalized()
		var i0 := inner[i]
		var i1 := inner[j]
		var c0 := chamfer[i]
		var c1 := chamfer[j]
		_quad_uv(st, Vector3(i0.x, top - bevel, i0.y), Vector3(i1.x, top - bevel, i1.y),
			Vector3(c1.x, top, c1.y), Vector3(c0.x, top, c0.y), ba, bb,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad_uv(st, Vector3(i0.x, bottom, i0.y), Vector3(i1.x, bottom, i1.y),
			Vector3(i1.x, top - bevel, i1.y), Vector3(i0.x, top - bevel, i0.y), wa, wb,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)

	var leather := PoolArt.mat(LEATHER, 0.55, 0.0)
	leather.cull_mode = BaseMaterial3D.CULL_DISABLED
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.25
	leather.clearcoat_roughness = 0.5
	var parts := [[st_wood, wood, "Rails"], [st_cloth, PoolArt.cloth_mat(CUSHION_COL, 0.4), "RailCloth"],
		[st_leather, leather, "PocketLiners"]]
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = (part[0] as SurfaceTool).commit()
		mi.material_override = part[1]
		mi.name = part[2]
		add_child(mi)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	var uv := func(v: Vector3) -> Vector2:
		return Vector2(v.x * 1.4 + v.z * 0.25, v.z * 1.4 + v.y * 2.0)
	_tri(st, a, b, c, nrm, nrm, nrm, uv.call(a), uv.call(b), uv.call(c))
	_tri(st, a, c, d, nrm, nrm, nrm, uv.call(a), uv.call(c), uv.call(d))


func _build_sights() -> void:
	var ivory := PoolArt.mat(Color("ddd2b4"), 0.35)
	var mid_line := HW + SIGHT_FROM_NOSE
	for x: float in [-0.9525, -0.635, -0.3175, 0.3175, 0.635, 0.9525]:
		for s: float in [1.0, -1.0]:
			_box(Vector3(0.019, 0.003, 0.019), Vector3(x, CAP_TOP + 0.0006, mid_line * s), ivory, PI * 0.25)
	var mid_x := HL + SIGHT_FROM_NOSE
	for z: float in [-0.3175, 0.3175]:
		for s: float in [1.0, -1.0]:
			_box(Vector3(0.019, 0.003, 0.019), Vector3(mid_x * s, CAP_TOP + 0.0006, z), ivory, PI * 0.25)


# A pocket is the hole, a leather throat under it, and the bag it drops into.
func _build_pockets(sim: PoolSim) -> void:
	var leather := PoolArt.mat(LEATHER, 0.62, 0.0)
	leather.cull_mode = BaseMaterial3D.CULL_DISABLED
	var deep := PoolArt.mat(Color("070605"), 0.95)
	deep.cull_mode = BaseMaterial3D.CULL_DISABLED

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 30
	for pk in sim.pockets:
		var c: Vector2 = pk.c
		var r := mouth_radius(pk)
		# collar just under the cloth, then the throat drawing in as it falls
		var rings := [
			{"r": r, "y": 0.0},
			{"r": r * 0.97, "y": -0.030},
			{"r": r * 0.80, "y": -0.085},
			{"r": r * 0.62, "y": -0.150},
			{"r": r * 0.55, "y": -0.205},
		]
		for level in rings.size() - 1:
			var r0: float = float(rings[level].r)
			var r1: float = float(rings[level + 1].r)
			var y0: float = float(rings[level].y)
			var y1: float = float(rings[level + 1].y)
			for i in segs:
				var a0 := TAU * float(i) / float(segs)
				var a1 := TAU * float(i + 1) / float(segs)
				var d0 := Vector2(cos(a0), sin(a0))
				var d1 := Vector2(cos(a1), sin(a1))
				var n0 := Vector3(-d0.x, 0.25, -d0.y).normalized()
				_quad(st,
					Vector3(c.x + d0.x * r0, y0, c.y + d0.y * r0),
					Vector3(c.x + d1.x * r0, y0, c.y + d1.y * r0),
					Vector3(c.x + d1.x * r1, y1, c.y + d1.y * r1),
					Vector3(c.x + d0.x * r1, y1, c.y + d0.y * r1), n0)
		# bottom of the bag
		var rb: float = r * 0.55
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			_quad(st,
				Vector3(c.x + cos(a0) * rb, -0.205, c.y + sin(a0) * rb),
				Vector3(c.x + cos(a1) * rb, -0.205, c.y + sin(a1) * rb),
				Vector3(c.x, -0.225, c.y), Vector3(c.x, -0.225, c.y), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = leather
	mi.name = "Pockets"
	add_child(mi)

	# a darker inner sleeve so the throat does not read as a lit tube
	for pk in sim.pockets:
		var c2: Vector2 = pk.c
		_cyl(mouth_radius(pk) * 0.52, mouth_radius(pk) * 0.52, 0.10,
			Vector3(c2.x, -0.17, c2.y), deep, 24)


func _build_frame() -> void:
	var cabinet := PoolArt.wood_mat(Color("2b170c"), 0.34, 0.28, 0.07)
	PoolArt.set_clearcoat(cabinet, 0.45, 0.2)
	var dark := PoolArt.wood_mat(Color("1d0f07"), 0.45, 0.26, 0.06, Vector3.UP)
	var brass := PoolArt.mat(Color("7a5f26"), 0.26, 0.9)

	var ox := HL + CUSHION_D + CAP_W
	var oz := HW + CUSHION_D + CAP_W

	# The cabinet follows the rail's own outline, chamfered corners and all,
	# set in so the rail reads as an overhang, and it runs right up to the
	# rail's underside. As four boxes it stopped short of the rail, leaving a
	# slot you could see the cloth through, and its square corners stuck out
	# past the rail's cut ones.
	var inset := 0.028
	var body_h := 0.225
	var body_y := -0.03 - body_h * 0.5
	var bottom := body_y - body_h * 0.5
	_octagon_band(ox - inset, oz - inset, -0.03, bottom, cabinet, true)
	# a brass bead along the bottom of the cabinet
	_octagon_band(ox - inset + 0.0035, oz - inset + 0.0035, bottom + 0.008, bottom, brass, true)

	# four legs: shoulder, tapered post, foot
	var floor_y := -BED_Y
	var top_y := body_y - body_h * 0.5
	var lx := ox - 0.30
	var lz := oz - 0.30
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			var px := lx * sx
			var pz := lz * sz
			_box(Vector3(0.225, 0.075, 0.225), Vector3(px, top_y - 0.038, pz), cabinet)
			_leg(Vector3(px, top_y - 0.072, pz), (top_y - 0.072) - floor_y, dark)
			_cyl(0.074, 0.074, 0.014, Vector3(px, top_y - 0.082, pz), brass, 24)
			_cyl(0.097, 0.097, 0.013, Vector3(px, floor_y + 0.011, pz), brass, 24)

	# ball trays either side, where pocketed balls collect, fixed to the
	# cabinet rather than floating off it
	var tray := PoolArt.mat(Color("1a0f08"), 0.7)
	for s: float in [1.0, -1.0]:
		_box(Vector3(1.5, 0.03, 0.135), Vector3(0.0, -0.085, (oz + 0.0375) * s), tray)
		_box(Vector3(1.5, 0.03, 0.012), Vector3(0.0, -0.062, (oz + 0.099) * s), tray)


# The rail's outline (a rectangle with its corners cut at 45 degrees), as a
# vertical band from `top` down to `bot`, optionally closed underneath.
func _octagon_band(hx: float, hz: float, top: float, bot: float, m: Material, closed := false) -> void:
	# the rail's corners are cut 0.15 along each side; an outline set in by d
	# keeps the same 45-degree line, so its cut is a little longer
	var cut: float = 0.15 + (HL + CUSHION_D + CAP_W - hx) * (sqrt(2.0) - 1.0)
	var pts: Array[Vector2] = [
		Vector2(hx, -hz + cut), Vector2(hx, hz - cut), Vector2(hx - cut, hz), Vector2(-hx + cut, hz),
		Vector2(-hx, hz - cut), Vector2(-hx, -hz + cut), Vector2(-hx + cut, -hz), Vector2(hx - cut, -hz),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var mid := (a + b) * 0.5
		var e := (b - a).normalized()
		var n := Vector3(e.y, 0.0, -e.x)
		if n.dot(Vector3(mid.x, 0.0, mid.y)) < 0.0:
			n = -n
		_quad(st, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y),
			Vector3(b.x, bot, b.y), Vector3(a.x, bot, a.y), n)
	if closed:
		for i in range(1, pts.size() - 1):
			_tri(st, Vector3(pts[0].x, bot, pts[0].y), Vector3(pts[i].x, bot, pts[i].y),
				Vector3(pts[i + 1].x, bot, pts[i + 1].y), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.name = "Cabinet"
	add_child(mi)


# A turned leg, lathed from a profile rather than stacked from cylinders: the
# shoulder, the swell below it, the waist, and the flare into the foot.
func _leg(top: Vector3, length: float, m: Material) -> void:
	# (radius in metres, height as a fraction of the leg)
	var prof: Array[Vector2] = [
		Vector2(0.094, 0.000), Vector2(0.094, 0.055), Vector2(0.068, 0.092),
		Vector2(0.082, 0.140), Vector2(0.092, 0.215), Vector2(0.074, 0.300),
		Vector2(0.058, 0.400), Vector2(0.053, 0.560), Vector2(0.061, 0.650),
		Vector2(0.048, 0.740), Vector2(0.054, 0.830), Vector2(0.078, 0.925),
		Vector2(0.088, 0.975), Vector2(0.088, 1.000),
	]
	var segs := 26
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in prof.size() - 1:
		var r0: float = prof[k].x
		var r1: float = prof[k + 1].x
		var y0: float = -prof[k].y * length
		var y1: float = -prof[k + 1].y * length
		var along := Vector2(r1 - r0, y1 - y0).normalized()
		var n2 := Vector2(-along.y, along.x).normalized()
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var nm0 := Vector3(d0.x * n2.x, n2.y, d0.y * n2.x).normalized()
			var nm1 := Vector3(d1.x * n2.x, n2.y, d1.y * n2.x).normalized()
			_quad_uv(st,
				Vector3(d0.x * r0, y0, d0.y * r0), Vector3(d1.x * r0, y0, d1.y * r0),
				Vector3(d1.x * r1, y1, d1.y * r1), Vector3(d0.x * r1, y1, d0.y * r1),
				nm0, nm1,
				Vector2(float(i) / float(segs) * 2.0, prof[k].y * 1.4),
				Vector2(float(i + 1) / float(segs) * 2.0, prof[k].y * 1.4),
				Vector2(float(i + 1) / float(segs) * 2.0, prof[k + 1].y * 1.4),
				Vector2(float(i) / float(segs) * 2.0, prof[k + 1].y * 1.4))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = top
	mi.name = "Leg"
	add_child(mi)


func _build_balls() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = R
	sphere.height = R * 2.0
	sphere.radial_segments = 56
	sphere.rings = 28
	for i in 16:
		var m := StandardMaterial3D.new()
		m.albedo_texture = PoolArt.ball_texture(i)
		m.roughness = 0.1
		m.metallic = 0.0
		m.metallic_specular = 0.6
		m.clearcoat_enabled = true
		m.clearcoat = 0.85
		m.clearcoat_roughness = 0.03
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = m
		mi.name = "Ball%d" % i
		add_child(mi)
		ball_nodes.append(mi)
		ball_spin.append(Basis.IDENTITY.rotated(Vector3.UP, randf_range(0.0, TAU)))


# The faces of the balls are painted with a real typeface, the heavy rounded
# sans the numbers on a set of balls are printed in, rather than the blocky
# stand-in the balls start with. The 2D renderer paints all sixteen into an
# offscreen canvas once, a frame after the table is built, and they are read
# back and swapped in. The 8 carries the J.
class BallPainter extends Control:
	const CW := 512
	const CH := 256
	# made once: its glyphs are rasterised on the first frame it draws and
	# are only there to be drawn from the next one on
	var sf: SystemFont

	func _init() -> void:
		sf = SystemFont.new()
		sf.font_names = PackedStringArray(["Arial Rounded MT Bold", "Arial", "Helvetica Neue", "Liberation Sans"])
		sf.font_weight = 700
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	func _draw() -> void:
		for i in 16:
			var o := Vector2(float(i % 4) * CW, float(i / 4) * CH)
			var base: Color = PoolArt.BALL_COLORS.get(i, PoolArt.IVORY) if i > 0 else PoolArt.IVORY
			if i >= 9:
				draw_rect(Rect2(o, Vector2(CW, CH)), PoolArt.IVORY)
				draw_rect(Rect2(o + Vector2(0, CH * 0.285), Vector2(CW, CH * 0.43)), base)
			else:
				draw_rect(Rect2(o, Vector2(CW, CH)), base)
			if i == 0:
				# measle spots so spin is readable in play
				for s: Vector2 in [Vector2(0.12, 0.5), Vector2(0.37, 0.5), Vector2(0.62, 0.5),
						Vector2(0.87, 0.5), Vector2(0.25, 0.22), Vector2(0.75, 0.78)]:
					draw_circle(o + Vector2(s.x * CW, s.y * CH), 14.0, Color("9c2f26"), true, -1.0, true)
				continue
			var label := "J" if i == PoolSim.EIGHT else str(i)
			var r := CH * 0.164
			var fs := int(r * (1.32 if label.length() == 1 else 1.08))
			var w := sf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cap := float(fs) * 0.716
			for cx: float in [0.25, 0.75]:
				var c := o + Vector2(cx * CW, 0.5 * CH)
				draw_circle(c, r, PoolArt.IVORY, true, -1.0, true)
				draw_string(sf, c + Vector2(-w * 0.5, cap * 0.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color("151515"))


func _bake_ball_faces() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(BallPainter.CW * 4, BallPainter.CH * 4)
	vp.transparent_bg = false
	vp.disable_3d = true
	# a few frames, not one: the typeface's glyphs are rasterised on the
	# first, and only drawn properly once they are
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var painter := BallPainter.new()
	painter.size = Vector2(vp.size)
	vp.add_child(painter)
	add_child(vp)
	for _i in 4:
		await RenderingServer.frame_post_draw
		painter.queue_redraw()
	await RenderingServer.frame_post_draw
	var atlas := vp.get_texture().get_image()
	vp.queue_free()
	if atlas == null or atlas.is_empty():
		return
	atlas.convert(Image.FORMAT_RGBA8)
	for i in 16:
		var img := atlas.get_region(Rect2i((i % 4) * BallPainter.CW, (i / 4) * BallPainter.CH,
			BallPainter.CW, BallPainter.CH))
		PoolArt.grain(img, i, 3600)
		img.generate_mipmaps()
		var m: StandardMaterial3D = ball_nodes[i].material_override
		m.albedo_texture = ImageTexture.create_from_image(img)


func reset_trays() -> void:
	_tray_count = {"near": 0, "far": 0}
	_trayed.clear()


# Drop a pocketed ball into one of the two trays.
func send_to_tray(id: int, side: String) -> void:
	var idx: int = _tray_count[side]
	_tray_count[side] = idx + 1
	_trayed[id] = true
	var oz := HW + CUSHION_D + CAP_W + 0.075
	var s := 1.0 if side == "far" else -1.0
	var x := -0.66 + float(idx) * (R * 2.15)
	var node: MeshInstance3D = ball_nodes[id]
	node.visible = true
	node.position = Vector3(x, -0.05, oz * s)


func update_balls(sim: PoolSim, dt: float) -> void:
	for i in 16:
		var b: PoolSim.Ball = sim.ball(i)
		var node: MeshInstance3D = ball_nodes[i]
		if i == PoolSim.CUE and cue_hand != null:
			node.visible = true
			node.position = to_local(cue_hand)
			continue
		if not b.on_table:
			if not _trayed.has(i):
				node.visible = false
			continue
		node.visible = true
		var basis: Basis = ball_spin[i]
		var w: Vector3 = b.spin
		var wl := w.length()
		if wl > 0.0001:
			basis = Basis(w / wl, wl * dt) * basis
			basis = basis.orthonormalized()
			ball_spin[i] = basis
		var lift := cue_lift if i == PoolSim.CUE else 0.0
		node.transform = Transform3D(basis, Vector3(b.pos.x, R + lift, b.pos.y))


func ball_world(sim: PoolSim, id: int) -> Vector3:
	var b := sim.ball(id)
	return to_global(Vector3(b.pos.x, R, b.pos.y))


func table_to_world(p: Vector2, y := R) -> Vector3:
	return to_global(Vector3(p.x, y, p.y))
