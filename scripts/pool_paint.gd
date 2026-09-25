class_name PoolPaint
extends RefCounted

# Painted textures: posters, the dartboard, the chalkboard, the drink cards.
# Each is drawn with the 2D renderer into an offscreen canvas for a few
# frames (so the lettering is rasterised before it is read back), then copied
# into an ordinary mipmapped texture and handed to whoever asked. Until then
# the material shows a plain colour, for the few frames that takes.

class Canvas extends Control:
	var painter: Callable
	var fonts: Dictionary = {}

	func _draw() -> void:
		painter.call(self)

	# a font that lives as long as the canvas, so its glyphs stay cached
	func font(names: Array, weight := 400) -> Font:
		var key := "%s:%d" % [str(names), weight]
		if not fonts.has(key):
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(names)
			sf.font_weight = weight
			sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			fonts[key] = sf
		return fonts[key]


# Paints `size` pixels with `draw` (called with the canvas to draw on) and
# sets the result as the albedo of `mat` once it is ready.
static func into(owner: Node, size: Vector2i, draw: Callable, mat: BaseMaterial3D, emissive := false,
		transparent := false) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var c := Canvas.new()
	c.painter = draw
	c.size = Vector2(size)
	vp.add_child(c)
	owner.add_child(vp)
	_finish(vp, c, mat, emissive)


static func _finish(vp: SubViewport, c: Canvas, mat: BaseMaterial3D, emissive: bool) -> void:
	for _i in 4:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(c):
			return
		c.queue_redraw()
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	if emissive:
		mat.emission_texture = tex


static func hand() -> Array:
	return ["Segoe Print", "Ink Free", "Comic Sans MS", "Bahnschrift", "Arial"]


static func poster() -> Array:
	return ["Bahnschrift", "Impact", "Arial Black", "Arial"]
