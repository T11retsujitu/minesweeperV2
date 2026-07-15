extends Control

const BattleController = preload("res://scripts/application/battle_controller.gd")
const BattleFeedback = preload("res://scripts/presentation/battle_feedback.gd")
const FxLayer = preload("res://scripts/presentation/fx_layer.gd")
const BoardViewScene = preload("res://scenes/battle/board_view.tscn")

var controller = BattleController.new()
var debug_show_mines = false

var root = null
var board_view = null
var fx_layer = null
var feedback = null
var player_hp_label = null
var enemy_hp_label = null
var enemy_countdown_label = null
var enemy_intent_label = null
var seed_label = null
var turn_label = null
var input_mode_label = null
var status_label = null
var log_box = null
var log_scroll = null
var mine_toggle = null
var preview_overlay = null
var preview_body_label = null
var help_overlay = null
var terminal_overlay = null
var terminal_title_label = null


func _ready():
	_build_layout()
	feedback = BattleFeedback.new()
	feedback.setup({
		"board_view": board_view,
		"fx_layer": fx_layer,
		"player_hp_label": player_hp_label,
		"enemy_hp_label": enemy_hp_label,
		"status_label": status_label,
		"controller": controller,
	})
	controller.events_emitted.connect(_on_events_emitted)
	controller.state_reset.connect(_on_state_reset)
	_render()


func debug_tap(coord):
	_on_cell_tapped(coord)


func debug_flag(coord):
	_on_cell_long_pressed(coord)


func debug_confirm():
	_on_detonate_pressed()


func debug_cancel():
	_on_cancel_detonation_pressed()


func debug_retry():
	_on_retry_pressed()


func debug_set_mode(mode_name):
	if mode_name == "fixed":
		controller.set_mode("fixed")
	elif mode_name == "random":
		controller.set_mode("random")


func debug_same_seed():
	controller.regen_same_seed()


func debug_new_seed():
	controller.regen_new_seed()


func debug_open_help():
	help_overlay.visible = true
	_render()


func debug_set_show_mines(enabled):
	if not OS.is_debug_build():
		return
	debug_show_mines = enabled
	if mine_toggle != null:
		mine_toggle.set_pressed_no_signal(enabled)
	_render()


func debug_cell_canvas_position(coord):
	return board_view.debug_cell_canvas_position(coord)


func debug_wait_until_idle():
	while controller.is_busy:
		await get_tree().process_frame


func _on_cell_tapped(coord):
	if _is_overlay_blocking_board():
		return
	controller.tap(coord)


func _on_cell_long_pressed(coord):
	if _is_overlay_blocking_board():
		return
	controller.long_press(coord)


func _on_events_emitted(events):
	await _handle_events(events)


func _on_state_reset(_state):
	if fx_layer != null:
		fx_layer.clear_all()
	_hide_preview()
	_hide_terminal()
	_render()


func _handle_events(events):
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "detonation_preview":
			_show_preview(event)
		elif event_type == "detonation_cancelled":
			_hide_preview()
		elif event_type == "state_reset":
			_hide_preview()
			_hide_terminal()
		elif event_type == "victory":
			_show_terminal("VICTORY")
		elif event_type == "defeat":
			_show_terminal("DEFEAT")

	_update_status_from_events(events)
	_render()
	if controller.is_busy:
		await _play_event_feedback(events)
		controller.notify_effects_done()
		_render()


func _render():
	var snapshot = controller.get_snapshot()
	player_hp_label.text = "Player HP: %d" % int(snapshot["player_hp"])
	enemy_hp_label.text = "Enemy HP: %d" % int(snapshot["enemy_hp"])
	enemy_countdown_label.text = "Enemy countdown: %d" % int(snapshot["enemy_countdown"])
	enemy_intent_label.text = "Enemy intent: Attack 2"
	seed_label.text = "Seed: " + str(snapshot["seed_label"])
	turn_label.text = "Turn: %d" % int(snapshot["turn_count"])
	input_mode_label.text = "Input: " + _input_mode_text()
	board_view.update_from_snapshot(snapshot, debug_show_mines)
	board_view.set_input_enabled(not _is_overlay_blocking_board())
	_update_log(snapshot["action_log"])


func _input_mode_text():
	if controller.is_busy:
		return "resolving"
	if preview_overlay.visible:
		return "confirm_detonation"
	return "idle"


func _is_overlay_blocking_board():
	return controller.is_busy or preview_overlay.visible or help_overlay.visible or terminal_overlay.visible


func _show_preview(event):
	var preview = event["preview"]
	board_view.set_preview(event["cell"], preview)
	preview_body_label.text = _format_preview_text(event["cell"], preview)
	preview_overlay.visible = true
	status_label.text = "Detonation preview"


func _hide_preview():
	preview_overlay.visible = false
	board_view.clear_preview()


func _show_terminal(title):
	terminal_title_label.text = title
	terminal_overlay.visible = true


func _hide_terminal():
	terminal_overlay.visible = false


func _format_preview_text(center, preview):
	var damage_map = preview["damage_map"]
	var lines = []
	lines.append("Cell: (%d, %d)" % [center.x, center.y])
	lines.append("Damage map:")
	for y in range(center.y - 1, center.y + 2):
		var row = []
		for x in range(center.x - 1, center.x + 2):
			var coord = Vector2i(x, y)
			if damage_map.has(coord):
				row.append(str(damage_map[coord]))
			else:
				row.append("--")
		lines.append(" ".join(row))
	var enemy_text = "no"
	if preview["enemy_hit"]:
		enemy_text = "yes"
	lines.append("Enemy in range: " + enemy_text)
	lines.append("Expected enemy damage: %d" % int(preview["expected_enemy_damage"]))
	return "\n".join(lines)


func _update_status_from_events(events):
	var next_status = ""
	var pending_reveal = ""
	var has_mine_result = false
	var has_dud_result = false
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "detonation_preview":
			next_status = "Detonation preview"
		elif event_type == "detonation_cancelled":
			next_status = "Ready"
		elif event_type == "state_reset":
			next_status = "Ready"
		elif event_type == "turn_rejected":
			next_status = "Input rejected: " + str(event.get("reason", "unknown"))
		elif event_type == "flag_toggled":
			var flag_text = "off"
			if bool(event.get("flagged", false)):
				flag_text = "on"
			next_status = "Flag %s (%d, %d)" % [flag_text, event["cell"].x, event["cell"].y]
		elif event_type == "cells_revealed":
			var trigger = event["trigger"]
			pending_reveal = "Revealed (%d, %d)" % [trigger.x, trigger.y]
		elif event_type == "mine_exploded":
			has_mine_result = true
			if bool(event.get("accidental", false)):
				next_status = "Accidental mine (%d, %d)!" % [event["cell"].x, event["cell"].y]
			else:
				next_status = "Detonated (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "dud_detonation":
			has_dud_result = true
			next_status = "Dud detonation (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "enemy_attacked":
			next_status = "Enemy attacked"
		elif event_type == "victory":
			next_status = "VICTORY"
		elif event_type == "defeat":
			next_status = "DEFEAT"
	if next_status == "" and pending_reveal != "" and not has_mine_result and not has_dud_result:
		next_status = pending_reveal
	if next_status != "":
		status_label.text = next_status


func _play_event_feedback(events):
	await feedback.play_events(events, controller.get_snapshot())


func _update_log(lines):
	for child in log_box.get_children():
		child.queue_free()
	var start = max(0, lines.size() - 8)
	for index in range(start, lines.size()):
		var label = Label.new()
		label.text = str(lines[index])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.90))
		log_box.add_child(label)
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _on_detonate_pressed():
	_hide_preview()
	controller.confirm_detonation()


func _on_cancel_detonation_pressed():
	controller.cancel_detonation()


func _on_retry_pressed():
	controller.retry()


func _on_fixed_pressed():
	controller.set_mode("fixed")


func _on_random_pressed():
	controller.set_mode("random")


func _on_same_seed_pressed():
	controller.regen_same_seed()


func _on_new_seed_pressed():
	controller.regen_new_seed()


func _on_help_pressed():
	help_overlay.visible = true
	_render()


func _on_help_close_pressed():
	help_overlay.visible = false
	_render()


func _on_mine_toggle_toggled(value):
	debug_show_mines = value
	_render()


func _build_layout():
	var background = ColorRect.new()
	background.color = Color(0.08, 0.10, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	root = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 20
	root.offset_top = 18
	root.offset_right = -20
	root.offset_bottom = -18
	add_child(root)

	_build_hud()
	_build_board_area()
	_build_controls()
	_build_log()
	fx_layer = FxLayer.new()
	add_child(fx_layer)
	board_view.set_fx_layer(fx_layer)
	_build_preview_overlay()
	_build_help_overlay()
	_build_terminal_overlay()


func _build_hud():
	var panel = _make_panel(Color(0.13, 0.17, 0.19))
	panel.custom_minimum_size = Vector2(0, 150)
	root.add_child(panel)

	var margin = _make_margin(14)
	panel.add_child(margin)

	var hud = GridContainer.new()
	hud.columns = 2
	hud.add_theme_constant_override("h_separation", 18)
	hud.add_theme_constant_override("v_separation", 7)
	margin.add_child(hud)

	player_hp_label = _make_hud_label()
	enemy_hp_label = _make_hud_label()
	enemy_countdown_label = _make_hud_label()
	enemy_intent_label = _make_hud_label()
	seed_label = _make_hud_label()
	turn_label = _make_hud_label()
	input_mode_label = _make_hud_label()
	status_label = _make_hud_label()
	status_label.text = "Ready"

	for label in [player_hp_label, enemy_hp_label, enemy_countdown_label, enemy_intent_label, seed_label, turn_label, input_mode_label, status_label]:
		hud.add_child(label)


func _build_board_area():
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)

	board_view = BoardViewScene.instantiate()
	board_view.cell_tapped.connect(_on_cell_tapped)
	board_view.cell_long_pressed.connect(_on_cell_long_pressed)
	center.add_child(board_view)


func _build_controls():
	var panel = _make_panel(Color(0.12, 0.15, 0.17))
	panel.custom_minimum_size = Vector2(0, 112)
	root.add_child(panel)

	var margin = _make_margin(10)
	panel.add_child(margin)

	var controls = HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 8)
	controls.add_theme_constant_override("v_separation", 8)
	margin.add_child(controls)

	_add_button(controls, "Fixed", _on_fixed_pressed)
	_add_button(controls, "Random", _on_random_pressed)
	_add_button(controls, "Same Seed", _on_same_seed_pressed)
	_add_button(controls, "New Seed", _on_new_seed_pressed)
	_add_button(controls, "Retry", _on_retry_pressed)
	_add_button(controls, "Help", _on_help_pressed)

	if OS.is_debug_build():
		mine_toggle = CheckBox.new()
		mine_toggle.text = "Show Mines"
		mine_toggle.add_theme_font_size_override("font_size", 16)
		mine_toggle.toggled.connect(_on_mine_toggle_toggled)
		controls.add_child(mine_toggle)


func _build_log():
	var panel = _make_panel(Color(0.09, 0.12, 0.14))
	panel.custom_minimum_size = Vector2(0, 190)
	root.add_child(panel)

	var margin = _make_margin(10)
	panel.add_child(margin)

	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(log_scroll)

	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 3)
	log_scroll.add_child(log_box)


func _build_preview_overlay():
	preview_overlay = _make_overlay()
	add_child(preview_overlay)

	var panel = _make_overlay_panel(Vector2(430, 360))
	preview_overlay.add_child(panel)

	var margin = _make_margin(22)
	panel.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title = _make_overlay_label("Detonation Preview", 24)
	box.add_child(title)
	preview_body_label = _make_overlay_label("", 18)
	box.add_child(preview_body_label)

	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_add_button(buttons, "Detonate", _on_detonate_pressed)
	_add_button(buttons, "Cancel", _on_cancel_detonation_pressed)


func _build_help_overlay():
	help_overlay = _make_overlay()
	add_child(help_overlay)

	var panel = _make_overlay_panel(Vector2(560, 420))
	help_overlay.add_child(panel)

	var margin = _make_margin(22)
	panel.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	box.add_child(_make_overlay_label("Help", 26))
	var body = _make_overlay_label(
		"Left click: reveal or open detonation preview\nRight click or long press: toggle flag\nGoal: read the numbers, identify mines, then detonate them to reduce enemy HP 6 to zero.\nThe enemy attacks for 2 when its countdown reaches 0.",
		18
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	_add_button(box, "Close", _on_help_close_pressed)


func _build_terminal_overlay():
	terminal_overlay = _make_overlay()
	add_child(terminal_overlay)

	var panel = _make_overlay_panel(Vector2(430, 260))
	terminal_overlay.add_child(panel)

	var margin = _make_margin(22)
	panel.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	terminal_title_label = _make_overlay_label("", 36)
	terminal_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(terminal_title_label)
	_add_button(box, "Retry", _on_retry_pressed)


func _make_panel(color):
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.28, 0.34, 0.36)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_margin(size):
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", size)
	margin.add_theme_constant_override("margin_top", size)
	margin.add_theme_constant_override("margin_right", size)
	margin.add_theme_constant_override("margin_bottom", size)
	return margin


func _make_hud_label():
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.90, 0.93, 0.94))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_overlay():
	var overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.035, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	return overlay


func _make_overlay_panel(minimum_size):
	var panel = _make_panel(Color(0.14, 0.17, 0.19))
	panel.custom_minimum_size = minimum_size
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -minimum_size.x * 0.5
	panel.offset_top = -minimum_size.y * 0.5
	panel.offset_right = minimum_size.x * 0.5
	panel.offset_bottom = minimum_size.y * 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel


func _make_overlay_label(text, font_size):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.96))
	return label


func _add_button(parent, text, callback):
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(96, 42)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
