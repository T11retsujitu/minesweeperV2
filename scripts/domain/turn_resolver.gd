extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")

const ACTION_REVEAL = "REVEAL"
const ACTION_DETONATE = "DETONATE"


static func resolve(state, action):
	var events = []
	if state == null or not state.is_playing():
		return [_event("turn_rejected", {"reason": "state_not_playing"})]
	if not action.has("type") or not action.has("cell"):
		return [_event("turn_rejected", {"reason": "invalid_action"})]

	var action_type = action["type"]
	var cell = action["cell"]
	var result = null
	if action_type == ACTION_REVEAL:
		result = state.board.reveal_cell(cell)
	elif action_type == ACTION_DETONATE:
		result = state.board.detonate_flagged_cell(cell)
	else:
		return [_event("turn_rejected", {"reason": "unknown_action", "action_type": action_type})]

	if not result["accepted"]:
		return [_event("turn_rejected", {"reason": result["reason"], "cell": cell})]

	state.turn_count += 1
	if action_type == ACTION_REVEAL:
		state.first_reveal_done = true
	_append_action_events(state, events, action_type, result)
	_apply_explosion_damage(state, events, action_type, result)

	if state.enemy.is_dead():
		events.append(_event("enemy_died", {"enemy_hp": state.enemy.hp}))
		state.phase = CombatState.PHASE_VICTORY
		events.append(_event("victory", {"turn_count": state.turn_count}))
		state.record_log("Victory")
		return events

	var countdown_change = state.enemy.decrement_countdown()
	events.append(_event("countdown_changed", countdown_change))
	state.record_log("Enemy countdown: %d -> %d" % [countdown_change["before"], countdown_change["after"]])

	if state.enemy.countdown <= 0:
		var player_damage = state.player.apply_damage(state.enemy.attack_damage)
		events.append(_event("enemy_attacked", {"damage": state.enemy.attack_damage}))
		events.append(_event("player_damaged", _with_source(player_damage, "enemy_attack")))
		state.record_log("Enemy attack: %d" % state.enemy.attack_damage)
		state.record_log("Player damage: %d, HP=%d" % [player_damage["amount"], player_damage["after"]])
		var reset_change = state.enemy.reset_countdown()
		events.append(_event("countdown_changed", reset_change))
		state.record_log("Enemy countdown: %d -> %d" % [reset_change["before"], reset_change["after"]])

	if state.player.is_dead():
		state.phase = CombatState.PHASE_DEFEAT
		events.append(_event("defeat", {"turn_count": state.turn_count}))
		state.record_log("Defeat")

	return events


static func _append_action_events(state, events, action_type, result):
	var coord = result["cell"]
	if action_type == ACTION_REVEAL and result["kind"] == "safe":
		events.append(_event("cells_revealed", {"cells": result["cells_revealed"], "trigger": coord}))
		state.record_log(
			"Turn %d: reveal (%d, %d) -> safe, adjacent=%d"
			% [state.turn_count, coord.x, coord.y, result["adjacent"]]
		)
	elif action_type == ACTION_REVEAL and result["kind"] == "accidental_mine":
		events.append(_event("cells_revealed", {"cells": result["cells_revealed"], "trigger": coord}))
		events.append(_event("mine_exploded", {"cell": coord, "accidental": true}))
		state.record_log("Turn %d: reveal (%d, %d) -> accidental mine" % [state.turn_count, coord.x, coord.y])
	elif action_type == ACTION_DETONATE and result["kind"] == "mine":
		events.append(_event("mine_exploded", {"cell": coord, "accidental": false}))
	elif action_type == ACTION_DETONATE and result["kind"] == "dud":
		events.append(_event("dud_detonation", {"cell": coord}))
		events.append(_event("cells_revealed", {"cells": result["cells_revealed"], "trigger": coord}))
		state.record_log(
			"Turn %d: detonate (%d, %d) -> dud, adjacent=%d"
			% [state.turn_count, coord.x, coord.y, result["adjacent"]]
		)


static func _apply_explosion_damage(state, events, action_type, result):
	if not result.has("explosion"):
		return

	var coord = result["cell"]
	var enemy_damage = state.board.explosion_damage_at(coord, state.enemy.position)
	if enemy_damage > 0:
		var enemy_damage_result = state.enemy.apply_damage(enemy_damage)
		events.append(_event("enemy_damaged", enemy_damage_result))
	else:
		events.append(_event("enemy_damaged", {"before": state.enemy.hp, "after": state.enemy.hp, "amount": 0}))

	if action_type == ACTION_DETONATE:
		state.record_log("Turn %d: detonate (%d, %d) -> enemy damage=%d" % [state.turn_count, coord.x, coord.y, enemy_damage])

	if action_type == ACTION_REVEAL and result["kind"] == "accidental_mine":
		var player_damage = state.player.apply_damage(Balance.ACCIDENTAL_MINE_DAMAGE)
		events.append(_event("player_damaged", _with_source(player_damage, "accidental_mine")))
		state.record_log("Player damage: %d, HP=%d" % [player_damage["amount"], player_damage["after"]])


static func _event(type, payload):
	var event = payload.duplicate()
	event["type"] = type
	return event


static func _with_source(payload, source):
	var result = payload.duplicate()
	result["source"] = source
	return result
