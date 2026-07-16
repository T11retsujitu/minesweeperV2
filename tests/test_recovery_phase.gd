extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")
const BattleController = preload("res://scripts/application/battle_controller.gd")


func run(t):
	_test_snapshot_safe_counts(t)
	_test_recovery_oracle_perfect_clear(t)
	_test_finish_recovery(t)
	_test_recovery_accidental_death(t)
	_test_simultaneous_death_skips_recovery(t)
	_test_recovery_skips_countdown(t)


func _test_snapshot_safe_counts(t):
	var state = _avatar_state()
	var snapshot = state.to_snapshot()
	t.equal(snapshot["phase"], CombatState.PHASE_PLAYING, "snapshot includes phase")
	t.equal(snapshot["accidental_mine_count"], 0, "snapshot accidental count starts at zero")
	t.equal(snapshot["safe_cells_total"], Balance.BOARD_W * Balance.BOARD_H - Balance.MINE_COUNT, "snapshot safe total")
	t.equal(snapshot["safe_cells_revealed"], 8, "snapshot initial safe revealed count")

	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(0, 3)})
	t.equal(state.accidental_mine_count, 1, "accidental mine increments counter")
	t.equal(state.to_snapshot()["accidental_mine_count"], 1, "snapshot exposes accidental count")


func _test_recovery_oracle_perfect_clear(t):
	var state = _recovery_state()
	var final_events = _complete_recovery_with_oracle(t, state)
	t.equal(state.phase, CombatState.PHASE_VICTORY, "oracle reaches victory")
	t.check(state.board.all_safe_cells_revealed(), "oracle opens every safe cell")
	t.check(_has_event(final_events, "perfect_clear"), "oracle emits perfect_clear")
	t.equal(_event(final_events, "victory").get("perfect", false), true, "oracle victory is perfect")


func _test_finish_recovery(t):
	var playing_controller = BattleController.new(CombatState.RULESET_AVATAR)
	var playing_finish = playing_controller.finish_recovery()
	t.equal(_event_reason(playing_finish), "finish_not_available", "finish rejected while playing")
	t.equal(playing_controller.state.turn_count, 0, "playing finish rejection is free")
	t.check(not playing_controller.is_busy, "playing finish rejection does not lock input")

	var recovery_controller = BattleController.new(CombatState.RULESET_AVATAR)
	recovery_controller.state = _recovery_state()
	var before_turn = recovery_controller.state.turn_count
	var events = recovery_controller.finish_recovery()
	t.equal(recovery_controller.state.phase, CombatState.PHASE_VICTORY, "finish sets victory")
	t.equal(recovery_controller.state.turn_count, before_turn, "finish does not consume a turn")
	t.equal(_event(events, "victory").get("perfect", true), false, "finish victory is non-perfect")
	t.check(not _has_event(events, "perfect_clear"), "finish does not emit perfect_clear")
	t.check(recovery_controller.is_busy, "accepted finish enters feedback busy state")


func _test_recovery_accidental_death(t):
	var state = _recovery_state()
	state.player.hp = Balance.ACCIDENTAL_MINE_DAMAGE
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(3, 4)})
	t.equal(state.accidental_mine_count, 1, "recovery accidental increments counter")
	t.equal(state.player.hp, 0, "recovery accidental mine can kill player")
	t.equal(state.phase, CombatState.PHASE_DEFEAT, "recovery accidental death defeats")
	t.check(_has_event(events, "defeat"), "recovery accidental death emits defeat")
	t.check(not _has_event(events, "victory"), "recovery accidental death does not emit victory")


func _test_simultaneous_death_skips_recovery(t):
	var state = _avatar_state(Vector2i(2, 1))
	state.enemy.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	state.player.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	state.board.toggle_flag(Vector2i(1, 1))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.equal(state.enemy.hp, 0, "simultaneous setup kills enemy")
	t.equal(state.player.hp, 0, "simultaneous setup kills player")
	t.equal(state.phase, CombatState.PHASE_VICTORY, "simultaneous death goes straight to victory")
	t.equal(_event(events, "victory").get("perfect", true), false, "simultaneous victory is non-perfect")
	t.check(not _has_event(events, "combat_won"), "simultaneous death skips recovery event")
	t.check(not _has_event(events, "defeat"), "simultaneous death keeps victory priority")


func _test_recovery_skips_countdown(t):
	var state = _recovery_state()
	var before_turn = state.turn_count
	var before_countdown = state.enemy.countdown
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(3, 3)})
	t.equal(state.phase, CombatState.PHASE_RECOVERY, "recovery move stays in recovery")
	t.equal(state.turn_count, before_turn + 1, "recovery move consumes a turn")
	t.equal(state.enemy.countdown, before_countdown, "recovery move keeps countdown")
	t.check(not _has_event(events, "countdown_changed"), "recovery move emits no countdown event")
	t.check(not _has_event(events, "enemy_attacked"), "recovery move emits no enemy attack")


func _recovery_state():
	var state = _avatar_state()
	_flag_and_detonate(state, Vector2i(1, 1))
	_flag_and_detonate(state, Vector2i(0, 1))
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(2, 4)})
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(2, 4)})
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 5)})
	var events = _flag_and_detonate(state, Vector2i(0, 3))
	if state.phase != CombatState.PHASE_RECOVERY or not _has_event(events, "combat_won"):
		push_error("Recovery fixture setup failed")
	return state


func _complete_recovery_with_oracle(t, state):
	var last_events = []
	var guard = 0
	while state.phase == CombatState.PHASE_RECOVERY and guard < 200:
		var reveal_cell = _adjacent_hidden_safe_cell(state)
		if reveal_cell != null:
			last_events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": reveal_cell})
		else:
			var move_cell = _next_step_to_frontier(state)
			if move_cell == null:
				t.check(false, "oracle finds a path to the next frontier")
				return last_events
			last_events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": move_cell})
		t.check(not _has_event(last_events, "turn_rejected"), "oracle action accepted")
		guard += 1
	t.check(guard < 200, "oracle finishes within guard")
	return last_events


func _adjacent_hidden_safe_cell(state):
	for coord in state.board.get_neighbor_coords(state.player.position):
		var cell = state.board.get_cell(coord)
		if cell != null and not cell.contains_mine and cell.can_reveal():
			return coord
	return null


func _next_step_to_frontier(state):
	var start = state.player.position
	var queue = [start]
	var came_from = {}
	came_from[start] = null
	while not queue.is_empty():
		var current = queue.pop_front()
		if current != start and _has_adjacent_hidden_safe_cell(state, current):
			return _first_step(came_from, start, current)
		for neighbor in state.board.get_neighbor_coords(current):
			if came_from.has(neighbor) or not _is_passable_recovery_cell(state, neighbor):
				continue
			came_from[neighbor] = current
			queue.append(neighbor)
	return null


func _first_step(came_from, start, target):
	var step = target
	while came_from[step] != start and came_from[step] != null:
		step = came_from[step]
	return step


func _has_adjacent_hidden_safe_cell(state, coord):
	for neighbor in state.board.get_neighbor_coords(coord):
		var cell = state.board.get_cell(neighbor)
		if cell != null and not cell.contains_mine and cell.can_reveal():
			return true
	return false


func _is_passable_recovery_cell(state, coord):
	var cell = state.board.get_cell(coord)
	return cell != null and cell.is_revealed() and not cell.is_detonated()


func _avatar_state(position = Vector2i(1, 3)):
	var state = BoardGenerator.create_fixture_state(Fixtures.PHASE1_CORE_DEMO, CombatState.RULESET_AVATAR)
	state.player.position = position
	return state


func _flag_and_detonate(state, coord):
	state.board.toggle_flag(coord)
	return TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": coord})


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
