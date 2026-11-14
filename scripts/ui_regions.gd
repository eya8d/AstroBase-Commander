## scripts/ui_regions.gd
## The Stitch artwork arrives as complete screens: buttons, panels and read-outs are
## already painted into the pixels.  Instead of redrawing them in another style, this
## helper cuts a painted button out of the artwork (AtlasTexture) and drops a real Godot
## control exactly on top of it, so the button you see IS the button you press.
##
## Regions are given in ARTWORK PIXELS.  A "holder" control returned by
## add_artwork_panel() has size == artwork size and scale == display scale, therefore
## children placed in artwork pixels land exactly on the painted pixels at any window
## size (the project uses canvas_items stretch, so the whole layer scales together).
##
## Every coordinate used by the callers was measured from the processed PNGs
## (documented in docs/assets_pack_v2.json).
class_name UiRegions

const HOVER_MODULATE := Color(1.3, 1.3, 1.4, 1.0)


## Uniform scale factor that maps artwork pixels onto `surface`.
static func scale_for(surface: Control, art_size: Vector2) -> Vector2:
	if art_size.x <= 0.0 or art_size.y <= 0.0:
		return Vector2.ONE
	return surface.size / art_size


## A TextureButton covering `region` of `art`, added to `surface`.
## `surface` draws `art` at its own size, so the mapping is linear.
## Returns the button (null if the artwork is missing) so the caller connects `pressed`.
static func add_region_button(surface: Control, art: Texture2D, region: Rect2,
		node_name: String = "RegionButton") -> TextureButton:
	if art == null or surface == null:
		return null
	var art_size := Vector2(art.get_width(), art.get_height())
	var k := scale_for(surface, art_size)

	var atlas := AtlasTexture.new()
	atlas.atlas = art
	atlas.region = region
	atlas.filter_clip = true

	var button := TextureButton.new()
	button.name = node_name
	button.texture_normal = atlas
	button.texture_pressed = atlas
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.focus_mode = Control.FOCUS_NONE
	button.position = region.position * k
	button.size = region.size * k
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	surface.add_child(button)

	button.mouse_entered.connect(func() -> void:
		button.self_modulate = HOVER_MODULATE
		AudioManager.play_ui_hover()
	)
	button.mouse_exited.connect(func() -> void: button.self_modulate = Color.WHITE)
	if node_name.to_lower().contains("back") or node_name.to_lower().contains("close"):
		button.pressed.connect(AudioManager.play_ui_back)
	else:
		button.pressed.connect(AudioManager.play_ui_confirm)
	return button


## Draws a full-screen piece of artwork (menu / briefing / result screens).
## The returned TextureRect is anchored to the parent's full rect, so artwork pixels
## map through scale_for() — the painted buttons keep their alignment.
static func add_fullscreen_art(parent: Control, art: Texture2D,
		name_hint: String = "ScreenArt") -> TextureRect:
	var view := TextureRect.new()
	view.name = name_hint
	view.texture = art
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(view)
	return view


## Draws a panel/modal centred inside `parent` at `display_scale`.
## Returns a holder Control whose local coordinates ARE artwork pixels, so
## add_region_button(holder, art, rect) can be used directly.
static func add_artwork_panel(parent: Control, art: Texture2D, display_scale: float,
		name_hint: String = "ArtworkHolder") -> Control:
	if art == null or parent == null:
		return null
	var art_size := Vector2(art.get_width(), art.get_height())

	var holder := Control.new()
	holder.name = name_hint
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.scale = Vector2(display_scale, display_scale)
	holder.size = art_size
	holder.position = (parent.size - art_size * display_scale) * 0.5
	parent.add_child(holder)

	var view := TextureRect.new()
	view.name = "Art"
	view.texture = art
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size = art_size
	holder.add_child(view)
	return holder


## Re-centres a holder produced by add_artwork_panel() (call when the parent resizes).
static func recenter(holder: Control, parent: Control) -> void:
	if holder == null or parent == null:
		return
	holder.position = (parent.size - holder.size * holder.scale.x) * 0.5


## Runtime text printed inside an artwork-pixel rect (a value slot the cleanup pass
## emptied).  Font size is given in artwork pixels too, so it scales with the panel.
static func add_label(parent: Control, rect: Rect2, font_size: int,
		color: Color = Color(0.94, 0.97, 1.0),
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
		valign: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER,
		word_wrap: bool = false, plate: bool = true) -> Label:
	# The artwork was drawn with invented numbers in these slots.  Rather than painting
	# over the original PNG (which dulled the bright headings around them), the fake value
	# is covered by a dark read-out plate and the live number is printed on top of it.
	if plate:
		var backing := Panel.new()
		backing.name = "ValuePlate"
		var box := StyleBoxFlat.new()
		## Fully opaque: at 0.92 the bright invented digits still ghosted through as a
		## grey shape behind the live value (clearly visible in the build-menu cards).
		box.bg_color = Color(0.043, 0.063, 0.098, 1.0)
		box.border_color = Color(0.34, 0.62, 0.72, 0.55)
		box.set_border_width_all(2)
		box.set_corner_radius_all(8)
		backing.add_theme_stylebox_override("panel", box)
		backing.position = rect.position
		backing.size = rect.size
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(backing)
	var label := Label.new()
	label.name = "ValueText"
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = halign
	label.vertical_alignment = valign
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.07, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	if word_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
