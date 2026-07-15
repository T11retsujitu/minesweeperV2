extends RefCounted

signal events_emitted(events)
signal state_reset(state)

const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")

var state = null
var mode = CombatState.MODE_FIXED
var seed = 1
var is_busy = false
var pending_detonation_cell = null
var last_events = []


func _init():
	state = BoardGenerator.create_fixture_state()
	mode = state.mode
	seed = state.seed


func tap(cell):
	if is_busy:
		return _reject("input_locked", cell)
	if state == null or not state.is_playing():
		return _reject("state_not_playing", cell)
	if state.board.is_flagged(cell):
		pending_detonation_cell = cell
		last_events = [{
			"type": "detonation_preview",
			"cell": cell,
			"preview": state.board.preview_detonation(cell),
		}]
		events_emitted.emit(last_events)
		return last_events
	var relocation_event = null
	if BoardGenerator.ensure_first_reveal_safe(state, cell):
		relocation_event = {
			"type": "mine_relocated",
			"from": state.last_first_reveal_relocation["from"],
			"to": state.last_first_reveal_relocation["to"],
		}
	return _consume_turn({"type": TurnResolver.ACTION_REVEAL, "cell": cell}, relocation_event)


func long_press(cell):
	if is_busy:
		return _reject("input_locked", cell)
	if state == null or not state.is_playing():
		return _reject("state_not_playing", cell)
	var result = state.board.toggle_flag(cell)
	if not result["accepted"]:
		return _reject(result["reason"], cell)
	last_events = [{
		"type": "flag_toggled",
		"cell": cell,
		"flagged": result["flagged"],
	}]
	events_emitted.emit(last_events)
	return last_events


func confirm_detonation():
	if is_busy:
		return _reject("input_locked", pending_detonation_cell)
	if pending_detonation_cell == null:
		return _reject("no_pending_detonation", Vector2i.ZERO)
	var cell = pending_detonation_cell
	pending_detonation_cell = null
	return _consume_turn({"type": TurnResolver.ACTION_DETONATE, "cell": cell})


func cancel_detonation():
	pending_detonation_cell = null
	last_events = [{"type": "detonation_cancelled"}]
	events_emitted.emit(last_events)
	return last_events


func notify_effects_done():
	is_busy = false


func retry():
	state = BoardGenerator.create_state(mode, seed)
	is_busy = false
	pending_detonation_cell = null
	last_events = [{"type": "state_reset", "reason": "retry"}]
	state_reset.emit(state)
	events_emitted.emit(last_events)
	return last_events


func set_mode(next_mode, next_seed = null):
	mode = next_mode
	if next_seed != null:
		seed = next_seed
	elif mode == CombatState.MODE_FIXED:
		seed = 0
	elif seed == 0:
		seed = _make_new_seed()
	state = BoardGenerator.create_state(mode, seed)
	is_busy = false
	pending_detonation_cell = null
	last_events = [{"type": "state_reset", "reason": "mode_changed"}]
	state_reset.emit(state)
	events_emitted.emit(last_events)
	return last_events


func regen_same_seed():
	state = BoardGenerator.create_state(mode, seed)
	is_busy = false
	pending_detonation_cell = null
	last_events = [{"type": "state_reset", "reason": "same_seed"}]
	state_reset.emit(state)
	events_emitted.emit(last_events)
	return last_events


func regen_new_seed():
	if mode == CombatState.MODE_FIXED:
		mode = CombatState.MODE_RANDOM
	seed = _make_new_seed()
	state = BoardGenerator.create_state(mode, seed)
	is_busy = false
	pending_detonation_cell = null
	last_events = [{"type": "state_reset", "reason": "new_seed"}]
	state_reset.emit(state)
	events_emitted.emit(last_events)
	return last_events


func get_snapshot():
	return state.to_snapshot()


func _consume_turn(action, prefix_event = null):
	var events = TurnResolver.resolve(state, action)
	if prefix_event != null:
		events.push_front(prefix_event)
	last_events = events
	var accepted = not _events_contain(events, "turn_rejected")
	if accepted:
		is_busy = true
	events_emitted.emit(events)
	return events


func _reject(reason, cell):
	last_events = [{
		"type": "turn_rejected",
		"reason": reason,
		"cell": cell,
	}]
	events_emitted.emit(last_events)
	return last_events


func _events_contain(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return true
	return false


func _make_new_seed():
	var rng = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	return int(rng.randi())
