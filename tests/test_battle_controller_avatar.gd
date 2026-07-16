extends RefCounted

const CombatState = preload("res://scripts/domain/combat_state.gd")
const BattleController = preload("res://scripts/application/battle_controller.gd")

var captured_events = []


func run(t):
	_test_avatar_initial_snapshot(t)
	_test_tap_revealed_cell_moves_avatar(t)
	_test_tap_hidden_adjacent_cell_reveals(t)
	_test_tap_hidden_remote_cell_rejected_by_resolver(t)
	_test_tap_flagged_cell_previews_detonation(t)
	_test_retry_restores_avatar_start(t)
	_test_default_controller_stays_phase1(t)


func _test_avatar_initial_snapshot(t):
	var controller = BattleController.new(CombatState.RULESET_AVATAR)
	var snapshot = controller.get_snapshot()
	t.equal(snapshot["ruleset"], CombatState.RULESET_AVATAR, "avatar controller snapshot ruleset")
	t.equal(snapshot["player_position"], Vector2i(1, 3), "avatar controller snapshot player position")


func _test_tap_revealed_cell_moves_avatar(t):
	var controller = _controller_with_signal(CombatState.RULESET_AVATAR)
	var events = controller.tap(Vector2i(2, 3))
	var emitted = _last_emitted()
	t.equal(_event_type(events, 0), "player_moved", "avatar tap revealed returns player_moved")
	t.equal(_event_type(emitted, 0), "player_moved", "avatar tap revealed emits player_moved")
	t.equal(_event(emitted, "player_moved").get("from", Vector2i.ZERO), Vector2i(1, 3), "avatar tap move emitted from")
	t.equal(_event(emitted, "player_moved").get("to", Vector2i.ZERO), Vector2i(2, 3), "avatar tap move emitted to")
	t.equal(controller.get_snapshot()["player_position"], Vector2i(2, 3), "avatar tap move updates snapshot position")


func _test_tap_hidden_adjacent_cell_reveals(t):
	var controller = _controller_with_signal(CombatState.RULESET_AVATAR)
	var events = controller.tap(Vector2i(1, 4))
	var emitted = _last_emitted()
	t.equal(_event_type(events, 0), "cells_revealed", "avatar tap hidden adjacent returns reveal")
	t.equal(_event_type(emitted, 0), "cells_revealed", "avatar tap hidden adjacent emits reveal")
	t.equal(_event(emitted, "cells_revealed").get("cells", []), [Vector2i(1, 4)], "avatar tap hidden adjacent reveals target")
	t.equal(controller.get_snapshot()["player_position"], Vector2i(1, 3), "avatar tap reveal keeps player position")


func _test_tap_hidden_remote_cell_rejected_by_resolver(t):
	var controller = _controller_with_signal(CombatState.RULESET_AVATAR)
	var events = controller.tap(Vector2i(5, 6))
	var emitted = _last_emitted()
	t.equal(_event_type(events, 0), "turn_rejected", "avatar tap hidden remote returns rejection")
	t.equal(_event_type(emitted, 0), "turn_rejected", "avatar tap hidden remote emits rejection")
	t.equal(_event(emitted, "turn_rejected").get("reason", ""), "cell_not_adjacent_to_player", "avatar tap hidden remote reject reason")
	t.equal(controller.state.turn_count, 0, "avatar tap hidden remote does not consume turn")
	t.equal(controller.get_snapshot()["player_position"], Vector2i(1, 3), "avatar tap hidden remote keeps player position")


func _test_tap_flagged_cell_previews_detonation(t):
	var controller = _controller_with_signal(CombatState.RULESET_AVATAR)
	controller.long_press(Vector2i(1, 1))
	var events = controller.tap(Vector2i(1, 1))
	var emitted = _last_emitted()
	t.equal(_event_type(events, 0), "detonation_preview", "avatar tap flagged returns detonation preview")
	t.equal(_event_type(emitted, 0), "detonation_preview", "avatar tap flagged emits detonation preview")
	t.check(not _has_event(emitted, "player_moved"), "avatar tap flagged is not treated as move")
	t.equal(controller.get_snapshot()["player_position"], Vector2i(1, 3), "avatar tap flagged keeps player position")


func _test_retry_restores_avatar_start(t):
	var controller = _controller_with_signal(CombatState.RULESET_AVATAR)
	controller.tap(Vector2i(2, 3))
	controller.notify_effects_done()
	t.equal(controller.get_snapshot()["player_position"], Vector2i(2, 3), "avatar retry setup moved position")
	controller.retry()
	var snapshot = controller.get_snapshot()
	t.equal(snapshot["ruleset"], CombatState.RULESET_AVATAR, "avatar retry keeps ruleset")
	t.equal(snapshot["player_position"], Vector2i(1, 3), "avatar retry restores player_start")
	t.equal(_event_type(_last_emitted(), 0), "state_reset", "avatar retry emits state_reset")


func _test_default_controller_stays_phase1(t):
	var controller = BattleController.new()
	var snapshot = controller.get_snapshot()
	t.equal(snapshot["ruleset"], CombatState.RULESET_PHASE1, "default controller snapshot ruleset")
	t.equal(snapshot["movable_cells"], [], "default controller movable cells empty")


func _controller_with_signal(ruleset):
	captured_events = []
	var controller = BattleController.new(ruleset)
	controller.events_emitted.connect(Callable(self, "_capture_events"))
	return controller


func _capture_events(events):
	captured_events.append(events)


func _last_emitted():
	if captured_events.is_empty():
		return []
	return captured_events[captured_events.size() - 1]


func _event_type(events, index):
	if index < 0 or index >= events.size():
		return ""
	return events[index].get("type", "")


func _event(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return event
	return {}


func _has_event(events, event_type):
	return not _event(events, event_type).is_empty()
