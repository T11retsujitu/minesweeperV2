extends Control

const BattleController = preload("res://scripts/application/battle_controller.gd")
const BattleFeedback = preload("res://scripts/presentation/battle_feedback.gd")
const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const FxLayer = preload("res://scripts/presentation/fx_layer.gd")
const HpBar = preload("res://scripts/presentation/hp_bar.gd")
const BoardWorld = preload("res://scripts/presentation/board_world.gd")
const BackgroundTexture = preload("res://assets/textures/bg/bg_dungeon.png")
const PixelFont = preload("res://assets/fonts/PressStart2P-Regular.ttf")
const HudPanelTexture = preload("res://assets/textures/ui/hud_panel.png")
const IconMineTexture = preload("res://assets/textures/ui/icon_mine.png")
const IconFlagTexture = preload("res://assets/textures/ui/icon_flag.png")

var controller = BattleController.new(CombatState.RULESET_AVATAR)
var debug_show_mines = false

var root = null
var background_layer = null
var hud_layer = null
var fx_canvas_layer = null
var overlay_layer = null
var board_slot = null
var board_view = null
var fx_layer = null
var feedback = null
var player_bar = null
var enemy_bar = null
var enemy_countdown_label = null
var enemy_intent_label = null
var mines_label = null
var flags_label = null
var seed_label = null
var turn_label = null
var input_mode_label = null
var status_label = null
var log_box = null
var log_scroll = null
var mine_toggle = null
var finish_button = null
var toast_panel = null
var toast_label = null
var toast_tween = null
var preview_overlay = null
var preview_body_label = null
var defuse_button = null
var help_overlay = null
var terminal_overlay = null
var terminal_panel = null
var terminal_title_label = null
var terminal_stats_label = null
var terminal_tween = null
var debug_drawer_panel = null
var debug_drawer_content = null
var debug_drawer_toggle = null
var debug_drawer_expanded = false


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()
	feedback = BattleFeedback.new()
	feedback.setup({
		"board_view": board_view,
		"fx_layer": fx_layer,
		"player_bar": player_bar,
		"enemy_bar": enemy_bar,
		"status_label": status_label,
		"controller": controller,
		"show_terminal": Callable(self, "_show_terminal"),
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


func debug_finish():
	_on_finish_pressed()


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


func debug_camera_state():
	return board_view.debug_camera_state()


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
	_sync_hp_bars_immediate(controller.get_snapshot())
	_hide_toast()
	_hide_preview()
	_hide_terminal()
	_render()
	_refit_board_to_slot()


func _handle_events(events):
	var terminal_title = _terminal_title_from_events(events)
	var flag_pop_events = []
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "detonation_preview":
			_show_preview(event)
		elif event_type == "detonation_cancelled":
			_hide_preview()
		elif event_type == "state_reset":
			_hide_preview()
			_hide_terminal()
		elif event_type == "flag_toggled":
			flag_pop_events.append(event)
		elif event_type == "combat_won":
			_show_toast("ENEMY DOWN — collect the board!")

	_update_status_from_events(events)
	_render()
	for event in flag_pop_events:
		board_view.play_flag_pop(event["cell"], bool(event.get("flagged", false)))
	if controller.is_busy:
		await _play_event_feedback(events)
		controller.notify_effects_done()
		_render()
	elif terminal_title != "":
		_show_terminal_immediate(terminal_title)


func _render():
	var snapshot = controller.get_snapshot()
	if not controller.is_busy:
		player_bar.animate_to(int(snapshot["player_hp"]))
		enemy_bar.animate_to(int(snapshot["enemy_hp"]))
	if _is_recovery_snapshot(snapshot):
		enemy_countdown_label.text = "Countdown: —(stopped)"
	elif _is_countdown_paused_snapshot(snapshot):
		enemy_countdown_label.text = "Countdown: %d (paused)" % int(snapshot["enemy_countdown"])
	else:
		enemy_countdown_label.text = "Enemy countdown: %d" % int(snapshot["enemy_countdown"])
	enemy_intent_label.text = _enemy_intent_text(snapshot)
	_update_mine_counters(snapshot)
	seed_label.text = "Seed: " + str(snapshot["seed_label"])
	turn_label.text = "Turn: %d" % int(snapshot["turn_count"])
	input_mode_label.text = "Input: " + _input_mode_text()
	if finish_button != null:
		finish_button.visible = _is_recovery_snapshot(snapshot)
		finish_button.disabled = controller.is_busy
	board_view.update_from_snapshot(snapshot, debug_show_mines)
	board_view.set_input_enabled(not _is_overlay_blocking_board())
	_update_log(snapshot["action_log"])


func _input_mode_text():
	if controller.is_busy:
		return "resolving"
	if preview_overlay.visible:
		return "confirm_detonation"
	return "idle"


func _enemy_intent_text(snapshot):
	if _is_recovery_snapshot(snapshot) or int(snapshot["enemy_hp"]) <= 0:
		return "Enemy: defeated"
	return "Enemy intent: Attack %d" % Balance.ENEMY_ATTACK


func _update_mine_counters(snapshot):
	var mine_count = 0
	var flag_count = 0
	for cell_data in snapshot["cells"]:
		if bool(cell_data["contains_mine"]):
			mine_count += 1
		if cell_data["flag_state"] == "flagged":
			flag_count += 1
	mines_label.text = "×%d" % (mine_count - flag_count)
	if _is_recovery_snapshot(snapshot):
		flags_label.text = "%d/%d" % [int(snapshot.get("safe_cells_revealed", 0)), int(snapshot.get("safe_cells_total", 0))]
	else:
		flags_label.text = "×%d" % flag_count


func _is_recovery_snapshot(snapshot):
	return str(snapshot.get("phase", "")) == "recovery"


func _is_countdown_paused_snapshot(snapshot):
	return int(snapshot.get("enemy_hp", 0)) > 0 and not bool(snapshot.get("player_in_territory", true))


func _is_overlay_blocking_board():
	return controller.is_busy or preview_overlay.visible or help_overlay.visible or terminal_overlay.visible


func _show_preview(event):
	var preview = event["preview"]
	board_view.set_preview(event["cell"], preview)
	preview_body_label.text = _format_preview_text(event["cell"], preview)
	if defuse_button != null:
		defuse_button.visible = bool(event.get("can_defuse", false))
	preview_overlay.visible = true
	status_label.text = "Detonation preview"


func _hide_preview():
	preview_overlay.visible = false
	if defuse_button != null:
		defuse_button.visible = false
	board_view.clear_preview()


func _show_terminal(title):
	_kill_terminal_tween()
	_hide_toast()
	_prepare_terminal_content(title)
	if title == "PERFECT CLEAR":
		_spawn_perfect_terminal_burst()
	terminal_overlay.visible = true
	terminal_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_prepare_terminal_panel_pivot()
	var start_scale = FxConfig.TERMINAL_START_SCALE
	if title == "PERFECT CLEAR":
		start_scale = FxConfig.PERFECT_TERMINAL_START_SCALE
	terminal_panel.scale = Vector2.ONE * start_scale
	terminal_tween = create_tween()
	terminal_tween.set_parallel(true)
	terminal_tween.tween_property(terminal_overlay, "modulate:a", 1.0, FxConfig.TERMINAL_FADE_SEC)
	terminal_tween.tween_property(terminal_panel, "scale", Vector2.ONE, FxConfig.TERMINAL_FADE_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var timer = get_tree().create_timer(FxConfig.TERMINAL_FADE_SEC)
	timer.timeout.connect(_on_terminal_animation_done)
	return timer.timeout


func _show_terminal_immediate(title):
	_kill_terminal_tween()
	_hide_toast()
	_prepare_terminal_content(title)
	terminal_overlay.visible = true
	terminal_overlay.modulate = Color.WHITE
	_prepare_terminal_panel_pivot()
	terminal_panel.scale = Vector2.ONE


func _hide_terminal():
	_kill_terminal_tween()
	terminal_overlay.visible = false
	terminal_overlay.modulate = Color.WHITE
	if terminal_panel != null:
		_prepare_terminal_panel_pivot()
		terminal_panel.scale = Vector2.ONE
	if terminal_title_label != null:
		terminal_title_label.text = ""
		terminal_title_label.add_theme_color_override("font_color", FxConfig.COLOR_TERMINAL_DEFAULT)
	if terminal_stats_label != null:
		terminal_stats_label.text = ""


func _kill_terminal_tween():
	if terminal_tween != null:
		terminal_tween.kill()
		terminal_tween = null


func _on_terminal_animation_done():
	terminal_tween = null


func _prepare_terminal_panel_pivot():
	if terminal_panel == null:
		return
	var panel_size = terminal_panel.size
	if panel_size == Vector2.ZERO:
		panel_size = terminal_panel.custom_minimum_size
	terminal_panel.pivot_offset = panel_size * 0.5


func _prepare_terminal_content(title):
	terminal_title_label.text = title
	terminal_title_label.add_theme_color_override("font_color", _terminal_title_color(title))
	if terminal_stats_label != null:
		terminal_stats_label.text = _terminal_stats_text(controller.get_snapshot())


func _terminal_title_color(title):
	if title == "PERFECT CLEAR":
		return FxConfig.COLOR_PERFECT
	if title == "VICTORY":
		return FxConfig.COLOR_TERMINAL_VICTORY
	if title == "DEFEAT":
		return FxConfig.COLOR_TERMINAL_DEFEAT
	return FxConfig.COLOR_TERMINAL_DEFAULT


func _terminal_stats_text(snapshot):
	var safe_total = int(snapshot.get("safe_cells_total", 0))
	var safe_revealed = int(snapshot.get("safe_cells_revealed", 0))
	var board_percent = 0
	if safe_total > 0:
		board_percent = int(round(float(safe_revealed) * 100.0 / float(safe_total)))
	return "Turns: %d\nHP: %d/%d\nBoard: %d%% (%d/%d)\nMisfires: %d" % [
		int(snapshot["turn_count"]),
		int(snapshot["player_hp"]),
		Balance.PLAYER_MAX_HP,
		board_percent,
		safe_revealed,
		safe_total,
		int(snapshot.get("accidental_mine_count", 0)),
	]


func _spawn_perfect_terminal_burst():
	if fx_layer == null:
		return
	var center = fx_layer.get_global_rect().get_center()
	var offsets = [Vector2.ZERO, Vector2(-70.0, 24.0), Vector2(70.0, 24.0)]
	for offset in offsets:
		fx_layer.spawn_explosion_particles(center + offset, true, FxConfig.COLOR_PERFECT)


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
			next_status = _reject_status_text(str(event.get("reason", "unknown")))
		elif event_type == "flag_toggled":
			var flag_text = "off"
			if bool(event.get("flagged", false)):
				flag_text = "on"
			next_status = "Flag %s (%d, %d)" % [flag_text, event["cell"].x, event["cell"].y]
		elif event_type == "cells_revealed":
			var trigger = event["trigger"]
			pending_reveal = "Revealed (%d, %d)" % [trigger.x, trigger.y]
		elif event_type == "player_moved":
			var target = event["to"]
			next_status = "Moved to (%d, %d)" % [target.x, target.y]
		elif event_type == "enemy_bumped":
			next_status = "Bumped enemy"
		elif event_type == "mine_exploded":
			has_mine_result = true
			if bool(event.get("accidental", false)):
				next_status = "Accidental mine (%d, %d)!" % [event["cell"].x, event["cell"].y]
			else:
				next_status = "Detonated (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "dud_detonation":
			has_dud_result = true
			next_status = "Dud detonation (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "mine_defused":
			next_status = "Defused (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "defuse_dud":
			next_status = "Defuse dud (%d, %d)" % [event["cell"].x, event["cell"].y]
		elif event_type == "enemy_attacked":
			next_status = "Enemy attacked"
		elif event_type == "combat_won":
			next_status = "Recovery"
		elif event_type == "perfect_clear":
			next_status = "PERFECT CLEAR"
		elif event_type == "victory":
			next_status = "VICTORY"
		elif event_type == "defeat":
			next_status = "DEFEAT"
	if next_status == "" and pending_reveal != "" and not has_mine_result and not has_dud_result:
		next_status = pending_reveal
	if next_status != "":
		status_label.text = next_status


func _reject_status_text(reason):
	if reason == "invalid_move_target":
		return "Can't move there"
	if reason == "cell_not_adjacent_to_player":
		return "Too far to reveal"
	if reason == "move_not_available":
		return "Move unavailable"
	if reason == "invalid_bump_target":
		return "Can't bump there"
	if reason == "defuse_not_adjacent":
		return "Too far to defuse"
	if reason == "cell_not_defusable":
		return "Can't defuse there"
	return "Input rejected: " + reason


func _play_event_feedback(events):
	await feedback.play_events(events, controller.get_snapshot())


func _terminal_title_from_events(events):
	var title = ""
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "victory":
			if bool(event.get("perfect", false)):
				title = "PERFECT CLEAR"
			else:
				title = "VICTORY"
		elif event_type == "defeat":
			title = "DEFEAT"
	return title


func _sync_hp_bars_immediate(snapshot):
	player_bar.set_value_immediate(int(snapshot["player_hp"]))
	enemy_bar.set_value_immediate(int(snapshot["enemy_hp"]))


func _update_log(lines):
	for child in log_box.get_children():
		child.queue_free()
	var start = max(0, lines.size() - 8)
	for index in range(start, lines.size()):
		var label = Label.new()
		label.text = str(lines[index])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_font(label, 8)
		label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.90))
		log_box.add_child(label)
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _on_detonate_pressed():
	_hide_preview()
	controller.confirm_detonation()


func _on_defuse_pressed():
	_hide_preview()
	controller.confirm_defuse()


func _on_cancel_detonation_pressed():
	controller.cancel_detonation()


func _on_retry_pressed():
	controller.retry()


func _on_finish_pressed():
	controller.finish_recovery()


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
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	background_layer = CanvasLayer.new()
	background_layer.name = "BackgroundLayer"
	background_layer.layer = -1
	add_child(background_layer)

	var background = TextureRect.new()
	background.texture = BackgroundTexture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)

	board_view = BoardWorld.new()
	board_view.name = "BoardWorld"
	board_view.cell_tapped.connect(_on_cell_tapped)
	board_view.cell_long_pressed.connect(_on_cell_long_pressed)
	add_child(board_view)

	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 1
	add_child(hud_layer)

	root = VBoxContainer.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 20
	root.offset_top = 18
	root.offset_right = -20
	root.offset_bottom = -18
	hud_layer.add_child(root)

	_build_hud()
	_build_board_area()
	_build_debug_drawer()

	fx_canvas_layer = CanvasLayer.new()
	fx_canvas_layer.name = "FxLayer"
	fx_canvas_layer.layer = 2
	add_child(fx_canvas_layer)
	fx_layer = FxLayer.new()
	fx_layer.name = "FxRoot"
	fx_canvas_layer.add_child(fx_layer)
	board_view.set_fx_layer(fx_layer)
	fx_layer.set_camera_rig(board_view.get_camera_rig())

	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "OverlayLayer"
	overlay_layer.layer = 3
	add_child(overlay_layer)
	_build_preview_overlay()
	_build_help_overlay()
	_build_terminal_overlay()
	_build_toast()
	board_view.set_board_slot(board_slot)
	_request_board_refit()


func _build_hud():
	var panel = _make_texture_panel()
	panel.custom_minimum_size = Vector2(0, 112)
	root.add_child(panel)

	var margin = _make_margin(12)
	panel.add_child(margin)

	var hud = VBoxContainer.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_constant_override("separation", 6)
	margin.add_child(hud)

	var top_row = HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 12)
	hud.add_child(top_row)

	player_bar = HpBar.new()
	player_bar.setup("PLAYER", Balance.PLAYER_MAX_HP, FxConfig.COLOR_HP_PLAYER)
	enemy_bar = HpBar.new()
	enemy_bar.setup("ENEMY", Balance.ENEMY_MAX_HP, FxConfig.COLOR_HP_ENEMY)
	top_row.add_child(player_bar)
	top_row.add_child(enemy_bar)

	var counters = HBoxContainer.new()
	counters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counters.add_theme_constant_override("separation", 8)
	top_row.add_child(counters)

	mines_label = _make_hud_label()
	flags_label = _make_hud_label()
	counters.add_child(_make_counter(IconMineTexture, mines_label))
	counters.add_child(_make_counter(IconFlagTexture, flags_label))

	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	top_row.add_child(actions)
	_add_small_button(actions, "Retry", _on_retry_pressed)
	_add_small_button(actions, "Help", _on_help_pressed)
	finish_button = _add_small_button(actions, "Finish", _on_finish_pressed)
	finish_button.visible = false

	status_label = _make_hud_label()
	status_label.text = "Ready"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(status_label)

	enemy_countdown_label = _make_hud_label()
	enemy_intent_label = _make_hud_label()
	seed_label = _make_hud_label()
	turn_label = _make_hud_label()
	input_mode_label = _make_hud_label()


func _build_board_area():
	board_slot = Control.new()
	board_slot.name = "BoardSlot"
	board_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_slot.resized.connect(_on_board_slot_resized)
	root.add_child(board_slot)


func _on_board_slot_resized():
	_refit_board_to_slot()


func _request_board_refit():
	_refit_board_after_layout.call_deferred()


func _refit_board_after_layout():
	await get_tree().process_frame
	_refit_board_to_slot()


func _refit_board_to_slot():
	if board_view == null or board_slot == null:
		return
	board_view.refit_to_slot(board_slot)


func _build_debug_drawer():
	debug_drawer_panel = _make_texture_panel()
	debug_drawer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(debug_drawer_panel)

	var margin = _make_margin(8)
	debug_drawer_panel.add_child(margin)

	var drawer = VBoxContainer.new()
	drawer.add_theme_constant_override("separation", 8)
	margin.add_child(drawer)

	debug_drawer_toggle = Button.new()
	debug_drawer_toggle.text = "Debug"
	debug_drawer_toggle.toggle_mode = true
	debug_drawer_toggle.button_pressed = false
	debug_drawer_toggle.custom_minimum_size = Vector2(120, 32)
	_apply_font(debug_drawer_toggle, 16)
	debug_drawer_toggle.pressed.connect(_on_debug_drawer_pressed)
	drawer.add_child(debug_drawer_toggle)

	debug_drawer_content = VBoxContainer.new()
	debug_drawer_content.add_theme_constant_override("separation", 8)
	drawer.add_child(debug_drawer_content)

	var controls = HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 8)
	controls.add_theme_constant_override("v_separation", 8)
	debug_drawer_content.add_child(controls)

	_add_button(controls, "Fixed", _on_fixed_pressed)
	_add_button(controls, "Random", _on_random_pressed)
	_add_button(controls, "Same Seed", _on_same_seed_pressed)
	_add_button(controls, "New Seed", _on_new_seed_pressed)
	_add_button(controls, "Retry", _on_retry_pressed)
	_add_button(controls, "Help", _on_help_pressed)

	mine_toggle = CheckBox.new()
	mine_toggle.text = "Show Mines"
	_apply_font(mine_toggle, 16)
	mine_toggle.toggled.connect(_on_mine_toggle_toggled)
	controls.add_child(mine_toggle)

	var info = GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 16)
	info.add_theme_constant_override("v_separation", 5)
	debug_drawer_content.add_child(info)
	for label in [enemy_countdown_label, enemy_intent_label, seed_label, turn_label, input_mode_label]:
		info.add_child(label)

	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 88)
	log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_drawer_content.add_child(log_scroll)

	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 3)
	log_scroll.add_child(log_box)

	_apply_debug_drawer_state()
	if not OS.is_debug_build():
		debug_drawer_panel.visible = false


func _on_debug_drawer_pressed():
	debug_drawer_expanded = debug_drawer_toggle.button_pressed
	_apply_debug_drawer_state()


func _apply_debug_drawer_state():
	if debug_drawer_panel == null:
		return
	debug_drawer_content.visible = debug_drawer_expanded
	debug_drawer_toggle.text = "Debug ▲" if debug_drawer_expanded else "Debug"
	debug_drawer_panel.custom_minimum_size = Vector2(0, 250 if debug_drawer_expanded else 48)


func _build_preview_overlay():
	preview_overlay = _make_overlay()
	overlay_layer.add_child(preview_overlay)

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
	defuse_button = _add_button(buttons, "Defuse", _on_defuse_pressed)
	defuse_button.visible = false
	_add_button(buttons, "Cancel", _on_cancel_detonation_pressed)


func _build_help_overlay():
	help_overlay = _make_overlay()
	overlay_layer.add_child(help_overlay)

	var panel = _make_overlay_panel(Vector2(560, 420))
	help_overlay.add_child(panel)

	var margin = _make_margin(22)
	panel.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	box.add_child(_make_overlay_label("Help", 26))
	var body = _make_overlay_label(
		"Tap adjacent hidden cell = reveal\nTap adjacent revealed cell = move\nTap adjacent enemy = bump\nFlag adjacent mine, then Defuse = remove\nFlag & detonate = remote\nRight click or long press: toggle flag\nGoal: read the numbers, identify mines, then detonate them to reduce enemy HP 6 to zero.\nThe enemy attacks for 2 when its countdown reaches 0.",
		18
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	_add_button(box, "Close", _on_help_close_pressed)


func _build_terminal_overlay():
	terminal_overlay = _make_overlay()
	overlay_layer.add_child(terminal_overlay)

	terminal_panel = _make_overlay_panel(Vector2(430, 340))
	terminal_overlay.add_child(terminal_panel)

	var margin = _make_margin(22)
	terminal_panel.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	terminal_title_label = _make_overlay_label("", 36)
	terminal_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(terminal_title_label)
	terminal_stats_label = _make_overlay_label("", 18)
	terminal_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(terminal_stats_label)
	_add_button(box, "Retry", _on_retry_pressed)


func _build_toast():
	toast_panel = _make_panel(FxConfig.COLOR_TOAST_BACKGROUND)
	toast_panel.custom_minimum_size = Vector2(460, 54)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_top = 0.0
	toast_panel.anchor_right = 0.5
	toast_panel.anchor_bottom = 0.0
	toast_panel.offset_left = -230.0
	toast_panel.offset_top = 88.0
	toast_panel.offset_right = 230.0
	toast_panel.offset_bottom = 142.0
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	overlay_layer.add_child(toast_panel)

	var margin = _make_margin(10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(margin)

	toast_label = Label.new()
	toast_label.text = ""
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", FxConfig.COLOR_TOAST_TEXT)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(toast_label)


func _show_toast(text):
	_hide_toast()
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate = Color.WHITE
	toast_tween = create_tween()
	toast_tween.tween_interval(max(0.0, FxConfig.TOAST_SEC - FxConfig.TOAST_FADE_SEC))
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, FxConfig.TOAST_FADE_SEC)
	toast_tween.finished.connect(_on_toast_finished)


func _hide_toast():
	if toast_tween != null:
		toast_tween.kill()
		toast_tween = null
	if toast_panel != null:
		toast_panel.visible = false
		toast_panel.modulate = Color.WHITE


func _on_toast_finished():
	toast_tween = null
	if toast_panel != null:
		toast_panel.visible = false
		toast_panel.modulate = Color.WHITE


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


func _make_texture_panel():
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxTexture.new()
	style.texture = HudPanelTexture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 24.0)
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
	_apply_font(label, 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.93, 0.94))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_counter(icon_texture, label):
	var box = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(76, 32)
	box.add_theme_constant_override("separation", 3)

	var icon = TextureRect.new()
	icon.texture = icon_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(40, 32)
	box.add_child(label)
	return box


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
	_apply_font(button, 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_small_button(parent, text, callback):
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(74, 32)
	_apply_font(button, 8)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _apply_font(control, font_size):
	control.add_theme_font_override("font", PixelFont)
	control.add_theme_font_size_override("font_size", font_size)
