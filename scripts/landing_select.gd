## scripts/landing_select.gd
## DAY 0 — MAIN CONTROL ROOM: choose where the colony lands.
##
## Layers, bottom to top (the supplied artwork is never edited):
##   1. the supplied global Mars mosaic (game/map/full map no gridlines no names.png)
##   2. MapGrid — latitude / longitude lines and labels drawn by code, toggleable
##   3. one marker per site from data/landing_sites.json (hover = scan, click = open data)
##   4. the site's own information panel (game/map/..._panel_N.png) whose painted
##      BACK TO ORBIT / CONFIRM LANDING SITE / X buttons are made real controls
##
## Scientific values come from the "nasa_data" block of the JSON (USGS Gazetteer).
## Starting resources and modifiers come from the "gameplay" block and are always shown
## as game rules, never as NASA data.  Three sites ship (Elysium, Valles, Acidalia), each
## with its own supplied regional image, information panel and in-game ground map.
## The map window cycles the three supplied global-map variants (clean + code grid,
## supplied grid, supplied names) listed in landing_sites.json "view_modes".
##
## menu_main.gd creates this screen after the briefing and listens for:
##   site_confirmed(site_id)  -> loading screen -> main.tscn on Sol 1
##   back_requested           -> back to the briefing
class_name LandingSelect
extends Control

signal site_confirmed(site_id: String)
signal back_requested

const SCREEN := Vector2(1280, 720)
## Where the global map is drawn (keeps the image's 767:510 aspect ratio).
const MAP_RECT := Rect2(26, 70, 872, 580)
const RETICLE_TEX := "res://map/Screenshot_2026-11-14_071355-removebg-preview.png"
const LANDER_TEX := "res://map/screen-removebg-preview (4).png"

## Fallback only: the line is read from data/story/campaign_30_sols.json "day0".
const NOVA_OPENING := "Landing orbit successfully aligned. Choose your settlement location carefully, Commander. Every coordinate comes with its own environmental challenges."

## Painted controls on the 578x432 information panels (the three share one layout).
const PANEL_BACK := Rect2(52, 367, 227, 31)
const PANEL_CONFIRM := Rect2(295, 366, 231, 33)
const PANEL_CLOSE := Rect2(506, 42, 22, 24)
const PANEL_SCALE := 1.2

const BG := Color(0.025, 0.04, 0.07)
const FRAME := Color(0.35, 0.75, 0.9, 0.85)
const TEAL := Color(0.45, 0.92, 0.95)
const ACCENT := Color(1.0, 0.72, 0.35)
const TEXT := Color(0.92, 0.96, 1.0)
const DIM_TEXT := Color(0.66, 0.78, 0.88)

const MARKER_SIZE := 46.0
const NOVA_CHARS_PER_SECOND := 55.0

var _map_cfg: Dictionary = {}
var _sites: Array = []
var _markers: Dictionary = {}      # site id -> {root, reticle, tag}
var _list_buttons: Dictionary = {} # site id -> Button
var _map_box: Control
var _grid: MapGrid
var _nova_label: Label
var _nova_progress: float = 0.0
var _readout_title: Label
var _readout_body: Label
var _cursor_label: Label
var _view_button: Button
var _map_view: TextureRect
var _view_modes: Array = []
var _view_index: int = 0
var _modal: Control
var _hover_id: String = ""
var _selected_id: String = ""
var _busy: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = SCREEN
	var catalogue: Dictionary = DataLoader.get_landing_catalogue()
	var cfg: Variant = catalogue.get("map", {})
	_map_cfg = cfg if cfg is Dictionary else {}
	_sites = DataLoader.get_landing_sites()
	if _sites.is_empty():
		push_error("LandingSelect: data/landing_sites.json has no sites")

	_build_room()
	_build_map()
	_build_side_column()
	for site: Variant in _sites:
		if site is Dictionary:
			_add_marker(site)
	_show_default_readout()
	nova_say(_opening_line())


## NOVA's Day 0 line from the story file (the 30-day script), English only.
func _opening_line() -> String:
	var day0: Variant = DataLoader.get_story().get("day0", {})
	if day0 is Dictionary:
		for line: Variant in (day0 as Dictionary).get("dialogue", []):
			if line is Dictionary and str((line as Dictionary).get("speaker", "")) == "NOVA":
				return str((line as Dictionary).get("text", NOVA_OPENING))
	return NOVA_OPENING


# ==================== layout ====================

func _build_room() -> void:
	var bg := ColorRect.new()
	bg.name = "ControlRoomBackground"
	bg.color = BG
	bg.size = SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Thin console bands top and bottom.
	for band: Rect2 in [Rect2(0, 0, 1280, 54), Rect2(0, 686, 1280, 34)]:
		var strip := ColorRect.new()
		strip.color = Color(0.05, 0.08, 0.13)
		strip.position = band.position
		strip.size = band.size
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(strip)

	_label(Rect2(26, 8, 900, 40), "MAIN CONTROL ROOM  //  DAY 0 — LANDING SITE SELECTION",
		24, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	var scenario: Dictionary = GameState.get_scenario()
	_label(Rect2(760, 8, 496, 40), "ORBIT STABLE · SOL 0 · %s · SOLS %d–%d" % [
		str(scenario.get("menu_tag", "MISSION")).to_upper(), int(scenario.get("start_sol", 1)),
		int(scenario.get("end_sol", GameState.target_sols))], 16, TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(Rect2(26, 690, 1230, 26),
		"Base map: supplied global Mars mosaic, unmodified (3 supplied variants). The game grid is drawn by code (approx. equirectangular, 90°W–180°E). Site data: USGS Gazetteer of Planetary Nomenclature.",
		12, DIM_TEXT, HORIZONTAL_ALIGNMENT_LEFT)


func _build_map() -> void:
	_panel_frame(MAP_RECT.grow(6))
	_map_box = Control.new()
	_map_box.name = "MapBox"
	_map_box.position = MAP_RECT.position
	_map_box.size = MAP_RECT.size
	_map_box.clip_contents = true
	_map_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_map_box)

	var view := TextureRect.new()
	view.name = "GlobalMarsMap"
	view.texture = load(str(_map_cfg.get("texture", ""))) as Texture2D
	if view.texture == null:
		push_error("LandingSelect: global map texture missing")
	_map_view = view
	var modes: Variant = _map_cfg.get("view_modes", [])
	if modes is Array:
		for mode: Variant in modes:
			if mode is Dictionary and ResourceLoader.exists(str((mode as Dictionary).get("texture", ""))):
				_view_modes.append(mode)
	# A real photo mosaic: smooth filtering so it never looks pixelated when scaled.
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.size = MAP_RECT.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_box.add_child(view)

	_grid = MapGrid.new()
	_grid.name = "CoordinateGrid"
	_grid.lon_west = float(_map_cfg.get("lon_west", -90.0))
	_grid.lon_east = float(_map_cfg.get("lon_east", 180.0))
	_grid.lat_north = float(_map_cfg.get("lat_north", 90.0))
	_grid.lat_south = float(_map_cfg.get("lat_south", -90.0))
	_grid.size = MAP_RECT.size
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_box.add_child(_grid)

	_cursor_label = _label(Rect2(MAP_RECT.position.x + 8, MAP_RECT.end.y - 30, 330, 24), "",
		14, TEAL, HORIZONTAL_ALIGNMENT_LEFT)


func _build_side_column() -> void:
	var x := 918.0
	var w := 340.0
	# NOVA comms box.
	_panel_frame(Rect2(x, 64, w, 132))
	_label(Rect2(x + 12, 70, w - 24, 22), "NOVA // MISSION AI", 15, TEAL, HORIZONTAL_ALIGNMENT_LEFT)
	_nova_label = _label(Rect2(x + 12, 90, w - 24, 104), "", 15, TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	_nova_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Target read-out.
	_panel_frame(Rect2(x, 204, w, 268))
	_readout_title = _label(Rect2(x + 12, 210, w - 24, 26), "", 18, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_readout_body = _label(Rect2(x + 12, 238, w - 24, 230), "", 13, TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, true)
	_readout_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# One list button per site (same action as clicking its marker).
	var y := 480.0
	for site: Variant in _sites:
		if not site is Dictionary:
			continue
		var id: String = str(site.get("id", ""))
		var caption: String = str(site.get("name", id)).to_upper()
		var button := _flat_button(caption, Rect2(x, y, w, 36))
		button.mouse_entered.connect(_on_marker_hover.bind(id))
		button.mouse_exited.connect(_on_marker_unhover.bind(id))
		button.pressed.connect(_select.bind(id))
		_list_buttons[id] = button
		y += 42.0

	_view_button = _flat_button("VIEW: CLEAN + GRID [G]", Rect2(x, 648, 196, 32))
	_view_button.add_theme_font_size_override("font_size", 12)
	_view_button.pressed.connect(_cycle_view)
	_apply_view()
	var back := _flat_button("< BRIEFING", Rect2(x + 204, 648, 136, 32))
	back.add_theme_font_size_override("font_size", 13)
	back.pressed.connect(_on_back)


# ==================== markers ====================

## Map-local pixel position of a latitude / longitude (degrees, +East).
func lonlat_to_map(lat: float, lon: float) -> Vector2:
	var west: float = float(_map_cfg.get("lon_west", -90.0))
	var east: float = float(_map_cfg.get("lon_east", 180.0))
	var north: float = float(_map_cfg.get("lat_north", 90.0))
	var south: float = float(_map_cfg.get("lat_south", -90.0))
	return Vector2((lon - west) / (east - west) * MAP_RECT.size.x,
		(north - lat) / (north - south) * MAP_RECT.size.y)


func map_to_lonlat(local: Vector2) -> Vector2:
	var west: float = float(_map_cfg.get("lon_west", -90.0))
	var east: float = float(_map_cfg.get("lon_east", 180.0))
	var north: float = float(_map_cfg.get("lat_north", 90.0))
	var south: float = float(_map_cfg.get("lat_south", -90.0))
	return Vector2(north - local.y / MAP_RECT.size.y * (north - south),
		west + local.x / MAP_RECT.size.x * (east - west))


func _add_marker(site: Dictionary) -> void:
	var id: String = str(site.get("id", ""))
	var nasa: Dictionary = site.get("nasa_data", {}) as Dictionary
	var lat: float = float(nasa.get("latitude", 0.0))
	var lon: float = float(nasa.get("longitude", 0.0))
	if lon > float(_map_cfg.get("lon_east", 180.0)):
		lon -= 360.0
	var point: Vector2 = lonlat_to_map(lat, lon)

	var root := Control.new()
	root.name = "Marker_%s" % id
	root.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	root.position = point - root.size * 0.5
	root.pivot_offset = root.size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root.tooltip_text = ""
	_map_box.add_child(root)

	# A small pulsing beacon so every site is easy to spot before it is hovered.
	var dot := Panel.new()
	dot.name = "Beacon"
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = ACCENT
	dot_style.border_color = Color(0.02, 0.03, 0.05, 0.9)
	dot_style.set_border_width_all(2)
	dot_style.set_corner_radius_all(8)
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.size = Vector2(12, 12)
	dot.position = (root.size - dot.size) * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)

	var reticle := TextureRect.new()
	reticle.name = "Reticle"
	reticle.texture = load(RETICLE_TEX) as Texture2D
	reticle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reticle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reticle.size = root.size
	reticle.pivot_offset = root.size * 0.5
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.modulate = Color(1, 1, 1, 0.9)
	root.add_child(reticle)

	var tag_text: String = str(site.get("name", id)).to_upper()
	var tag := Label.new()
	tag.name = "Tag"
	tag.text = tag_text
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", TEXT)
	tag.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 1.0))
	tag.add_theme_constant_override("outline_size", 5)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size = Vector2(190, 36)
	# Tags read to the right unless the marker is near the east edge.
	if point.x > MAP_RECT.size.x - 200.0:
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.position = Vector2(-tag.size.x - 4, 4)
	else:
		tag.position = Vector2(MARKER_SIZE + 2, 4)
	root.add_child(tag)

	root.mouse_entered.connect(_on_marker_hover.bind(id))
	root.mouse_exited.connect(_on_marker_unhover.bind(id))
	root.gui_input.connect(_on_marker_input.bind(id))
	_markers[id] = {"root": root, "reticle": reticle, "tag": tag, "dot": dot}


func _on_marker_input(event: InputEvent, id: String) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_select(id)
		accept_event()


func _on_marker_hover(id: String) -> void:
	if _busy or _modal != null:
		return
	_hover_id = id
	AudioManager.play_interface_zoom()
	_set_marker_focus(id, true)
	_show_readout(id)


func _on_marker_unhover(id: String) -> void:
	if _hover_id == id:
		_hover_id = ""
	if id != _selected_id:
		_set_marker_focus(id, false)
	if _modal == null and not _busy:
		if _selected_id.is_empty():
			_show_default_readout()
		else:
			_show_readout(_selected_id)


## Hover / selection feedback: the reticle grows, brightens and starts turning.
func _set_marker_focus(id: String, focused: bool) -> void:
	if not _markers.has(id):
		return
	var marker: Dictionary = _markers[id]
	var reticle: TextureRect = marker["reticle"]
	var tag: Label = marker["tag"]
	var tween := create_tween()
	tween.tween_property(reticle, "scale", Vector2.ONE * (2.3 if focused else 1.0), 0.16)
	if focused:
		reticle.modulate = Color(1.25, 1.35, 1.35, 1.0)
		tag.add_theme_color_override("font_color", ACCENT)
	else:
		reticle.modulate = Color(1, 1, 1, 0.9)
		tag.add_theme_color_override("font_color", TEXT)
		reticle.rotation = 0.0


func _process(delta: float) -> void:
	# NOVA types her line out.
	if _nova_label != null and _nova_label.visible_characters >= 0:
		_nova_progress += delta * NOVA_CHARS_PER_SECOND
		var total: int = _nova_label.get_total_character_count()
		if int(_nova_progress) >= total:
			_nova_label.visible_characters = -1
		else:
			_nova_label.visible_characters = int(_nova_progress)

	for id: String in [_hover_id, _selected_id]:
		if id.is_empty() or not _markers.has(id):
			continue
		var reticle: TextureRect = _markers[id]["reticle"]
		reticle.rotation += delta * 0.8

	var pulse: float = 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.006)
	for id: String in _markers:
		var dot: Panel = _markers[id]["dot"]
		dot.modulate = Color(1, 1, 1, pulse)

	# Live cursor coordinates over the map.
	if _cursor_label != null:
		var mouse: Vector2 = get_global_mouse_position()
		if MAP_RECT.has_point(mouse):
			var ll: Vector2 = map_to_lonlat(mouse - MAP_RECT.position)
			_cursor_label.text = "CURSOR  %s  %s  (approx.)" % [_fmt_lat(ll.x), _fmt_lon(ll.y)]
		else:
			_cursor_label.text = ""


# ==================== read-outs ====================

func nova_say(text: String) -> void:
	if _nova_label == null:
		return
	_nova_label.text = text
	_nova_label.visible_characters = 0
	_nova_progress = 0.0


func _show_default_readout() -> void:
	_readout_title.text = "NO TARGET"
	_readout_body.text = "Three candidate sites are in range.\nHover a marker to scan a site.\nClick it to open the landing data.\n\nEvery site changes the starting stores and the colony rules for the whole mission.\n\n[G] cycles the three supplied map views."


func _show_readout(id: String) -> void:
	var site: Dictionary = _site(id)
	if site.is_empty():
		return
	var nasa: Dictionary = site.get("nasa_data", {}) as Dictionary
	_readout_title.text = str(site.get("name", id)).to_upper()
	var lines := PackedStringArray()
	lines.append("%s  %s  ·  Ø %s km" % [_fmt_lat(float(nasa.get("latitude", 0.0))),
		_fmt_lon(float(nasa.get("longitude", 0.0))), _fmt_km(float(nasa.get("diameter_km", 0.0)))])
	lines.append("USGS feature #%d · %s" % [int(nasa.get("usgs_feature_id", 0)),
		str(nasa.get("feature_type", ""))])
	_readout_title.add_theme_color_override("font_color", ACCENT)
	var rules: Dictionary = site.get("gameplay", {}) as Dictionary
	var start: Dictionary = rules.get("starting_resources", {}) as Dictionary
	lines.append("")
	lines.append("GAME RULES (design values, not NASA data)")
	lines.append("Solar ×%.2f · Ice deposits ×%.2f · Build ore ×%.2f" % [
		float(rules.get("solar_output", 1.0)), float(rules.get("water_ice_yield", 1.0)),
		float(rules.get("build_ore_cost", 1.0))])
	lines.append("Start: %d energy · %d O2 · %d water · %d food · %d ore · %d shield" % [
		int(start.get("energy", 0)), int(start.get("oxygen", 0)), int(start.get("water", 0)),
		int(start.get("food", 0)), int(start.get("ore", 0)), int(start.get("shield", 0))])
	for good: Variant in rules.get("advantages", []):
		lines.append("+ " + str(good))
	for bad: Variant in rules.get("challenges", []):
		lines.append("– " + str(bad))
	_readout_body.text = "\n".join(lines)


# ==================== select / panel / confirm ====================

func _select(id: String) -> void:
	if _busy or _modal != null:
		return
	var site: Dictionary = _site(id)
	if site.is_empty():
		return
	AudioManager.play_ui_confirm()
	var previous: String = _selected_id
	_selected_id = id
	if not previous.is_empty() and previous != id:
		_set_marker_focus(previous, false)
	_set_marker_focus(id, true)
	_show_readout(id)
	var nasa: Dictionary = site.get("nasa_data", {}) as Dictionary
	nova_say("Target acquired: %s, %s %s. Review the telemetry, then confirm the landing site." % [
		str(site.get("name", id)), _fmt_lat(float(nasa.get("latitude", 0.0))),
		_fmt_lon(float(nasa.get("longitude", 0.0)))])
	_open_panel(site)


func _open_panel(site: Dictionary) -> void:
	var panel_tex := load(str(site.get("panel_texture", ""))) as Texture2D
	if panel_tex == null:
		push_warning("LandingSelect: no information panel for %s" % str(site.get("id", "")))
		return
	_modal = Control.new()
	_modal.name = "SiteModal"
	_modal.size = SCREEN
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.modulate = Color(1, 1, 1, 0)
	add_child(_modal)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.size = SCREEN
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(dim)

	# Orbital approach: the site's supplied regional image fills the map window.
	var orbital_tex := load(str(site.get("orbital_texture", ""))) as Texture2D
	if orbital_tex != null:
		var clip := Control.new()
		clip.position = MAP_RECT.position
		clip.size = MAP_RECT.size
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_modal.add_child(clip)
		var orbital := TextureRect.new()
		orbital.name = "OrbitalApproach"
		orbital.texture = orbital_tex
		orbital.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		orbital.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		orbital.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		orbital.size = MAP_RECT.size
		orbital.modulate = Color(0.55, 0.55, 0.6, 1.0)
		orbital.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(orbital)
		_label(Rect2(MAP_RECT.position.x + 10, MAP_RECT.position.y + 8, 600, 22),
			"ORBITAL APPROACH // %s (supplied regional image)" % str(site.get("name", "")).to_upper(),
			14, TEAL, HORIZONTAL_ALIGNMENT_LEFT, false, _modal)

	var holder: Control = UiRegions.add_artwork_panel(_modal, panel_tex, PANEL_SCALE, "SitePanel")
	holder.position = ((SCREEN - holder.size * PANEL_SCALE) * 0.5).floor()
	var back := UiRegions.add_region_button(holder, panel_tex, PANEL_BACK, "BackToOrbit")
	back.pressed.connect(_close_panel.bind(true))
	var close := UiRegions.add_region_button(holder, panel_tex, PANEL_CLOSE, "Close")
	close.pressed.connect(_close_panel.bind(true))
	var confirm := UiRegions.add_region_button(holder, panel_tex, PANEL_CONFIRM, "ConfirmLanding")
	confirm.pressed.connect(_confirm)

	var nasa: Dictionary = site.get("nasa_data", {}) as Dictionary
	var note_y: float = holder.position.y + holder.size.y * PANEL_SCALE + 4.0
	var note: String = "Telemetry: USGS Gazetteer feature #%d. Rating bars on the panel are game ratings." % int(nasa.get("usgs_feature_id", 0))
	if nasa.has("extra_fact"):
		note += "\n" + str(nasa.get("extra_fact", ""))
	_label(Rect2(holder.position.x, note_y, holder.size.x * PANEL_SCALE, 40), note,
		13, DIM_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, _modal)

	var tween := create_tween()
	tween.tween_property(_modal, "modulate", Color.WHITE, 0.18)


func _close_panel(deselect: bool) -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	if deselect and not _selected_id.is_empty():
		var id: String = _selected_id
		_selected_id = ""
		_set_marker_focus(id, false)
		_show_default_readout()
		nova_say("Back in orbit. Take your time, Commander.")


func _confirm() -> void:
	if _busy or _selected_id.is_empty():
		return
	var id: String = _selected_id
	if not GameState.select_landing_site(id):
		AudioManager.play_ui_error()
		nova_say("That site cannot be confirmed.")
		return
	_busy = true
	AudioManager.play_mission_confirm()
	_close_panel(false)
	var site: Dictionary = _site(id)
	nova_say("Descent locked on %s. Touchdown confirmed — the colony begins on Sol %d." % [
		str(site.get("name", id)), GameState.get_start_sol()])
	await _play_descent(id)
	await get_tree().create_timer(0.9).timeout
	site_confirmed.emit(id)


## The supplied lander sprite drops from orbit onto the chosen marker.
func _play_descent(id: String) -> void:
	var marker: Control = _markers[id]["root"]
	var target: Vector2 = marker.position + marker.size * 0.5
	var lander := TextureRect.new()
	lander.name = "Lander"
	lander.texture = load(LANDER_TEX) as Texture2D
	lander.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lander.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lander.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lander.size = Vector2(110, 110)
	lander.pivot_offset = lander.size * 0.5
	lander.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lander.position = target - lander.size * 0.5 + Vector2(0, -320)
	lander.scale = Vector2.ONE * 1.6
	lander.modulate = Color(1, 1, 1, 0)
	_map_box.add_child(lander)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(lander, "position", target - lander.size * 0.5 + Vector2(0, -22), 1.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lander, "scale", Vector2.ONE * 0.55, 1.7)
	tween.tween_property(lander, "modulate", Color.WHITE, 0.4)
	await tween.finished


## Cycles the three supplied global-map variants; the code grid only shows over the clean one.
func _cycle_view() -> void:
	if _view_modes.is_empty():
		_grid.visible = not _grid.visible
		return
	_view_index = (_view_index + 1) % _view_modes.size()
	AudioManager.play_interface_zoom()
	_apply_view()


func _apply_view() -> void:
	if _view_modes.is_empty() or _map_view == null:
		return
	var mode: Dictionary = _view_modes[_view_index]
	var tex := load(str(mode.get("texture", ""))) as Texture2D
	if tex != null:
		_map_view.texture = tex
	_grid.visible = bool(mode.get("code_grid", false))
	if _view_button != null:
		_view_button.text = "VIEW: %s [G]" % str(mode.get("caption", "MAP"))


func _on_back() -> void:
	if _busy:
		return
	back_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_G and _modal == null:
		_cycle_view()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel"):
		if _modal != null:
			AudioManager.play_ui_back()
			_close_panel(true)
		else:
			AudioManager.play_ui_back()
			back_requested.emit()
		get_viewport().set_input_as_handled()


# ==================== helpers ====================

func _site(id: String) -> Dictionary:
	for site: Variant in _sites:
		if site is Dictionary and str(site.get("id", "")) == id:
			return site
	return {}


static func _fmt_lat(lat: float) -> String:
	return "%.2f°%s" % [absf(lat), "N" if lat >= 0.0 else "S"]


static func _fmt_lon(lon: float) -> String:
	return "%.2f°%s" % [absf(lon), "E" if lon >= 0.0 else "W"]


static func _fmt_km(km: float) -> String:
	var whole: int = int(km)
	var frac: int = roundi((km - float(whole)) * 100.0)
	var thousands: int = int(whole / 1000.0)
	if thousands > 0:
		return "%d,%03d.%02d" % [thousands, whole - thousands * 1000, frac]
	return "%d.%02d" % [whole, frac]


func _label(rect: Rect2, text: String, font_size: int, color: Color,
		halign: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false,
		parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = halign
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(label)
	return label


func _panel_frame(rect: Rect2) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.96)
	style.border_color = FRAME
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


func _flat_button(caption: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.1, 0.16, 0.95)
	normal.border_color = Color(0.3, 0.62, 0.75, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.18, 0.26, 1.0)
	hover.border_color = TEAL
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)
	return button


# ==================== grid layer ====================

## Latitude / longitude lines and labels drawn by code on top of the untouched map.
class MapGrid extends Control:
	var lon_west: float = -90.0
	var lon_east: float = 180.0
	var lat_north: float = 90.0
	var lat_south: float = -90.0

	func _x(lon: float) -> float:
		return (lon - lon_west) / (lon_east - lon_west) * size.x

	func _y(lat: float) -> float:
		return (lat_north - lat) / (lat_north - lat_south) * size.y

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var line := Color(0.8, 0.95, 1.0, 0.3)
		var axis := Color(1.0, 0.82, 0.5, 0.55)
		var ink := Color(0.88, 0.96, 1.0, 0.95)
		var shadow := Color(0.0, 0.0, 0.0, 0.85)
		var lon: int = int(ceil(lon_west / 30.0)) * 30
		while float(lon) <= lon_east:
			var x: float = _x(float(lon))
			if float(lon) > lon_west and float(lon) < lon_east:
				draw_line(Vector2(x, 0), Vector2(x, size.y), axis if lon == 0 else line, 1.0)
			var text: String = "0°" if lon == 0 else ("%d°%s" % [absi(lon), "E" if lon > 0 else "W"])
			if lon == 180:
				text = "180°"
			var px: float = x + 4.0
			if float(lon) >= lon_east:
				px = x - 38.0
			draw_string(font, Vector2(px + 1, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, shadow)
			draw_string(font, Vector2(px, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
			lon += 30
		var lat: int = 60
		while lat >= -60:
			var y: float = _y(float(lat))
			draw_line(Vector2(0, y), Vector2(size.x, y), axis if lat == 0 else line, 1.0)
			var label: String = "EQ" if lat == 0 else ("%d°%s" % [absi(lat), "N" if lat > 0 else "S"])
			draw_string(font, Vector2(5, y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, shadow)
			draw_string(font, Vector2(4, y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
			lat -= 30
