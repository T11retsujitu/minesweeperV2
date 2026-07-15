extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")


func run(t):
	_test_victory_line(t)
	_test_defeat_line(t)


func _test_victory_line(t):
	var state = BoardGenerator.create_fixture_state()

	_flag_and_detonate(state, Vector2i(1, 1))
	t.equal(state.enemy.hp, 4, "victory line T1 enemy hp")
	t.equal(state.enemy.countdown, 2, "victory line T1 countdown")
	t.equal(state.turn_count, 1, "victory line T1 turn")

	_flag_and_detonate(state, Vector2i(0, 1))
	t.equal(state.enemy.hp, 2, "victory line T2 enemy hp")
	t.equal(state.enemy.countdown, 1, "victory line T2 countdown")
	t.equal(state.turn_count, 2, "victory line T2 turn")

	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.equal(state.player.hp, 8, "victory line T3 player hp after enemy attack")
	t.equal(state.enemy.countdown, Balance.ENEMY_COUNTDOWN, "victory line T3 countdown reset")
	t.equal(state.turn_count, 3, "victory line T3 turn")

	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(2, 4)})
	t.equal(state.enemy.countdown, 2, "victory line T4 countdown")
	t.equal(state.turn_count, 4, "victory line T4 turn")

	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 5)})
	t.equal(_event_cells(events, "cells_revealed").size(), 11, "victory line T5 flood count")
	t.equal(state.enemy.countdown, 1, "victory line T5 countdown")
	t.equal(state.turn_count, 5, "victory line T5 turn")

	var final_events = _flag_and_detonate(state, Vector2i(0, 3))
	t.equal(state.enemy.hp, 0, "victory line T6 enemy hp")
	t.equal(state.phase, CombatState.PHASE_VICTORY, "victory line T6 phase")
	t.equal(state.player.hp, 8, "victory line T6 no enemy attack")
	t.equal(state.enemy.countdown, 1, "victory line T6 skips countdown")
	t.check(_has_event(final_events, "victory"), "victory line emits victory")
	t.check(not _has_event(final_events, "enemy_attacked"), "victory line skips enemy attack")


func _test_defeat_line(t):
	var state = BoardGenerator.create_fixture_state()
	var first = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(4, 1)})
	t.equal(state.player.hp, 7, "defeat line T1 player hp")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP, "defeat line T1 enemy hp")
	t.equal(state.enemy.countdown, 2, "defeat line T1 countdown")
	t.equal(_enemy_damage_amount(first), 0, "defeat line T1 enemy damage zero")

	var second = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(6, 1)})
	t.equal(state.player.hp, 4, "defeat line T2 player hp")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP, "defeat line T2 enemy hp")
	t.equal(state.enemy.countdown, 1, "defeat line T2 countdown")
	t.equal(_enemy_damage_amount(second), 0, "defeat line T2 enemy damage zero")

	var third = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(6, 3)})
	t.equal(state.player.hp, -1, "defeat line T3 player hp after attack")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP, "defeat line T3 enemy hp")
	t.equal(state.phase, CombatState.PHASE_DEFEAT, "defeat line T3 phase")
	t.equal(state.turn_count, 3, "defeat line T3 turn")
	t.equal(_enemy_damage_amount(third), 0, "defeat line T3 enemy damage zero")
	t.check(_has_event(third, "enemy_attacked"), "defeat line enemy attacks at countdown zero")
	t.check(_has_event(third, "defeat"), "defeat line emits defeat")


func _flag_and_detonate(state, coord):
	state.board.toggle_flag(coord)
	return TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": coord})


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


func _enemy_damage_amount(events):
	for event in events:
		if event.get("type", "") == "enemy_damaged":
			return event.get("amount", 0)
	return 0
