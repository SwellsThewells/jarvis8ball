class_name PoolCharacter
extends Node3D

# Somebody else in the room: a rigged model, the one idle clip it came with,
# and a body animated on top of that clip every frame.
#
# Feet are planted on the floor and only step when the body has moved off
# them, so nothing ever slides or pops. Legs and arms reach with two-bone IK:
# the legs to wherever the feet are planted, the back hand always to the cue,
# the front hand to the bridge, the chin, the cue ball. The spine bends over a
# shot, the head turns to look. Every layer eases in and out, so the body
# never jumps from one pose to the next.
#
# It knows nothing about pool or about who is steering it: the bot's brain
# drives this one, and a player over the network will drive another.

signal stepped(at: Vector3, strength: float)
signal getting_up
signal landed(at: Vector3)

# anything else on the floor a body can't lie across: [centre, radius]
static var obstacles: Array = []

const RADIUS := 0.30
const WALK_SPEED := 0.85
const ACCEL := 2.0
const TURN_RATE := 2.6
const ANKLE_H := 0.092
const STEP_TRIGGER := 0.12
const LEAD := 0.2
const LIFT := 0.065
const GRIP := 1.17          # metres from the tip where the back hand holds the cue
# Getting back up after being knocked flat: long and wobbly. Deliberately daft.
const KO_RISE := 3.6
# Knocked flat by you: a real ragdoll, then his own two feet again
const RAG_TIME := 6.2         # flying, landing and lying there, all physics
const RAG_BLEND := 0.8        # from the heap he ended in to the lying pose
const LAUNCH_SPEED := 6.0     # m/s back, and up
const LAUNCH_UP := 3.4
# bone, the bone its body reaches to, thickness, mass, swing and twist
# allowed at its joint (degrees; 0 for the root), length if not the gap
const RAG_BONES := [
	["Hips", "Spine", 0.14, 12.0, 0.0, 0.0, 0.24],
	["Spine", "Spine2", 0.13, 9.0, 25.0, 15.0, 0.0],
	["Spine2", "Neck", 0.15, 11.0, 20.0, 15.0, 0.0],
	["Head", "HeadTop_End", 0.1, 5.0, 40.0, 35.0, 0.0],
	["LeftArm", "LeftForeArm", 0.05, 2.2, 75.0, 20.0, 0.0],
	["LeftForeArm", "LeftHand", 0.045, 1.6, 70.0, 10.0, 0.3],
	["RightArm", "RightForeArm", 0.05, 2.2, 75.0, 20.0, 0.0],
	["RightForeArm", "RightHand", 0.045, 1.6, 70.0, 10.0, 0.3],
	["LeftUpLeg", "LeftLeg", 0.075, 7.0, 55.0, 15.0, 0.0],
	["LeftLeg", "LeftFoot", 0.058, 3.5, 60.0, 8.0, 0.0],
	["LeftFoot", "LeftToeBase", 0.045, 1.0, 30.0, 5.0, 0.0],
	["RightUpLeg", "RightLeg", 0.075, 7.0, 55.0, 15.0, 0.0],
	["RightLeg", "RightFoot", 0.058, 3.5, 60.0, 8.0, 0.0],
	["RightFoot", "RightToeBase", 0.045, 1.0, 30.0, 5.0, 0.0],
]
# his own punch: a huge wind-up, then the swing
const PUNCH_WINDUP := 0.55
const PUNCH_STRIKE := 0.13
const PUNCH_RECOVER := 0.45
const PUNCH_HIT := PUNCH_WINDUP + PUNCH_STRIKE

# The knock-down as poses in the body's own frame (x to its left, y up, z
# forward): time, hips height (-1: standing height), hips back, torso lean
# back, each foot, each hand, how much the hands are doing it, toes up.
# Lying flat, the feet point back at whoever did it.
const LIE_KEY := [0.0, 0.13, 0.3, 1.4, Vector3(0.16, 0.08, 0.6), Vector3(-0.14, 0.08, 0.64),
	Vector3(0.62, 0.05, -0.48), Vector3(-0.6, 0.05, -0.42), 1.0, 1.0]
# getting back up, in seconds: sat up on his hands, over onto a knee, pushing
# up off it, nearly there, legs going, and at last stood
const RISE_KEYS := [
	[0.0, 0.13, 0.3, 1.4, Vector3(0.16, 0.08, 0.6), Vector3(-0.14, 0.08, 0.64), Vector3(0.62, 0.05, -0.48), Vector3(-0.6, 0.05, -0.42), 1.0, 1.0],
	[0.9, 0.16, 0.24, 0.22, Vector3(0.13, 0.08, 0.5), Vector3(-0.15, 0.08, 0.55), Vector3(0.3, 0.05, -0.22), Vector3(-0.3, 0.05, -0.22), 1.0, 1.0],
	[1.8, 0.47, 0.06, -0.55, Vector3(0.15, 0.092, 0.34), Vector3(-0.13, 0.1, -0.3), Vector3(0.14, 0.52, 0.36), Vector3(-0.26, 0.05, 0.3), 1.0, 0.0],
	[2.5, 0.78, 0.0, -0.3, Vector3(0.12, 0.092, 0.14), Vector3(-0.12, 0.092, -0.06), Vector3(0.18, 0.62, 0.2), Vector3(-0.2, 0.62, 0.15), 0.8, 0.0],
	[2.85, 0.64, 0.02, -0.42, Vector3(0.12, 0.092, 0.14), Vector3(-0.12, 0.092, -0.06), Vector3(0.18, 0.55, 0.22), Vector3(-0.2, 0.55, 0.18), 0.9, 0.0],
	[3.6, -1.0, 0.0, 0.0, Vector3(0.11, 0.092, 0.0), Vector3(-0.11, 0.092, 0.0), Vector3(0.2, 0.8, 0.1), Vector3(-0.2, 0.8, 0.1), 0.0, 0.0],
]
const BRIDGE := 0.21        # where the shaft rests on the front hand

const TABLE_HALF := Vector2(
	PoolSim.HALF_LEN + PoolTableView.CUSHION_D + PoolTableView.CAP_W + 0.2,
	PoolSim.HALF_WID + PoolTableView.CUSHION_D + PoolTableView.CAP_W + 0.2)
const ROOM_HALF := Vector2(5.1, 3.7)

# feet, in the body's own frame: x to its left, y forward
const FEET_STAND := [Vector2(0.11, 0.0), Vector2(-0.11, 0.0)]
const FEET_STANCE := [Vector2(0.17, 0.28), Vector2(-0.10, -0.17)]
const SPLAY_STAND := [0.12, -0.12]
const SPLAY_STANCE := [0.05, -0.75]
# how far each spine bone bends over a shot, and turns, in radians
const STANCE_BEND := [0.58, 0.46, 0.34]
const STANCE_TWIST := [-0.06, -0.08, -0.06]
const REACH_BEND := [0.40, 0.32, 0.22]
const THINK_BEND := [0.03, 0.05, 0.06]

enum { R_NONE, R_HIPS, R_SPINE, R_SPINE1, R_SPINE2, R_NECK, R_HEAD,
	R_L_ARM, R_L_FORE, R_L_HAND, R_R_ARM, R_R_FORE, R_R_HAND,
	R_L_THIGH, R_L_SHIN, R_L_FOOT, R_R_THIGH, R_R_SHIN, R_R_FOOT }

const BONES := {
	R_HIPS: "Hips", R_SPINE: "Spine", R_SPINE1: "Spine1", R_SPINE2: "Spine2",
	R_NECK: "Neck", R_HEAD: "Head",
	R_L_ARM: "LeftArm", R_L_FORE: "LeftForeArm", R_L_HAND: "LeftHand",
	R_R_ARM: "RightArm", R_R_FORE: "RightForeArm", R_R_HAND: "RightHand",
	R_L_THIGH: "LeftUpLeg", R_L_SHIN: "LeftLeg", R_L_FOOT: "LeftFoot",
	R_R_THIGH: "RightUpLeg", R_R_SHIN: "RightLeg", R_R_FOOT: "RightFoot",
}

var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var cue: Node3D
var cue_id := ""

# where the body is, on the floor
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var yaw := 0.0
var _yaw_vel := 0.0
var shove := Vector2.ZERO        # knocked about: moves the body without turning it
var avoid := Vector2.ZERO        # steering nudge from whoever drives it

var _path: Array = []
var _path_i := 0
var _speed := WALK_SPEED
var _face := INF

# what the body is being asked to do
var stance_on := false
var think_on := false
var reach_point: Variant = null
var holding_ball := false
var look_target: Variant = null
var lean_extra := 0.0            # metres short of the ideal stance: bend further

# and how far into each it is, eased 0..1
var _ss := 0.0
var _ts := 0.0
var _rs := 0.0
var _hs := 0.0
var _cs := 0.0
var _ls := 0.0
var _hold_s := 0.0
var walk_w := 0.0
var _dt := 0.016

var _shot_xf := Transform3D()
var _shot_rest := Transform3D()
var _has_shot := false
var _cue_xf := Transform3D()
var _reach_w := Vector3.ZERO

var _look := Vector3.ZERO
var _look_yp := Vector2.ZERO     # head turn and nod from the chest, eased
var _look_over := Vector3.ZERO
var _look_over_t := 0.0

var _hit_axis := Vector3.RIGHT   # body space
var _hit_ang := 0.0
var _hit_vel := 0.0
var _hurt_t := 0.0
var _stun_t := 0.0
var _punch_t := -1.0
var _punch_at := Vector3.ZERO
var _punch_stepped := false
var _ko_t := -1.0                # seconds since the blow, -1 when on your feet
var _ko_dir := Vector3.BACK      # world, the way the blow sent you
var _ko_w := 0.0                 # how much of the body the knock-down owns
var _ko_pose := {}
var _rising := false
var _dizzy := 0.0
var _air := 0.0                  # the whole body off the floor, in flight
var _stars: Node3D
var _sim: PhysicalBoneSimulator3D
var _rag: Array = []
var _rag_bone: Array = []
var _rag_half: Array = []
var _rag_hips: PhysicalBone3D
var _rag_head: PhysicalBone3D
var _rag_rarm: PhysicalBone3D
var _rag_rot: Array = []          # captured local rotations, per bone (null: not simulated)
var _rag_hips_xf := Transform3D()
var _rag_w := 0.0                 # how much of the pose is still the heap he landed in
var _rag_landed := false

# feet, in world space; t < 1 while a foot is in the air
var _foot: Array = [Vector3.ZERO, Vector3.ZERO]
var _foot_from: Array = [Vector3.ZERO, Vector3.ZERO]
var _foot_to: Array = [Vector3.ZERO, Vector3.ZERO]
var _foot_t: Array = [1.0, 1.0]
var _foot_dur: Array = [0.35, 0.35]
var _foot_lift: Array = [1.0, 1.0]
var _foot_yaw: Array = [0.0, 0.0]
var _foot_yaw_from: Array = [0.0, 0.0]
var _foot_yaw_to: Array = [0.0, 0.0]
var _settle := 0.0
var _hip_drop := 0.0
var _bob := 0.0

# the rig
var _S := Transform3D()          # skeleton space from body space
var _C := Transform3D()          # body space from skeleton space
var _w2s := Transform3D()
var _s2w := Transform3D()
var _par := PackedInt32Array()
var _order := PackedInt32Array()
var _role := PackedInt32Array()
var _child := PackedInt32Array()
var _len := PackedFloat32Array()
var _L: Array[Transform3D] = []
var _G: Array[Transform3D] = []
var _b := {}
var _f_head := Vector3.ZERO      # the head's forward, in its own frame
var _f_chest := Vector3.ZERO
var _u_chest := Vector3.ZERO
var _cU := Vector3.UP            # body axes in skeleton space
var _cL := Vector3.RIGHT
var _cF := Vector3.BACK
var _hips_rest := Vector3.ZERO   # body space
var _toe_drop := 0.08
var _pending := {}
var _mid_l := -1

# where things ended up this frame, in world space
var head_w := Vector3(0, 1.6, 0)
var head_fwd_w := Vector3.FORWARD
var hips_w := Vector3(0, 0.9, 0)
var lhand_w := Vector3.ZERO
var rhand_w := Vector3.ZERO
var _lmid_w := Vector3.ZERO


# ---------------------------------------------------------------------------
# Setting up
# ---------------------------------------------------------------------------

func build(path: String, texture_path := "") -> void:
	model = (load(path) as PackedScene).instantiate()
	add_child(model)
	# anything the file carries besides the body (a camera, empty helpers) goes
	for c in model.get_children():
		if c is AnimationPlayer:
			continue
		if c.find_children("*", "Skeleton3D", true, false).is_empty():
			model.remove_child(c)
			c.queue_free()
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]

	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# the body bends a long way from where it was modelled
		m.extra_cull_margin = 1.2
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si)
			if src is BaseMaterial3D:
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				# the clothes are single sheets: bent far enough, you'd see
				# through the inside of the shirt without this
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				if texture_path != "" and ResourceLoader.exists(texture_path):
					mat.albedo_texture = load(texture_path)
				m.set_surface_override_material(si, mat)

	# skeleton space against this node's space, from the transforms between
	var t := Transform3D.IDENTITY
	var n: Node = skel
	while n != self:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	_C = t
	_S = t.affine_inverse()
	_cU = (_S.basis * Vector3.UP).normalized()
	_cL = (_S.basis * Vector3.RIGHT).normalized()
	_cF = (_S.basis * Vector3.BACK).normalized()

	var count := skel.get_bone_count()
	_par.resize(count)
	_role.resize(count)
	_child.resize(count)
	_len.resize(count)
	_L.resize(count)
	_G.resize(count)
	for i in count:
		_par[i] = skel.get_bone_parent(i)
		_role[i] = R_NONE
		_child[i] = -1
	for r in BONES:
		var idx := _find(BONES[r])
		_b[r] = idx
		if idx >= 0:
			_role[idx] = r
	_mid_l = _find("LeftHandMiddle1")
	var chains := [[R_L_ARM, R_L_FORE, R_L_HAND], [R_R_ARM, R_R_FORE, R_R_HAND],
		[R_L_THIGH, R_L_SHIN, R_L_FOOT], [R_R_THIGH, R_R_SHIN, R_R_FOOT]]
	for ch in chains:
		_child[_b[ch[0]]] = _b[ch[1]]
		_child[_b[ch[1]]] = _b[ch[2]]
	_child[_b[R_L_FOOT]] = _find("LeftToeBase")
	_child[_b[R_R_FOOT]] = _find("RightToeBase")
	for i in count:
		if _child[i] >= 0:
			_len[i] = skel.get_bone_rest(_child[i]).origin.length()
	# parents before children, whatever order the file lists them in
	var queue: Array[int] = []
	for i in count:
		if _par[i] < 0:
			queue.append(i)
	while not queue.is_empty():
		var b: int = queue.pop_front()
		_order.append(b)
		for c in skel.get_bone_children(b):
			queue.append(c)

	var head_rest := skel.get_bone_global_rest(_b[R_HEAD]).basis.orthonormalized()
	var chest_rest := skel.get_bone_global_rest(_b[R_SPINE2]).basis.orthonormalized()
	_f_head = (head_rest.inverse() * _cF).normalized()
	_f_chest = (chest_rest.inverse() * _cF).normalized()
	_u_chest = (chest_rest.inverse() * _cU).normalized()
	_hips_rest = _C * skel.get_bone_rest(_b[R_HIPS]).origin
	var foot_r := skel.get_bone_global_rest(_b[R_L_FOOT]).origin
	var toe_r := skel.get_bone_global_rest(_child[_b[R_L_FOOT]]).origin
	_toe_drop = maxf((foot_r - toe_r).dot(_cU), 0.0)

	# the clip he came with: standing, breathing, looking about. Played back
	# and forth so there is never a seam where it loops.
	var clip: StringName = anim.get_animation_list()[0]
	anim.get_animation(clip).loop_mode = Animation.LOOP_PINGPONG
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play(clip)
	anim.seek(randf() * anim.current_animation_length, true)

	cue = Node3D.new()
	cue.name = "Cue"
	add_child(cue)
	_make_stars()
	_build_ragdoll()


# The little yellow stars that go round your head when you've been hit.
func _make_stars() -> void:
	_stars = Node3D.new()
	_stars.top_level = true
	_stars.visible = false
	add_child(_stars)
	for i in 5:
		_stars.add_child(star(true))


# One cartoon star, a unit across.
static func star(billboard: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a0 := TAU * float(i) / 10.0 + PI * 0.5
		var a1 := TAU * float(i + 1) / 10.0 + PI * 0.5
		var r0 := 1.0 if i % 2 == 0 else 0.45
		var r1 := 1.0 if (i + 1) % 2 == 0 else 0.45
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0.0))
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.7, 1.35, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	var s := MeshInstance3D.new()
	s.mesh = st.commit()
	s.material_override = m
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


func _update_stars() -> void:
	var on := _dizzy > 0.01
	_stars.visible = on
	if not on:
		return
	var c := head_w + Vector3.UP * 0.2
	var tt := Time.get_ticks_msec() * 0.001
	var i := 0
	for s in _stars.get_children():
		var a := tt * 2.4 + TAU * float(i) / 5.0
		var st := s as Node3D
		st.position = c + Vector3(cos(a) * 0.2, 0.035 * sin(a * 2.0 + float(i)), sin(a) * 0.2)
		st.scale = Vector3.ONE * 0.045 * _dizzy * (0.85 + 0.15 * sin(tt * 7.0 + float(i)))
		i += 1


func _find(bone: String) -> int:
	for prefix in ["mixamorig_", "mixamorig:", "mixamorig1_", ""]:
		var i := skel.find_bone(prefix + bone)
		if i >= 0:
			return i
	return -1


func set_cue(id: String) -> void:
	if id == cue_id:
		return
	cue_id = id
	for c in cue.get_children():
		cue.remove_child(c)
		c.queue_free()
	cue.add_child(PoolCueModel.build(PoolCues.by_id(id)))


# Put the body somewhere at once, feet and all. Only for when it first
# appears; everything after that walks.
func place(p: Vector2, facing: float) -> void:
	pos = p
	yaw = facing
	vel = Vector2.ZERO
	shove = Vector2.ZERO
	_yaw_vel = 0.0
	_path.clear()
	_path_i = 0
	_face = INF
	_sync_node()
	for f in 2:
		_foot[f] = _home(f, false)
		_foot_t[f] = 1.0
		_foot_yaw[f] = _home_yaw(f)


# ---------------------------------------------------------------------------
# Driving it
# ---------------------------------------------------------------------------

func go(points: Array, face_yaw := INF, speed := WALK_SPEED) -> void:
	_path = points.duplicate()
	_path_i = 0
	_face = face_yaw
	_speed = speed


func stop(face_yaw := INF) -> void:
	_path.clear()
	_path_i = 0
	_face = face_yaw


func face(face_yaw: float) -> void:
	_face = face_yaw


func arrived() -> bool:
	return _path_i >= _path.size() and vel.length() < 0.06 and \
		(_face == INF or absf(wrapf(_face - yaw, -PI, PI)) < 0.08)


func goal() -> Variant:
	return _path[_path.size() - 1] if not _path.is_empty() else null


func set_shot_cue(now_w: Transform3D, rest_w: Transform3D) -> void:
	_shot_xf = now_w
	_shot_rest = rest_w
	_has_shot = true


func clear_shot() -> void:
	_has_shot = false


func stance_ready() -> bool:
	return stance_on and _ss >= 0.999 and _cs >= 0.999 and _foot_t[0] >= 1.0 \
		and _foot_t[1] >= 1.0 and _settle > 0.2 and not stunned()


func stood_up() -> bool:
	return _ss < 0.02


func stunned() -> bool:
	return _stun_t > 0.0


func anchored() -> bool:
	return _ss > 0.2


# Punched: he goes limp and the physics has him. Launched up and back across
# the room, arms and legs going wherever they go, bouncing off whatever's in
# the way, and he lies where he lands seeing stars for a good few seconds.
# Then a long struggle back up. Down over a shot or not, it's the same;
# afterwards he walks back and takes it up again where he left it.
func hit(from_world: Vector3, strength := 1.0) -> void:
	var d := Vector2(pos.x - from_world.x, pos.y - from_world.z)
	if d.length_squared() < 1.0e-4:
		d = -forward()
	d = d.normalized()
	if _ko_t >= 0.0:
		return
	_ko_dir = Vector3(d.x, 0.0, d.y)
	_ko_t = 0.0
	_rag_landed = false
	_rag_w = 0.0
	_start_ragdoll(_ko_dir * LAUNCH_SPEED * strength + Vector3.UP * LAUNCH_UP * strength)
	_rising = false
	_stun_t = ko_length() + 0.3
	_hurt_t = _stun_t + 1.2
	_punch_t = -1.0
	_path.clear()
	_path_i = 0
	vel = Vector2.ZERO
	shove = Vector2.ZERO
	var dc := (global_transform.basis.inverse() * _ko_dir).normalized()
	_hit_axis = Vector3.UP.cross(dc).normalized()
	_hit_vel += 3.0
	_look_over = from_world
	_look_over_t = 0.0


func knocked() -> bool:
	return _ko_t >= 0.0


# The whole knock-down, from the blow to stood up again.
func ko_length() -> float:
	return RAG_TIME + RAG_BLEND + KO_RISE


# ---------------------------------------------------------------------------
# The ragdoll
# ---------------------------------------------------------------------------

# A physics body on each of the big bones, jointed to the one above with as
# much swing as a real joint has. They collide with the room (layer 1) but
# not with each other, which is what keeps a heap of limbs from fighting
# itself and jittering.
func _build_ragdoll() -> void:
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "Ragdoll"
	skel.add_child(_sim)
	for spec in RAG_BONES:
		var b := _find(spec[0])
		if b < 0:
			continue
		var c := _find(spec[1])
		var here := skel.get_bone_global_rest(b)
		var v: Vector3
		if c >= 0:
			v = here.affine_inverse() * skel.get_bone_global_rest(c).origin
		else:
			v = here.basis.inverse() * (_S.basis * Vector3.UP)
		if float(spec[6]) > 0.0:
			v = v.normalized() * float(spec[6])
		var length := v.length()
		var half := length * 0.5
		var r: float = spec[2]
		var up := Vector3.UP
		if up.cross(v).is_zero_approx():
			up = Vector3.BACK
		var bb := Basis.looking_at(v, up)
		var pb := PhysicalBone3D.new()
		pb.name = "Rag_" + str(spec[0])
		pb.bone_name = skel.get_bone_name(b)
		pb.body_offset = Transform3D(bb, bb * Vector3(0.0, 0.0, -half))
		pb.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, half))
		pb.mass = spec[3]
		pb.friction = 0.9
		pb.bounce = 0.05
		pb.linear_damp = 0.05
		pb.angular_damp = 0.9
		pb.collision_layer = 1 << 3
		pb.collision_mask = 1
		if float(spec[4]) > 0.0:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", spec[4])
			pb.set("joint_constraints/twist_span", spec[5])
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = maxf(length, r * 2.0 + 0.02)
		var cs := CollisionShape3D.new()
		cs.shape = cap
		cs.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		pb.add_child(cs)
		_sim.add_child(pb)
		_rag.append(pb)
		_rag_bone.append(b)
		_rag_half.append(half)
		if str(spec[0]) == "Hips":
			_rag_hips = pb
		elif str(spec[0]) == "Head":
			_rag_head = pb
		elif str(spec[0]) == "RightForeArm":
			_rag_rarm = pb


func _start_ragdoll(v: Vector3) -> void:
	var sg := skel.global_transform
	for i in _rag.size():
		var pb: PhysicalBone3D = _rag[i]
		pb.global_transform = sg * skel.get_bone_global_pose(_rag_bone[i]) * pb.body_offset
	_sim.active = true
	_sim.influence = 1.0
	_sim.physical_bones_start_simulation()
	# a proper wallop: the top half goes faster than the legs, so he tips
	# over backwards on the way
	for i in _rag.size():
		var pb: PhysicalBone3D = _rag[i]
		var h := clampf((pb.global_position.y - position.y) / 1.6, 0.0, 1.0)
		pb.linear_velocity = v * (0.7 + 0.5 * h)
		# and tumbling over backwards, heels up
		pb.angular_velocity = Vector3.UP.cross(Vector3(v.x, 0.0, v.z).normalized()) * 6.0


# Where the physics left him, as bone poses, and the body moved to lie there,
# so the struggle up starts from exactly that heap.
func _end_ragdoll() -> void:
	var sg := skel.global_transform
	var cap_g := {}
	for i in _rag.size():
		var pb: PhysicalBone3D = _rag[i]
		cap_g[_rag_bone[i]] = sg.affine_inverse() * pb.global_transform * pb.body_offset.affine_inverse()
	var hips_world: Vector3 = _rag_hips.global_position
	var head_world: Vector3 = _rag_head.global_position if _rag_head != null else hips_world + _ko_dir
	var hips_w_xf: Transform3D = sg * (cap_g[_b[R_HIPS]] as Transform3D)
	# local rotations of the simulated bones, against whatever holds them
	var g := {}
	_rag_rot.clear()
	_rag_rot.resize(skel.get_bone_count())
	for b in _order:
		var p := _par[b]
		var gl: Transform3D
		if cap_g.has(b):
			gl = cap_g[b]
		else:
			gl = (g[p] as Transform3D) * skel.get_bone_pose(b) if p >= 0 else skel.get_bone_pose(b)
		g[b] = gl
		if cap_g.has(b):
			var local := (g[p] as Transform3D).affine_inverse() * gl if p >= 0 else gl
			_rag_rot[b] = local.basis.get_rotation_quaternion()
		else:
			_rag_rot[b] = null
	_sim.physical_bones_stop_simulation()
	_sim.active = false
	# lie the body down along the heap: feet away from the head
	var hd := Vector2(head_world.x - hips_world.x, head_world.z - hips_world.z)
	if hd.length_squared() < 1.0e-4:
		hd = Vector2(_ko_dir.x, _ko_dir.z)
	hd = hd.normalized()
	yaw = atan2(-hd.x, -hd.y)
	var fwd := forward()
	pos = Vector2(hips_world.x, hips_world.z) + fwd * 0.3
	# up off the table, if that's where he ended up
	var q := Vector2(absf(pos.x) - TABLE_HALF.x, absf(pos.y) - TABLE_HALF.y)
	if q.x < 0.0 and q.y < 0.0:
		if q.x > q.y:
			pos.x = signf(pos.x) * (TABLE_HALF.x + 0.05)
		else:
			pos.y = signf(pos.y) * (TABLE_HALF.y + 0.05)
	pos.x = clampf(maxf(pos.x, BarRoom.BAR_FRONT_X + 0.35), -ROOM_HALF.x, ROOM_HALF.x)
	pos.y = clampf(pos.y, -ROOM_HALF.y, ROOM_HALF.y)
	_air = 0.0
	_sync_node()
	# the hips, where they were in the world, in the skeleton's new place
	_rag_hips_xf = skel.global_transform.affine_inverse() * hips_w_xf
	_rag_w = 1.0


# Whether a body can lie at `p`: clear of the table, the bar, the walls and
# the furniture.
static func lie_clear(p: Vector2) -> bool:
	var box := TABLE_HALF - Vector2(0.12, 0.12)
	if absf(p.x) < box.x and absf(p.y) < box.y:
		return false
	if absf(p.x) > ROOM_HALF.x + 0.3 or absf(p.y) > ROOM_HALF.y + 0.3:
		return false
	if p.x < BarRoom.BAR_FRONT_X + 0.18:
		return false
	for o in obstacles:
		if p.distance_to(o[0]) < float(o[1]) + 0.12:
			return false
	return true


# Where you can stand afterwards.
static func stand_clear(p: Vector2) -> bool:
	if absf(p.x) < TABLE_HALF.x and absf(p.y) < TABLE_HALF.y:
		return false
	if absf(p.x) > ROOM_HALF.x or absf(p.y) > ROOM_HALF.y or p.x < BarRoom.BAR_FRONT_X + 0.35:
		return false
	for o in obstacles:
		if p.distance_to(o[0]) < float(o[1]) + 0.25:
			return false
	return true


# How far a body flies from `from` along `d` before something stops it (the
# table, the bar, the walls, the stools) and which way it ends up lying:
# [where the feet land, the way the head points]. A body is about a metre
# long, so the room behind has to be clear too; thrown up against something,
# it lies alongside it instead.
static func landing(from: Vector2, d: Vector2, dist: float) -> Array:
	var p := from
	var step := 0.05
	var travelled := 0.0
	while travelled < dist:
		var q := p + d * step
		if not (stand_clear(q) and lie_clear(q + d * 0.5) and lie_clear(q + d * 1.0)):
			break
		p = q
		travelled += step
	var head := d
	if not (lie_clear(p + d * 0.5) and lie_clear(p + d * 1.0)):
		for a in [PI * 0.5, -PI * 0.5, PI * 0.25, -PI * 0.25, PI * 0.75, -PI * 0.75, PI]:
			var h := d.rotated(a)
			if lie_clear(p + h * 0.5) and lie_clear(p + h * 1.0):
				head = h
				break
	return [p, head]


func bump(from_world: Vector3, strength := 1.0) -> void:
	var d := Vector3(pos.x - from_world.x, 0.0, pos.y - from_world.z).normalized()
	var dc := (global_transform.basis.inverse() * d).normalized()
	_hit_axis = Vector3.UP.cross(dc).normalized()
	_hit_vel += 2.4 * strength
	if not anchored():
		shove += Vector2(d.x, d.z) * 0.35 * strength
	_look_over = from_world
	_look_over_t = 1.6


# A haymaker at a point in the room, with the left: drawn right back behind
# him first, then thrown with everything he has. It lands PUNCH_HIT seconds in.
func punch(at_world: Vector3) -> void:
	_punch_t = 0.0
	_punch_stepped = false
	_punch_at = at_world


# Re-aim a punch that's still being drawn back.
func punch_at(at_world: Vector3) -> void:
	_punch_at = at_world


# The body as a capsule, for anything that wants to hit it: bottom, top,
# radius, in world space.
func capsule() -> Array:
	return [Vector3(pos.x, 0.3, pos.y), head_w, 0.24]


# Where a held ball sits, in the front hand.
func ball_world() -> Vector3:
	var along := (_lmid_w - lhand_w)
	if along.length_squared() < 1.0e-6:
		along = Vector3.DOWN
	return lhand_w + along.normalized() * 0.045 + Vector3.DOWN * 0.035


func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


# ---------------------------------------------------------------------------
# Each frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if skel == null:
		return
	_dt = maxf(delta, 0.0001)
	_locomotion(delta)
	_feet(delta)
	_layers(delta)
	_update_cue_xf()
	skel.reset_bone_poses()
	anim.advance(delta)
	_solve()
	cue.global_transform = _cue_xf


func _sync_node() -> void:
	position = Vector3(pos.x, _air, pos.y)
	rotation = Vector3(0.0, yaw, 0.0)


func _locomotion(delta: float) -> void:
	if _ko_t >= 0.0:
		_knockdown(delta)
		return
	var desired := Vector2.ZERO
	var walking := false
	if _path_i < _path.size():
		var tgt: Vector2 = _path[_path_i]
		var to := tgt - pos
		var d := to.length()
		var last := _path_i == _path.size() - 1
		if not last and d < 0.45:
			_path_i += 1
			if _path_i < _path.size():
				tgt = _path[_path_i]
				to = tgt - pos
				d = to.length()
				last = _path_i == _path.size() - 1
		if last and d < 0.025:
			_path_i = _path.size()
		else:
			# ease into the last spot rather than stopping dead on it
			var sp := _speed if not last else minf(_speed, d * 1.5 + 0.05)
			desired = to / maxf(d, 0.001) * sp
			walking = true
	if walking:
		desired += avoid
	if _ss > 0.02 or stance_on or stunned():
		desired = Vector2.ZERO
	vel = vel.move_toward(desired, ACCEL * delta)
	pos += (vel + shove) * delta
	shove = shove.move_toward(Vector2.ZERO, 3.5 * delta)
	_confine()

	# face the way you are walking; on arrival, the way you were asked to
	var want := yaw
	var spd := vel.length()
	if spd > 0.18 and walking:
		want = atan2(vel.x, vel.y)
	elif _face != INF:
		want = _face
	var diff := wrapf(want - yaw, -PI, PI)
	var target_rate := clampf(diff * 3.5, -TURN_RATE, TURN_RATE)
	if _ss > 0.02:
		target_rate = 0.0
	_yaw_vel = move_toward(_yaw_vel, target_rate, 9.0 * delta)
	yaw = wrapf(yaw + _yaw_vel * delta, -PI, PI)
	_sync_node()


# Out of the table and inside the walls. Eased out rather than snapped, so a
# knock into the rail never teleports him.
func _confine() -> void:
	var q := Vector2(absf(pos.x) - TABLE_HALF.x, absf(pos.y) - TABLE_HALF.y)
	if q.x < 0.0 and q.y < 0.0:
		var k := clampf(12.0 * _dt, 0.0, 1.0)
		if q.x > q.y:
			pos.x -= signf(pos.x) * q.x * k
			vel.x = 0.0 if signf(vel.x) != signf(pos.x) else vel.x
		else:
			pos.y -= signf(pos.y) * q.y * k
			vel.y = 0.0 if signf(vel.y) != signf(pos.y) else vel.y
	# the stools and the high table, and the front of the bar
	var k2 := clampf(10.0 * _dt, 0.0, 1.0)
	for o in obstacles:
		var off: Vector2 = pos - (o[0] as Vector2)
		var r: float = float(o[1]) + RADIUS * 0.8
		if off.length() < r and off.length() > 1.0e-4:
			pos += off.normalized() * (r - off.length()) * k2
	if pos.x < BarRoom.BAR_FRONT_X + 0.35:
		pos.x += (BarRoom.BAR_FRONT_X + 0.35 - pos.x) * k2
	pos.x = clampf(pos.x, -ROOM_HALF.x, ROOM_HALF.x)
	pos.y = clampf(pos.y, -ROOM_HALF.y, ROOM_HALF.y)


# The knock-down, on its own clock: the flight, the landing, lying there
# seeing stars, and the struggle back up. It owns the whole body meanwhile.
func _knockdown(delta: float) -> void:
	_ko_t += delta
	var t := _ko_t
	var key: Array
	_air = 0.0
	if t < RAG_TIME:
		# the physics has him. Underneath, the body holds the lying pose it
		# will come round into.
		key = RISE_KEYS[0].duplicate()
		_ko_w = 1.0
		if not _rag_landed and t > 0.25 and _rag_hips.global_position.y < 0.4:
			_rag_landed = true
			landed.emit(_rag_hips.global_position)
		_dizzy = smoothstep(0.9, 1.7, t)
	elif t < RAG_TIME + RAG_BLEND:
		# coming round: from the heap he's in to flat on his back
		if _sim.active:
			_end_ragdoll()
		_rag_w = 1.0 - smoothstep(0.0, RAG_BLEND, t - RAG_TIME)
		key = RISE_KEYS[0].duplicate()
		_ko_w = 1.0
		_dizzy = 1.0
	elif t < ko_length():
		var r := t - RAG_TIME - RAG_BLEND
		_rag_w = 0.0
		if not _rising:
			_rising = true
			getting_up.emit()
		key = _key_at(RISE_KEYS, r)
		# the legs going under him near the top
		var wob := _bump(r, 1.9, 3.2)
		key[4] += Vector3(0.03 * sin(r * 11.0), 0.0, 0.0) * wob
		key[1] += 0.025 * sin(r * 13.0) * wob
		_ko_w = 1.0 - smoothstep(RISE_KEYS[4][0], KO_RISE, r)
		_dizzy = 1.0 - smoothstep(0.3, 2.9, r)
	else:
		_ko_t = -1.0
		_ko_w = 0.0
		_rag_w = 0.0
		_dizzy = 0.0
		_rising = false
		yaw = wrapf(yaw, -PI, PI)
		_yaw_vel = 0.0
		_sync_node()
		return
	yaw = wrapf(yaw, -PI, PI)
	_yaw_vel = 0.0
	_sync_node()
	_ko_pose = {"hips_h": key[1], "hips_back": key[2], "torso": key[3],
		"hand_l": key[6], "hand_r": key[7], "hand_w": key[8], "toes": key[9]}
	for f in 2:
		_foot[f] = global_transform * (key[4 + f] as Vector3)
		_foot_t[f] = 1.0
		_foot_yaw[f] = yaw + SPLAY_STAND[f] * 1.6


# A pose from a list of them, eased from one to the next.
func _key_at(keys: Array, t: float) -> Array:
	var n := keys.size()
	var a: Array = keys[0]
	var b: Array = keys[n - 1]
	var k := 1.0
	for i in range(1, n):
		if t <= float(keys[i][0]):
			a = keys[i - 1]
			b = keys[i]
			k = smoothstep(0.0, 1.0, (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1.0e-4))
			break
	var out := [t]
	for j in range(1, a.size()):
		var va: Variant = a[j]
		var vb: Variant = b[j]
		if j == 1:
			va = _hips_rest.y if float(va) < 0.0 else va
			vb = _hips_rest.y if float(vb) < 0.0 else vb
		out.append(lerp(va, vb, k))
	return out


# 0 outside [a, b], rising to 1 in the middle of it and back.
static func _bump(t: float, a: float, b: float) -> float:
	if t <= a or t >= b:
		return 0.0
	return sin(PI * (t - a) / (b - a))


func _home(f: int, lead := true) -> Vector3:
	var off: Vector2 = FEET_STANCE[f] if stance_on else FEET_STAND[f]
	var fwd := forward()
	var left := Vector2(fwd.y, -fwd.x)
	var p := pos + left * off.x + fwd * off.y
	if lead:
		p += vel * LEAD
	return Vector3(p.x, ANKLE_H, p.y)


func _home_yaw(f: int) -> float:
	return yaw + (SPLAY_STANCE[f] if stance_on else SPLAY_STAND[f])


# A foot lifts only when the body has moved far enough off it, and never while
# the other one is in the air; it lands a little ahead of where the body is
# going. Walking falls out of that on its own, and so does turning on the
# spot and the small settling step when you stop.
func _feet(delta: float) -> void:
	_bob = 0.0
	for f in 2:
		if _foot_t[f] >= 1.0:
			continue
		_foot_t[f] = minf(1.0, _foot_t[f] + delta / _foot_dur[f])
		var t: float = _foot_t[f]
		var s := smoothstep(0.0, 1.0, t)
		var p: Vector3 = (_foot_from[f] as Vector3).lerp(_foot_to[f], s)
		p.y = ANKLE_H + sin(PI * t) * LIFT * float(_foot_lift[f])
		_foot[f] = p
		_foot_yaw[f] = lerp_angle(_foot_yaw_from[f], _foot_yaw_to[f], s)
		_bob += sin(PI * t) * 0.012 * float(_foot_lift[f])
		if _foot_t[f] >= 1.0:
			stepped.emit(p, clampf(vel.length() / WALK_SPEED, 0.25, 1.0))

	var planted: bool = _foot_t[0] >= 1.0 and _foot_t[1] >= 1.0
	if not planted:
		_settle = 0.0
		return
	_settle += delta
	if _ko_t >= 0.0:
		return
	var speed := vel.length() + shove.length()
	var turning := absf(_yaw_vel) > 0.25
	var e := [_foot_err(0), _foot_err(1)]
	var f := 0 if e[0] >= e[1] else 1
	var err: float = e[f]
	var trigger := lerpf(STEP_TRIGGER, 0.03, clampf(speed / 0.35, 0.0, 1.0))
	if err > trigger or (err > 0.035 and _settle > 0.35 and not turning and speed < 0.05):
		var dur := lerpf(0.42, 0.32, clampf(speed / WALK_SPEED, 0.0, 1.0))
		var to := _home(f)
		to += Vector3(vel.x, 0.0, vel.y) * dur * 0.5
		_foot_from[f] = _foot[f]
		_foot_to[f] = to
		_foot_yaw_from[f] = _foot_yaw[f]
		_foot_yaw_to[f] = _home_yaw(f)
		_foot_dur[f] = dur
		_foot_lift[f] = clampf(Vector2(to.x - _foot[f].x, to.z - _foot[f].z).length() / 0.25, 0.3, 1.0)
		_foot_t[f] = 0.0


func _foot_err(f: int) -> float:
	var h := _home(f)
	var p: Vector3 = _foot[f]
	return Vector2(h.x - p.x, h.z - p.z).length() + 0.12 * absf(wrapf(_home_yaw(f) - _foot_yaw[f], -PI, PI))


func _ease(v: float, on: bool, secs_in: float, secs_out: float) -> float:
	return move_toward(v, 1.0 if on else 0.0, _dt / (secs_in if on else secs_out))


func _layers(delta: float) -> void:
	_stun_t = maxf(0.0, _stun_t - delta)
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_look_over_t = maxf(0.0, _look_over_t - delta)
	var bend := stance_on and not stunned() and vel.length() < 0.1
	_ss = _ease(_ss, bend, 1.0, 0.8)
	_cs = _ease(_cs, bend and _ss > 0.3, 0.7, 0.5)
	_ts = _ease(_ts, think_on and _ss < 0.05 and not stunned(), 0.7, 0.5)
	_hs = _ease(_hs, _hurt_t > 0.5, 0.25, 0.6)
	_rs = _ease(_rs, reach_point != null and not stunned(), 0.55, 0.45)
	_hold_s = _ease(_hold_s, holding_ball, 0.3, 0.3)
	if reach_point != null:
		_reach_w = reach_point
	var looking := (look_target != null or _look_over_t > 0.0) and _ko_w < 0.2
	_ls = _ease(_ls, looking, 0.5, 0.8)
	var lt: Vector3 = _look_over if _look_over_t > 0.0 else (look_target if look_target != null else _look)
	if _ls <= 0.001:
		_look = lt
	else:
		_look = _look.lerp(lt, 1.0 - exp(-4.0 * delta))
	walk_w = smoothstep(0.06, 0.45, vel.length())
	# the knock from a hit or a bump, as a spring
	var acc := -70.0 * _hit_ang - 10.0 * _hit_vel
	_hit_vel += acc * delta
	_hit_ang += _hit_vel * delta
	if _punch_t >= 0.0:
		_punch_t += delta
		# the step into it, as the fist goes
		if not _punch_stepped and _punch_t >= PUNCH_WINDUP:
			_punch_stepped = true
			shove += forward() * 1.3
		if _punch_t > PUNCH_HIT + PUNCH_RECOVER:
			_punch_t = -1.0
	_update_stars()


# The swing, as a turn of the shoulders and a lean: drawn right back and
# round, then all of it thrown forward. [twist, bend], whole spine.
func _punch_swing() -> Vector2:
	var t := _punch_t
	if t < 0.0:
		return Vector2.ZERO
	if t < PUNCH_WINDUP:
		var k := smoothstep(0.0, 1.0, t / PUNCH_WINDUP)
		return Vector2(0.5, -0.14) * k
	if t < PUNCH_HIT:
		var k := pow((t - PUNCH_WINDUP) / PUNCH_STRIKE, 0.7)
		return Vector2(0.5, -0.14).lerp(Vector2(-0.45, 0.24), k)
	var k := smoothstep(0.0, 1.0, (t - PUNCH_HIT) / PUNCH_RECOVER)
	return Vector2(-0.45, 0.24).lerp(Vector2.ZERO, k)


func _update_cue_xf() -> void:
	var hip_h := _hips_rest.y - 0.02 - _hip_drop
	var grip_c := Vector3(-0.23, hip_h - 0.03 + _bob * 0.5, 0.15)
	var up_c := Vector3(-0.05, 1.0, 0.12).normalized()
	var carry := _cue_frame(global_transform * grip_c, (global_transform.basis * up_c).normalized())
	if _has_shot and _cs > 0.0:
		var s := smoothstep(0.0, 1.0, _cs)
		_cue_xf = carry.interpolate_with(_shot_xf, s)
	else:
		_cue_xf = carry
	if _ko_w > 0.0:
		# he never lets go of it: waved about in the air, flat on the floor
		# beside him, then leant on to get up
		var hk: Vector3 = _ko_pose.hand_r
		var grip := global_transform * hk
		grip.y = maxf(grip.y - 0.02, 0.025)
		var s := smoothstep(0.12, 0.5, hk.y)
		var ko_up := Vector3(0.1, 0.02, 1.0).lerp(Vector3(-0.05, 1.0, 0.12), s).normalized()
		var ko_xf := _cue_frame(grip, (global_transform.basis * ko_up).normalized())
		_cue_xf = _cue_xf.interpolate_with(ko_xf, _ko_w)
	if _sim != null and _sim.active and _rag_rarm != null:
		# flung about in his fist
		var fx := _rag_rarm.global_transform
		var half: float = _rag_half[_rag.find(_rag_rarm)]
		var hand := fx * Vector3(0.0, 0.0, -half - 0.02)
		var up := fx.basis.x.normalized()
		var y := -up
		var x := fx.basis.z.normalized()
		x = (x - y * x.dot(y)).normalized()
		_cue_xf = Transform3D(Basis(x, y, x.cross(y).normalized()), hand + up * GRIP)


# The cue model runs along +Y from its tip; this puts the grip at `grip` with
# the tip up along `up`.
func _cue_frame(grip: Vector3, up: Vector3) -> Transform3D:
	var y := -up
	var left := global_transform.basis.x.normalized()
	var x := (left - y * left.dot(y)).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), grip + up * GRIP)


# ---------------------------------------------------------------------------
# The pose
# ---------------------------------------------------------------------------

func _solve() -> void:
	_w2s = _S * global_transform.affine_inverse()
	_s2w = global_transform * _C
	_pending.clear()
	for b in _order:
		var p := _par[b]
		_L[b] = skel.get_bone_pose(b)
		_G[b] = _G[p] * _L[b] if p >= 0 else _L[b]
		match _role[b]:
			R_HIPS:
				_do_hips(b)
			R_SPINE:
				_do_spine(b, 0)
			R_SPINE1:
				_do_spine(b, 1)
			R_SPINE2:
				_do_spine(b, 2)
			R_NECK:
				_do_look(b, 0.4)
			R_HEAD:
				_do_look(b, 1.0)
			R_L_ARM:
				_upper(b, _arm_goal(0))
			R_R_ARM:
				_upper(b, _arm_goal(1))
			R_L_THIGH:
				_upper(b, _leg_goal(0))
			R_R_THIGH:
				_upper(b, _leg_goal(1))
			R_L_FORE, R_R_FORE, R_L_SHIN, R_R_SHIN:
				_lower(b)
			R_L_FOOT:
				_do_foot(b, 0)
			R_R_FOOT:
				_do_foot(b, 1)
	var hb: int = _b[R_HIPS]
	var blend := _rag_w > 0.0 and _rag_rot.size() == skel.get_bone_count()
	for b in _order:
		var q := _L[b].basis.get_rotation_quaternion()
		if blend and _rag_rot[b] != null:
			# still partly the heap the ragdoll left him in
			q = q.slerp(_rag_rot[b], _rag_w)
		skel.set_bone_pose_rotation(b, q)
	var hp := _L[hb].origin
	if blend:
		hp = hp.lerp(_rag_hips_xf.origin, _rag_w)
	skel.set_bone_pose_position(hb, hp)
	if _sim != null and _sim.active:
		# the physics has him: read him off the bodies
		hips_w = _rag_hips.global_position
		head_w = _rag_head.global_position + Vector3.UP * 0.05
		return
	hips_w = _s2w * _G[hb].origin
	lhand_w = _s2w * _G[_b[R_L_HAND]].origin
	rhand_w = _s2w * _G[_b[R_R_HAND]].origin
	if _mid_l >= 0:
		_lmid_w = _s2w * (_G[_b[R_L_HAND]] * skel.get_bone_pose_position(_mid_l))


# Rotate bone `b` by `q` (skeleton space, about its own joint), `w` of the way.
func _turn(b: int, q: Quaternion, w := 1.0) -> void:
	if w <= 0.0:
		return
	if w < 1.0:
		q = Quaternion.IDENTITY.slerp(q, w)
	_G[b].basis = Basis(q) * _G[b].basis
	var p := _par[b]
	_L[b].basis = _G[p].basis.inverse() * _G[b].basis if p >= 0 else _G[b].basis


func _do_hips(b: int) -> void:
	var o := _C * _L[b].origin
	o.x = lerpf(o.x, _hips_rest.x, walk_w)
	o.z = lerpf(o.z, _hips_rest.z, walk_w)
	o += Vector3(0.0, -0.07, -0.05) * _ss
	o += Vector3(0.0, 0.0, minf(lean_extra, 0.25)) * _ss
	o += Vector3(0.0, -0.05, -0.08) * _rs
	o.y += _bob
	# knocked down: the whole body tipped over from the hips
	if _ko_w > 0.0:
		var ko := Vector3(_hips_rest.x, float(_ko_pose.hips_h), -float(_ko_pose.hips_back))
		o = o.lerp(ko, _ko_w)
	_L[b].origin = _S * o
	_G[b] = _L[b]
	if _ko_w > 0.0:
		_turn(b, Quaternion(_cL, -float(_ko_pose.torso) * _ko_w))
	# drop the pelvis just enough for both legs to reach their feet
	var need := 0.0
	for leg in 2:
		var thigh: int = _b[R_L_THIGH] if leg == 0 else _b[R_R_THIGH]
		var hj := _G[b] * skel.get_bone_pose_position(thigh)
		var dv := _w2s * (_foot[leg] as Vector3) - hj
		var vert := -dv.dot(_cU)
		var horiz := (dv + _cU * vert).length()
		var reach := (_len[thigh] + _len[_child[thigh]]) * 0.975
		need = maxf(need, vert - sqrt(maxf(reach * reach - horiz * horiz, 0.0)))
	need *= 1.0 - _ko_w
	var rate := 18.0 if need > _hip_drop else 5.0
	_hip_drop = lerpf(_hip_drop, maxf(need, 0.0), 1.0 - exp(-rate * _dt))
	_L[b].origin -= _cU * _hip_drop
	_G[b] = _L[b]


func _do_spine(b: int, i: int) -> void:
	var bend: float = STANCE_BEND[i] * _ss + REACH_BEND[i] * _rs + THINK_BEND[i] * _ts
	bend += clampf(lean_extra, 0.0, 0.5) * 0.35 * _ss
	var twist: float = STANCE_TWIST[i] * _ss
	if _punch_t >= 0.0:
		# the whole of him goes into it
		var sw := _punch_swing()
		twist += sw.x / 3.0
		bend += sw.y / 3.0
	var q := Quaternion(_cL, bend) * Quaternion(_cU, twist)
	if absf(_hit_ang) > 1.0e-4:
		q = Quaternion((_S.basis * _hit_axis).normalized(), _hit_ang * [0.18, 0.22, 0.26][i]) * q
	_turn(b, q)


# Neck and head share the turn towards whatever is being looked at, held
# within what a neck can do from where the chest is facing.
func _do_look(b: int, share: float) -> void:
	if absf(_hit_ang) > 1.0e-4:
		_turn(b, Quaternion((_S.basis * _hit_axis).normalized(), _hit_ang * (0.35 if share < 1.0 else 0.45)))
	var head_b: int = _b[R_HEAD]
	if _ls > 0.001:
		var head_basis := _G[b].basis
		var head_pos := _G[b].origin
		if b != head_b:
			var hl := skel.get_bone_pose(head_b)
			head_basis = _G[b].basis * hl.basis
			head_pos = _G[b] * hl.origin
		var eye := head_pos + _cU * 0.08
		var cur := (head_basis * _f_head).normalized()
		var want := _clamp_look(_w2s * _look - eye, b != head_b)
		_turn(b, Quaternion(cur, want), share * _ls)
	if _dizzy > 0.001:
		# seeing stars: the head lolls from side to side
		var cb := _G[_b[R_SPINE2]].basis
		var up := (cb * _u_chest).normalized()
		var fwd := (cb * _f_chest).normalized()
		var tt := Time.get_ticks_msec() * 0.001
		_turn(b, Quaternion(up, 0.36 * sin(tt * 2.3) * _dizzy * share)
			* Quaternion(fwd, 0.18 * sin(tt * 3.1 + 1.0) * _dizzy * share))
	if b == head_b:
		head_w = _s2w * (_G[b].origin + _cU * 0.08)
		head_fwd_w = (_s2w.basis * (_G[b].basis * _f_head)).normalized()


# Where the head points, as a turn and a nod from where the chest faces,
# kept within what a neck can do. It turns at a person's pace, and when
# what it is watching goes round behind, it stays over the shoulder it was
# already looking over rather than whipping across to the other one.
func _clamp_look(dir: Vector3, update: bool) -> Vector3:
	var cb := _G[_b[R_SPINE2]].basis
	var fwd := (cb * _f_chest).normalized()
	var up := (cb * _u_chest).normalized()
	var left := up.cross(fwd).normalized()
	if update:
		var x := dir.dot(left)
		var y := dir.dot(up)
		var z := dir.dot(fwd)
		var raw := atan2(x, z)
		if absf(raw) > 2.2 and signf(raw) != signf(_look_yp.x) and absf(_look_yp.x) > 0.25:
			raw = signf(_look_yp.x) * PI
		var want := Vector2(clampf(raw, -1.2, 1.2),
			clampf(atan2(y, Vector2(x, z).length()), -0.9, 0.7 + 0.55 * _ss))
		var eased := _look_yp.lerp(want, 1.0 - exp(-10.0 * _dt))
		var step := eased - _look_yp
		var most := 4.5 * _dt
		if step.length() > most:
			step = step.normalized() * most
		_look_yp += step
	var yaw_a := _look_yp.x
	var pitch := _look_yp.y
	return (fwd * cos(yaw_a) * cos(pitch) + left * sin(yaw_a) * cos(pitch) + up * sin(pitch)).normalized()


# Two-bone IK: the upper bone turns so the joint lands where it has to for
# the end to reach the goal, bending towards the pole.
func _upper(b: int, goal: Dictionary) -> void:
	if goal.is_empty() or float(goal.w) <= 0.001:
		return
	var lower := _child[b]
	var la := _len[b]
	var lb := _len[lower]
	var h := _G[b].origin
	var dv: Vector3 = goal.t - h
	var d := clampf(dv.length(), 0.01, (la + lb) * 0.999)
	var u := dv.normalized()
	var pole: Vector3 = goal.pole
	var v := pole - u * pole.dot(u)
	if v.length_squared() < 1.0e-6:
		v = u.cross(_cL)
	v = v.normalized()
	var ca := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var joint_dir := u * ca + v * sqrt(1.0 - ca * ca)
	var cur := (_G[b].basis * skel.get_bone_pose_position(lower)).normalized()
	_turn(b, Quaternion(cur, joint_dir), goal.w)
	_pending[lower] = {"t": h + u * d, "w": goal.w}


func _lower(b: int) -> void:
	if not _pending.has(b):
		return
	var g: Dictionary = _pending[b]
	var cur := (_G[b].basis * skel.get_bone_pose_position(_child[b])).normalized()
	var want: Vector3 = (g.t - _G[b].origin).normalized()
	_turn(b, Quaternion(cur, want), g.w)


func _do_foot(b: int, f: int) -> void:
	var toe := _child[b]
	if toe < 0:
		return
	var fy: float = _foot_yaw[f]
	var fwd := (_w2s.basis * Vector3(sin(fy), 0.0, cos(fy))).normalized()
	var l := _len[b]
	var horiz := sqrt(maxf(l * l - _toe_drop * _toe_drop, 0.0))
	var want := (fwd * horiz - _cU * _toe_drop).normalized()
	if _ko_w > 0.0:
		# flat on your back, toes to the ceiling
		var up_t := float(_ko_pose.toes) * _ko_w
		want = want.slerp((fwd * 0.3 + _cU).normalized(), up_t)
	var cur := (_G[b].basis * skel.get_bone_pose_position(toe)).normalized()
	_turn(b, Quaternion(cur, want))


func _leg_goal(f: int) -> Dictionary:
	var fy: float = _foot_yaw[f]
	var knee := Vector3(sin(fy), 0.0, cos(fy))
	# knees a touch outward, the way people stand
	var side := global_transform.basis.x.normalized() * (0.25 if f == 0 else -0.25)
	# on the floor, knees point at the ceiling
	var pole := knee + side + Vector3.UP * 1.2 * _ko_w
	return {"t": _w2s * (_foot[f] as Vector3), "pole": (_w2s.basis * pole).normalized(), "w": 1.0}


func _arm_goal(side: int) -> Dictionary:
	var up := Vector3.UP
	if side == 1:
		# the back hand always has the cue
		var grip := _cue_xf * Vector3(0.0, GRIP, 0.0)
		var pole_c := Vector3(-0.4, -1.0, -0.4).lerp(Vector3(-0.35, 0.9, -0.8), _ss)
		pole_c = pole_c.lerp(Vector3(-0.8, 0.2, -0.3), _ko_w)
		return {"t": _w2s * grip, "pole": (_S.basis * pole_c).normalized(), "w": 1.0}

	var acc := {"t": Vector3.ZERO, "pole": Vector3.ZERO, "w": 0.0}
	var fwd := head_fwd_w
	var left_w := global_transform.basis.x.normalized()
	# swinging with the walk, against the left leg
	var fl: float = (global_transform.affine_inverse() * (_foot[0] as Vector3)).z
	var fr: float = (global_transform.affine_inverse() * (_foot[1] as Vector3)).z
	var sw := clampf((fl - fr) / 0.35, -1.0, 1.0)
	var hip_h := _hips_rest.y - _hip_drop
	_mix(acc, global_transform * Vector3(0.21, hip_h - 0.12, 0.05 - 0.16 * sw),
		Vector3(0.3, 0.0, -1.0), walk_w * 0.85)
	# carrying the cue ball in front of you
	_mix(acc, global_transform * Vector3(0.12, hip_h + 0.02, 0.26), Vector3(0.3, -1.0, -0.3), _hold_s)
	# hand to chin, thinking: the wrist just under and in front of the jaw,
	# elbow down in front of the chest
	var fwd_h := Vector3(fwd.x, 0.0, fwd.z)
	fwd_h = fwd_h.normalized() if fwd_h.length_squared() > 1.0e-4 else global_transform.basis.z.normalized()
	var chin := head_w - up * 0.15 + fwd_h * 0.13 - left_w * 0.01
	_mix(acc, chin, Vector3(0.15, -1.0, 0.7), _ts)
	# hand to where it hurts
	var cheek := head_w - up * 0.09 + fwd_h * 0.07 + left_w * 0.10
	_mix(acc, cheek, Vector3(0.6, -1.0, 0.2), _hs)
	# the bridge on the cloth, under the shaft
	if _has_shot:
		var bridge := _shot_rest * Vector3(0.0, BRIDGE, 0.0) - up * 0.03
		_mix(acc, bridge, Vector3(1.0, 0.3, -0.2), _ss)
	# reaching for something on the table
	_mix(acc, _reach_w + up * 0.05, Vector3(0.5, -0.3, -1.0), _rs)
	if _punch_t >= 0.0:
		# a haymaker: the fist drawn way back up behind his shoulder, a
		# tremble at the top, then thrown at whatever he's aiming at
		var t := _punch_t
		var back := global_transform * Vector3(0.36, 1.36, -0.4)
		var guard := global_transform * Vector3(0.2, 1.22, 0.24)
		var tgt: Vector3
		var pole := Vector3(0.9, -0.5, -0.4)
		if t < PUNCH_WINDUP:
			var k := smoothstep(0.0, 1.0, t / PUNCH_WINDUP)
			tgt = guard.lerp(back, k) + Vector3(sin(t * 55.0), cos(t * 43.0), 0.0) * 0.012 * k
		elif t < PUNCH_HIT:
			tgt = back.lerp(_punch_at, pow((t - PUNCH_WINDUP) / PUNCH_STRIKE, 0.6))
			pole = pole.lerp(Vector3(0.3, -1.0, 0.0), (t - PUNCH_WINDUP) / PUNCH_STRIKE)
		else:
			tgt = _punch_at.lerp(guard, smoothstep(0.0, 1.0, (t - PUNCH_HIT) / PUNCH_RECOVER))
			pole = Vector3(0.3, -1.0, 0.0)
		var w := minf(t / 0.15, 1.0) * (1.0 - smoothstep(PUNCH_HIT + 0.12, PUNCH_HIT + PUNCH_RECOVER, t))
		_mix(acc, tgt, pole, w)
	# knocked down: flailing, flat out, pushing himself up
	if _ko_w > 0.0:
		_mix(acc, global_transform * (_ko_pose.hand_l as Vector3), Vector3(0.8, 0.2, -0.3),
			_ko_w * float(_ko_pose.hand_w))
	if float(acc.w) <= 0.0:
		return {}
	return {"t": _w2s * (acc.t as Vector3), "pole": (_S.basis * (acc.pole as Vector3)).normalized(), "w": acc.w}


func _mix(acc: Dictionary, t: Vector3, pole_c: Vector3, w: float) -> void:
	if w <= 0.0:
		return
	if float(acc.w) <= 0.0:
		acc.t = t
		acc.pole = pole_c
	else:
		acc.t = (acc.t as Vector3).lerp(t, w)
		acc.pole = (acc.pole as Vector3).lerp(pole_c, w)
	acc.w = float(acc.w) + (1.0 - float(acc.w)) * w
