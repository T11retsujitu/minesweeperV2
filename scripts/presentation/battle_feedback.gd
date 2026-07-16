extends RefCounted

const FxConfig = preload("res://scripts/presentation/fx_config.gd")

var board_view = null
var fx_layer = null
var player_bar = null
var enemy_bar = null
var status_label = null
var controller = null
var last_enemy_position = null
var show_terminal_callback = Callable()


func setup(refs: Dictionary):
	board_view = refs.get("board_view")
	fx_layer = refs.get("fx_layer")
	player_bar = refs.get("player_bar")
	enemy_bar = refs.get("enemy_bar")
	status_label = refs.get("status_label")
	controller = refs.get("controller")
	show_terminal_callback = refs.get("show_terminal", Callable())


func play_events(events, snapshot):
	var waited = false
	var accidental_mine_cell = null
	var skip_reveal_cascade = _has_accidental_mine_explosion(events)
	var consumed_enemy_attack_damage_indexes = {}
	var terminal_title = _terminal_title_from_events(events)
	var pos = snapshot["enemy_position"]
	# Enemy placement is restricted to the inner 5x5, so (0,0) is only the dead-enemy sentinel.
	if pos != Vector2i.ZERO:
		last_enemy_position = pos
	for index in range(events.size()):
		if controller != null and not controller.is_busy:
			return
		var event = events[index]
		if consumed_enemy_attack_damage_indexes.has(index):
			continue
		var event_type = event.get("type", "")
		if event_type == "mine_exploded":
			var accidental = bool(event.get("accidental", false))
			if accidental:
				accidental_mine_cell = event["cell"]
			await board_view.play_explosion(event["cell"], accidental)
			waited = true
		elif event_type == "cells_revealed" and not skip_reveal_cascade:
			await board_view.play_reveal_cascade(event.get("cells", []), event.get("trigger", Vector2i.ZERO))
			waited = true
		elif event_type == "player_moved":
			await _play_player_move_feedback(event["from"], event["to"])
			waited = true
		elif event_type == "dud_detonation":
			await board_view.play_dud(event["cell"])
			waited = true
		elif event_type == "enemy_damaged" and int(event.get("amount", 0)) > 0:
			var enemy_amount = int(event.get("amount", 0))
			if last_enemy_position != null:
				var enemy_pos = board_view.debug_cell_canvas_position(last_enemy_position)
				fx_layer.spawn_damage_float(enemy_pos, "-%d" % enemy_amount, FxConfig.COLOR_DAMAGE_DEALT)
			enemy_bar.flash()
			await enemy_bar.animate_to(int(event["after"]))
			waited = true
		elif event_type == "player_damaged" and int(event.get("amount", 0)) > 0:
			await _play_player_damage_feedback(event, accidental_mine_cell, snapshot)
			waited = true
		elif event_type == "enemy_attacked":
			status_label.text = "Enemy attacked"
			_flash_label_nonblocking(status_label, FxConfig.COLOR_ENEMY_ATTACK_STATUS)
			var damage_index = _enemy_attack_damage_index(events, index + 1)
			if damage_index >= 0 and last_enemy_position != null:
				consumed_enemy_attack_damage_indexes[damage_index] = true
				await _play_enemy_attack_chain(events[damage_index], snapshot)
			else:
				await board_view.get_tree().process_frame
			waited = true
		elif event_type == "enemy_died":
			await _play_enemy_down_feedback()
			waited = true
	if terminal_title != "":
		await board_view.get_tree().create_timer(FxConfig.TERMINAL_DELAY_SEC).timeout
		if controller != null and not controller.is_busy:
			return
		if show_terminal_callback.is_valid():
			await show_terminal_callback.call(terminal_title)
		waited = true
	if not waited:
		await board_view.get_tree().process_frame


func _play_player_move_feedback(from_cell, to_cell):
	if fx_layer == null:
		await board_view.get_tree().create_timer(FxConfig.PLAYER_MOVE_SEC).timeout
		return
	var marker = Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.size = Vector2(FxConfig.PLAYER_MARKER_OUTLINE_SIZE, FxConfig.PLAYER_MARKER_OUTLINE_SIZE)
	var outline = _make_move_marker_rect(
		FxConfig.PLAYER_MARKER_OUTLINE_SIZE,
		Color(1.0, 1.0, 1.0, 0.88)
	)
	var fill = _make_move_marker_rect(FxConfig.PLAYER_MARKER_SIZE, FxConfig.COLOR_PLAYER_MARKER)
	fill.position = (marker.size - fill.size) * 0.5
	marker.add_child(outline)
	marker.add_child(fill)
	var local_from = fx_layer.get_global_transform().affine_inverse() * board_view.debug_cell_canvas_position(from_cell)
	var local_to = fx_layer.get_global_transform().affine_inverse() * board_view.debug_cell_canvas_position(to_cell)
	marker.position = local_from - marker.size * 0.5
	fx_layer.add_child(marker)
	var tween = fx_layer.create_tween()
	tween.tween_property(marker, "position", local_to - marker.size * 0.5, FxConfig.PLAYER_MOVE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(marker.queue_free)
	await board_view.get_tree().create_timer(FxConfig.PLAYER_MOVE_SEC).timeout


func _make_move_marker_rect(marker_size, color):
	var rect = ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(marker_size, marker_size)
	rect.pivot_offset = rect.size * 0.5
	rect.position = (Vector2(FxConfig.PLAYER_MARKER_OUTLINE_SIZE, FxConfig.PLAYER_MARKER_OUTLINE_SIZE) - rect.size) * 0.5
	rect.rotation_degrees = 45.0
	return rect


func _play_player_damage_feedback(event, accidental_mine_cell, snapshot):
	var player_amount = int(event.get("amount", 0))
	var source = str(event.get("source", ""))
	var player_pos = _player_feedback_position(snapshot)
	var text = "-%d" % player_amount
	var color = FxConfig.COLOR_DAMAGE_ENEMY_ATK
	if source == "accidental_mine":
		if accidental_mine_cell != null:
			player_pos = board_view.debug_cell_canvas_position(accidental_mine_cell)
		text = "-%d MINE!" % player_amount
		color = FxConfig.COLOR_DAMAGE_MINE
	elif source == "enemy_attack":
		text = "-%d ENEMY ATK" % player_amount
	elif source == "detonation_splash":
		text = "-%d SPLASH!" % player_amount
		color = FxConfig.COLOR_DAMAGE_MINE
	fx_layer.spawn_damage_float(player_pos, text, color)
	player_bar.flash()
	await player_bar.animate_to(int(event["after"]))


func _play_enemy_attack_chain(damage_event, snapshot):
	var enemy_pos = board_view.debug_cell_canvas_position(last_enemy_position)
	var player_pos = _player_feedback_position(snapshot)
	await board_view.play_enemy_attack_glow(last_enemy_position)
	await fx_layer.fire_projectile(enemy_pos, player_pos)
	var amount = int(damage_event.get("amount", 0))
	fx_layer.spawn_damage_float(player_pos, "-%d ENEMY ATK" % amount, FxConfig.COLOR_DAMAGE_ENEMY_ATK)
	player_bar.flash()
	fx_layer.shake(0.5)
	await player_bar.animate_to(int(damage_event["after"]))


func _play_enemy_down_feedback():
	var elapsed = 0.0
	if fx_layer != null and last_enemy_position != null:
		var enemy_pos = board_view.debug_cell_canvas_position(last_enemy_position)
		fx_layer.spawn_explosion_particles(enemy_pos, true, FxConfig.COLOR_ENEMY_DOWN)
		fx_layer.spawn_damage_float(enemy_pos, "ENEMY DOWN!", FxConfig.COLOR_ENEMY_DOWN)
	if fx_layer != null:
		await fx_layer.hit_stop()
		elapsed += FxConfig.HIT_STOP_SEC
		await fx_layer.shake(0.65)
		elapsed += FxConfig.SHAKE_DURATION
	var remaining = max(0.0, FxConfig.ENEMY_DOWN_BLOCK_SEC - elapsed)
	if remaining > 0.0:
		await board_view.get_tree().create_timer(remaining).timeout


func _player_feedback_position(snapshot):
	if str(snapshot.get("ruleset", "")) == "phase2_avatar" and snapshot.has("player_position"):
		var cell_pos = board_view.debug_cell_canvas_position(snapshot["player_position"])
		if cell_pos != Vector2.ZERO:
			return cell_pos
	return player_bar.get_global_rect().get_center()


func _enemy_attack_damage_index(events, index):
	if index >= events.size():
		return -1
	var event = events[index]
	if event.get("type", "") != "player_damaged":
		return -1
	if str(event.get("source", "")) != "enemy_attack":
		return -1
	if int(event.get("amount", 0)) <= 0:
		return -1
	return index


func _has_accidental_mine_explosion(events):
	for event in events:
		if event.get("type", "") == "mine_exploded" and bool(event.get("accidental", false)):
			return true
	return false


func _terminal_title_from_events(events):
	var title = ""
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "victory":
			title = "VICTORY"
		elif event_type == "defeat":
			title = "DEFEAT"
	return title


func _flash_label_nonblocking(label, color):
	label.modulate = color
	var tween = board_view.create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, FxConfig.LABEL_FLASH_SEC)
