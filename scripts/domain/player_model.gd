extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")

var position = Vector2i.ZERO
var max_hp = Balance.PLAYER_MAX_HP
var hp = Balance.PLAYER_MAX_HP


func _init(p_position = Vector2i.ZERO, p_hp = Balance.PLAYER_MAX_HP):
	max_hp = Balance.PLAYER_MAX_HP
	if typeof(p_position) == TYPE_VECTOR2I:
		position = p_position
		hp = p_hp
	else:
		position = Vector2i.ZERO
		hp = p_position


func apply_damage(amount):
	var before = hp
	hp -= amount
	return {
		"before": before,
		"after": hp,
		"amount": amount,
	}


func is_dead():
	return hp <= 0
