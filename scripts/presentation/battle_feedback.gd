extends RefCounted

const FxConfig = preload("res://scripts/presentation/fx_config.gd")

var board_view = null
var fx_layer = null
var player_hp_label = null
var enemy_hp_label = null
var status_label = null
var controller = null


func setup(refs: Dictionary):
	board_view = refs.get("board_view")
	fx_layer = refs.get("fx_layer")
	player_hp_label = refs.get("player_hp_label")
	enemy_hp_label = refs.get("enemy_hp_label")
	status_label = refs.get("status_label")
	controller = refs.get("controller")


func play_events(events, _snapshot):
	var waited = false
	for event in events:
		var event_type = event.get("type", "")
		if event_type == "mine_exploded" or event_type == "dud_detonation":
			await board_view.flash_explosion(event["cell"])
			waited = true
		elif event_type == "enemy_damaged" and int(event.get("amount", 0)) > 0:
			await _flash_label(enemy_hp_label, FxConfig.COLOR_DAMAGE_ENEMY_ATK)
			waited = true
		elif event_type == "player_damaged":
			await _flash_label(player_hp_label, FxConfig.COLOR_DAMAGE_ENEMY_ATK)
			waited = true
		elif event_type == "enemy_attacked":
			status_label.text = "Enemy attacked"
			await _flash_label(status_label, FxConfig.COLOR_ENEMY_ATTACK_STATUS)
			waited = true
	if not waited:
		await board_view.get_tree().process_frame


func _flash_label(label, color):
	label.modulate = color
	var tween = board_view.create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, FxConfig.LABEL_FLASH_SEC)
	await tween.finished
