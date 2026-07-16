extends Control

signal tapped(coord)
signal long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")
const FxConfig = preload("res://scripts/presentation/fx_config.gd")

var coord = Vector2i.ZERO
var input_enabled = true
var flagged_display = false
var press_active = false
var long_press_sent = false
var press_elapsed = 0.0

var background_panel = null
var highlight_rect = null
var overlay_draw = null
var reveal_pop_rect = null
var flag_pop_rect = null
var preview_rect = null
var player_marker_outline = null
var player_marker_fill = null
var flash_rect = null
var number_label = null
var detonation_label = null
var mine_marker_label = null
var preview_damage_label = null
var enemy_badge = null
var enemy_label = null
var enemy_pulse_tween = null
var reveal_pop_tween = null
var flag_pop_tween = null
var highlight_border_visible = false
var highlight_border_color = FxConfig.COLOR_HIGHLIGHT_MOVABLE_BORDER


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
	var adjacent_count = int(cell_data["adjacent_mine_count"])
	flagged_display = flagged and not detonated

	_apply_background(revealed, flagged, detonated, adjacent_count)
	number_label.text = ""
	if revealed and adjacent_count > 0 and not detonated:
		number_label.text = str(adjacent_count)
		number_label.add_theme_color_override("font_color", _number_color(adjacent_count))

	detonation_label.visible = detonated
	mine_marker_label.visible = bool(options.get("debug_mine", false))
	var enemy_visible = bool(options.get("enemy_visible", false))
	enemy_badge.visible = enemy_visible
	enemy_label.visible = enemy_visible
	_update_enemy_badge(enemy_visible, int(options.get("enemy_countdown", 0)))

	var movable = bool(options.get("movable", false))
	var revealable = bool(options.get("revealable", false))
	highlight_rect.visible = movable or revealable
	highlight_border_visible = movable or revealable
	if movable:
		highlight_rect.color = FxConfig.COLOR_HIGHLIGHT_MOVABLE
		highlight_border_color = FxConfig.COLOR_HIGHLIGHT_MOVABLE_BORDER
	elif revealable:
		highlight_rect.color = FxConfig.COLOR_HIGHLIGHT_REVEALABLE
		highlight_border_color = FxConfig.COLOR_HIGHLIGHT_REVEALABLE_BORDER

	var player_here = bool(options.get("player_here", false))
	player_marker_outline.visible = player_here
	player_marker_fill.visible = player_here

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
	if overlay_draw != null:
		overlay_draw.queue_redraw()


func flash(color, duration):
	flash_rect.visible = true
	flash_rect.color = color
	flash_rect.modulate = Color(1, 1, 1, 0.85)
	var tween = create_tween()
	tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
	tween.finished.connect(_on_flash_finished)


func flash_attack_glow(duration):
	flash_rect.visible = true
	flash_rect.color = FxConfig.COLOR_ENEMY_ATTACK_GLOW_START
	flash_rect.modulate = Color.WHITE
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_rect, "color", FxConfig.COLOR_ENEMY_ATTACK_GLOW_END, duration)
	tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
	tween.finished.connect(_on_flash_finished)


func play_reveal_pop():
	if reveal_pop_tween != null:
		reveal_pop_tween.kill()
		reveal_pop_tween = null
	reveal_pop_rect.visible = true
	reveal_pop_rect.color = FxConfig.COLOR_REVEAL_POP
	reveal_pop_rect.scale = Vector2.ONE * FxConfig.REVEAL_POP_START_SCALE
	reveal_pop_rect.modulate = Color.WHITE
	reveal_pop_tween = create_tween()
	reveal_pop_tween.set_parallel(true)
	reveal_pop_tween.tween_property(reveal_pop_rect, "scale", Vector2.ONE, FxConfig.REVEAL_POP_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal_pop_tween.tween_property(reveal_pop_rect, "modulate:a", 0.0, FxConfig.REVEAL_POP_SEC)
	reveal_pop_tween.finished.connect(_on_reveal_pop_finished)


func play_flag_pop(flagged):
	if flag_pop_tween != null:
		flag_pop_tween.kill()
		flag_pop_tween = null
	overlay_draw.scale = Vector2.ONE
	overlay_draw.modulate = Color.WHITE
	flag_pop_rect.visible = true
	flag_pop_rect.color = _flag_pop_color(flagged)
	flag_pop_rect.modulate = Color.WHITE
	flag_pop_rect.scale = Vector2.ONE
	if flagged:
		flag_pop_rect.scale = Vector2.ONE * FxConfig.FLAG_POP_START_SCALE
		overlay_draw.scale = Vector2.ONE * FxConfig.FLAG_POP_START_SCALE
	flag_pop_tween = create_tween()
	flag_pop_tween.set_parallel(true)
	flag_pop_tween.tween_property(flag_pop_rect, "scale", Vector2.ONE, FxConfig.FLAG_POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flag_pop_tween.tween_property(flag_pop_rect, "modulate:a", 0.0, FxConfig.FLAG_POP_SEC)
	flag_pop_tween.tween_property(overlay_draw, "scale", Vector2.ONE, FxConfig.FLAG_POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flag_pop_tween.finished.connect(_on_flag_pop_finished)


func _on_flash_finished():
	flash_rect.visible = false


func _on_reveal_pop_finished():
	reveal_pop_tween = null
	reveal_pop_rect.visible = false
	reveal_pop_rect.modulate = Color.WHITE
	reveal_pop_rect.scale = Vector2.ONE


func _on_flag_pop_finished():
	flag_pop_tween = null
	flag_pop_rect.visible = false
	flag_pop_rect.modulate = Color.WHITE
	flag_pop_rect.scale = Vector2.ONE
	overlay_draw.scale = Vector2.ONE
	overlay_draw.modulate = Color.WHITE


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_layout_player_marker()
		_layout_feedback_overlays()
		if overlay_draw != null:
			overlay_draw.queue_redraw()


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


func _on_overlay_draw():
	var cell_size = overlay_draw.size
	if cell_size == Vector2.ZERO:
		cell_size = custom_minimum_size
	if flagged_display:
		_draw_bomb(overlay_draw, cell_size)
	if highlight_border_visible:
		_draw_highlight_border(overlay_draw, cell_size)


func _draw_bomb(canvas, cell_size):
	var side = min(cell_size.x, cell_size.y)
	if side <= 0.0:
		return
	var center = cell_size * 0.5
	var radius = side * 0.27
	var fuse_width = side * 0.045
	var fuse_start = center + Vector2(radius * 0.58, -radius * 0.72)
	var fuse_mid = center + Vector2(radius * 0.92, -radius * 1.08)
	var fuse_end = center + Vector2(radius * 1.18, -radius * 1.26)
	var spark_center = fuse_end + Vector2(radius * 0.16, -radius * 0.08)

	canvas.draw_circle(center, radius, FxConfig.COLOR_BOMB_BODY_RIM)
	canvas.draw_circle(center + Vector2(radius * 0.05, radius * 0.06), radius * 0.91, FxConfig.COLOR_BOMB_BODY)
	canvas.draw_arc(center, radius * 0.68, deg_to_rad(206.0), deg_to_rad(286.0), 16, FxConfig.COLOR_BOMB_HIGHLIGHT, side * 0.025, true)
	canvas.draw_line(fuse_start, fuse_mid, FxConfig.COLOR_BOMB_FUSE, fuse_width, true)
	canvas.draw_line(fuse_mid, fuse_end, FxConfig.COLOR_BOMB_FUSE, fuse_width, true)
	canvas.draw_circle(spark_center, radius * 0.17, FxConfig.COLOR_BOMB_SPARK)


func _draw_highlight_border(canvas, cell_size):
	var border_width = FxConfig.HIGHLIGHT_BORDER_WIDTH
	var rect_size = cell_size - Vector2(border_width, border_width)
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return
	var rect = Rect2(Vector2(border_width * 0.5, border_width * 0.5), rect_size)
	canvas.draw_rect(rect, highlight_border_color, false, border_width)


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
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_panel)

	highlight_rect = ColorRect.new()
	highlight_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_rect.visible = false
	add_child(highlight_rect)

	overlay_draw = Control.new()
	overlay_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_draw.draw.connect(_on_overlay_draw)
	add_child(overlay_draw)

	reveal_pop_rect = ColorRect.new()
	reveal_pop_rect.color = FxConfig.COLOR_REVEAL_POP
	reveal_pop_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	reveal_pop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_pop_rect.visible = false
	add_child(reveal_pop_rect)

	flag_pop_rect = ColorRect.new()
	flag_pop_rect.color = FxConfig.COLOR_FLAG_POP
	flag_pop_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flag_pop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_pop_rect.visible = false
	add_child(flag_pop_rect)
	_layout_feedback_overlays()

	preview_rect = ColorRect.new()
	preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_rect.visible = false
	add_child(preview_rect)

	player_marker_outline = ColorRect.new()
	player_marker_outline.color = Color(1.0, 1.0, 1.0, 0.88)
	player_marker_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_marker_outline.visible = false
	player_marker_outline.rotation_degrees = 45.0
	add_child(player_marker_outline)

	player_marker_fill = ColorRect.new()
	player_marker_fill.color = FxConfig.COLOR_PLAYER_MARKER
	player_marker_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_marker_fill.visible = false
	player_marker_fill.rotation_degrees = 45.0
	add_child(player_marker_fill)
	_layout_player_marker()

	number_label = _make_label(34, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	number_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(number_label)

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
	enemy_badge.color = FxConfig.COLOR_ENEMY_BADGE
	enemy_badge.anchor_left = 1.0
	enemy_badge.anchor_right = 1.0
	enemy_badge.offset_left = -FxConfig.ENEMY_BADGE_MARGIN_RIGHT - FxConfig.ENEMY_BADGE_SIZE
	enemy_badge.offset_top = FxConfig.ENEMY_BADGE_MARGIN_TOP
	enemy_badge.offset_right = -FxConfig.ENEMY_BADGE_MARGIN_RIGHT
	enemy_badge.offset_bottom = FxConfig.ENEMY_BADGE_MARGIN_TOP + FxConfig.ENEMY_BADGE_SIZE
	enemy_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_badge.visible = false
	add_child(enemy_badge)

	enemy_label = _make_label(FxConfig.ENEMY_BADGE_FONT_SIZE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	enemy_label.add_theme_color_override("font_color", Color.WHITE)
	enemy_label.add_theme_constant_override("outline_size", 2)
	enemy_label.add_theme_color_override("font_outline_color", Color.BLACK)
	enemy_label.anchor_left = 1.0
	enemy_label.anchor_right = 1.0
	enemy_label.offset_left = -FxConfig.ENEMY_BADGE_MARGIN_RIGHT - FxConfig.ENEMY_BADGE_SIZE
	enemy_label.offset_top = FxConfig.ENEMY_BADGE_MARGIN_TOP
	enemy_label.offset_right = -FxConfig.ENEMY_BADGE_MARGIN_RIGHT
	enemy_label.offset_bottom = FxConfig.ENEMY_BADGE_MARGIN_TOP + FxConfig.ENEMY_BADGE_SIZE
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


func _update_enemy_badge(enemy_visible, countdown):
	_stop_enemy_pulse()
	if not enemy_visible:
		enemy_label.text = ""
		return
	enemy_badge.color = FxConfig.COLOR_ENEMY_BADGE
	enemy_label.text = str(countdown)
	if countdown == 1:
		enemy_badge.color = FxConfig.COLOR_ENEMY_BADGE_DANGER
		enemy_label.text = "1!"
		enemy_pulse_tween = create_tween()
		enemy_pulse_tween.set_loops()
		enemy_pulse_tween.tween_property(enemy_badge, "modulate:a", FxConfig.ENEMY_BADGE_PULSE_ALPHA, FxConfig.ENEMY_BADGE_PULSE_SEC)
		enemy_pulse_tween.tween_property(enemy_badge, "modulate:a", 1.0, FxConfig.ENEMY_BADGE_PULSE_SEC)


func _stop_enemy_pulse():
	if enemy_pulse_tween != null:
		enemy_pulse_tween.kill()
		enemy_pulse_tween = null
	if enemy_badge != null:
		enemy_badge.modulate = Color.WHITE


func _apply_background(revealed, flagged, detonated, adjacent_count):
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
		style.bg_color = _heat_color(adjacent_count)
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


func _heat_color(adjacent_count):
	var max_index = FxConfig.COLOR_HEAT_LEVELS.size() - 1
	var index = int(clamp(adjacent_count, 0, max_index))
	return FxConfig.COLOR_HEAT_LEVELS[index]


func _flag_pop_color(flagged):
	var color = FxConfig.COLOR_FLAG_POP
	if not flagged:
		color.a *= 0.45
	return color


func _layout_feedback_overlays():
	var cell_size = size
	if cell_size == Vector2.ZERO:
		cell_size = custom_minimum_size
	if overlay_draw != null:
		overlay_draw.pivot_offset = cell_size * 0.5
	if reveal_pop_rect != null:
		reveal_pop_rect.pivot_offset = cell_size * 0.5
	if flag_pop_rect != null:
		flag_pop_rect.pivot_offset = cell_size * 0.5


func _layout_player_marker():
	if player_marker_outline == null or player_marker_fill == null:
		return
	var cell_size = size
	if cell_size == Vector2.ZERO:
		cell_size = custom_minimum_size
	var outline_size = Vector2(FxConfig.PLAYER_MARKER_OUTLINE_SIZE, FxConfig.PLAYER_MARKER_OUTLINE_SIZE)
	var fill_size = Vector2(FxConfig.PLAYER_MARKER_SIZE, FxConfig.PLAYER_MARKER_SIZE)
	player_marker_outline.size = outline_size
	player_marker_outline.pivot_offset = outline_size * 0.5
	player_marker_outline.position = (cell_size - outline_size) * 0.5
	player_marker_fill.size = fill_size
	player_marker_fill.pivot_offset = fill_size * 0.5
	player_marker_fill.position = (cell_size - fill_size) * 0.5


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
