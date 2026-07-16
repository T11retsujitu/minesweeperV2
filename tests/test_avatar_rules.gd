extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")


func run(t):
	_test_snapshot_avatar_lists(t)
	_test_move_legal(t)
	_test_move_rejections(t)
	_test_reveal_adjacency_guard(t)
	_test_zero_flood_is_not_range_limited(t)
	_test_remote_flag_is_free(t)
	_test_remote_detonate_is_allowed(t)
	_test_detonation_splash(t)
	_test_accidental_mine_uses_flat_damage_only(t)
	_test_remote_dud_reveals_safe_cell(t)
	_test_phase1_move_rejected(t)
	_test_victory_priority_over_splash_defeat(t)


func _test_snapshot_avatar_lists(t):
	var phase1 = BoardGenerator.create_fixture_state()
	var phase1_snapshot = phase1.to_snapshot()
	t.equal(phase1_snapshot["ruleset"], CombatState.RULESET_PHASE1, "phase1 snapshot ruleset")
	t.equal(phase1_snapshot["player_position"], Vector2i.ZERO, "phase1 snapshot player position")
	t.equal(phase1_snapshot["movable_cells"], [], "phase1 snapshot movable cells empty")
	t.equal(phase1_snapshot["revealable_cells"], [], "phase1 snapshot revealable cells empty")

	var state = _avatar_state()
	var snapshot = state.to_snapshot()
	t.equal(snapshot["ruleset"], CombatState.RULESET_AVATAR, "avatar snapshot ruleset")
	t.equal(snapshot["player_position"], Vector2i(1, 3), "avatar snapshot player position")
	t.equal(
		snapshot["movable_cells"],
		[Vector2i(2, 2), Vector2i(2, 3)],
		"avatar movable cells are y/x ordered"
	)
	t.equal(
		snapshot["revealable_cells"],
		[Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4)],
		"avatar revealable cells are y/x ordered"
	)


func _test_move_legal(t):
	var state = _avatar_state()
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 3)})
	var moved = _event(events, "player_moved")
	t.equal(state.player.position, Vector2i(2, 3), "legal move updates player position")
	t.equal(state.turn_count, 1, "legal move consumes one turn")
	t.equal(state.enemy.countdown, Balance.ENEMY_COUNTDOWN - 1, "legal move decrements countdown")
	t.equal(moved.get("from", Vector2i.ZERO), Vector2i(1, 3), "player_moved from")
	t.equal(moved.get("to", Vector2i.ZERO), Vector2i(2, 3), "player_moved to")


func _test_move_rejections(t):
	_assert_rejected_move(t, _avatar_state(), Vector2i(3, 3), "non-adjacent revealed move rejected")
	_assert_rejected_move(t, _avatar_state(), Vector2i(1, 3), "self move rejected")
	_assert_rejected_move(t, _avatar_state(), Vector2i(1, 2), "enemy cell move rejected")
	_assert_rejected_move(t, _avatar_state(), Vector2i(1, 4), "unrevealed move rejected")

	var detonated = _avatar_state()
	detonated.board.toggle_flag(Vector2i(0, 3))
	TurnResolver.resolve(detonated, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(0, 3)})
	t.check(detonated.board.get_cell(Vector2i(0, 3)).is_detonated(), "detonated move target setup")
	_assert_rejected_move(t, detonated, Vector2i(0, 3), "detonated move rejected")


func _test_reveal_adjacency_guard(t):
	var adjacent = _avatar_state()
	var adjacent_events = TurnResolver.resolve(adjacent, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.check(not _has_event(adjacent_events, "turn_rejected"), "adjacent reveal accepted")
	t.equal(adjacent.turn_count, 1, "adjacent reveal consumes one turn")
	t.check(adjacent.board.get_cell(Vector2i(1, 4)).is_revealed(), "adjacent reveal opens cell")

	var remote = _avatar_state()
	var remote_events = TurnResolver.resolve(remote, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(5, 6)})
	t.equal(_event_reason(remote_events), "cell_not_adjacent_to_player", "remote reveal rejected by avatar guard")
	t.equal(remote.turn_count, 0, "remote reveal rejection does not consume turn")
	t.check(remote.board.get_cell(Vector2i(5, 6)).is_hidden(), "remote reveal rejection leaves cell hidden")


func _test_zero_flood_is_not_range_limited(t):
	var state = _avatar_state()
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(2, 4)})
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 4)})
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 5)})
	var expected = _keys([
		Vector2i(0, 4),
		Vector2i(0, 5),
		Vector2i(0, 6),
		Vector2i(1, 5),
		Vector2i(1, 6),
		Vector2i(2, 5),
		Vector2i(2, 6),
		Vector2i(3, 5),
		Vector2i(3, 6),
		Vector2i(4, 5),
		Vector2i(4, 6),
	])
	t.equal(_event_cells(events, "cells_revealed").size(), 11, "avatar zero flood reveal count")
	t.equal(_keys(_event_cells(events, "cells_revealed")), expected, "avatar zero flood reveal set")


func _test_remote_flag_is_free(t):
	var state = _avatar_state()
	var result = state.board.toggle_flag(Vector2i(6, 5))
	t.check(result["accepted"], "remote flag accepted")
	t.check(state.board.get_cell(Vector2i(6, 5)).is_flagged(), "remote flag marks cell")
	t.equal(state.turn_count, 0, "remote flag does not consume turn")


func _test_remote_detonate_is_allowed(t):
	var state = _avatar_state()
	state.board.toggle_flag(Vector2i(6, 5))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(6, 5)})
	t.check(_has_event(events, "mine_exploded"), "remote mine detonation emits explosion")
	t.check(not _has_event(events, "turn_rejected"), "remote mine detonation accepted")
	t.check(state.board.get_cell(Vector2i(6, 5)).is_detonated(), "remote mine becomes detonated")
	t.equal(state.turn_count, 1, "remote detonation consumes one turn")


func _test_detonation_splash(t):
	var adjacent = _avatar_state(Vector2i(2, 3))
	adjacent.board.toggle_flag(Vector2i(3, 4))
	var adjacent_events = TurnResolver.resolve(adjacent, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(3, 4)})
	var splash = _player_damage_event(adjacent_events, "detonation_splash")
	t.equal(splash.get("amount", 0), Balance.EXPLOSION_ADJACENT_DAMAGE, "adjacent detonation splash amount")
	t.equal(adjacent.player.hp, Balance.PLAYER_MAX_HP - Balance.EXPLOSION_ADJACENT_DAMAGE, "adjacent detonation splash hp")

	var distance_two = _avatar_state(Vector2i(1, 3))
	distance_two.board.toggle_flag(Vector2i(3, 4))
	var distance_two_events = TurnResolver.resolve(distance_two, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(3, 4)})
	t.check(not _has_player_damage_source(distance_two_events, "detonation_splash"), "distance two detonation has no splash event")
	t.equal(distance_two.player.hp, Balance.PLAYER_MAX_HP, "distance two detonation has no player damage")


func _test_accidental_mine_uses_flat_damage_only(t):
	var state = _avatar_state()
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(0, 3)})
	var accidental = _player_damage_event(events, "accidental_mine")
	t.equal(accidental.get("amount", 0), Balance.ACCIDENTAL_MINE_DAMAGE, "accidental mine flat damage")
	t.check(not _has_player_damage_source(events, "detonation_splash"), "accidental mine does not add splash")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP - Balance.ACCIDENTAL_MINE_DAMAGE, "accidental mine hp")


func _test_remote_dud_reveals_safe_cell(t):
	var state = _avatar_state()
	state.board.toggle_flag(Vector2i(5, 6))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(5, 6)})
	t.check(_has_event(events, "dud_detonation"), "remote dud event emitted")
	t.check(state.board.get_cell(Vector2i(5, 6)).is_revealed(), "remote dud reveals safe cell")
	t.check(not state.board.get_cell(Vector2i(5, 6)).is_flagged(), "remote dud clears flag")
	t.equal(state.turn_count, 1, "remote dud consumes one turn")


func _test_phase1_move_rejected(t):
	var state = BoardGenerator.create_fixture_state()
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 3)})
	t.equal(_event_reason(events), "move_not_available", "phase1 move rejected")
	t.equal(state.turn_count, 0, "phase1 move rejection does not consume turn")
	t.equal(state.player.position, Vector2i.ZERO, "phase1 move rejection leaves player position")


func _test_victory_priority_over_splash_defeat(t):
	var state = _avatar_state(Vector2i(2, 1))
	state.enemy.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	state.player.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	state.board.toggle_flag(Vector2i(1, 1))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.equal(state.enemy.hp, 0, "splash priority setup enemy killed")
	t.equal(state.player.hp, 0, "splash priority setup player killed")
	t.equal(state.phase, CombatState.PHASE_VICTORY, "victory beats simultaneous splash defeat")
	t.check(_has_event(events, "victory"), "simultaneous splash result emits victory")
	t.check(not _has_event(events, "defeat"), "simultaneous splash result does not emit defeat")


func _assert_rejected_move(t, state, cell, message):
	var before_position = state.player.position
	var before_turn = state.turn_count
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": cell})
	t.equal(_event_reason(events), "invalid_move_target", message + " reason")
	t.equal(state.player.position, before_position, message + " position unchanged")
	t.equal(state.turn_count, before_turn, message + " turn unchanged")


func _avatar_state(position = Vector2i(1, 3)):
	var state = BoardGenerator.create_fixture_state()
	state.ruleset = CombatState.RULESET_AVATAR
	state.player.position = position
	return state


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


func _event_reason(events):
	return _event(events, "turn_rejected").get("reason", "")


func _event_cells(events, event_type):
	return _event(events, event_type).get("cells", [])


func _player_damage_event(events, source):
	for event in events:
		if event.get("type", "") == "player_damaged" and event.get("source", "") == source:
			return event
	return {}


func _has_player_damage_source(events, source):
	return not _player_damage_event(events, source).is_empty()


func _keys(coords):
	var result = []
	for coord in coords:
		result.append("%d,%d" % [coord.x, coord.y])
	result.sort()
	return result
