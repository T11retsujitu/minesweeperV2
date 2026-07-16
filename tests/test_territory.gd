extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")


func run(t):
	_test_outside_territory_pauses_countdown(t)
	_test_reentry_resumes_from_frozen_countdown(t)
	_test_outside_territory_prevents_attack(t)
	_test_territory_cells_are_clipped(t)
	_test_phase1_ignores_territory(t)


func _test_outside_territory_pauses_countdown(t):
	var state = _avatar_state(Vector2i(5, 6))
	var before = state.enemy.countdown
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(4, 6)})
	t.equal(state.enemy.countdown, before, "outside territory keeps countdown value")
	t.check(_has_event(events, "countdown_paused"), "outside territory emits paused event")
	t.equal(_event(events, "countdown_paused").get("countdown", -1), before, "paused event carries current countdown")
	t.check(not _has_event(events, "countdown_changed"), "outside territory does not emit countdown_changed")


func _test_reentry_resumes_from_frozen_countdown(t):
	var state = _avatar_state(Vector2i(5, 6))
	state.enemy.countdown = 2
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(4, 6)})
	t.equal(state.enemy.countdown, 2, "outside turn freezes countdown at two")

	state.player.position = Vector2i(1, 3)
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.equal(state.enemy.countdown, 1, "reentry resumes countdown from frozen value")
	t.check(_has_event(events, "countdown_changed"), "reentry emits countdown_changed")
	t.check(not _has_event(events, "countdown_paused"), "reentry no longer emits paused")


func _test_outside_territory_prevents_attack(t):
	var state = _avatar_state(Vector2i(5, 6))
	state.enemy.countdown = 1
	state.board.get_cell(Vector2i(5, 6)).force_reveal()
	state.board.get_cell(Vector2i(4, 6)).force_reveal()

	var first = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(4, 6)})
	var second = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_MOVE, "cell": Vector2i(5, 6)})
	t.equal(state.enemy.countdown, 1, "outside moves keep countdown at one")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP, "outside territory does not damage player")
	t.check(not _has_event(first, "enemy_attacked"), "first outside move has no enemy attack")
	t.check(not _has_event(second, "enemy_attacked"), "second outside move has no enemy attack")
	t.check(_has_event(first, "countdown_paused"), "first outside move emits paused")
	t.check(_has_event(second, "countdown_paused"), "second outside move emits paused")


func _test_territory_cells_are_clipped(t):
	var state = _avatar_state()
	var cells = state.territory_cells()
	t.equal(cells.size(), 20, "fixture territory clips to twenty cells")
	for coord in cells:
		t.check(coord.x >= 0 and coord.x <= 3, "territory x clipped")
		t.check(coord.y >= 0 and coord.y <= 4, "territory y clipped")
	t.equal(_keys(cells), _expected_fixture_territory_keys(), "fixture territory exact cells")

	var snapshot = state.to_snapshot()
	t.equal(_keys(snapshot["territory_cells"]), _expected_fixture_territory_keys(), "snapshot exposes living enemy territory")
	t.check(snapshot["player_in_territory"], "fixture player starts inside territory")
	state.enemy.hp = 0
	t.equal(state.to_snapshot()["territory_cells"], [], "dead enemy hides territory cells")


func _test_phase1_ignores_territory(t):
	var state = BoardGenerator.create_fixture_state()
	t.check(state.is_player_in_territory(), "phase1 treats player as in territory")
	var before = state.enemy.countdown
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.equal(state.enemy.countdown, before - 1, "phase1 countdown still advances")
	t.check(_has_event(events, "countdown_changed"), "phase1 emits countdown_changed")
	t.check(not _has_event(events, "countdown_paused"), "phase1 does not emit countdown_paused")


func _avatar_state(position = Vector2i(1, 3)):
	var state = BoardGenerator.create_fixture_state(Fixtures.PHASE1_CORE_DEMO, CombatState.RULESET_AVATAR)
	state.player.position = position
	return state


func _expected_fixture_territory_keys():
	var result = []
	for y in range(0, 5):
		for x in range(0, 4):
			result.append("%d,%d" % [x, y])
	result.sort()
	return result


func _keys(coords):
	var result = []
	for coord in coords:
		result.append("%d,%d" % [coord.x, coord.y])
	result.sort()
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
