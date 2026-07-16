extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")

const PHASE1_CORE_DEMO = "phase1_core_demo"


static func get_phase1_core_demo():
	return {
		"fixture_id": PHASE1_CORE_DEMO,
		"board_size": Vector2i(Balance.BOARD_W, Balance.BOARD_H),
		"mines": [
			Vector2i(0, 1),
			Vector2i(1, 1),
			Vector2i(4, 1),
			Vector2i(6, 1),
			Vector2i(0, 3),
			Vector2i(6, 3),
			Vector2i(3, 4),
			Vector2i(5, 5),
			Vector2i(6, 5),
		],
		"enemy_position": Vector2i(1, 2),
		"enemy_hp": Balance.ENEMY_MAX_HP,
		"initial_revealed": [
			Vector2i(1, 2),
			Vector2i(2, 1),
			Vector2i(3, 1),
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(1, 3),
			Vector2i(2, 3),
			Vector2i(3, 3),
		],
		"player_start": Vector2i(1, 3),
	}
