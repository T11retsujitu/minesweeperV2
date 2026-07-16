extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")


func run(t):
	_test_avatar_victory_line(t)
	_test_avatar_defeat_line(t)


func _test_avatar_victory_line(t):
	var state = _fixture_avatar_state()
	t.equal(state.player.position, Vector2i(1, 3), "avatar fixture player_start")

	var t1 = _flag_and_detonate(state, Vector2i(1, 1))
	_assert_state(t, state, 4, 2, 10, Vector2i(1, 3), 1, "avatar victory T1")
	t.equal(_event_types(t1), ["mine_exploded", "enemy_damaged", "countdown_changed"], "avatar victory T1 events")
	t.equal(_enemy_damage_amount(t1), 2, "avatar victory T1 enemy damage")
	t.check(not _has_player_damage_source(t1, "detonation_splash"), "avatar victory T1 no splash")

	var t2 = _flag_and_detonate(state, Vector2i(0, 1))
	_assert_state(t, state, 2, 1, 10, Vector2i(1, 3), 2, "avatar victory T2")
	t.equal(_event_types(t2), ["mine_exploded", "enemy_damaged", "countdown_changed"], "avatar victory T2 events")
	t.equal(_enemy_damage_amount(t2), 2, "avatar victory T2 enemy damage")
	t.check(not _has_player_damage_source(t2, "detonation_splash"), "avatar victory T2 no splash")

	var t3 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	_assert_state(t, state, 2, Balance.ENEMY_COUNTDOWN, 8, Vector2i(1, 3), 3, "avatar victory T3")
	t.equal(_event_types(t3), ["cells_revealed", "countdown_changed", "enemy_attacked", "player_damaged", "countdown_changed"], "avatar victory T3 events")
	t.equal(_event_cells(t3, "cells_revealed"), [Vector2i(1, 4)], "avatar victory T3 single reveal")
	t.equal(_player_damage_amount(t3, "enemy_attack"), Balance.ENEMY_ATTACK, "avatar victory T3 enemy attack damage")

	var t4 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(2, 4)})
	_assert_state(t, state, 2, 2, 8, Vector2i(1, 3), 4, "avatar victory T4")
	t.equal(_event_types(t4), ["cells_revealed", "countdown_changed"], "avatar victory T4 events")
	t.equal(_event_cells(t4, "cells_revealed"), [Vector2i(2, 4)], "avatar victory T4 single reveal")

	var t5 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 4)})
	_assert_state(t, state, 2, 1, 8, Vector2i(2, 4), 5, "avatar victory T5")
	t.equal(_event_types(t5), ["player_moved", "countdown_changed"], "avatar victory T5 events")
	t.equal(_event(t5, "player_moved").get("from", Vector2i.ZERO), Vector2i(1, 3), "avatar victory T5 move from")
	t.equal(_event(t5, "player_moved").get("to", Vector2i.ZERO), Vector2i(2, 4), "avatar victory T5 move to")

	var t6 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 5)})
	_assert_state(t, state, 2, Balance.ENEMY_COUNTDOWN, 6, Vector2i(2, 4), 6, "avatar victory T6")
	t.equal(_event_types(t6), ["cells_revealed", "countdown_changed", "enemy_attacked", "player_damaged", "countdown_changed"], "avatar victory T6 events")
	t.equal(_event_cells(t6, "cells_revealed").size(), 11, "avatar victory T6 flood count")
	t.equal(_player_damage_amount(t6, "enemy_attack"), Balance.ENEMY_ATTACK, "avatar victory T6 enemy attack damage")

	var t7 = _flag_and_detonate(state, Vector2i(0, 3))
	_assert_state(t, state, 0, Balance.ENEMY_COUNTDOWN, 6, Vector2i(2, 4), 7, "avatar victory T7")
	t.equal(_event_types(t7), ["mine_exploded", "enemy_damaged", "enemy_died", "combat_won"], "avatar victory T7 events")
	t.equal(state.phase, CombatState.PHASE_RECOVERY, "avatar victory T7 phase")
	t.check(not _has_event(t7, "countdown_changed"), "avatar victory T7 skips countdown")
	t.check(not _has_event(t7, "victory"), "avatar victory T7 does not emit final victory yet")
	t.check(not _has_event(t7, "defeat"), "avatar victory T7 no defeat")


func _test_avatar_defeat_line(t):
	var state = _fixture_avatar_state()
	t.equal(state.player.position, Vector2i(1, 3), "avatar defeat fixture player_start")

	var t1 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(0, 3)})
	_assert_state(t, state, 4, 2, 7, Vector2i(1, 3), 1, "avatar defeat T1")
	t.equal(_event_types(t1), ["cells_revealed", "mine_exploded", "enemy_damaged", "player_damaged", "countdown_changed"], "avatar defeat T1 events")
	t.equal(_enemy_damage_amount(t1), 2, "avatar defeat T1 enemy damage")
	t.equal(_player_damage_amount(t1, "accidental_mine"), Balance.ACCIDENTAL_MINE_DAMAGE, "avatar defeat T1 accidental damage")

	var t2 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 2)})
	_assert_state(t, state, 4, 1, 7, Vector2i(2, 2), 2, "avatar defeat T2")
	t.equal(_event_types(t2), ["player_moved", "countdown_changed"], "avatar defeat T2 events")
	t.equal(_event(t2, "player_moved").get("from", Vector2i.ZERO), Vector2i(1, 3), "avatar defeat T2 move from")
	t.equal(_event(t2, "player_moved").get("to", Vector2i.ZERO), Vector2i(2, 2), "avatar defeat T2 move to")

	var t3 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 1)})
	_assert_state(t, state, 2, Balance.ENEMY_COUNTDOWN, 2, Vector2i(2, 2), 3, "avatar defeat T3")
	t.equal(_event_types(t3), ["cells_revealed", "mine_exploded", "enemy_damaged", "player_damaged", "countdown_changed", "enemy_attacked", "player_damaged", "countdown_changed"], "avatar defeat T3 events")
	t.equal(_enemy_damage_amount(t3), 2, "avatar defeat T3 enemy damage")
	t.equal(_player_damage_amount(t3, "accidental_mine"), Balance.ACCIDENTAL_MINE_DAMAGE, "avatar defeat T3 accidental damage")
	t.equal(_player_damage_amount(t3, "enemy_attack"), Balance.ENEMY_ATTACK, "avatar defeat T3 enemy attack damage")

	var t4 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(3, 2)})
	_assert_state(t, state, 2, 2, 2, Vector2i(3, 2), 4, "avatar defeat T4")
	t.equal(_event_types(t4), ["player_moved", "countdown_changed"], "avatar defeat T4 events")
	t.equal(_event(t4, "player_moved").get("from", Vector2i.ZERO), Vector2i(2, 2), "avatar defeat T4 move from")
	t.equal(_event(t4, "player_moved").get("to", Vector2i.ZERO), Vector2i(3, 2), "avatar defeat T4 move to")

	var t5 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(4, 1)})
	_assert_state(t, state, 2, 1, -1, Vector2i(3, 2), 5, "avatar defeat T5")
	t.equal(_event_types(t5), ["cells_revealed", "mine_exploded", "enemy_damaged", "player_damaged", "countdown_changed", "defeat"], "avatar defeat T5 events")
	t.equal(_enemy_damage_amount(t5), 0, "avatar defeat T5 enemy damage")
	t.equal(_player_damage_amount(t5, "accidental_mine"), Balance.ACCIDENTAL_MINE_DAMAGE, "avatar defeat T5 accidental damage")
	t.equal(state.phase, CombatState.PHASE_DEFEAT, "avatar defeat T5 phase")


func _fixture_avatar_state():
	return BoardGenerator.create_fixture_state(Fixtures.PHASE1_CORE_DEMO, CombatState.RULESET_AVATAR)


func _flag_and_detonate(state, coord):
	state.board.toggle_flag(coord)
	return TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": coord})


func _assert_state(t, state, enemy_hp, countdown, player_hp, player_position, turn_count, label):
	t.equal(state.enemy.hp, enemy_hp, label + " enemy hp")
	t.equal(state.enemy.countdown, countdown, label + " countdown")
	t.equal(state.player.hp, player_hp, label + " player hp")
	t.equal(state.player.position, player_position, label + " player position")
	t.equal(state.turn_count, turn_count, label + " turn count")


func _event_types(events):
	var result = []
	for event in events:
		result.append(event.get("type", ""))
	return result


func _has_event(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return true
	return false


func _event(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return event
	return {}


func _event_cells(events, event_type):
	return _event(events, event_type).get("cells", [])


func _enemy_damage_amount(events):
	return _event(events, "enemy_damaged").get("amount", 0)


func _player_damage_amount(events, source):
	for event in events:
		if event.get("type", "") == "player_damaged" and event.get("source", "") == source:
			return event.get("amount", 0)
	return 0


func _has_player_damage_source(events, source):
	for event in events:
		if event.get("type", "") == "player_damaged" and event.get("source", "") == source:
			return true
	return false
