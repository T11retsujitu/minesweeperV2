extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")

var max_hp = Balance.PLAYER_MAX_HP
var hp = Balance.PLAYER_MAX_HP


func _init(p_hp = Balance.PLAYER_MAX_HP):
	max_hp = Balance.PLAYER_MAX_HP
	hp = p_hp


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
