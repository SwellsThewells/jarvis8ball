class_name PoolCueView
extends Node3D

# Added as a child of the table, so all coordinates here are table-local:
# x, z are the physics plane and y = 0 is the cloth.

const R := PoolSim.R

var stick_root: Node3D
var stick: Node3D
var guide: MeshInstance3D
var guide_mesh: ImmediateMesh
var _guide_mat: StandardMaterial3D
var skin_id := "house"
var _added := 0


func build() -> void:
	stick_root = Node3D.new()
	add_child(stick_root)
	stick = Node3D.new()
	stick.rotation_degrees = Vector3(0, 0, -90)   # cylinders run along local +X
	stick_root.add_child(stick)
	_build_stick()

	guide_mesh = ImmediateMesh.new()
	guide = MeshInstance3D.new()
	guide.mesh = guide_mesh
	_guide_mat = StandardMaterial3D.new()
	_guide_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_guide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guide_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_guide_mat.vertex_color_use_as_albedo = true
	_guide_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	guide.material_override = _guide_mat
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(guide)


# Swap the stick for another skin. Always rebuilt, so what you picked in the
# shop is what you are holding the moment you go back to the table.
func set_skin(id: String) -> void:
	skin_id = id
	for c in stick.get_children():
		stick.remove_child(c)
		c.queue_free()
	_build_stick()


func _build_stick() -> void:
	var model := PoolCueModel.build(PoolCues.by_id(skin_id))
	stick.add_child(model)


# How far off the ball the tip rests before you draw it back.
const TIP_GAP := 0.012


# Place the cue behind the ball. `pull` is how far it is drawn back, `elev`
# how far the butt is raised, and `english` where on the ball the tip is
# pointed, in ball radii (x right, y up), so the stick sits where you'll hit.
func aim(cue_pos: Vector2, dir: Vector2, pull: float, elev := 0.075, english := Vector2.ZERO) -> void:
	stick_root.visible = true
	var back := Vector3(-dir.x, 0.0, -dir.y)
	var right := Vector3(-dir.y, 0.0, dir.x)
	var off := right * (english.x * R) + Vector3.UP * (english.y * R)
	var axis := back * cos(elev) + Vector3.UP * sin(elev)
	stick_root.position = Vector3(cue_pos.x, R, cue_pos.y) + off
	stick_root.rotation = Vector3(0.0, atan2(-back.z, back.x), elev)
	stick.position = Vector3(tip_distance(off, axis) + pull, 0.0, 0.0)


# Where the cue model sits for the same arguments as aim(), in table-local
# space, for a stick that belongs to somebody else's hands.
static func stick_transform(cue_pos: Vector2, dir: Vector2, pull: float, elev: float,
		english := Vector2.ZERO) -> Transform3D:
	var back := Vector3(-dir.x, 0.0, -dir.y)
	var right := Vector3(-dir.y, 0.0, dir.x)
	var off := right * (english.x * R) + Vector3.UP * (english.y * R)
	var axis := back * cos(elev) + Vector3.UP * sin(elev)
	var root := Transform3D(Basis.from_euler(Vector3(0.0, atan2(-back.z, back.x), elev)),
		Vector3(cue_pos.x, R, cue_pos.y) + off)
	var stick := Transform3D(Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-90.0))),
		Vector3(tip_distance(off, axis) + pull, 0.0, 0.0))
	return root * stick


# Along the stick from `off` (relative to the ball centre), how far until the
# tip is TIP_GAP clear of the ball.
static func tip_distance(off: Vector3, axis: Vector3) -> float:
	var ob := off.dot(axis)
	var rr := (R + TIP_GAP) * (R + TIP_GAP)
	return -ob + sqrt(maxf(ob * ob - off.length_squared() + rr, 0.0))


func hide_stick() -> void:
	stick_root.visible = false


# Ball in hand: a ring on the cloth where the cue ball will go, white when the
# spot is good and red when it is not, and the head string on the break.
func draw_place_marker(p: Vector2, ok: bool, head_line: bool) -> void:
	guide_mesh.clear_surfaces()
	guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.004
	var col := Color(0.85, 0.92, 1.0, 0.8) if ok else Color(1.0, 0.25, 0.18, 0.9)
	_ring(p, R * 1.25, y, col, 40, 0.004)
	if head_line:
		var hx := PoolSim.HEAD_X
		_seg(Vector2(hx, -PoolSim.HALF_WID), Vector2(hx, PoolSim.HALF_WID), y,
			Color(1.0, 1.0, 1.0, 0.22), Color(1.0, 1.0, 1.0, 0.22), 0.003)
	guide_mesh.surface_end()


# ---------------------------------------------------------------------------
# Aiming guide
# ---------------------------------------------------------------------------

func clear_guide() -> void:
	guide_mesh.clear_surfaces()


func draw_guide(sim: PoolSim, dir: Vector2, tint: Color) -> void:
	guide_mesh.clear_surfaces()
	var cue := sim.ball(PoolSim.CUE)
	var hit := sim.trace(cue.pos, dir)
	var y := 0.006
	# ribbons rather than hairlines: a one-pixel line disappears against cloth
	guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_added = 0

	var blue := Color(0.40, 0.72, 1.0, 0.95)
	var contact: Vector2 = hit.point
	_dashed(cue.pos, contact, y, blue, 0.034, 0.018, 0.008)

	if hit.kind == "ball":
		var obj := sim.ball(hit.ball)
		_ring(contact, R, y, Color(0.55, 0.82, 1.0, 0.85), 34, 0.0045)
		var line := (obj.pos - contact).normalized()
		_seg(obj.pos, obj.pos + line * 0.62, y, Color(1.0, 0.86, 0.62, 0.95),
			Color(1.0, 0.86, 0.62, 0.0), 0.009)
		# cue ball carries on along the tangent
		var tangent := Vector2(-line.y, line.x)
		var side := tangent if tangent.dot(dir) > 0.0 else -tangent
		var carry: float = clampf(absf(dir.dot(side)), 0.0, 1.0)
		_seg(contact, contact + side * (0.38 * carry + 0.05), y,
			Color(0.45, 0.75, 1.0, 0.7), Color(0.45, 0.75, 1.0, 0.0), 0.007)
	elif hit.kind == "rail":
		var n: Vector2 = hit.normal
		var refl := dir - 2.0 * dir.dot(n) * n
		_seg(contact, contact + refl * 0.5, y, Color(0.40, 0.72, 1.0, 0.6),
			Color(0.40, 0.72, 1.0, 0.0), 0.007)

	# a line that runs out through a pocket gap draws nothing, and an empty
	# surface is an error: close it with one invisible, zero-size triangle
	if _added == 0:
		for _i in 3:
			guide_mesh.surface_set_color(Color(0, 0, 0, 0))
			guide_mesh.surface_add_vertex(Vector3(cue.pos.x, y, cue.pos.y))
	guide_mesh.surface_end()


func _seg(a: Vector2, b: Vector2, y: float, ca: Color, cb: Color, w := 0.007) -> void:
	var d := b - a
	if d.length_squared() < 1.0e-8:
		return
	var n := Vector2(-d.y, d.x).normalized() * (w * 0.5)
	var a1 := Vector3(a.x + n.x, y, a.y + n.y)
	var a2 := Vector3(a.x - n.x, y, a.y - n.y)
	var b1 := Vector3(b.x + n.x, y, b.y + n.y)
	var b2 := Vector3(b.x - n.x, y, b.y - n.y)
	for v in [[a1, ca], [b1, cb], [b2, cb], [a1, ca], [b2, cb], [a2, ca]]:
		guide_mesh.surface_set_color(v[1])
		guide_mesh.surface_add_vertex(v[0])
	_added += 1


func _dashed(a: Vector2, b: Vector2, y: float, col: Color, dash: float, gap: float, w := 0.007) -> void:
	var d := b - a
	var total := d.length()
	if total < 1e-4:
		return
	var dir := d / total
	var t := 0.0
	while t < total:
		var t2: float = minf(t + dash, total)
		var fade: float = 1.0 - t / maxf(total, 0.001) * 0.55
		var c := Color(col.r, col.g, col.b, col.a * fade)
		_seg(a + dir * t, a + dir * t2, y, c, c, w)
		t = t2 + gap


func _ring(c: Vector2, r: float, y: float, col: Color, segs: int, w := 0.005) -> void:
	var prev := c + Vector2(r, 0.0)
	for i in range(1, segs + 1):
		var ang := TAU * float(i) / float(segs)
		var p := c + Vector2(cos(ang), sin(ang)) * r
		_seg(prev, p, y, col, col, w)
		prev = p
