extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")

var id = "basic_soldier"
var position = Vector2i.ZERO
var max_hp = Balance.ENEMY_MAX_HP
var hp = Balance.ENEMY_MAX_HP
var attack_damage = Balance.ENEMY_ATTACK
var countdown = Balance.ENEMY_COUNTDOWN


func _init(p_position = Vector2i.ZERO, p_hp = Balance.ENEMY_MAX_HP):
	position = p_position
	max_hp = Balance.ENEMY_MAX_HP
	hp = p_hp
	attack_damage = Balance.ENEMY_ATTACK
	countdown = Balance.ENEMY_COUNTDOWN


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


func decrement_countdown():
	var before = countdown
	countdown -= 1
	return {
		"before": before,
		"after": countdown,
	}


func reset_countdown():
	var before = countdown
	countdown = Balance.ENEMY_COUNTDOWN
	return {
		"before": before,
		"after": countdown,
	}
