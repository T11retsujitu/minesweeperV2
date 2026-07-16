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
	t.equal(cells.size(), 9, "fixture territory contains nine cells")
	for coord in cells:
		t.check(coord.x >= 0 and coord.x <= 2, "territory x range")
		t.check(coord.y >= 1 and coord.y <= 3, "territory y range")
	t.equal(_keys(cells), _expected_fixture_territory_keys(), "fixture territory exact cells")

	var snapshot = state.to_snapshot()
	t.equal(_keys(snapshot["territory_cells"]), _expected_fixture_territory_keys(), "snapshot exposes living enemy territory")
	t.check(snapshot["player_in_territory"], "fixture player starts inside territory")
	_assert_radius_two_ring_is_outside(t, state)
	_assert_corner_territory_clips(t, state)
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
	for y in range(1, 4):
		for x in range(0, 3):
			result.append("%d,%d" % [x, y])
	result.sort()
	return result


func _assert_radius_two_ring_is_outside(t, state):
	for coord in _old_radius_two_ring_coords():
		state.player.position = coord
		t.check(not state.is_player_in_territory(), "radius two ring is outside territory")


func _assert_corner_territory_clips(t, state):
	state.enemy.position = Vector2i(0, 0)
	var cells = state.territory_cells()
	t.equal(cells.size(), 4, "corner territory clips to four cells")
	for coord in cells:
		t.check(coord.x >= 0 and coord.x <= 1, "corner territory x clipped")
		t.check(coord.y >= 0 and coord.y <= 1, "corner territory y clipped")
	t.equal(_keys(cells), _corner_territory_keys(), "corner territory exact cells")


func _old_radius_two_ring_coords():
	return [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
		Vector2i(3, 1),
		Vector2i(3, 2),
		Vector2i(3, 3),
		Vector2i(0, 4),
		Vector2i(1, 4),
		Vector2i(2, 4),
		Vector2i(3, 4),
	]


func _corner_territory_keys():
	var result = ["0,0", "1,0", "0,1", "1,1"]
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
