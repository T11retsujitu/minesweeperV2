extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")
const BattleController = preload("res://scripts/application/battle_controller.gd")


func run(t):
	_test_balance_watchdog(t)
	_test_aggro_line_uses_bump_as_finisher(t)
	_test_non_adjacent_enemy_tap_does_not_bump(t)
	_test_bump_counter_only_when_enemy_survives(t)
	_test_bump_counter_death_defeats_player(t)
	_test_defuse_mine_recalculates_numbers_and_damages_enemy(t)
	_test_defuse_dud_opens_flagged_safe_cell(t)
	_test_non_adjacent_defuse_rejected(t)
	_test_recovery_defuse_has_no_enemy_damage_and_can_perfect_clear(t)
	_test_outside_territory_defuse_pauses_countdown(t)


func _test_balance_watchdog(t):
	t.check(Balance.BUMP_DAMAGE < Balance.EXPLOSION_ADJACENT_DAMAGE, "bump damage stays below adjacent explosion damage")
	t.check(Balance.DEFUSE_DAMAGE <= Balance.EXPLOSION_ADJACENT_DAMAGE, "defuse damage stays at or below adjacent explosion damage")
	var bump_hits_to_kill = int(ceil(float(Balance.ENEMY_MAX_HP) / float(Balance.BUMP_DAMAGE)))
	var counter_damage_before_kill = (bump_hits_to_kill - 1) * Balance.BUMP_COUNTER_DAMAGE
	t.check(counter_damage_before_kill >= Balance.PLAYER_MAX_HP, "bump-only line is mathematically losing")


func _test_aggro_line_uses_bump_as_finisher(t):
	var state = _avatar_state()

	var t1 = _flag_and_detonate(state, Vector2i(1, 1))
	_assert_state(t, state, 4, 2, 10, Vector2i(1, 3), 1, "aggro T1")
	t.equal(_event_types(t1), ["mine_exploded", "enemy_damaged", "countdown_changed"], "aggro T1 events")
	t.equal(_damage_amount(t1, "enemy_damaged"), Balance.EXPLOSION_ADJACENT_DAMAGE, "aggro T1 enemy damage")

	var t2 = _flag_and_detonate(state, Vector2i(0, 1))
	_assert_state(t, state, 2, 1, 10, Vector2i(1, 3), 2, "aggro T2")
	t.equal(_event_types(t2), ["mine_exploded", "enemy_damaged", "countdown_changed"], "aggro T2 events")
	t.equal(_damage_amount(t2, "enemy_damaged"), Balance.EXPLOSION_ADJACENT_DAMAGE, "aggro T2 enemy damage")

	var t3 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_BUMP, "cell": Vector2i(1, 2)})
	_assert_state(t, state, 1, Balance.ENEMY_COUNTDOWN, 6, Vector2i(1, 3), 3, "aggro T3")
	t.equal(_event_types(t3), ["enemy_bumped", "enemy_damaged", "player_damaged", "countdown_changed", "enemy_attacked", "player_damaged", "countdown_changed"], "aggro T3 events")
	t.equal(_damage_amount(t3, "enemy_damaged", "bump"), Balance.BUMP_DAMAGE, "aggro T3 bump damage")
	t.equal(_damage_amount(t3, "player_damaged", "bump_counter"), Balance.BUMP_COUNTER_DAMAGE, "aggro T3 counter damage")
	t.equal(_damage_amount(t3, "player_damaged", "enemy_attack"), Balance.ENEMY_ATTACK, "aggro T3 countdown attack damage")

	var t4 = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_BUMP, "cell": Vector2i(1, 2)})
	_assert_state(t, state, 0, Balance.ENEMY_COUNTDOWN, 6, Vector2i(1, 3), 4, "aggro T4")
	t.equal(_event_types(t4), ["enemy_bumped", "enemy_damaged", "enemy_died", "combat_won"], "aggro T4 events")
	t.check(not _has_event(t4, "player_damaged"), "aggro T4 finishing bump has no counter")
	t.equal(state.phase, CombatState.PHASE_RECOVERY, "aggro T4 enters recovery")


func _test_non_adjacent_enemy_tap_does_not_bump(t):
	var controller = BattleController.new(CombatState.RULESET_AVATAR)
	controller.state.player.position = Vector2i(5, 6)
	var events = controller.tap(Vector2i(1, 2))
	t.equal(_event_reason(events), "invalid_move_target", "remote enemy tap follows move rejection path")
	t.check(not _has_event(events, "enemy_bumped"), "remote enemy tap does not emit bump")
	t.equal(controller.state.enemy.hp, Balance.ENEMY_MAX_HP, "remote enemy tap deals no damage")
	t.equal(controller.state.turn_count, 0, "remote enemy tap consumes no turn")


func _test_bump_counter_only_when_enemy_survives(t):
	var state = _avatar_state()
	state.enemy.hp = Balance.BUMP_DAMAGE
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_BUMP, "cell": Vector2i(1, 2)})
	t.equal(state.enemy.hp, 0, "lethal bump kills enemy")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP, "lethal bump leaves player undamaged")
	t.check(not _has_player_damage_source(events, "bump_counter"), "lethal bump has no counter event")
	t.check(_has_event(events, "combat_won"), "lethal bump enters recovery")


func _test_bump_counter_death_defeats_player(t):
	var state = _avatar_state()
	state.enemy.hp = Balance.BUMP_DAMAGE + 1
	state.player.hp = Balance.BUMP_COUNTER_DAMAGE
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_BUMP, "cell": Vector2i(1, 2)})
	t.equal(state.enemy.hp, 1, "nonlethal bump leaves enemy alive")
	t.equal(state.player.hp, 0, "counter can kill player")
	t.equal(state.phase, CombatState.PHASE_DEFEAT, "counter death is defeat")
	t.check(_has_player_damage_source(events, "bump_counter"), "counter death emits bump counter damage")
	t.check(_has_event(events, "defeat"), "counter death emits defeat")


func _test_defuse_mine_recalculates_numbers_and_damages_enemy(t):
	var controller = BattleController.new(CombatState.RULESET_AVATAR)
	var state = controller.state
	var mine_cell = Vector2i(0, 3)
	var number_cell = Vector2i(1, 4)
	t.equal(state.board.get_cell(number_cell).adjacent_mine_count, 1, "defuse setup adjacent count before")

	controller.long_press(mine_cell)
	var preview = controller.tap(mine_cell)
	t.equal(_event(preview, "detonation_preview").get("can_defuse", false), true, "adjacent flagged mine preview can defuse")
	var events = controller.confirm_defuse()

	t.equal(_event_types(events), ["mine_defused", "cells_revealed", "enemy_damaged", "countdown_changed"], "defuse mine events")
	t.equal(state.board.get_cell(mine_cell).contains_mine, false, "defuse removes mine")
	t.check(state.board.get_cell(mine_cell).is_revealed(), "defuse reveals removed mine cell")
	t.equal(state.board.get_cell(number_cell).adjacent_mine_count, 0, "defuse recalculates adjacent count")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP - Balance.DEFUSE_DAMAGE, "defuse damages living enemy")
	t.equal(_damage_amount(events, "enemy_damaged", "defuse"), Balance.DEFUSE_DAMAGE, "defuse damage event amount")
	t.equal(state.enemy.countdown, Balance.ENEMY_COUNTDOWN - 1, "defuse advances countdown in territory")


func _test_defuse_dud_opens_flagged_safe_cell(t):
	var state = _avatar_state()
	var dud_cell = Vector2i(1, 4)
	state.board.toggle_flag(dud_cell)
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DEFUSE, "cell": dud_cell})
	t.equal(_event_types(events), ["defuse_dud", "cells_revealed", "countdown_changed"], "defuse dud events")
	t.check(state.board.get_cell(dud_cell).is_revealed(), "defuse dud reveals safe cell")
	t.equal(state.enemy.hp, Balance.ENEMY_MAX_HP, "defuse dud deals no enemy damage")
	t.check(not _has_event(events, "enemy_damaged"), "defuse dud emits no enemy damage")


func _test_non_adjacent_defuse_rejected(t):
	var state = _avatar_state()
	var remote_mine = Vector2i(6, 5)
	state.board.toggle_flag(remote_mine)
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DEFUSE, "cell": remote_mine})
	t.equal(_event_reason(events), "defuse_not_adjacent", "remote defuse rejected as non-adjacent")
	t.equal(state.turn_count, 0, "remote defuse rejection consumes no turn")
	t.check(state.board.is_flagged(remote_mine), "remote defuse rejection keeps flag")


func _test_recovery_defuse_has_no_enemy_damage_and_can_perfect_clear(t):
	var state = _avatar_state(Vector2i(2, 4))
	state.phase = CombatState.PHASE_RECOVERY
	state.enemy.hp = 0
	for cell in state.board.get_all_cells():
		if not cell.contains_mine:
			cell.force_reveal()
	var mine_cell = Vector2i(3, 4)
	state.board.toggle_flag(mine_cell)

	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DEFUSE, "cell": mine_cell})
	t.equal(_event(events, "mine_defused").get("damage", -1), 0, "recovery defuse reports zero enemy damage")
	t.check(not _has_event(events, "enemy_damaged"), "recovery defuse emits no enemy damage")
	t.check(_has_event(events, "perfect_clear"), "recovery defuse can trigger perfect clear")
	t.equal(_event(events, "victory").get("perfect", false), true, "recovery defuse perfect victory")
	t.equal(state.phase, CombatState.PHASE_VICTORY, "recovery defuse reaches victory")


func _test_outside_territory_defuse_pauses_countdown(t):
	var state = _avatar_state(Vector2i(5, 6))
	var mine_cell = Vector2i(6, 5)
	state.board.toggle_flag(mine_cell)
	var before_countdown = state.enemy.countdown
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DEFUSE, "cell": mine_cell})
	t.equal(state.enemy.countdown, before_countdown, "outside defuse keeps countdown frozen")
	t.check(_has_event(events, "countdown_paused"), "outside defuse emits paused countdown")
	t.check(not _has_event(events, "enemy_attacked"), "outside defuse has no enemy attack")
	t.equal(_damage_amount(events, "enemy_damaged", "defuse"), Balance.DEFUSE_DAMAGE, "outside defuse still damages enemy")


func _avatar_state(position = Vector2i(1, 3)):
	var state = BoardGenerator.create_fixture_state(Fixtures.PHASE1_CORE_DEMO, CombatState.RULESET_AVATAR)
	state.player.position = position
	return state


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


func _event_reason(events):
	return _event(events, "turn_rejected").get("reason", "")


func _damage_amount(events, event_type, source = ""):
	for event in events:
		if event.get("type", "") != event_type:
			continue
		if source != "" and str(event.get("source", "")) != source:
			continue
		return int(event.get("amount", 0))
	return 0


func _has_player_damage_source(events, source):
	for event in events:
		if event.get("type", "") == "player_damaged" and str(event.get("source", "")) == source:
			return true
	return false
