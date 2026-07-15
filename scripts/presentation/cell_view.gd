extends Control

signal tapped(coord)
signal long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")

var coord = Vector2i.ZERO
var input_enabled = true
var flagged_display = false
var press_active = false
var long_press_sent = false
var press_elapsed = 0.0

var background_panel = null
var preview_rect = null
var flash_rect = null
var number_label = null
var flag_label = null
var detonation_label = null
var mine_marker_label = null
var preview_damage_label = null
var enemy_badge = null
var enemy_label = null


func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	_build_view()


func set_coord(value):
	coord = value


func set_input_enabled(value):
	input_enabled = value


func set_display(cell_data, options):
	var revealed = cell_data["reveal_state"] == "revealed"
	var flagged = cell_data["flag_state"] == "flagged"
	var detonated = cell_data["detonation_state"] == "detonated"
	flagged_display = flagged

	_apply_background(revealed, flagged, detonated)
	number_label.text = ""
	if revealed and int(cell_data["adjacent_mine_count"]) > 0 and not detonated:
		number_label.text = str(cell_data["adjacent_mine_count"])
		number_label.add_theme_color_override("font_color", _number_color(int(cell_data["adjacent_mine_count"])))

	flag_label.visible = flagged and not detonated
	detonation_label.visible = detonated
	mine_marker_label.visible = bool(options.get("debug_mine", false))
	enemy_badge.visible = bool(options.get("enemy_visible", false))
	enemy_label.visible = enemy_badge.visible

	var previewed = bool(options.get("previewed", false))
	preview_rect.visible = previewed
	preview_damage_label.visible = previewed
	if previewed:
		preview_rect.color = Color(1.0, 0.78, 0.22, 0.42)
		if bool(options.get("preview_center", false)):
			preview_rect.color = Color(1.0, 0.36, 0.12, 0.62)
		preview_damage_label.text = str(options.get("preview_damage", ""))
	else:
		preview_damage_label.text = ""
	queue_redraw()


func flash(color, duration):
	flash_rect.visible = true
	flash_rect.color = color
	flash_rect.modulate = Color(1, 1, 1, 0.85)
	var tween = create_tween()
	tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
	tween.finished.connect(_on_flash_finished)


func _on_flash_finished():
	flash_rect.visible = false


func _gui_input(event):
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)


func _process(delta):
	if not press_active:
		return
	press_elapsed += delta
	if press_elapsed >= Balance.LONG_PRESS_SEC:
		long_press_sent = true
		press_active = false
		set_process(false)
		long_pressed.emit(coord)


func _draw():
	if flagged_display:
		var points = PackedVector2Array([
			Vector2(18, 18),
			Vector2(18, 54),
			Vector2(58, 31),
		])
		draw_polygon(points, PackedColorArray([Color(1.0, 0.82, 0.12)]))
		draw_line(Vector2(18, 18), Vector2(18, 66), Color(0.94, 0.96, 1.0), 3.0)


func _handle_mouse_button(event):
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		long_pressed.emit(coord)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_press()
		else:
			_finish_press()
		accept_event()


func _handle_screen_touch(event):
	if event.pressed:
		_start_press()
	else:
		_finish_press()
	accept_event()


func _start_press():
	press_active = true
	long_press_sent = false
	press_elapsed = 0.0
	set_process(true)


func _finish_press():
	var should_tap = press_active and not long_press_sent
	press_active = false
	set_process(false)
	if should_tap:
		tapped.emit(coord)


func _build_view():
	background_panel = Panel.new()
	background_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background_panel)

	preview_rect = ColorRect.new()
	preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_rect.visible = false
	add_child(preview_rect)

	number_label = _make_label(34, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	number_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(number_label)

	flag_label = _make_label(34, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	flag_label.text = "F"
	flag_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.38))
	flag_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	flag_label.visible = false
	add_child(flag_label)

	detonation_label = _make_label(36, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	detonation_label.text = "X"
	detonation_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.22))
	detonation_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	detonation_label.visible = false
	add_child(detonation_label)

	mine_marker_label = _make_label(18, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	mine_marker_label.text = "*"
	mine_marker_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.22))
	mine_marker_label.offset_left = 6
	mine_marker_label.offset_top = 4
	mine_marker_label.visible = false
	add_child(mine_marker_label)

	preview_damage_label = _make_label(16, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	preview_damage_label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	preview_damage_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_damage_label.offset_right = -5
	preview_damage_label.offset_bottom = -3
	preview_damage_label.visible = false
	add_child(preview_damage_label)

	enemy_badge = ColorRect.new()
	enemy_badge.color = Color(0.83, 0.18, 0.24)
	enemy_badge.anchor_left = 1.0
	enemy_badge.anchor_right = 1.0
	enemy_badge.offset_left = -28
	enemy_badge.offset_top = 6
	enemy_badge.offset_right = -6
	enemy_badge.offset_bottom = 28
	enemy_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_badge.visible = false
	add_child(enemy_badge)

	enemy_label = _make_label(13, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	enemy_label.text = "E"
	enemy_label.add_theme_color_override("font_color", Color.WHITE)
	enemy_label.anchor_left = 1.0
	enemy_label.anchor_right = 1.0
	enemy_label.offset_left = -28
	enemy_label.offset_top = 6
	enemy_label.offset_right = -6
	enemy_label.offset_bottom = 28
	enemy_label.visible = false
	add_child(enemy_label)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.visible = false
	add_child(flash_rect)


func _make_label(font_size, horizontal_alignment, vertical_alignment):
	var label = Label.new()
	label.horizontal_alignment = horizontal_alignment
	label.vertical_alignment = vertical_alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _apply_background(revealed, flagged, detonated):
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	if detonated and not revealed:
		style.bg_color = Color(0.12, 0.13, 0.15)
		style.border_color = Color(0.03, 0.03, 0.04)
	elif revealed:
		style.bg_color = Color(0.73, 0.76, 0.76)
		style.border_color = Color(0.48, 0.52, 0.53)
	elif flagged:
		style.bg_color = Color(0.48, 0.16, 0.16)
		style.border_color = Color(0.98, 0.74, 0.18)
	else:
		style.bg_color = Color(0.23, 0.34, 0.40)
		style.border_color = Color(0.45, 0.57, 0.62)
		style.shadow_color = Color(0.04, 0.06, 0.07, 0.35)
		style.shadow_size = 3
	background_panel.add_theme_stylebox_override("panel", style)


func _number_color(value):
	if value == 1:
		return Color(0.05, 0.20, 0.78)
	if value == 2:
		return Color(0.00, 0.45, 0.18)
	if value == 3:
		return Color(0.75, 0.06, 0.05)
	if value == 4:
		return Color(0.30, 0.10, 0.64)
	if value == 5:
		return Color(0.58, 0.22, 0.00)
	return Color(0.08, 0.08, 0.08)
