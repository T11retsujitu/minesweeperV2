extends RefCounted

const FxConfig = preload("res://scripts/presentation/fx_config.gd")

var board_view = null
var fx_layer = null
var player_bar = null
var enemy_bar = null
var status_label = null
var controller = null
var last_enemy_position = null


func setup(refs: Dictionary):
	board_view = refs.get("board_view")
	fx_layer = refs.get("fx_layer")
	player_bar = refs.get("player_bar")
	enemy_bar = refs.get("enemy_bar")
	status_label = refs.get("status_label")
	controller = refs.get("controller")


func play_events(events, snapshot):
	var waited = false
	var accidental_mine_cell = null
	var consumed_enemy_attack_damage_indexes = {}
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
			await _play_player_damage_feedback(event, accidental_mine_cell)
			waited = true
		elif event_type == "enemy_attacked":
			status_label.text = "Enemy attacked"
			_flash_label_nonblocking(status_label, FxConfig.COLOR_ENEMY_ATTACK_STATUS)
			var damage_index = _enemy_attack_damage_index(events, index + 1)
			if damage_index >= 0 and last_enemy_position != null:
				consumed_enemy_attack_damage_indexes[damage_index] = true
				await _play_enemy_attack_chain(events[damage_index])
			else:
				await board_view.get_tree().process_frame
			waited = true
	if not waited:
		await board_view.get_tree().process_frame


func _play_player_damage_feedback(event, accidental_mine_cell):
	var player_amount = int(event.get("amount", 0))
	var source = str(event.get("source", ""))
	var player_pos = player_bar.get_global_rect().get_center()
	var text = "-%d" % player_amount
	var color = FxConfig.COLOR_DAMAGE_ENEMY_ATK
	if source == "accidental_mine":
		if accidental_mine_cell != null:
			player_pos = board_view.debug_cell_canvas_position(accidental_mine_cell)
		text = "-%d MINE!" % player_amount
		color = FxConfig.COLOR_DAMAGE_MINE
	elif source == "enemy_attack":
		text = "-%d ENEMY ATK" % player_amount
	fx_layer.spawn_damage_float(player_pos, text, color)
	player_bar.flash()
	await player_bar.animate_to(int(event["after"]))


func _play_enemy_attack_chain(damage_event):
	var enemy_pos = board_view.debug_cell_canvas_position(last_enemy_position)
	var player_pos = player_bar.get_global_rect().get_center()
	await board_view.play_enemy_attack_glow(last_enemy_position)
	await fx_layer.fire_projectile(enemy_pos, player_pos)
	var amount = int(damage_event.get("amount", 0))
	fx_layer.spawn_damage_float(player_pos, "-%d ENEMY ATK" % amount, FxConfig.COLOR_DAMAGE_ENEMY_ATK)
	player_bar.flash()
	fx_layer.shake(0.5)
	await player_bar.animate_to(int(damage_event["after"]))


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


func _flash_label_nonblocking(label, color):
	label.modulate = color
	var tween = board_view.create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, FxConfig.LABEL_FLASH_SEC)
