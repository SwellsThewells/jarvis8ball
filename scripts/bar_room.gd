class_name BarRoom
extends Node3D

# A late-night bar built out of primitives and painted textures.
# The table is still the brightest thing in the room, under its three low
# pendants, but the rest of it is lit the way a real bar is: warm sconces on
# the walls, picture lights over the frames, a glow behind the bottles, and a
# soft fill so nobody standing in it turns into a silhouette.

const W := 5.6     # half width  (x)
const L := 4.2     # half length (z)
const H := 3.05    # ceiling height

# The bar runs along the -x wall. You stand in front of it; the bartender
# stands behind it, in the walkway between the counter and the back bar.
const BAR_FRONT_X := -3.95
const BAR_DEPTH := 0.66
const BAR_TOP_Y := 1.08
const BAR_Z0 := -2.5
const BAR_Z1 := 2.7
const BACK_BAR_X := -5.18
const BARTENDER_AT := Vector3(-4.78, 0.0, 0.35)
# things to walk round: [centre (x, z), radius]
var obstacles: Array = []

var _wood_dark: Material
var _wood_bar: Material
var _brass: StandardMaterial3D
var _chrome: StandardMaterial3D


func build() -> void:
	_wood_dark = PoolArt.mat(Color("1a120c"), 0.7)
	_wood_bar = PoolArt.wood_mat(Color("4a2612"), 0.26, 0.30, 0.08, Vector3.BACK)
	PoolArt.set_clearcoat(_wood_bar, 0.9, 0.08)
	_brass = PoolArt.mat(Color("a07a34"), 0.24, 0.95)
	_chrome = PoolArt.mat(Color("8a8680"), 0.14, 0.95)
	_environment()
	_shell()
	_pendants()
	_room_light()
	_bar()
	_props()
	_colliders()


# The solid parts of the room, for anything thrown about in it: floor, walls,
# ceiling, the bar and the cabinet behind it, the table, stools and the high
# table. Layer 1.
func _colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "RoomSolids"
	add_child(body)
	var zc := (BAR_Z0 + BAR_Z1) * 0.5
	var zl := BAR_Z1 - BAR_Z0
	var boxes := [
		[Vector3(W * 2.0 + 1.0, 0.4, L * 2.0 + 1.0), Vector3(0.0, -0.2, 0.0)],
		[Vector3(W * 2.0 + 1.0, 0.4, L * 2.0 + 1.0), Vector3(0.0, H + 0.2, 0.0)],
		[Vector3(0.4, H, L * 2.0), Vector3(W - 0.08 + 0.2, H * 0.5, 0.0)],
		[Vector3(0.4, H, L * 2.0), Vector3(-W + 0.08 - 0.2, H * 0.5, 0.0)],
		[Vector3(W * 2.0, H, 0.4), Vector3(0.0, H * 0.5, L - 0.08 + 0.2)],
		[Vector3(W * 2.0, H, 0.4), Vector3(0.0, H * 0.5, -L + 0.08 - 0.2)],
		# the bar, top overhang and all, and the cabinet behind it
		[Vector3(BAR_DEPTH + 0.14, BAR_TOP_Y + 0.02, zl + 0.1), Vector3(BAR_FRONT_X - BAR_DEPTH * 0.5 + 0.07, (BAR_TOP_Y + 0.02) * 0.5, zc)],
		[Vector3(0.5, 0.96, zl), Vector3(BACK_BAR_X - 0.05, 0.48, zc)],
	]
	# the table, to the top of its rails
	var th := PoolCharacter.TABLE_HALF - Vector2(0.2, 0.2)
	var ty := PoolTableView.BED_Y + 0.05
	boxes.append([Vector3(th.x * 2.0, ty, th.y * 2.0), Vector3(0.0, ty * 0.5, 0.0)])
	for bx in boxes:
		var s := BoxShape3D.new()
		s.size = bx[0]
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.position = bx[1]
		body.add_child(cs)
	for o in obstacles:
		var c := CylinderShape3D.new()
		var r: float = o[1]
		c.radius = r * 0.9
		c.height = 1.05 if r > 0.3 else 0.8
		var cs := CollisionShape3D.new()
		cs.shape = c
		cs.position = Vector3((o[0] as Vector2).x, c.height * 0.5, (o[0] as Vector2).y)
		body.add_child(cs)


# Dust, turning slowly in the air over the table: only the specks that drift
# into the light under the pendants show at all.
func _motes() -> void:
	var p := GPUParticles3D.new()
	p.amount = 180
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(0.0, 1.35, 0.0)
	p.visibility_aabb = AABB(Vector3(-2.2, -1.0, -1.3), Vector3(4.4, 2.0, 2.6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.8, 0.5, 0.95)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.015
	pm.gravity = Vector3(0.0, -0.003, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.03
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.0032, 0.0032)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.93, 0.82, 0.3)
	m.roughness = 1.0
	q.material = m
	p.draw_pass_1 = q
	add_child(p)


func _box(size: Vector3, pos: Vector3, m: Material, yaw := 0.0, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(rt: float, rb: float, h: float, pos: Vector3, m: Material, segs := 16, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = rt
	mesh.bottom_radius = rb
	mesh.height = h
	mesh.radial_segments = segs
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	(parent if parent else self).add_child(mi)
	return mi


# A flat picture facing along `facing` (+Z unless turned), painted by `draw`.
func _picture(size: Vector2, pos: Vector3, yaw: float, px_per_m: float, draw: Callable,
		transparent := false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2a1f18")
	m.roughness = 0.75
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	add_child(mi)
	PoolPaint.into(self, Vector2i(int(size.x * px_per_m), int(size.y * px_per_m)), draw, m, false, transparent)
	return mi


func _omni(pos: Vector3, col: Color, energy: float, rng: float, shadow := false, fog := 0.6) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = fog
	add_child(l)
	return l


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0806")
	# a warm, low floor of light everywhere, so the dark corners are dim
	# rather than black
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6e5a48")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssil_enabled = true
	env.ssil_intensity = 0.7
	# the lacquered bar and the floorboards pick up what's around them
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color("5a4028")
	env.volumetric_fog_length = 24.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_anisotropy = 0.45

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 0.96

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------------------
# Walls, floor, ceiling
# ---------------------------------------------------------------------------

func _shell() -> void:
	_box(Vector3(W * 2.0, 0.1, L * 2.0), Vector3(0, -0.05, 0), PoolArt.plank_mat(Color("40291a")))

	var brick := PoolArt.brick_mat()
	var plaster := PoolArt.mat(Color("5a4232"), 0.92)
	var wainscot := PoolArt.wood_mat(Color("3a2214"), 0.42, 0.22, 0.09, Vector3.UP)
	PoolArt.set_clearcoat(wainscot, 0.35, 0.3)

	_box(Vector3(W * 2.0, H, 0.12), Vector3(0, H * 0.5, L), brick)
	_box(Vector3(W * 2.0, H, 0.12), Vector3(0, H * 0.5, -L), plaster)
	_box(Vector3(0.12, H, L * 2.0), Vector3(W, H * 0.5, 0), plaster)
	_box(Vector3(0.12, H, L * 2.0), Vector3(-W, H * 0.5, 0), brick)
	_box(Vector3(W * 2.0, 0.12, L * 2.0), Vector3(0, H, 0), PoolArt.mat(Color("241a13"), 0.95))

	# panelling, chair rail, skirting and crown. The side runs stop where the
	# end runs start, so no two faces lie in the same plane at a corner.
	for s: float in [1.0, -1.0]:
		_box(Vector3(W * 2.0, 1.0, 0.06), Vector3(0, 0.5, L * s - 0.09 * s), wainscot)
		_box(Vector3(0.06, 1.0, (L - 0.12) * 2.0), Vector3(W * s - 0.09 * s, 0.5, 0), wainscot)
		_box(Vector3(W * 2.0, 0.05, 0.10), Vector3(0, 1.02, L * s - 0.08 * s), wainscot)
		_box(Vector3(0.10, 0.05, (L - 0.13) * 2.0), Vector3(W * s - 0.08 * s, 1.02, 0), wainscot)
		_box(Vector3(W * 2.0 - 0.3, 0.12, 0.03), Vector3(0, 0.06, L * s - 0.135 * s), _wood_dark)
		_box(Vector3(0.03, 0.12, (L - 0.16) * 2.0), Vector3(W * s - 0.135 * s, 0.06, 0), _wood_dark)
		_box(Vector3(W * 2.0, 0.08, 0.08), Vector3(0, H - 0.1, L * s - 0.1 * s), _wood_dark)
		_box(Vector3(0.08, 0.08, (L - 0.14) * 2.0), Vector3(W * s - 0.1 * s, H - 0.1, 0), _wood_dark)
		# raised panel mouldings, so the wainscot reads as panels, not a board
		for i in 11:
			var x := -W + 0.55 + float(i) * 1.0
			_box(Vector3(0.025, 0.7, 0.012), Vector3(x, 0.5, L * s - 0.126 * s), _wood_dark)
		for i in 8:
			var z := -L + 0.55 + float(i) * 1.0
			_box(Vector3(0.012, 0.7, 0.025), Vector3(W * s - 0.126 * s, 0.5, z), _wood_dark)

	var beam := PoolArt.wood_mat(Color("2e1d12"), 0.6, 0.20, 0.05, Vector3.BACK)
	for i in 5:
		var x := -W + 1.2 + float(i) * 2.3
		_box(Vector3(0.16, 0.22, L * 2.0 - 0.04), Vector3(x, H - 0.13, 0), beam)


# ---------------------------------------------------------------------------
# Light
# ---------------------------------------------------------------------------

func _pendants() -> void:
	var enamel := PoolArt.mat(Color("143028"), 0.35, 0.25)
	var inner := PoolArt.mat(Color("efe3c6"), 0.5)
	var cord := PoolArt.mat(Color("0d0b09"), 0.8)
	var bulb := PoolArt.glow_mat(Color("ffd694"), 3.4)

	for x: float in [-0.92, 0.0, 0.92]:
		var y := 1.90
		_cyl(0.006, 0.006, H - y - 0.08, Vector3(x, (H + y - 0.08) * 0.5, 0), cord, 8)
		_cyl(0.035, 0.20, 0.17, Vector3(x, y, 0), enamel, 28)
		_cyl(0.19, 0.19, 0.004, Vector3(x, y - 0.084, 0), inner, 28)
		_bulb(Vector3(x, y - 0.105, 0), 0.036, bulb, enamel)

		var lamp := SpotLight3D.new()
		lamp.position = Vector3(x, y - 0.10, 0)
		lamp.rotation_degrees = Vector3(-90, 0, 0)
		lamp.light_color = Color("ffc172")
		lamp.light_energy = 3.9
		lamp.light_specular = 0.8
		lamp.spot_range = 4.2
		lamp.spot_angle = 60.0
		lamp.spot_angle_attenuation = 0.7
		lamp.spot_attenuation = 1.3
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.015
		lamp.shadow_normal_bias = 1.2
		lamp.light_volumetric_fog_energy = 0.7
		add_child(lamp)


# Screw cap, neck, and a rounded envelope with a brighter filament inside it.
func _bulb(at: Vector3, r: float, glass: Material, cap: Material) -> void:
	var screw := _cyl(r * 0.52, r * 0.46, r * 0.55, at + Vector3(0, r * 0.95, 0), cap, 12)
	screw.name = "BulbCap"
	_cyl(r * 0.46, r * 0.78, r * 0.42, at + Vector3(0, r * 0.52, 0), glass, 14)
	var env := SphereMesh.new()
	env.radius = r
	env.height = r * 2.15
	env.radial_segments = 20
	env.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = env
	mi.position = at
	mi.material_override = glass
	add_child(mi)
	var fil := SphereMesh.new()
	fil.radius = r * 0.24
	fil.height = r * 0.48
	fil.radial_segments = 8
	fil.rings = 5
	var fm := MeshInstance3D.new()
	fm.mesh = fil
	fm.position = at + Vector3(0, r * 0.1, 0)
	fm.material_override = PoolArt.glow_mat(Color("fff0cf"), 7.0)
	add_child(fm)


# Wall sconces and a soft fill: enough warm light to see a face by anywhere in
# the room, none of it bright enough to compete with the table.
func _room_light() -> void:
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color("f3d9a8")
	shade.emission_enabled = true
	shade.emission = Color("ffc47a")
	shade.emission_energy_multiplier = 1.6
	shade.roughness = 0.6
	var sconces := [
		[Vector3(-3.0, 2.0, L - 0.07), Vector3(0, 0, -1)],
		[Vector3(0.6, 2.0, L - 0.07), Vector3(0, 0, -1)],
		[Vector3(4.4, 2.0, L - 0.07), Vector3(0, 0, -1)],
		[Vector3(3.0, 2.0, -L + 0.07), Vector3(0, 0, 1)],
		[Vector3(4.7, 2.0, -L + 0.07), Vector3(0, 0, 1)],
		[Vector3(W - 0.07, 2.0, -2.9), Vector3(-1, 0, 0)],
		[Vector3(W - 0.07, 2.0, 0.3), Vector3(-1, 0, 0)],
		[Vector3(W - 0.07, 2.0, 2.8), Vector3(-1, 0, 0)],
	]
	for sc in sconces:
		var at: Vector3 = sc[0]
		var out: Vector3 = sc[1]
		_box(Vector3(0.1, 0.16, 0.1), at, _brass)
		var arm := _cyl(0.008, 0.008, 0.14, at + out * 0.07 + Vector3.UP * 0.02, _brass, 8)
		arm.rotation = Vector3(PI * 0.5, 0, 0) if out.x == 0.0 else Vector3(0, 0, PI * 0.5)
		_cyl(0.05, 0.075, 0.14, at + out * 0.15 + Vector3.UP * 0.1, shade, 18)
		# the cue-rack wall, away from the bar, is the dim end of the room
		var e := 0.55 if at.x > W - 0.5 else 0.9
		_omni(at + out * 0.22 + Vector3.UP * 0.05, Color("ffc58a"), e, 3.2, false, 0.8)

	# a broad, dim fill from overhead so nobody is lost in the dark
	_omni(Vector3(2.4, 2.6, 0.0), Color("ffd2a4"), 0.2, 5.5, false, 0.2)
	_omni(Vector3(-1.8, 2.6, 1.8), Color("ffd2a4"), 0.35, 6.0, false, 0.2)
	_omni(Vector3(-1.8, 2.6, -2.2), Color("ffd2a4"), 0.35, 6.0, false, 0.2)


# ---------------------------------------------------------------------------
# The bar
# ---------------------------------------------------------------------------

func _bar() -> void:
	var front := BAR_FRONT_X
	var back := BAR_FRONT_X - BAR_DEPTH
	var zc := (BAR_Z0 + BAR_Z1) * 0.5
	var zl := BAR_Z1 - BAR_Z0
	var cx := (front + back) * 0.5

	# counter body: a dark carcass, raised panels on the front, a kick plate
	_box(Vector3(BAR_DEPTH - 0.06, BAR_TOP_Y - 0.05, zl), Vector3(cx - 0.03, (BAR_TOP_Y - 0.05) * 0.5, zc), _wood_dark)
	var panel_wood := PoolArt.wood_mat(Color("3c1f0e"), 0.3, 0.3, 0.08, Vector3.UP)
	PoolArt.set_clearcoat(panel_wood, 0.6, 0.15)
	var n := int(zl / 0.62)
	for i in n:
		var z := BAR_Z0 + (float(i) + 0.5) * zl / float(n)
		_box(Vector3(0.03, 0.62, zl / float(n) - 0.08), Vector3(front - 0.02, 0.58, z), panel_wood)
	_box(Vector3(0.04, 0.12, zl), Vector3(front - 0.04, 0.06, zc), PoolArt.mat(Color("0e0907"), 0.8))

	# the bar top: thick lacquered wood with a rounded front edge
	_box(Vector3(BAR_DEPTH + 0.12, 0.06, zl + 0.1), Vector3(cx + 0.04, BAR_TOP_Y - 0.01, zc), _wood_bar)
	var edge := _cyl(0.035, 0.035, zl + 0.1, Vector3(front + 0.1, BAR_TOP_Y - 0.01, zc), _wood_bar, 16)
	edge.rotation = Vector3(PI * 0.5, 0, 0)

	# a warm strip tucked under the lip of the bar top, washing down the
	# front panels, and a little light on the floor in front
	var under := PoolArt.glow_mat(Color("ffb870"), 1.6)
	_box(Vector3(0.012, 0.012, zl - 0.1), Vector3(front + 0.07, BAR_TOP_Y - 0.06, zc), under)
	for z: float in [zc - 1.5, zc, zc + 1.5]:
		_omni(Vector3(front + 0.35, 0.75, z), Color("ffc890"), 0.35, 2.2, false, 0.3)

	# brass foot rail on brackets
	var rail := _cyl(0.024, 0.024, zl - 0.2, Vector3(front + 0.2, 0.2, zc), _brass, 14)
	rail.rotation = Vector3(PI * 0.5, 0, 0)
	for z: float in [BAR_Z0 + 0.3, zc, BAR_Z1 - 0.3]:
		_box(Vector3(0.24, 0.03, 0.03), Vector3(front + 0.1, 0.2, z), _brass)

	# beer taps: a chrome tower with handles, a drip tray under the spouts
	var tap_z := zc + 1.35
	_box(Vector3(0.1, 0.34, 0.5), Vector3(front - 0.2, BAR_TOP_Y + 0.19, tap_z), _chrome)
	var tap_cols := [Color("c9a24a"), Color("2a5aa0"), Color("9a2020"), Color("1f6a3a")]
	for i in 4:
		var z: float = tap_z - 0.18 + float(i) * 0.12
		var spout := _cyl(0.012, 0.012, 0.1, Vector3(front - 0.12, BAR_TOP_Y + 0.28, z), _chrome, 8)
		spout.rotation = Vector3(0, 0, PI * 0.5)
		var hm := PoolArt.mat(tap_cols[i], 0.3)
		hm.clearcoat_enabled = true
		hm.clearcoat = 1.0
		_cyl(0.018, 0.011, 0.16, Vector3(front - 0.2, BAR_TOP_Y + 0.46, z), hm, 10)
	_box(Vector3(0.14, 0.012, 0.56), Vector3(front - 0.12, BAR_TOP_Y + 0.03, tap_z), PoolArt.mat(Color("2a2a2a"), 0.4, 0.8))

	# a cash register at the far end
	var reg := PoolArt.mat(Color("2b2622"), 0.4, 0.6)
	_box(Vector3(0.36, 0.2, 0.4), Vector3(cx - 0.05, BAR_TOP_Y + 0.12, BAR_Z0 + 0.45), reg)
	var top_box := _box(Vector3(0.22, 0.12, 0.3), Vector3(cx - 0.12, BAR_TOP_Y + 0.28, BAR_Z0 + 0.45), reg)
	top_box.rotation.z = 0.35
	_box(Vector3(0.02, 0.05, 0.14), Vector3(cx + 0.04, BAR_TOP_Y + 0.33, BAR_Z0 + 0.45),
		PoolArt.mat(Color("c9a24a"), 0.3, 0.9))

	# glasses, upended on a mat
	var glass := _glass_mat(Color(0.85, 0.9, 0.92), 0.16)
	for i in 6:
		var gz := zc - 1.6 + float(i % 3) * 0.11
		var gx := back + 0.14 + float(i / 3) * 0.11
		_cyl(0.034, 0.028, 0.13, Vector3(gx, BAR_TOP_Y + 0.09, gz), glass, 12)

	_back_bar()
	_bar_stools()

	# three small pendants over the counter
	var shade := PoolArt.mat(Color("2a1a10"), 0.45, 0.3)
	for z: float in [zc - 1.6, zc, zc + 1.6]:
		var x := cx + 0.05
		_cyl(0.005, 0.005, 0.9, Vector3(x, H - 0.45, z), _wood_dark, 6)
		_cyl(0.02, 0.14, 0.17, Vector3(x, H - 0.98, z), shade, 18)
		_bulb(Vector3(x, H - 1.05, z), 0.03, PoolArt.glow_mat(Color("ffd08a"), 2.4), shade)
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(x, H - 1.08, z)
		lamp.rotation_degrees = Vector3(-90, 0, 0)
		lamp.light_color = Color("ffc584")
		lamp.light_energy = 1.5
		lamp.spot_range = 3.0
		lamp.spot_angle = 55.0
		lamp.spot_angle_attenuation = 0.8
		lamp.shadow_enabled = true
		lamp.light_volumetric_fog_energy = 0.8
		add_child(lamp)


func _glass_mat(tint: Color, alpha: float) -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.04
	g.metallic_specular = 0.9
	g.rim_enabled = true
	g.rim = 0.4
	return g


# Shelves of bottles against a mirror, lit from behind, over a low cabinet.
func _back_bar() -> void:
	var x := BACK_BAR_X
	var zc := (BAR_Z0 + BAR_Z1) * 0.5
	var zl := BAR_Z1 - BAR_Z0 - 0.4
	# the low cabinet the bartender works at
	_box(Vector3(0.42, 0.92, zl), Vector3(x - 0.05, 0.46, zc), _wood_dark)
	_box(Vector3(0.48, 0.04, zl + 0.04), Vector3(x - 0.05, 0.94, zc), _wood_bar)
	for i in 6:
		var z := zc - zl * 0.5 + (float(i) + 0.5) * zl / 6.0
		_box(Vector3(0.02, 0.3, zl / 6.0 - 0.1), Vector3(x + 0.165, 0.62, z), PoolArt.mat(Color("2c180c"), 0.5))
		_box(Vector3(0.03, 0.02, 0.12), Vector3(x + 0.18, 0.68, z), _brass)

	# mirror and frame
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color(0.16, 0.14, 0.12)
	mirror.roughness = 0.06
	mirror.metallic = 0.85
	_box(Vector3(0.02, 1.1, zl), Vector3(-W + 0.07, 1.62, zc), mirror)
	_box(Vector3(0.05, 0.06, zl + 0.1), Vector3(-W + 0.08, 2.2, zc), _wood_bar)
	_box(Vector3(0.05, 0.06, zl + 0.1), Vector3(-W + 0.08, 1.06, zc), _wood_bar)

	# shelves, each lit along its front edge
	var strip := PoolArt.glow_mat(Color("ffa04a"), 2.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925
	for row in 2:
		var y := 1.32 + float(row) * 0.42
		_box(Vector3(0.3, 0.035, zl), Vector3(-W + 0.22, y, zc), _wood_bar)
		_box(Vector3(0.012, 0.014, zl - 0.1), Vector3(-W + 0.37, y - 0.022, zc), strip)
		var z := zc - zl * 0.5 + 0.12
		while z < zc + zl * 0.5 - 0.12:
			var kind := rng.randi_range(0, 3)
			var w := _bottle(Vector3(-W + 0.22, y + 0.018, z), kind, rng)
			z += w + rng.randf_range(0.015, 0.05)
	for z: float in [zc - 1.6, zc - 0.3, zc + 1.0, zc + 2.1]:
		_omni(Vector3(-W + 0.45, 1.62, z), Color("ffb878"), 0.8, 1.9, false, 1.0)

	# the chalkboard, over the mirror: what's on, and what it costs
	_box(Vector3(0.04, 0.64, 1.08), Vector3(-W + 0.085, 2.55, zc + 0.3), _wood_bar)
	_picture(Vector2(1.0, 0.56), Vector3(-W + 0.11, 2.55, zc + 0.3), PI * 0.5, 640.0, _paint_chalkboard)


# A bottle, lathed: body, shoulder, neck, lip, with the drink inside and a
# paper label. Returns how much shelf it takes.
func _bottle(at: Vector3, kind: int, rng: RandomNumberGenerator) -> float:
	var profiles := [
		# (radius, height) up from the base
		[[0.034, 0.0], [0.036, 0.02], [0.036, 0.2], [0.03, 0.235], [0.013, 0.26], [0.012, 0.31], [0.015, 0.32]],
		[[0.04, 0.0], [0.042, 0.02], [0.042, 0.14], [0.036, 0.17], [0.014, 0.2], [0.013, 0.26], [0.016, 0.27]],
		[[0.028, 0.0], [0.03, 0.02], [0.03, 0.24], [0.018, 0.28], [0.011, 0.3], [0.011, 0.35], [0.013, 0.355]],
		[[0.046, 0.0], [0.048, 0.015], [0.046, 0.12], [0.02, 0.15], [0.014, 0.18], [0.014, 0.21], [0.017, 0.215]],
	]
	var liquids := [Color("7a3a10"), Color("c28a2a"), Color("2a6a3a"), Color("6a1020"), Color("d8c89a"), Color("3a2410")]
	var glasses := [Color(0.35, 0.22, 0.1), Color(0.2, 0.4, 0.22), Color(0.85, 0.88, 0.9), Color(0.15, 0.2, 0.35)]
	var prof: Array = profiles[kind]
	var gcol: Color = glasses[rng.randi_range(0, glasses.size() - 1)]
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var bm := MeshInstance3D.new()
	bm.mesh = _lathe(prof, 14)
	bm.material_override = _glass_mat(gcol, 0.42)
	root.add_child(bm)
	# the drink, a little inside the glass, a random way full
	var fill := rng.randf_range(0.35, 0.95)
	var top_h: float = float(prof[2][1]) * fill
	var inner: Array = []
	for p in prof:
		if float(p[1]) < top_h:
			inner.append([float(p[0]) * 0.86, float(p[1]) + 0.004])
	inner.append([float(prof[1][0]) * 0.86, top_h])
	var lm := StandardMaterial3D.new()
	var lc: Color = liquids[rng.randi_range(0, liquids.size() - 1)]
	lm.albedo_color = lc
	lm.roughness = 0.1
	lm.emission_enabled = true
	lm.emission = lc
	lm.emission_energy_multiplier = 0.25
	var li := MeshInstance3D.new()
	li.mesh = _lathe(inner, 12)
	li.material_override = lm
	root.add_child(li)
	if rng.randf() < 0.8:
		var label := StandardMaterial3D.new()
		label.albedo_color = [Color("e8dcc0"), Color("1a1a1a"), Color("c9a24a"), Color("8a1a1a")][rng.randi_range(0, 3)]
		label.roughness = 0.8
		var r: float = float(prof[2][0]) + 0.0015
		var lh := float(prof[2][1]) * 0.35
		_cyl(r, r, lh, Vector3(0, float(prof[2][1]) * 0.45, 0), label, 14, root)
	return float(prof[1][0]) * 2.0


static func _lathe(prof: Array, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in prof.size() - 1:
		var r0: float = prof[k][0]
		var y0: float = prof[k][1]
		var r1: float = prof[k + 1][0]
		var y1: float = prof[k + 1][1]
		var slope := Vector2(y1 - y0, r0 - r1).normalized()
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var n0 := Vector3(cos(a0) * slope.x, slope.y, sin(a0) * slope.x)
			var n1 := Vector3(cos(a1) * slope.x, slope.y, sin(a1) * slope.x)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [[p00, n0], [p11, n1], [p10, n1], [p00, n0], [p01, n0], [p11, n1]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var top_r: float = prof[prof.size() - 1][0]
	var top_y: float = prof[prof.size() - 1][1]
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, top_y, 0))
		st.add_vertex(Vector3(cos(a1) * top_r, top_y, sin(a1) * top_r))
		st.add_vertex(Vector3(cos(a0) * top_r, top_y, sin(a0) * top_r))
	return st.commit()


# Stools along the counter, leaving the stretch in front of the bartender
# clear for ordering.
func _bar_stools() -> void:
	var seat := PoolArt.mat(Color("5a1c14"), 0.45)
	seat.clearcoat_enabled = true
	seat.clearcoat = 0.4
	for z: float in [-2.0, -1.25, 1.75, 2.35]:
		var sx := BAR_FRONT_X + 0.42
		_cyl(0.19, 0.18, 0.08, Vector3(sx, 0.76, z), seat, 22)
		_cyl(0.16, 0.19, 0.02, Vector3(sx, 0.71, z), _chrome, 22)
		_cyl(0.028, 0.034, 0.7, Vector3(sx, 0.36, z), _chrome, 12)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.17
		var rm := MeshInstance3D.new()
		rm.mesh = ring
		rm.material_override = _chrome
		rm.position = Vector3(sx, 0.28, z)
		add_child(rm)
		_cyl(0.2, 0.22, 0.03, Vector3(sx, 0.015, z), _chrome, 22)
		obstacles.append([Vector2(sx, z), 0.22])


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------

func _props() -> void:
	var wood := PoolArt.wood_mat(Color("3e2512"), 0.4, 0.24, 0.08)
	PoolArt.set_clearcoat(wood, 0.5, 0.2)

	# neon sign: an 8, in cheap bar magenta
	var neon := PoolArt.glow_mat(Color("ff69b0"), 4.0)
	for i in 2:
		var t := TorusMesh.new()
		t.inner_radius = 0.145
		t.outer_radius = 0.175
		t.rings = 40
		t.ring_segments = 12
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = Vector3(2.6, 2.15 - float(i) * 0.30, L - 0.14)
		mi.material_override = neon
		add_child(mi)
	_omni(Vector3(2.6, 2.0, L - 0.5), Color("ff5fae"), 1.3, 3.2, false, 0.9)

	_dartboard(Vector3(-1.1, 1.73, L - 0.09))

	# cue rack on the wall, with real cues standing in it
	_box(Vector3(0.1, 0.08, 0.66), Vector3(W - 0.14, 1.72, -1.6), wood)
	_box(Vector3(0.1, 0.08, 0.66), Vector3(W - 0.14, 0.4, -1.6), wood)
	for i in 4:
		var cue := PoolCueModel.build(PoolCues.CUES[[0, 1, 2, 14][i] % PoolCues.CUES.size()])
		# upright, tip up: the model runs +Y from the tip, so turn it over
		cue.position = Vector3(W - 0.2, 1.9, -1.84 + float(i) * 0.16)
		cue.rotation = Vector3(PI, 0.0, 0.0)
		add_child(cue)

	# high table with two pints on it
	var tx := 3.5
	var tz := -2.4
	_cyl(0.42, 0.42, 0.05, Vector3(tx, 1.02, tz), wood, 28)
	_cyl(0.05, 0.06, 1.0, Vector3(tx, 0.5, tz), _chrome, 12)
	_cyl(0.24, 0.24, 0.03, Vector3(tx, 0.015, tz), _chrome, 20)
	for o: float in [-0.13, 0.12]:
		_pint(Vector3(tx + o, 1.045, tz + o * 0.6), 0.55 + o)
	obstacles.append([Vector2(tx, tz), 0.44])

	_framed_art()


# A pint of beer: glass, beer, a head of foam.
func _pint(at: Vector3, fill: float) -> void:
	var beer := StandardMaterial3D.new()
	beer.albedo_color = Color("c7841c")
	beer.roughness = 0.15
	beer.emission_enabled = true
	beer.emission = Color("c7841c")
	beer.emission_energy_multiplier = 0.15
	var h := 0.14 * fill
	_cyl(0.031 + 0.003 * fill, 0.027, h, at + Vector3(0, 0.008 + h * 0.5, 0), beer, 16)
	_cyl(0.033, 0.032, 0.012, at + Vector3(0, 0.014 + h, 0), PoolArt.mat(Color("f2e8d0"), 0.9), 16)
	_cyl(0.037, 0.03, 0.16, at + Vector3(0, 0.08, 0), _glass_mat(Color(0.9, 0.93, 0.95), 0.18), 16)


# A proper board: black and cream segments, red and green doubles and trebles,
# a bull, the numbers round the outside, a light over it.
func _dartboard(at: Vector3) -> void:
	var back := _cyl(0.245, 0.245, 0.035, at + Vector3(0, 0, 0.005), PoolArt.mat(Color("141414"), 0.8), 48)
	back.rotation_degrees = Vector3(90, 0, 0)
	_picture(Vector2(0.48, 0.48), at - Vector3(0, 0, 0.016), PI, 900.0, _paint_dartboard, true)
	var spot := SpotLight3D.new()
	add_child(spot)
	spot.position = at + Vector3(0, 0.6, -0.45)
	spot.look_at(at, Vector3.UP)
	spot.light_color = Color("ffd29a")
	spot.light_energy = 2.2
	spot.spot_range = 1.5
	spot.spot_angle = 24.0


func _framed_art() -> void:
	var frame_wood := PoolArt.wood_mat(Color("2a1a0e"), 0.35, 0.3, 0.08)
	PoolArt.set_clearcoat(frame_wood, 0.6, 0.2)
	var art := [
		[-1.9, _paint_poster_jarvis, Vector2(0.56, 0.76)],
		[-0.35, _paint_poster_blitz, Vector2(0.52, 0.7)],
		[1.2, _paint_poster_wobbly, Vector2(0.52, 0.7)],
	]
	for a in art:
		var x: float = a[0]
		var sz: Vector2 = a[2]
		var y := 1.8
		_box(Vector3(sz.x + 0.08, sz.y + 0.08, 0.04), Vector3(x, y, -L + 0.08), frame_wood)
		_picture(sz, Vector3(x, y, -L + 0.102), 0.0, 700.0, a[1])
		# a brass picture light above each
		var top := y + sz.y * 0.5 + 0.1
		_box(Vector3(0.05, 0.03, 0.05), Vector3(x, top, -L + 0.08), _brass)
		var hood := _cyl(0.025, 0.025, sz.x * 0.6, Vector3(x, top, -L + 0.18), _brass, 10)
		hood.rotation = Vector3(0, 0, PI * 0.5)
		var sp := SpotLight3D.new()
		add_child(sp)
		sp.position = Vector3(x, top - 0.02, -L + 0.22)
		sp.look_at(Vector3(x, y - 0.12, -L + 0.1), Vector3.UP)
		sp.light_color = Color("ffcf94")
		sp.light_energy = 1.6
		sp.spot_range = 1.4
		sp.spot_angle = 40.0
		sp.light_volumetric_fog_energy = 0.4


# --- painted things ----------------------------------------------------------

func _paint_chalkboard(c: PoolPaint.Canvas) -> void:
	var s := c.size
	c.draw_rect(Rect2(Vector2.ZERO, s), Color("1f2622"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 60:
		c.draw_circle(Vector2(rng.randf() * s.x, rng.randf() * s.y), rng.randf_range(10, 40), Color(1, 1, 1, 0.018))
	var hand := c.font(PoolPaint.hand(), 700)
	var chalk := Color(0.94, 0.93, 0.88)
	c.draw_string(hand, Vector2(0, 62), "~ Drinks ~", HORIZONTAL_ALIGNMENT_CENTER, s.x, 44, chalk)
	c.draw_string(hand, Vector2(40, 150), "Blitzkraft", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("9fe8ff"))
	c.draw_string(hand, Vector2(40, 150), "$6", HORIZONTAL_ALIGNMENT_RIGHT, s.x - 80, 40, chalk)
	c.draw_string(hand, Vector2(56, 190), "Das Energie-Schnaps", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(chalk, 0.7))
	c.draw_string(hand, Vector2(40, 270), "Old Wobbly", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("ffc070"))
	c.draw_string(hand, Vector2(40, 270), "$4", HORIZONTAL_ALIGNMENT_RIGHT, s.x - 80, 40, chalk)
	c.draw_string(hand, Vector2(56, 310), "dark rum, no questions", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(chalk, 0.7))
	c.draw_string(hand, Vector2(0, s.y - 24), "no fighting at the table", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(chalk, 0.55))


func _paint_dartboard(c: PoolPaint.Canvas) -> void:
	var s := c.size
	var ctr := s * 0.5
	var r := s.x * 0.5
	var black := Color("161616")
	var cream := Color("e9dcc0")
	var red := Color("b02020")
	var green := Color("1e7a3a")
	c.draw_circle(ctr, r * 0.99, Color("141414"))
	for i in 20:
		var a0 := TAU * (float(i) - 0.5) / 20.0 - PI * 0.5
		var a1 := TAU * (float(i) + 0.5) / 20.0 - PI * 0.5
		var odd := i % 2 == 1
		# outer to inner: double, single, treble, single
		var bands := [[0.78, 0.72, red if odd else green], [0.72, 0.47, black if odd else cream],
			[0.47, 0.42, red if odd else green], [0.42, 0.08, black if odd else cream]]
		for band in bands:
			var pts := PackedVector2Array()
			for k in 7:
				var a := lerpf(a0, a1, float(k) / 6.0)
				pts.append(ctr + Vector2(cos(a), sin(a)) * r * float(band[0]))
			for k in 7:
				var a := lerpf(a1, a0, float(k) / 6.0)
				pts.append(ctr + Vector2(cos(a), sin(a)) * r * float(band[1]))
			c.draw_colored_polygon(pts, band[2])
	c.draw_circle(ctr, r * 0.08, green)
	c.draw_circle(ctr, r * 0.035, red)
	for ring: float in [0.78, 0.72, 0.47, 0.42, 0.08]:
		c.draw_arc(ctr, r * ring, 0.0, TAU, 96, Color(0.75, 0.75, 0.7, 0.8), 1.5, true)
	var nums := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
	var f := c.font(["Arial"], 700)
	for i in 20:
		var a := TAU * float(i) / 20.0 - PI * 0.5
		var p := ctr + Vector2(cos(a), sin(a)) * r * 0.89
		var t := str(nums[i])
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		c.draw_string(f, p + Vector2(-w * 0.5, 11), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, cream)


func _poster_base(c: PoolPaint.Canvas, bg: Color, ink: Color) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), bg)
	# old paper: a little uneven, darker at the edges
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bg.r * 1000.0)
	for i in 90:
		c.draw_circle(Vector2(rng.randf() * c.size.x, rng.randf() * c.size.y), rng.randf_range(20, 70), Color(0, 0, 0, 0.018))
	c.draw_rect(Rect2(Vector2(14, 14), c.size - Vector2(28, 28)), Color(ink, 0.8), false, 3.0)


func _paint_poster_jarvis(c: PoolPaint.Canvas) -> void:
	var s := c.size
	var ink := Color("2a1a10")
	_poster_base(c, Color("e6d3a8"), ink)
	var f := c.font(PoolPaint.poster(), 800)
	c.draw_string(f, Vector2(0, 86), "JARVIS'S", HORIZONTAL_ALIGNMENT_CENTER, s.x, 62, ink)
	c.draw_string(f, Vector2(0, 124), "BILLIARD PARLOUR", HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color("9a2a18"))
	var ctr := Vector2(s.x * 0.5, s.y * 0.53)
	for sgn: float in [1.0, -1.0]:
		var a := Vector2(sgn * 130, -150)
		var b := Vector2(-sgn * 130, 150)
		c.draw_line(ctr + a, ctr + b, Color("7a4a1c"), 12.0, true)
		c.draw_line(ctr + a * 0.55, ctr + a, Color("2a1a10"), 13.0, true)
	c.draw_circle(ctr, 82, Color("161616"))
	c.draw_circle(ctr + Vector2(-8, -10), 34, Color("f4efe2"))
	var f2 := c.font(["Arial"], 800)
	c.draw_string(f2, ctr + Vector2(-26, 14), "J", HORIZONTAL_ALIGNMENT_CENTER, 36, 48, Color("161616"))
	c.draw_circle(ctr + Vector2(-38, -44), 12, Color(1, 1, 1, 0.5))
	c.draw_string(f, Vector2(0, s.y - 70), "TABLES  ·  SPIRITS  ·  LATE", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, ink)
	c.draw_string(f, Vector2(0, s.y - 38), "EST. 1962", HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color("9a2a18"))


func _paint_poster_blitz(c: PoolPaint.Canvas) -> void:
	var s := c.size
	c.draw_rect(Rect2(Vector2.ZERO, s), Color("101a2e"))
	var ctr := Vector2(s.x * 0.5, s.y * 0.52)
	for i in 16:
		var a0 := TAU * float(i) / 16.0
		var a1 := a0 + TAU / 32.0
		c.draw_colored_polygon(PackedVector2Array([ctr, ctr + Vector2(cos(a0), sin(a0)) * 600.0,
			ctr + Vector2(cos(a1), sin(a1)) * 600.0]), Color("1c3a6a"))
	var f := c.font(PoolPaint.poster(), 800)
	c.draw_string(f, Vector2(0, 76), "BLITZKRAFT", HORIZONTAL_ALIGNMENT_CENTER, s.x, 56, Color("9fe8ff"))
	c.draw_string(f, Vector2(0, 110), "DAS ENERGIE-SCHNAPS", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color("ffe14a"))
	var bolt := PackedVector2Array([Vector2(-20, -120), Vector2(40, -120), Vector2(8, -20), Vector2(50, -20),
		Vector2(-30, 130), Vector2(-4, 10), Vector2(-46, 10)])
	for i in bolt.size():
		bolt[i] += ctr + Vector2(0, 16)
	c.draw_colored_polygon(bolt, Color("ffe14a"))
	c.draw_string(f, Vector2(0, s.y - 40), "ZUM WOHL!", HORIZONTAL_ALIGNMENT_CENTER, s.x, 30, Color("9fe8ff"))


func _paint_poster_wobbly(c: PoolPaint.Canvas) -> void:
	var s := c.size
	var ink := Color("3a1a0a")
	_poster_base(c, Color("d9b27a"), ink)
	var f := c.font(PoolPaint.poster(), 800)
	c.draw_string(f, Vector2(0, 80), "OLD WOBBLY", HORIZONTAL_ALIGNMENT_CENTER, s.x, 50, ink)
	c.draw_string(f, Vector2(0, 112), "FINE DARK RUM", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color("7a2a10"))
	# a ship leaning over on a swell
	var ctr := Vector2(s.x * 0.5, s.y * 0.56)
	var hull := PackedVector2Array([Vector2(-110, 0), Vector2(110, -20), Vector2(80, 40), Vector2(-90, 50)])
	for i in hull.size():
		hull[i] = ctr + hull[i].rotated(-0.18)
	c.draw_colored_polygon(hull, Color("4a2410"))
	c.draw_line(ctr + Vector2(-5, 0), ctr + Vector2(20, -170), ink, 6.0, true)
	c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(22, -160), ctr + Vector2(100, -60), ctr + Vector2(5, -40)]), Color("efe3c6"))
	for i in 5:
		var y := s.y * 0.72 + float(i) * 14.0
		for k in 8:
			var x0 := float(k) * s.x / 8.0
			c.draw_arc(Vector2(x0 + 24, y), 24, PI, TAU, 10, Color("2a5a7a"), 4.0, true)
	c.draw_string(f, Vector2(0, s.y - 36), "steady as she goes", HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, ink)
