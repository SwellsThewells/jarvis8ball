class_name PoolFPArm
extends Node3D

# Your right arm, as you see it: a jacket sleeve bending at the elbow, and a
# hand that can make a fist or close round a glass. It hangs off the camera,
# out of sight below the frame until something needs it.
#
# Everything is placed in camera space: x right, y up, -z straight ahead.

const SHOULDER := Vector3(0.24, -0.34, 0.2)
const UPPER := 0.3
const FORE := 0.3
const HIDDEN := Vector3(0.3, -0.72, -0.2)

var _upper: MeshInstance3D
var _fore: MeshInstance3D
var _elbow: MeshInstance3D
var _cuff: MeshInstance3D
var _hand: Node3D
var _fist: Node3D
var _grip: Node3D
var _hand_xf := Transform3D(Basis.IDENTITY, HIDDEN)
var _shown := 0.0


func build() -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("2b3140")
	cloth.roughness = 0.85
	cloth.rim_enabled = true
	cloth.rim = 0.3
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("bf8e76")
	skin.roughness = 0.6
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.35
	var crease := StandardMaterial3D.new()
	crease.albedo_color = Color("9a6c58")
	crease.roughness = 0.7
	var cuff_m := StandardMaterial3D.new()
	cuff_m.albedo_color = Color("20242e")
	cuff_m.roughness = 0.8

	_upper = _limb(0.058, 0.052, cloth)
	_fore = _limb(0.05, 0.043, cloth)
	var em := SphereMesh.new()
	em.radius = 0.055
	em.height = 0.11
	_elbow = MeshInstance3D.new()
	_elbow.mesh = em
	_elbow.material_override = cloth
	add_child(_elbow)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.046
	cm.bottom_radius = 0.046
	cm.height = 0.035
	_cuff = MeshInstance3D.new()
	_cuff.mesh = cm
	_cuff.material_override = cuff_m
	add_child(_cuff)

	_hand = Node3D.new()
	add_child(_hand)
	# the hand's own frame: -z out past the knuckles, +y the back of the hand
	_fist = Node3D.new()
	_hand.add_child(_fist)
	# a right fist, palm down: the back of the hand on top, the knuckles
	# along its front edge, the fingers rolled down and under, and the thumb
	# folded across them on the left
	_blob(_fist, Vector3(0.0, 0.004, 0.012), Vector3(0.088, 0.05, 0.095), skin)
	_blob(_fist, Vector3(0.0, -0.02, 0.0), Vector3(0.082, 0.05, 0.08), skin)
	_blob(_fist, Vector3(0.0, -0.004, 0.07), Vector3(0.064, 0.048, 0.07), skin)
	# the knuckles as one ridge, the fingers rolled under as another
	_ridge(_fist, Vector3(0.001, 0.008, -0.034), 0.0145, 0.088, Vector3(1.0, 1.0, 1.0), skin)
	_ridge(_fist, Vector3(0.0, -0.018, -0.042), 0.017, 0.082, Vector3(1.35, 1.0, 1.0), skin)
	for i in 3:
		_blob(_fist, Vector3(-0.0195 + float(i) * 0.0195, -0.017, -0.0585), Vector3(0.003, 0.034, 0.004), crease)
	# the thumb, folded across the front of the fingers
	_ridge(_fist, Vector3(-0.02, -0.037, -0.042), 0.012, 0.056, Vector3(1.0, 1.0, 1.0), skin)
	_blob(_fist, Vector3(-0.042, -0.022, -0.006), Vector3(0.026, 0.03, 0.045), skin)

	_grip = Node3D.new()
	_hand.add_child(_grip)
	# fingers wrapped round a glass about 7 cm across, the glass sitting at -x
	_blob(_grip, Vector3(0.02, 0.0, 0.0), Vector3(0.03, 0.085, 0.075), skin)
	for i in 4:
		var y := 0.03 - float(i) * 0.022
		_blob(_grip, Vector3(-0.02, y, -0.045), Vector3(0.05, 0.02, 0.022), skin)
		_blob(_grip, Vector3(-0.055, y, -0.03), Vector3(0.025, 0.019, 0.03), skin)
	_blob(_grip, Vector3(-0.03, 0.035, 0.045), Vector3(0.05, 0.02, 0.022), skin)

	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _limb(r0: float, r1: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = 1.0
	c.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	add_child(mi)
	return mi


func _blob(parent: Node3D, at: Vector3, size: Vector3, m: Material) -> void:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 14
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = at
	mi.scale = size
	parent.add_child(mi)


# A rounded bar lying across the hand (along x), `r` thick and `len` long;
# `sc` stretches it across its thickness (x: up and down).
func _ridge(parent: Node3D, at: Vector3, r: float, len: float, sc: Vector3, m: Material) -> void:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = len
	c.radial_segments = 16
	c.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(sc), at)
	parent.add_child(mi)


# A limb segment from a to b.
func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1.0e-4:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1.0e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


func _place() -> void:
	var w := _hand_xf.origin + _hand_xf.basis.z * 0.07
	# elbow: two-bone IK from the shoulder, the elbow dropping down and out
	var dv := w - SHOULDER
	var d := clampf(dv.length(), 0.05, UPPER + FORE - 0.001)
	var u := dv.normalized()
	var pole := Vector3(0.6, -1.0, 0.3)
	var v := (pole - u * pole.dot(u)).normalized()
	var ca := clampf((UPPER * UPPER + d * d - FORE * FORE) / (2.0 * UPPER * d), -1.0, 1.0)
	var e := SHOULDER + (u * ca + v * sqrt(1.0 - ca * ca)) * UPPER
	var wr := SHOULDER + u * d
	_span(_upper, SHOULDER, e)
	_span(_fore, e, wr)
	_elbow.position = e
	_cuff.transform = Transform3D(Basis(_fore.transform.basis.x.normalized(), (wr - e).normalized(),
		_fore.transform.basis.z.normalized()), wr - (wr - e).normalized() * 0.01)
	_hand.transform = Transform3D(_hand_xf.basis, wr + (_hand_xf.origin - w))


static func _look(fwd: Vector3, up: Vector3) -> Basis:
	var z := -fwd.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


# The punch, `t` seconds in: the fist comes up into view, is drawn right back
# up by your ear (shaking with the effort), then thrown straight down the
# middle, and dropped away.
func punch(t: float, windup: float, strike: float) -> void:
	visible = true
	_fist.visible = true
	_grip.visible = false
	var rest := Transform3D(_look(Vector3(0.0, 0.3, -1.0), Vector3.UP), HIDDEN)
	# the back of the hand towards you, so it reads as a fist from behind
	var guard := Transform3D(_look(Vector3(0.0, 0.3, -1.0), Vector3(0.0, 1.0, 0.45)), Vector3(0.15, -0.16, -0.36))
	var back := Transform3D(_look(Vector3(0.08, 0.4, -1.0), Vector3(-0.1, 1.0, 0.55)), Vector3(0.2, -0.04, -0.27))
	var out := Transform3D(_look(Vector3(-0.05, 0.02, -1.0), Vector3(0.0, 1.0, 0.0)), Vector3(0.03, -0.07, -0.72))
	var x: Transform3D
	var up := windup * 0.3
	if t < up:
		x = rest.interpolate_with(guard, smoothstep(0.0, 1.0, t / up))
	elif t < windup:
		var k := smoothstep(0.0, 1.0, (t - up) / (windup - up))
		x = guard.interpolate_with(back, k)
		# a shake of effort at the top of the wind-up
		x.origin += Vector3(sin(t * 60.0), cos(t * 47.0), 0.0) * 0.006 * k
	elif t < windup + strike:
		var k := pow((t - windup) / strike, 0.5)
		x = back.interpolate_with(out, k)
	else:
		var k := smoothstep(0.0, 1.0, clampf((t - windup - strike - 0.1) / 0.35, 0.0, 1.0))
		x = out.interpolate_with(rest, k)
	_hand_xf = x
	_place()


# Holding a glass: low in front of you at `raise` 0, at your lips at 1, and
# tipped up to drink by `tilt`.
func hold(raise: float, tilt: float) -> void:
	visible = true
	_fist.visible = false
	_grip.visible = true
	var low := Vector3(0.15, -0.15, -0.4)
	var mouth := Vector3(0.05, -0.09, -0.17)
	var p := low.lerp(mouth, smoothstep(0.0, 1.0, raise))
	var b := _look(Vector3(-0.2, 0.0, -1.0), Vector3.UP)
	b = b.rotated(Vector3.RIGHT, -0.15 * raise)
	b = Basis(Vector3(1, 0, 0), 1.25 * tilt) * b
	_hand_xf = Transform3D(b, p)
	_place()


# Where a held glass sits, in camera space: in the fingers, upright with the
# hand.
func glass_xf() -> Transform3D:
	var h := _hand.transform
	return Transform3D(h.basis, h.origin + h.basis * Vector3(-0.045, -0.055, -0.01))


func hide_arm() -> void:
	visible = false
