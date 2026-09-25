class_name PoolBartender
extends Node3D

# The man behind the bar. He came as a single scanned mesh with no skeleton,
# standing on a sheet of the floor he was scanned on, so the sheet is cut
# away when he loads and everything that makes him look alive happens in his
# vertex shader: a slow breath in the chest, a lazy shift of weight from foot
# to foot, and his head turning to keep an eye on you.

const MODEL := "res://characters/bartender/bartender.glb"
const HEIGHT := 1.84

var mesh_i: MeshInstance3D
var mat: ShaderMaterial
var look_at_w: Variant = null     # world point he watches, if any
var _yaw := 0.0
var _pitch := 0.0
var _neck := Vector3.ZERO         # model space
var _glance_t := 0.0
var _glance := Vector2.ZERO

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 neck = vec3(0.0, 1.6, 0.0);
uniform float head_yaw = 0.0;
uniform float head_pitch = 0.0;
uniform float breathe_y = 1.25;

mat3 rot_y(float a) { return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a))); }
mat3 rot_x(float a) { return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a))); }

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	// breathing: the chest swells a little, front and back
	float chest = smoothstep(breathe_y - 0.25, breathe_y, v.y) * (1.0 - smoothstep(breathe_y + 0.1, breathe_y + 0.28, v.y));
	float br = 0.5 + 0.5 * sin(TIME * 1.5);
	v.xz *= 1.0 + chest * br * 0.018;
	v.y += smoothstep(breathe_y - 0.3, neck.y, v.y) * br * 0.004;
	// the head turns on the neck
	float hw = smoothstep(neck.y - 0.05, neck.y + 0.07, v.y);
	mat3 hr = rot_y(head_yaw * hw) * rot_x(head_pitch * hw);
	v = neck + hr * (v - neck);
	n = hr * n;
	// weight shifting from one foot to the other, pivoting at the ankles
	float sway = sin(TIME * 0.55) * 0.009 + sin(TIME * 0.23) * 0.005;
	v.x += v.y * sway;
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
}
"""


func build() -> void:
	var scene := (load(MODEL) as PackedScene).instantiate()
	var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var tex: Texture2D = null
	var sm := src.get_active_material(0)
	if sm is BaseMaterial3D:
		tex = (sm as BaseMaterial3D).albedo_texture
	var arrays := src.mesh.surface_get_arrays(0)
	var xf := src.global_transform if src.is_inside_tree() else _to_root(src, scene)
	scene.free()

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = xf * verts[i]
	# a scan may come without normals; they're worked out afterwards if so
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size():
			normals[i] = (xf.basis * normals[i]).normalized()
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in verts.size():
			idx.append(i)

	# where he stands: the middle of what is above the floor sheet
	var top := -1.0e9
	var bottom := 1.0e9
	for v in verts:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	var sheet := bottom + 0.035
	# cut away the sheet he was scanned standing on: every triangle lying
	# flat on the floor, away from his feet
	var keep := PackedInt32Array()
	var body_x := 0.0
	var body_z := 0.0
	var nb := 0
	for v in verts:
		if v.y > 0.5:
			body_x += v.x
			body_z += v.z
			nb += 1
	var centre := Vector2(body_x, body_z) / maxf(float(nb), 1.0)
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var low := a.y < sheet and b.y < sheet and c.y < sheet
		var mid := (a + b + c) / 3.0
		var near_feet := Vector2(mid.x, mid.z).distance_to(centre) < 0.2
		if low and not near_feet:
			continue
		keep.append(idx[t])
		keep.append(idx[t + 1])
		keep.append(idx[t + 2])

	# stand him on y = 0, centred, at a sensible height
	var s := HEIGHT / maxf(top - bottom, 0.01)
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3((v.x - centre.x) * s, (v.y - bottom) * s, (v.z - centre.y) * s)

	# the neck: the narrowest ring below the head
	var neck_y := HEIGHT * 0.83
	var best := 1.0e9
	for k in 16:
		var y := HEIGHT * (0.78 + 0.01 * float(k))
		var w := 0.0
		for v in verts:
			if absf(v.y - y) < 0.01:
				w = maxf(w, Vector2(v.x, v.z).length())
		if w > 0.0 and w < best:
			best = w
			neck_y = y
	var nx := 0.0
	var nz := 0.0
	var nn := 0
	for v in verts:
		if absf(v.y - neck_y) < 0.02:
			nx += v.x
			nz += v.z
			nn += 1
	_neck = Vector3(nx / maxf(float(nn), 1.0), neck_y, nz / maxf(float(nn), 1.0))

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	if not normals.is_empty():
		out[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = keep
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	if normals.is_empty():
		var st := SurfaceTool.new()
		st.create_from(am, 0)
		st.generate_normals()
		am = st.commit()

	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("neck", _neck)
	mat.set_shader_parameter("breathe_y", neck_y - 0.3)
	mesh_i = MeshInstance3D.new()
	mesh_i.mesh = am
	mesh_i.material_override = mat
	mesh_i.extra_cull_margin = 0.3
	add_child(mesh_i)


func _to_root(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# His eye line, in world space, for speech bubbles.
func head_w() -> Vector3:
	return global_transform * (_neck + Vector3(0, 0.2, 0.02))


func _process(delta: float) -> void:
	if mat == null:
		return
	var want := Vector2.ZERO
	if look_at_w != null:
		var local := global_transform.affine_inverse() * (look_at_w as Vector3) - (_neck + Vector3(0, 0.12, 0))
		want = Vector2(atan2(local.x, local.z), atan2(-local.y, Vector2(local.x, local.z).length()))
		want.x = clampf(want.x, -1.0, 1.0)
		want.y = clampf(want.y, -0.35, 0.4)
	else:
		# nobody about: an idle glance now and then
		_glance_t -= delta
		if _glance_t <= 0.0:
			_glance_t = randf_range(2.5, 6.0)
			_glance = Vector2(randf_range(-0.7, 0.7), randf_range(-0.12, 0.1))
		want = _glance
	_yaw = lerpf(_yaw, want.x, 1.0 - exp(-3.5 * delta))
	_pitch = lerpf(_pitch, want.y, 1.0 - exp(-3.5 * delta))
	mat.set_shader_parameter("head_yaw", _yaw)
	mat.set_shader_parameter("head_pitch", _pitch)
