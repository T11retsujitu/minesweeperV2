extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const BoardModel = preload("res://scripts/domain/board_model.gd")
const EnemyModel = preload("res://scripts/domain/enemy_model.gd")
const PlayerModel = preload("res://scripts/domain/player_model.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")


func run(t):
	_test_preview_damage(t)
	_test_center_adjacent_and_outside_damage(t)
	_test_no_chain_and_no_reuse(t)
	_test_intentional_detonation_no_self_damage(t)
	_test_accidental_mine_damage_and_state(t)
	_test_dud_detonation_is_safe_reveal(t)
	_test_explosion_does_not_reveal_neighbors(t)
	_test_detonated_cell_is_non_interactive(t)


func _test_preview_damage(t):
	var state = BoardGenerator.create_fixture_state()
	var preview = state.board.preview_detonation(Vector2i(1, 1))
	t.equal(preview["damage_map"][Vector2i(1, 1)], Balance.EXPLOSION_CENTER_DAMAGE, "preview center damage")
	t.equal(preview["damage_map"][Vector2i(1, 2)], Balance.EXPLOSION_ADJACENT_DAMAGE, "preview adjacent damage")
	t.check(not preview["damage_map"].has(Vector2i(4, 4)), "preview excludes range outside")
	t.check(preview["enemy_hit"], "preview reports enemy hit")
	t.equal(preview["expected_enemy_damage"], Balance.EXPLOSION_ADJACENT_DAMAGE, "preview expected enemy damage")


func _test_center_adjacent_and_outside_damage(t):
	var board = BoardModel.new()
	board.setup(Balance.BOARD_W, Balance.BOARD_H, [Vector2i(3, 3)], [])
	t.equal(board.explosion_damage_at(Vector2i(3, 3), Vector2i(3, 3)), Balance.EXPLOSION_CENTER_DAMAGE, "center explosion damage")
	t.equal(board.explosion_damage_at(Vector2i(3, 3), Vector2i(4, 4)), Balance.EXPLOSION_ADJACENT_DAMAGE, "diagonal adjacent explosion damage")
	t.equal(board.explosion_damage_at(Vector2i(3, 3), Vector2i(5, 3)), 0, "outside explosion damage")


func _test_no_chain_and_no_reuse(t):
	var state = _custom_state([Vector2i(1, 1), Vector2i(1, 2)], Vector2i(4, 4))
	state.board.toggle_flag(Vector2i(1, 1))
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.check(state.board.get_cell(Vector2i(1, 1)).is_detonated(), "detonated mine is marked")
	t.check(not state.board.get_cell(Vector2i(1, 2)).is_detonated(), "adjacent mine does not chain detonate")
	var second = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.check(_has_event(second, "turn_rejected"), "detonated mine cannot be detonated again")


func _test_intentional_detonation_no_self_damage(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.toggle_flag(Vector2i(1, 1))
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP, "intentional detonation does not damage player")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP - Balance.EXPLOSION_ADJACENT_DAMAGE, "intentional detonation damages enemy")


func _test_accidental_mine_damage_and_state(t):
	var state = BoardGenerator.create_fixture_state()
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 1)})
	var cell = state.board.get_cell(Vector2i(1, 1))
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP - Balance.ACCIDENTAL_MINE_DAMAGE, "accidental mine damages player")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP - Balance.EXPLOSION_ADJACENT_DAMAGE, "accidental mine damages enemy in range")
	t.check(cell.is_revealed(), "accidental mine cell is revealed")
	t.check(cell.is_detonated(), "accidental mine cell is detonated")


func _test_dud_detonation_is_safe_reveal(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.reveal_cell(Vector2i(1, 4))
	state.board.reveal_cell(Vector2i(2, 4))
	state.board.toggle_flag(Vector2i(1, 5))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 5)})
	t.check(_has_event(events, "dud_detonation"), "dud detonation event emitted")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP, "dud does not damage player")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP, "dud does not damage enemy")
	t.equal(_event_cells(events, "cells_revealed").size(), 11, "dud zero cell floods as safe reveal")


func _test_explosion_does_not_reveal_neighbors(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.toggle_flag(Vector2i(1, 1))
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.check(state.board.get_cell(Vector2i(0, 0)).is_hidden(), "explosion does not reveal adjacent safe cell")
	t.check(state.board.get_cell(Vector2i(1, 1)).is_hidden(), "intentional explosion does not reveal center cell")
	t.check(not state.board.get_cell(Vector2i(1, 1)).is_flagged(), "flag is removed on detonation")


func _test_detonated_cell_is_non_interactive(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.toggle_flag(Vector2i(1, 1))
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	var reveal = state.board.reveal_cell(Vector2i(1, 1))
	var flag = state.board.toggle_flag(Vector2i(1, 1))
	t.check(not reveal["accepted"], "detonated cell cannot be revealed")
	t.check(not flag["accepted"], "detonated cell cannot be flagged")


func _custom_state(mines, enemy_position):
	var board = BoardModel.new()
	board.setup(Balance.BOARD_W, Balance.BOARD_H, mines, [enemy_position])
	board.set_enemy_position(enemy_position)
	return CombatState.new(board, EnemyModel.new(enemy_position, Balance.ENEMY_MAX_HP), PlayerModel.new(), 0, CombatState.MODE_FIXED)


func _has_event(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return true
	return false


func _event_cells(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return event.get("cells", [])
	return []
