class_name PoolCueModel
extends RefCounted

# One cue, lathed along +Y from the tip (y = 0) to the bumper (y = LENGTH).
# The stick on the table, the one in your hand and the one turning in the shop
# are all this same object. Every section's UV.y is metres from the tip and
# UV.x the fraction of the way round, which is what the art shader draws its
# inlays, flames and scales in.

const LENGTH := 1.47

# name, start, end, radius at start, radius at end
const SECTIONS := [
	["tip", 0.000, 0.006, 0.0063, 0.0065],
	["ferrule", 0.006, 0.025, 0.0065, 0.0066],
	["shaft", 0.025, 0.735, 0.0066, 0.0101],
	["rings", 0.735, 0.745, 0.0103, 0.0103],
	["joint", 0.745, 0.770, 0.0105, 0.0105],
	["rings", 0.770, 0.778, 0.0106, 0.0106],
	["forearm", 0.778, 1.075, 0.0107, 0.0119],
	["rings", 1.075, 1.083, 0.0120, 0.0120],
	["wrap", 1.083, 1.290, 0.0120, 0.0121],
	["rings", 1.290, 1.298, 0.0122, 0.0122],
	["sleeve", 1.298, 1.452, 0.0122, 0.0129],
	["cap", 1.452, 1.462, 0.0129, 0.0127],
	["bumper", 1.462, 1.470, 0.0118, 0.0108],
]

const PATTERNS := {
	"plain": 0, "wood": 1, "points": 2, "carbon": 3, "flames": 4, "neon": 5,
	"galaxy": 6, "marble": 7, "damascus": 8, "scales": 9, "lava": 10,
	"stripes": 11, "snake": 12, "filigree": 13, "knurl": 14, "linen": 15,
	"leather": 16, "tiger": 17, "holo": 18, "circuit": 19, "hex": 20,
	"camo": 21, "check": 22, "zebra": 23, "leopard": 24, "runes": 25,
	"aurora": 26, "pearl": 27, "gradient": 28, "pixel": 29, "lightning": 30,
	"wave": 31, "sakura": 32, "bone": 33, "tsuka": 34,
}

static var _shader: Shader
static var _mats: Dictionary = {}


# A section's style can also change its shape, not just its surface:
#   "flutes": n     grooves cut along it, like a column ("depth" as a fraction
#                   of the radius, "twist" turns over the section to spiral them)
#   "facets": n     n flat sides instead of round, like a cut crystal
# and a skin can add parts that stand off the cue: "helix" (something wound
# round it: a snake, a coil, a pipe), "studs" (spikes, domes, pyramids),
# "fins", "gears" (a toothed collar, or a plain guard with no teeth) and a
# "pommel" on the end of the butt.
static func build(skin: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Cue"
	for s in SECTIONS:
		var sec: String = s[0]
		var y0 := float(s[1])
		var y1 := float(s[2])
		var m := _section_material(skin, sec, y0, y1)
		var style: Dictionary = skin.get(sec, {}) if skin.get(sec, {}) is Dictionary else {}
		var mi := MeshInstance3D.new()
		if style.has("flutes") or style.has("facets"):
			mi.mesh = _lathe_shaped(y0, y1, float(s[3]), float(s[4]), style)
		else:
			var segs := maxi(1, int((y1 - y0) / 0.03))
			mi.mesh = _lathe(y0, y1, float(s[3]), float(s[4]), segs, 28)
		mi.material_override = m
		mi.name = sec
		root.add_child(mi)

	for h in _as_list(skin.get("helix", [])):
		_helix(root, h)
	for s in _as_list(skin.get("studs", [])):
		_studs(root, s)
	for f in _as_list(skin.get("fins", [])):
		_fins(root, f)
	for g in _as_list(skin.get("gears", [])):
		_gears(root, g)
	if skin.has("pommel"):
		_pommel(root, skin.pommel)

	# raised metal bands and set stones: the parts that are actually 3D
	var ring_mat := _section_material(skin, "rings", 0.0, 1.0)
	for at in skin.get("bands", []):
		var r := radius_at(float(at))
		var t := TorusMesh.new()
		t.inner_radius = r - 0.0006
		t.outer_radius = r + 0.0016
		t.rings = 32
		t.ring_segments = 8
		var bi := MeshInstance3D.new()
		bi.mesh = t
		bi.position = Vector3(0.0, float(at), 0.0)
		bi.material_override = ring_mat
		root.add_child(bi)

	var gems: Dictionary = skin.get("gems", {})
	if not gems.is_empty():
		var gm := StandardMaterial3D.new()
		var gc := Color(str(gems.color))
		gm.albedo_color = gc
		gm.metallic = 0.3
		gm.roughness = 0.04
		gm.metallic_specular = 1.0
		gm.emission_enabled = true
		gm.emission = gc
		gm.emission_energy_multiplier = float(gems.get("glow", 0.9))
		var size: float = float(gems.get("size", 0.0032))
		var gem := SphereMesh.new()
		gem.radius = size
		gem.height = size * 1.6
		gem.radial_segments = 6
		gem.rings = 3
		for at in gems.get("at", [0.757]):
			var n: int = int(gems.get("count", 6))
			var r := radius_at(float(at))
			for i in n:
				var a := TAU * float(i) / float(n)
				var gi := MeshInstance3D.new()
				gi.mesh = gem
				gi.material_override = gm
				gi.position = Vector3(cos(a) * r, float(at), sin(a) * r)
				gi.rotation = Vector3(0.0, -a, PI * 0.5)
				root.add_child(gi)
	return root


static func radius_at(along: float) -> float:
	for s in SECTIONS:
		if along >= float(s[1]) and along <= float(s[2]):
			var t := (along - float(s[1])) / maxf(float(s[2]) - float(s[1]), 0.0001)
			return lerpf(float(s[3]), float(s[4]), t)
	return 0.012


static func _as_list(v) -> Array:
	if v is Array:
		return v
	if v is Dictionary:
		return [v]
	return []


# ---------------------------------------------------------------------------
# Shaped sections
# ---------------------------------------------------------------------------

# A section whose radius changes round it: fluted like a column, spiralled,
# or cut flat into facets. The grooves fade out at both ends so it still
# meets the rings either side of it cleanly.
static func _lathe_shaped(y0: float, y1: float, r0: float, r1: float, style: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var facets := int(style.get("facets", 0))
	var flutes := int(style.get("flutes", 0))
	var depth := float(style.get("depth", 0.12))
	var twist := float(style.get("twist", 0.0))
	var length := y1 - y0

	if facets >= 3:
		# flat sides, lit flat, like a cut stone
		var rings := maxi(1, int(length / 0.03))
		for k in rings:
			var ya := lerpf(y0, y1, float(k) / float(rings))
			var yb := lerpf(y0, y1, float(k + 1) / float(rings))
			var ra := lerpf(r0, r1, float(k) / float(rings))
			var rb := lerpf(r0, r1, float(k + 1) / float(rings))
			for i in facets:
				var a0 := TAU * float(i) / float(facets)
				var a1 := TAU * float(i + 1) / float(facets)
				var am := (a0 + a1) * 0.5
				var nf := Vector3(cos(am), 0.0, sin(am))
				var u0 := float(i) / float(facets)
				var u1 := float(i + 1) / float(facets)
				var p00 := Vector3(cos(a0) * ra, ya, sin(a0) * ra)
				var p10 := Vector3(cos(a1) * ra, ya, sin(a1) * ra)
				var p01 := Vector3(cos(a0) * rb, yb, sin(a0) * rb)
				var p11 := Vector3(cos(a1) * rb, yb, sin(a1) * rb)
				_tri(st, p00, p10, p11, nf, nf, nf, Vector2(u0, ya), Vector2(u1, ya), Vector2(u1, yb))
				_tri(st, p00, p11, p01, nf, nf, nf, Vector2(u0, ya), Vector2(u1, yb), Vector2(u0, yb))
		_caps(st, y0, y1, r0, r1, facets)
		return st.commit()

	# every point once, on a grid; normals from the neighbours on that grid
	var segs := clampi(flutes * 10, 32, 140)
	var rings := maxi(int(length / (0.004 if twist != 0.0 else 0.012)), 4)
	var grid: Array = []
	for k in rings + 1:
		var t := float(k) / float(rings)
		var y := lerpf(y0, y1, t)
		var base := lerpf(r0, r1, t)
		var fade := smoothstep(0.0, 0.08, t) * smoothstep(1.0, 0.92, t)
		var row := PackedVector3Array()
		row.resize(segs + 1)
		for i in segs + 1:
			var a := TAU * float(i) / float(segs)
			var g := pow(0.5 + 0.5 * cos(a * float(flutes) + twist * TAU * t * float(flutes)), 2.0)
			var r := base * (1.0 - depth * g * fade)
			row[i] = Vector3(cos(a) * r, y, sin(a) * r)
		grid.append(row)
	var norms: Array = []
	for k in rings + 1:
		var row := PackedVector3Array()
		row.resize(segs + 1)
		for i in segs + 1:
			var ka := maxi(k - 1, 0)
			var kb := mini(k + 1, rings)
			var ia := (i - 1 + segs) % segs
			var ib := (i + 1) % segs
			var dy: Vector3 = (grid[kb] as PackedVector3Array)[i] - (grid[ka] as PackedVector3Array)[i]
			var da: Vector3 = (grid[k] as PackedVector3Array)[ib] - (grid[k] as PackedVector3Array)[ia]
			var n := dy.cross(da).normalized()
			var a := TAU * float(i) / float(segs)
			if n.dot(Vector3(cos(a), 0.0, sin(a))) < 0.0:
				n = -n
			row[i] = n
		norms.append(row)
	for k in rings:
		var ga: PackedVector3Array = grid[k]
		var gb: PackedVector3Array = grid[k + 1]
		var na_row: PackedVector3Array = norms[k]
		var nb_row: PackedVector3Array = norms[k + 1]
		var ya := ga[0].y
		var yb := gb[0].y
		for i in segs:
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			_tri(st, ga[i], ga[i + 1], gb[i + 1], na_row[i], na_row[i + 1], nb_row[i + 1],
				Vector2(u0, ya), Vector2(u1, ya), Vector2(u1, yb))
			_tri(st, ga[i], gb[i + 1], gb[i], na_row[i], nb_row[i + 1], nb_row[i],
				Vector2(u0, ya), Vector2(u1, yb), Vector2(u0, yb))
	_caps(st, y0, y1, r0, r1, 28)
	return st.commit()


static func _caps(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, segs: int) -> void:
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		_tri(st, Vector3(0, y0, 0), Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2(0.5, y0), Vector2(0.5, y0), Vector2(0.5, y0))
		_tri(st, Vector3(0, y1, 0), Vector3(cos(a0) * r1, y1, sin(a0) * r1), Vector3(cos(a1) * r1, y1, sin(a1) * r1),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector2(0.5, y1), Vector2(0.5, y1), Vector2(0.5, y1))


# ---------------------------------------------------------------------------
# Parts that stand off the cue
# ---------------------------------------------------------------------------

static func _feature_mat(d: Dictionary) -> Material:
	if d.has("style"):
		return _art(d.style, 0.0, 1.0)
	return _solid(str(d.get("color", "c9ccd2")), float(d.get("metal", 1.0)), float(d.get("rough", 0.25)),
		float(d.get("glow", 0.0)))


static func _solid(hex: String, metal: float, rough: float, glow: float) -> StandardMaterial3D:
	var key := "solid:%s:%f:%f:%f" % [hex, metal, rough, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = glow
	if metal < 0.5:
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.clearcoat_roughness = 0.1
	_mats[key] = m
	return m


# Something wound round the butt: a tube following a helix, tapering to a
# point at the tail. With "head" it is a snake, and gets a head and eyes.
static func _helix(root: Node3D, h: Dictionary) -> void:
	var from := float(h.get("from", 0.80))
	var to := float(h.get("to", 1.28))
	var turns := float(h.get("turns", 3.0))
	var count := int(h.get("count", 1))
	var tube := float(h.get("r", 0.0024))
	var tail := float(h.get("tail", 1.0))       # radius at the start, as a fraction
	var mat := _feature_mat(h)
	var ring_n := 10
	for c in count:
		var phase := TAU * float(c) / float(count)
		var steps := maxi(int(turns * 56.0), 24)
		var path: Array[Vector3] = []
		var radial: Array[Vector3] = []
		var tr: Array[float] = []
		for i in steps + 1:
			var t := float(i) / float(steps)
			var y := lerpf(from, to, t)
			var a := phase + t * turns * TAU
			var out := Vector3(cos(a), 0.0, sin(a))
			var r := lerpf(tube * tail, tube, smoothstep(0.0, 0.35, t))
			path.append(out * (radius_at(y) + r * 0.55) + Vector3(0.0, y, 0.0))
			radial.append(out)
			tr.append(r)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var run := 0.0
		for i in steps:
			var ta := (path[mini(i + 1, steps)] - path[maxi(i - 1, 0)]).normalized()
			var tb := (path[mini(i + 2, steps)] - path[i]).normalized()
			var ba := ta.cross(radial[i]).normalized()
			var bb := tb.cross(radial[i + 1]).normalized()
			var na := ba.cross(ta).normalized()
			var nb := bb.cross(tb).normalized()
			var seg_len := path[i].distance_to(path[i + 1])
			for k in ring_n:
				var q0 := TAU * float(k) / float(ring_n)
				var q1 := TAU * float(k + 1) / float(ring_n)
				var d00 := na * cos(q0) + ba * sin(q0)
				var d01 := na * cos(q1) + ba * sin(q1)
				var d10 := nb * cos(q0) + bb * sin(q0)
				var d11 := nb * cos(q1) + bb * sin(q1)
				var u0 := float(k) / float(ring_n)
				var u1 := float(k + 1) / float(ring_n)
				_tri(st, path[i] + d00 * tr[i], path[i] + d01 * tr[i], path[i + 1] + d11 * tr[i + 1],
					d00, d01, d11, Vector2(u0, run), Vector2(u1, run), Vector2(u1, run + seg_len))
				_tri(st, path[i] + d00 * tr[i], path[i + 1] + d11 * tr[i + 1], path[i + 1] + d10 * tr[i + 1],
					d00, d11, d10, Vector2(u0, run), Vector2(u1, run + seg_len), Vector2(u0, run + seg_len))
			run += seg_len
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.name = "Helix"
		root.add_child(mi)

		if h.get("head", false):
			var end := path[steps]
			var fwd := (path[steps] - path[steps - 2]).normalized()
			var up := radial[steps]
			var side := fwd.cross(up).normalized()
			var head := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = tube * 1.5
			sm.height = tube * 3.0
			sm.radial_segments = 14
			sm.rings = 8
			head.mesh = sm
			head.material_override = mat
			# the sphere's long axis is Y: point it along the body, flattened
			head.transform = Transform3D(Basis(side * 1.0, fwd * 1.5, up * 0.8), end + fwd * tube * 1.4)
			root.add_child(head)
			var eye_m := _solid(str(h.get("eyes", "ff2a2a")), 0.2, 0.05, 3.0)
			for s: float in [1.0, -1.0]:
				var eye := MeshInstance3D.new()
				var em := SphereMesh.new()
				em.radius = tube * 0.38
				em.height = tube * 0.76
				em.radial_segments = 8
				em.rings = 4
				eye.mesh = em
				eye.material_override = eye_m
				eye.position = end + fwd * tube * 2.3 + side * s * tube * 0.95 + up * tube * 0.55
				root.add_child(eye)


# Studs set round the butt in staggered rows: "spike", "dome" or "pyramid".
static func _studs(root: Node3D, s: Dictionary) -> void:
	var from := float(s.get("from", 1.31))
	var to := float(s.get("to", 1.44))
	var rows := int(s.get("rows", 3))
	var per := int(s.get("per_row", 8))
	var size := float(s.get("size", 0.006))
	var shape := str(s.get("shape", "spike"))
	var mat := _feature_mat(s)
	var mesh: Mesh
	var lift := size * 0.5
	match shape:
		"dome":
			var sm := SphereMesh.new()
			sm.radius = size * 0.5
			sm.height = size * 0.5
			sm.is_hemisphere = true
			sm.radial_segments = 12
			sm.rings = 4
			mesh = sm
			lift = -0.0004
		"pyramid":
			var pm := CylinderMesh.new()
			pm.top_radius = 0.0
			pm.bottom_radius = size * 0.62
			pm.height = size * 0.8
			pm.radial_segments = 4
			pm.rings = 1
			mesh = pm
			lift = size * 0.38
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = size * 0.34
			cm.height = size
			cm.radial_segments = 10
			cm.rings = 1
			mesh = cm
	for row in rows:
		var y := lerpf(from, to, (float(row) + 0.5) / float(rows))
		var r := radius_at(y)
		for k in per:
			var a := TAU * (float(k) + (0.5 if row % 2 == 1 else 0.0)) / float(per)
			var out := Vector3(cos(a), 0.0, sin(a))
			var tangent := Vector3(-sin(a), 0.0, cos(a))
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.transform = Transform3D(Basis(tangent, out, Vector3.UP), out * (r + lift) + Vector3(0.0, y, 0.0))
			root.add_child(mi)


# Thin blades standing off the butt, swept back towards the bumper.
static func _fins(root: Node3D, f: Dictionary) -> void:
	var from := float(f.get("from", 1.30))
	var to := float(f.get("to", 1.45))
	var count := int(f.get("count", 3))
	var height := float(f.get("height", 0.010))
	var thick := float(f.get("thick", 0.0012))
	var offset := float(f.get("offset", 0.0))
	var mat := _feature_mat(f)
	var span := to - from
	# outline in (along, out): a swept blade
	var outline: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(span, 0.0),
		Vector2(span * 0.96, height), Vector2(span * 0.62, height * 0.9), Vector2(0.0, 0.0)]
	for k in count:
		var a := TAU * float(k) / float(count) + offset
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts_a: Array[Vector3] = []
		var pts_b: Array[Vector3] = []
		for p in outline:
			var y := from + p.x
			var base := out * (radius_at(y) - 0.0005 + p.y) + Vector3(0.0, y, 0.0)
			pts_a.append(base + side * thick * 0.5)
			pts_b.append(base - side * thick * 0.5)
		for i in range(1, outline.size() - 2):
			_tri(st, pts_a[0], pts_a[i], pts_a[i + 1], side, side, side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(st, pts_b[0], pts_b[i], pts_b[i + 1], -side, -side, -side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		for i in outline.size() - 1:
			var e := (pts_a[i + 1] - pts_a[i]).normalized()
			var n := e.cross(side).normalized()
			if n.dot(out) < 0.0 and i > 0:
				n = -n
			_tri(st, pts_a[i], pts_a[i + 1], pts_b[i + 1], n, n, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(st, pts_a[i], pts_b[i + 1], pts_b[i], n, n, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.name = "Fin"
		root.add_child(mi)


# A collar round the cue. With teeth it is a gear; with none it is a guard,
# like the tsuba on a sword.
static func _gears(root: Node3D, g: Dictionary) -> void:
	var teeth := int(g.get("teeth", 14))
	var size := float(g.get("size", 0.005))
	var thick := float(g.get("thick", 0.004))
	var mat := _feature_mat(g)
	for at in _as_list(g.get("at", [0.76])):
		var y := float(at)
		var r := radius_at(y)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r + size * (0.55 if teeth > 0 else 1.0)
		cm.bottom_radius = cm.top_radius
		cm.height = thick
		cm.radial_segments = 40
		cm.rings = 1
		disc.mesh = cm
		disc.material_override = mat
		disc.position = Vector3(0.0, y, 0.0)
		root.add_child(disc)
		if teeth <= 0:
			continue
		var bm := BoxMesh.new()
		bm.size = Vector3(TAU * (r + size) / float(teeth) * 0.45, thick, size * 0.6)
		for k in teeth:
			var a := TAU * float(k) / float(teeth)
			var out := Vector3(cos(a), 0.0, sin(a))
			var tooth := MeshInstance3D.new()
			tooth.mesh = bm
			tooth.material_override = mat
			tooth.transform = Transform3D(Basis(Vector3(-sin(a), 0.0, cos(a)), Vector3.UP, -out),
				out * (r + size * 0.72) + Vector3(0.0, y, 0.0))
			root.add_child(tooth)


# Something on the very end of the butt: a cut "gem" or a glowing "orb",
# sitting in a small metal cup.
static func _pommel(root: Node3D, p: Dictionary) -> void:
	var size := float(p.get("size", 0.011))
	var shape := str(p.get("shape", "gem"))
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size * 0.95
	cm.bottom_radius = 0.0118
	cm.height = 0.008
	cm.radial_segments = 24
	cup.mesh = cm
	cup.material_override = _solid(str(p.get("metal_color", "c9ccd2")), 1.0, 0.18, 0.0)
	cup.position = Vector3(0.0, LENGTH + 0.004, 0.0)
	root.add_child(cup)
	var gm := StandardMaterial3D.new()
	var col := Color(str(p.get("color", "9fe8ff")))
	gm.albedo_color = col
	gm.metallic = 0.25
	gm.roughness = 0.04
	gm.metallic_specular = 1.0
	gm.emission_enabled = true
	gm.emission = col
	gm.emission_energy_multiplier = float(p.get("glow", 1.2))
	gm.clearcoat_enabled = true
	gm.clearcoat = 1.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	if shape == "orb":
		sm.radius = size
		sm.height = size * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		mi.position = Vector3(0.0, LENGTH + 0.008 + size * 0.85, 0.0)
	else:
		sm.radius = size
		sm.height = size * 3.0
		sm.radial_segments = 6
		sm.rings = 2
		mi.position = Vector3(0.0, LENGTH + 0.008 + size * 1.3, 0.0)
		gm.roughness = 0.02
	mi.mesh = sm
	mi.material_override = gm
	root.add_child(mi)


# A cone frustum along +Y, closed at both ends, wound so its outside faces
# out (Godot's front face is clockwise seen from the front).
static func _lathe(y0: float, y1: float, r0: float, r1: float, rings: int, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope := (r0 - r1) / maxf(y1 - y0, 0.0001)
	for k in rings:
		var ya := lerpf(y0, y1, float(k) / float(rings))
		var yb := lerpf(y0, y1, float(k + 1) / float(rings))
		var ra := lerpf(r0, r1, float(k) / float(rings))
		var rb := lerpf(r0, r1, float(k + 1) / float(rings))
		for i in segs:
			var u0 := float(i) / float(segs)
			var u1 := float(i + 1) / float(segs)
			var a0 := u0 * TAU
			var a1 := u1 * TAU
			var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
			var p00 := Vector3(cos(a0) * ra, ya, sin(a0) * ra)
			var p10 := Vector3(cos(a1) * ra, ya, sin(a1) * ra)
			var p01 := Vector3(cos(a0) * rb, yb, sin(a0) * rb)
			var p11 := Vector3(cos(a1) * rb, yb, sin(a1) * rb)
			_tri(st, p00, p10, p11, n0, n1, n1, Vector2(u0, ya), Vector2(u1, ya), Vector2(u1, yb))
			_tri(st, p00, p11, p01, n0, n1, n0, Vector2(u0, ya), Vector2(u1, yb), Vector2(u0, yb))
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		_tri(st, Vector3(0, y0, 0), Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2(0.5, y0), Vector2(0.5, y0), Vector2(0.5, y0))
		_tri(st, Vector3(0, y1, 0), Vector3(cos(a0) * r1, y1, sin(a0) * r1), Vector3(cos(a1) * r1, y1, sin(a1) * r1),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector2(0.5, y1), Vector2(0.5, y1), Vector2(0.5, y1))
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
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


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

static func _section_material(skin: Dictionary, sec: String, v0: float, v1: float) -> Material:
	match sec:
		"tip":
			return _flat(str(skin.get("tip", "2c4a6e")), 0.85, 0.0)
		"ferrule":
			return _flat(str(skin.get("ferrule", "ece6d6")), 0.3, 0.0)
		"bumper":
			return _flat("0c0c0c", 0.8, 0.0)
		"cap":
			return _art(skin.get("cap", skin.get("rings", {"p": "plain", "a": "222222"})), 0.0, 1.0)
	return _art(skin.get(sec, {"p": "plain", "a": "444444"}), v0, v1)


static func _flat(hex: String, rough: float, metal: float) -> StandardMaterial3D:
	var key := "flat:%s:%f:%f" % [hex, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func _art(style: Dictionary, v0: float, v1: float) -> ShaderMaterial:
	var key := "%s|%f|%f" % [str(style), v0, v1]
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type spatial;\nrender_mode cull_back;\n" + PoolArt._NOISE + _ART
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("pattern", int(PATTERNS.get(str(style.get("p", "plain")), 0)))
	m.set_shader_parameter("col_a", Color(str(style.get("a", "888888"))))
	m.set_shader_parameter("col_b", Color(str(style.get("b", "222222"))))
	m.set_shader_parameter("col_c", Color(str(style.get("c", "ffffff"))))
	m.set_shader_parameter("metal", float(style.get("m", 0.0)))
	m.set_shader_parameter("rough", float(style.get("r", 0.3)))
	m.set_shader_parameter("coat", float(style.get("coat", 0.5)))
	m.set_shader_parameter("glow", float(style.get("g", 0.0)))
	m.set_shader_parameter("count", float(style.get("n", 4.0)))
	m.set_shader_parameter("v0", v0)
	m.set_shader_parameter("v1", v1)
	_mats[key] = m
	return m


const _ART := """
uniform int pattern = 0;
uniform vec3 col_a : source_color = vec3(0.6, 0.45, 0.3);
uniform vec3 col_b : source_color = vec3(0.1);
uniform vec3 col_c : source_color = vec3(1.0);
uniform float metal = 0.0;
uniform float rough = 0.3;
uniform float coat = 0.5;
uniform float glow = 0.0;
uniform float count = 4.0;
uniform float v0 = 0.0;
uniform float v1 = 1.0;

void fragment() {
	float ang = UV.x;
	float along = UV.y;
	float t = clamp((along - v0) / max(v1 - v0, 0.001), 0.0, 1.0);
	// a point on a unit tube: seamless all the way round
	vec3 ring = vec3(cos(ang * TAU), sin(ang * TAU), 0.0);
	vec3 albedo = col_a;
	float m = metal;
	float r = rough;
	vec3 emit = vec3(0.0);

	if (pattern == 0) {
		emit = col_a * glow;
	} else if (pattern == 1) {
		float streak = fbm(vec3(ring.xy * 6.0, along * 2.5));
		float fine = fbm(vec3(ring.xy * 30.0, along * 9.0)) - 0.5;
		albedo = col_a * (0.82 + 0.3 * streak + 0.18 * fine);
	} else if (pattern == 2) {
		float ph = fract(ang * count + 0.5 / count) - 0.5;
		float w = 0.46 * clamp((t - 0.14) / 0.86, 0.0, 1.0);
		float inside = step(abs(ph), w);
		float veneer = step(abs(ph), w + 0.035) * step(0.11, t);
		albedo = mix(mix(col_a, col_c, veneer), col_b, inside);
		m = mix(metal, 0.0, veneer);
	} else if (pattern == 3) {
		vec2 q = vec2(ang * 22.0, along * 180.0);
		vec2 f = fract(q);
		float chk = mod(floor(q.x) + floor(q.y), 2.0);
		float strand = chk > 0.5 ? sin(f.x * 3.14159) : sin(f.y * 3.14159);
		albedo = col_a * (0.55 + 0.75 * strand);
		r = mix(0.42, 0.16, strand);
		m = 0.25;
	} else if (pattern == 4) {
		float h = 1.0 - t;
		float n = fbm(vec3(ring.xy * 2.0, along * 7.0));
		float tongue = 0.5 + 0.5 * sin(ang * TAU * count + n * 5.0);
		float reach = 0.25 + 0.55 * tongue * (0.55 + 0.6 * n);
		float f = smoothstep(reach, reach - 0.22, h);
		float core = smoothstep(reach - 0.12, reach - 0.45, h);
		vec3 fire = mix(col_b, col_c, core);
		albedo = mix(col_a, fire, f);
		emit = fire * f * glow;
		r = mix(rough, 0.25, f);
	} else if (pattern == 5) {
		float s = fract(ang * count + along * 7.0);
		float line = 1.0 - smoothstep(0.018, 0.03, abs(s - 0.5));
		albedo = mix(col_a, col_c, line);
		emit = col_c * line * glow;
	} else if (pattern == 6) {
		vec3 q3 = vec3(ring.xy * 2.2, along * 14.0);
		float neb = fbm(q3);
		float neb2 = fbm(q3 * 2.0 + 5.0);
		albedo = col_a + col_b * smoothstep(0.45, 0.85, neb) + col_c * smoothstep(0.55, 0.9, neb2) * 0.7;
		vec2 sc = vec2(ang * 90.0, along * 700.0);
		vec2 id = floor(sc);
		float star = step(0.94, hash12(id)) * (1.0 - smoothstep(0.08, 0.32, length(fract(sc) - 0.5)));
		albedo += vec3(star);
		emit = (col_b * 0.35 * smoothstep(0.5, 0.9, neb) + vec3(star) * 1.5) * glow;
	} else if (pattern == 7) {
		vec3 q3 = vec3(ring.xy * 2.0, along * 9.0);
		float v = abs(sin(along * 35.0 + fbm(q3) * 11.0 + ang * TAU));
		float vein = 1.0 - smoothstep(0.0, 0.07, v);
		float vein2 = 1.0 - smoothstep(0.0, 0.03, abs(sin(along * 70.0 + fbm(q3 * 2.3) * 9.0)));
		albedo = mix(col_a * (0.92 + 0.08 * fbm(q3 * 3.0)), col_b, vein * 0.8);
		albedo = mix(albedo, col_c, vein2 * 0.9);
		m = mix(0.0, 0.9, vein2);
		emit = col_c * vein2 * glow;
	} else if (pattern == 8) {
		float w = sin(along * 320.0 + fbm(vec3(ring.xy * 3.0, along * 25.0)) * 14.0);
		albedo = col_a * (0.5 + 0.35 * (0.5 + 0.5 * w));
		m = 1.0;
		r = 0.22 + 0.12 * w;
	} else if (pattern == 9) {
		vec2 q = vec2(ang * count * 2.0, along * 95.0);
		float row = floor(q.y);
		float x = q.x + mod(row, 2.0) * 0.5;
		vec2 f = vec2(fract(x) - 0.5, fract(q.y));
		float d = length(vec2(f.x, f.y * 0.85 - 0.05));
		float edge = smoothstep(0.44, 0.56, d);
		albedo = mix(col_a * (0.45 + 0.8 * (1.0 - f.y)), col_b, edge);
		r = mix(0.2, 0.6, edge);
	} else if (pattern == 10) {
		vec3 q3 = vec3(ring.xy * 1.8, along * 16.0);
		float n = fbm(q3);
		float crack = 1.0 - smoothstep(0.0, 0.04, abs(n - 0.5));
		float n2 = fbm(q3 * 2.3 + 3.0);
		albedo = mix(col_a * (0.55 + 0.6 * n2), col_b, crack);
		emit = mix(col_b, col_c, crack * n2) * crack * glow;
		r = mix(0.75, 0.3, crack);
	} else if (pattern == 11) {
		float s = fract(ang * count + along * 9.0);
		float band = step(0.5, s);
		float edge = 1.0 - smoothstep(0.0, 0.025, min(abs(s - 0.5), min(s, 1.0 - s)));
		albedo = mix(mix(col_a, col_b, band), col_c, edge * 0.8);
	} else if (pattern == 12) {
		vec2 q = vec2(ang * count, along * 45.0);
		vec2 dq = vec2(q.x + q.y, q.x - q.y);
		vec2 f = fract(dq) - 0.5;
		float e = max(abs(f.x), abs(f.y));
		float cell = hash12(floor(dq));
		vec3 inner = mix(col_a, col_c, step(0.7, cell));
		albedo = mix(inner * (0.8 + 0.4 * (0.5 - e)), col_b, smoothstep(0.36, 0.44, e));
		r = mix(0.35, 0.6, smoothstep(0.36, 0.44, e));
	} else if (pattern == 13) {
		float s1 = sin(ang * TAU * count + sin(along * 110.0) * 2.2);
		float s2 = sin(along * 220.0 + sin(ang * TAU * count * 2.0) * 1.6);
		float line = 1.0 - smoothstep(0.0, 0.22, abs(s1 * s2));
		albedo = mix(col_a, col_b, line * 0.85);
		m = mix(metal, 0.3, line);
		r = mix(rough, 0.55, line);
	} else if (pattern == 14) {
		vec2 q = vec2(ang * 70.0, along * 420.0);
		vec2 dq = vec2(q.x + q.y, q.x - q.y);
		vec2 f = abs(fract(dq) - 0.5);
		float h = 1.0 - (f.x + f.y);
		albedo = col_a * (0.55 + 0.6 * h);
		m = 1.0;
		r = mix(0.5, 0.2, h);
	} else if (pattern == 15) {
		float wv = sin(ang * TAU * 90.0) * sin(along * 1400.0);
		albedo = col_a * (0.8 + 0.2 * wv + 0.1 * fbm(vec3(ring.xy * 20.0, along * 40.0)));
		r = 0.85;
	} else if (pattern == 16) {
		float groove = smoothstep(0.0, 0.08, abs(fract(along * 110.0) - 0.5) - 0.42);
		albedo = col_a * (0.75 + 0.3 * fbm(vec3(ring.xy * 12.0, along * 60.0))) * (1.0 - groove * 0.5);
		r = 0.6;
	} else if (pattern == 17) {
		float fig = sin(along * 260.0 + fbm(vec3(ring.xy * 3.0, along * 12.0)) * 7.0 + ang * TAU * 2.0);
		float band = smoothstep(0.3, 1.0, fig);
		float streak = fbm(vec3(ring.xy * 6.0, along * 2.5));
		albedo = mix(col_a * (0.85 + 0.25 * streak), col_b, band * 0.55);
	} else if (pattern == 18) {
		// holographic foil: the colour runs with the angle you see it at
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float h = fract(fres * 1.6 + along * 3.0 + fbm(vec3(ring.xy * 3.0, along * 20.0)) * 0.6);
		vec3 rainbow = 0.5 + 0.5 * cos(TAU * (h + vec3(0.0, 0.33, 0.67)));
		float grain = step(0.5, fract(ang * 180.0 + along * 400.0)) * 0.06;
		albedo = mix(col_a, rainbow, 0.75) + grain;
		m = 0.85;
		r = 0.16;
		emit = rainbow * glow * 0.3;
	} else if (pattern == 19) {
		// circuit board: copper traces on a grid, some of them live
		vec2 q = vec2(ang * 40.0, along * 260.0);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float hsh = hash12(cell);
		float trace = hsh > 0.5 ? step(abs(f.y - 0.5), 0.12) : step(abs(f.x - 0.5), 0.12);
		trace *= step(0.35, hash12(cell + 17.0));
		float pad = step(length(f - 0.5), 0.28) * step(0.86, hsh);
		float lit = clamp(trace + pad, 0.0, 1.0);
		albedo = mix(col_a * (0.8 + 0.2 * hash12(cell + 3.0)), col_b, lit);
		m = mix(0.1, 0.9, lit);
		r = mix(0.45, 0.2, lit);
		float pulse = 0.55 + 0.45 * sin(TIME * 2.0 + along * 30.0);
		emit = col_c * lit * glow * pulse * step(0.6, hash12(cell + 9.0));
	} else if (pattern == 20) {
		// honeycomb, light pooled in the cells
		vec2 q = vec2(ang * count, along * count * 13.3);
		vec2 g = vec2(1.0, 1.7320508);
		vec2 a1 = mod(q, g) - g * 0.5;
		vec2 a2 = mod(q - g * 0.5, g) - g * 0.5;
		vec2 hx = dot(a1, a1) < dot(a2, a2) ? a1 : a2;
		vec2 ab = abs(hx);
		float d = 0.5 - max(dot(ab, normalize(vec2(1.0, 1.7320508))), ab.x);
		float wall = 1.0 - smoothstep(0.03, 0.07, d);
		albedo = mix(col_a * (0.6 + 0.8 * d), col_b, wall);
		m = mix(0.2, 1.0, wall);
		r = mix(0.3, 0.2, wall);
		emit = col_c * (1.0 - wall) * glow * smoothstep(0.1, 0.45, d);
	} else if (pattern == 21) {
		// woodland camouflage
		float n1 = fbm(vec3(ring.xy * 1.5, along * 12.0));
		float n2 = fbm(vec3(ring.xy * 1.5 + 7.0, along * 12.0 + 3.0));
		float n3 = fbm(vec3(ring.xy * 2.0 + 13.0, along * 16.0));
		vec3 c = mix(col_a, col_b, step(0.52, n1));
		c = mix(c, col_c, step(0.56, n2));
		albedo = mix(c, vec3(0.07, 0.06, 0.045), step(0.62, n3));
		r = 0.75;
	} else if (pattern == 22) {
		// chequered flag
		vec2 q = vec2(ang * count, along * count * 13.8);
		albedo = mix(col_a, col_b, mod(floor(q.x) + floor(q.y), 2.0));
	} else if (pattern == 23) {
		// zebra
		float s = sin(along * 90.0 + sin(ang * TAU * 2.0 + along * 20.0) * 1.8 + fbm(vec3(ring.xy * 2.0, along * 8.0)) * 4.0);
		albedo = mix(col_a, col_b, smoothstep(0.1, 0.25, s));
	} else if (pattern == 24) {
		// leopard rosettes
		vec2 q = vec2(ang * count, along * count * 13.0);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		vec2 o = vec2(hash12(cell), hash12(cell + 5.0)) * 0.4 + 0.3;
		float d = length(f - o);
		float spot = 1.0 - smoothstep(0.05, 0.09, abs(d - 0.24));
		float inner = 1.0 - smoothstep(0.15, 0.19, d);
		albedo = col_a * (0.9 + 0.2 * fbm(vec3(ring.xy * 4.0, along * 30.0)));
		albedo = mix(albedo, col_c, inner * 0.7);
		albedo = mix(albedo, col_b, spot);
		r = 0.6;
	} else if (pattern == 25) {
		// stone carved with runes that still glow
		vec2 q = vec2(ang * count, along * count * 12.0);
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float hsh = hash12(cell);
		float w = 0.045;
		float g = step(abs(f.x), w) * step(abs(f.y), 0.32);
		g += step(0.5, fract(hsh * 7.0)) * step(abs(f.y - f.x * 0.9 - 0.1), w) * step(abs(f.x), 0.22);
		g += step(0.5, fract(hsh * 13.0)) * step(abs(f.y + f.x * 0.9 + 0.05), w) * step(abs(f.x), 0.22);
		g += step(0.5, fract(hsh * 29.0)) * step(abs(f.y - 0.2), w) * step(abs(f.x), 0.18);
		g = clamp(g, 0.0, 1.0) * step(0.3, hsh);
		float stone = fbm(vec3(ring.xy * 3.0, along * 25.0));
		albedo = mix(col_a * (0.55 + 0.6 * stone), col_c, g);
		r = mix(0.8, 0.3, g);
		emit = col_c * g * glow * (0.7 + 0.3 * sin(TIME * 1.5 + hsh * 6.0));
	} else if (pattern == 26) {
		// northern lights over a starry sky
		float n = fbm(vec3(ring.xy * 1.2, along * 5.0 + TIME * 0.05));
		float band = sin(along * 40.0 + n * 8.0 + ang * TAU);
		float curtain = smoothstep(0.2, 1.0, band) * smoothstep(0.3, 0.7, fbm(vec3(ring.xy * 3.0, along * 20.0)));
		vec3 c = mix(col_b, col_c, smoothstep(0.3, 0.8, n));
		vec2 sc = vec2(ang * 70.0, along * 500.0);
		albedo = col_a + c * curtain * 0.6 + vec3(step(0.97, hash12(floor(sc)))) * 0.5;
		emit = c * curtain * glow;
	} else if (pattern == 27) {
		// mother of pearl
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float n = fbm(vec3(ring.xy * 4.0, along * 30.0));
		vec3 irid = 0.5 + 0.5 * cos(TAU * (fract(n * 3.0 + fres * 0.7) + vec3(0.0, 0.33, 0.67)));
		albedo = mix(col_a, irid, 0.35 + 0.3 * fres);
		m = 0.3;
		r = 0.12;
	} else if (pattern == 28) {
		// a sunset running down the section, with a retro striped horizon
		albedo = mix(col_a, col_b, t);
		albedo = mix(albedo, col_c, smoothstep(0.6, 1.0, t));
		float stripes = step(0.55, fract(along * 140.0)) * smoothstep(0.55, 0.85, t);
		albedo = mix(albedo, col_c * 0.3, stripes * 0.7);
		emit = albedo * glow * 0.4;
	} else if (pattern == 29) {
		// pixel art
		vec2 q = floor(vec2(ang * count * 4.0, along * count * 52.0));
		float h = hash12(q);
		vec3 c = h < 0.4 ? col_a : (h < 0.75 ? col_b : col_c);
		albedo = c;
		r = 0.5;
		emit = c * glow * step(0.88, h);
	} else if (pattern == 30) {
		// lightning through storm cloud
		float bolt = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float jag = (vnoise(vec3(along * 90.0, fi * 7.0, 1.0)) - 0.5) * 0.10 + (fbm(vec3(along * 12.0, fi * 3.0, 2.0)) - 0.5) * 0.2;
			float path = fract(ang + fi / 3.0 + jag);
			bolt += 1.0 - smoothstep(0.004, 0.016, abs(path - 0.5));
		}
		bolt = clamp(bolt, 0.0, 1.0);
		vec3 cloud = mix(col_a, col_b, smoothstep(0.45, 0.8, fbm(vec3(ring.xy * 2.0, along * 10.0))));
		albedo = mix(cloud, col_c, bolt);
		emit = col_c * bolt * glow * (0.75 + 0.25 * sin(TIME * 13.0));
	} else if (pattern == 31) {
		// ocean waves, crests breaking white
		float w1 = sin(ang * TAU * count + along * 60.0 + sin(along * 30.0) * 2.0);
		float crest = smoothstep(0.75, 0.95, w1);
		float band = fract(along * 25.0 + 0.15 * sin(ang * TAU * count));
		albedo = mix(mix(col_a, col_b, band), col_c, crest);
		r = mix(0.3, 0.5, crest);
	} else if (pattern == 32) {
		// cherry blossom on dark lacquer
		vec2 q = vec2(ang * count, along * count * 13.0);
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float hsh = hash12(cell);
		vec2 p = f - (vec2(hash12(cell + 3.0), hash12(cell + 7.0)) - 0.5) * 0.3;
		float an = atan(p.y, p.x) + hsh * 6.28;
		float rr = length(p);
		float flower = (1.0 - smoothstep(0.2 + 0.1 * cos(an * 5.0) - 0.02, 0.2 + 0.1 * cos(an * 5.0) + 0.02, rr)) * step(0.4, hsh);
		float centre = 1.0 - smoothstep(0.04, 0.06, rr);
		albedo = mix(col_a, col_b * (0.85 + 0.3 * rr), flower);
		albedo = mix(albedo, col_c, centre * flower);
	} else if (pattern == 33) {
		// scrimshaw: ivory scratched with inked lines
		float n = fbm(vec3(ring.xy * 5.0, along * 40.0));
		albedo = col_a * (0.88 + 0.12 * n);
		float eng = 1.0 - smoothstep(0.0, 0.05, abs(sin(along * 140.0 + sin(ang * TAU * 3.0) * 3.0)));
		float hatch = step(0.5, fract(ang * 60.0 + along * 300.0)) * step(0.6, fbm(vec3(ring.xy * 2.0, along * 15.0)));
		albedo = mix(albedo, col_b, clamp(eng * 0.8 + hatch * 0.35, 0.0, 1.0));
		r = 0.35;
	} else if (pattern == 34) {
		// sword-handle wrap: silk cord crossing over ray skin
		vec2 q = vec2(ang * count, along * count * 9.0);
		vec2 dq = vec2(q.x + q.y, q.x - q.y);
		vec2 f = fract(dq) - 0.5;
		float d = max(abs(f.x), abs(f.y));
		float cord = smoothstep(0.30, 0.36, d);
		vec3 skin = col_b * (0.8 + 0.3 * hash12(floor(vec2(ang * 300.0, along * 2000.0))));
		albedo = mix(skin, col_a * (0.85 + 0.25 * sin(dq.x * 40.0)), cord);
		r = mix(0.55, 0.45, cord);
	}

	ALBEDO = clamp(albedo, 0.0, 1.0);
	METALLIC = m;
	ROUGHNESS = clamp(r, 0.03, 1.0);
	SPECULAR = 0.55;
	CLEARCOAT = coat * (1.0 - m);
	CLEARCOAT_ROUGHNESS = 0.06;
	EMISSION = emit;
}
"""
