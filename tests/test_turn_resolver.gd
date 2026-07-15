extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const TurnResolver = preload("res://scripts/domain/turn_resolver.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const BattleController = preload("res://scripts/application/battle_controller.gd")


func run(t):
	_test_flag_does_not_advance_turn(t)
	_test_reveal_and_detonate_advance_once(t)
	_test_countdown_and_enemy_attack(t)
	_test_input_lock(t)
	_test_enemy_death_skips_countdown_and_attack(t)
	_test_victory_priority_over_defeat(t)
	_test_player_death_defeat(t)
	_test_detonate_requires_flag(t)
	_test_retry_resets_same_seed(t)


func _test_flag_does_not_advance_turn(t):
	var controller = BattleController.new()
	controller.long_press(Vector2i(1, 1))
	t.equal(controller.state.turn_count, 0, "flag does not advance turn")
	t.equal(controller.state.enemy.countdown, Balance.ENEMY_COUNTDOWN, "flag does not change countdown")


func _test_reveal_and_detonate_advance_once(t):
	var reveal_controller = BattleController.new()
	reveal_controller.tap(Vector2i(1, 4))
	t.equal(reveal_controller.state.turn_count, 1, "safe reveal advances one turn")
	t.equal(reveal_controller.state.enemy.countdown, Balance.ENEMY_COUNTDOWN - 1, "safe reveal decrements countdown once")

	var detonate_controller = BattleController.new()
	detonate_controller.long_press(Vector2i(1, 1))
	detonate_controller.tap(Vector2i(1, 1))
	t.equal(detonate_controller.state.turn_count, 0, "tap flagged cell only previews")
	detonate_controller.confirm_detonation()
	t.equal(detonate_controller.state.turn_count, 1, "detonation advances one turn")
	t.equal(detonate_controller.state.enemy.countdown, Balance.ENEMY_COUNTDOWN - 1, "detonation decrements countdown once")


func _test_countdown_and_enemy_attack(t):
	var state = BoardGenerator.create_fixture_state()
	state.enemy.countdown = 1
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.equal(state.enemy.countdown, Balance.ENEMY_COUNTDOWN, "countdown resets after attack")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP - Balance.ENEMY_ATTACK, "enemy attacks at countdown zero")
	t.equal(state.turn_count, 1, "countdown attack still comes from one input")


func _test_input_lock(t):
	var controller = BattleController.new()
	controller.tap(Vector2i(1, 4))
	var rejected = controller.tap(Vector2i(2, 4))
	t.check(_has_event(rejected, "turn_rejected"), "input is rejected while busy")
	t.equal(controller.state.turn_count, 1, "busy rejection does not advance turn")
	controller.notify_effects_done()
	controller.tap(Vector2i(2, 4))
	t.equal(controller.state.turn_count, 2, "input accepted after effects done")


func _test_enemy_death_skips_countdown_and_attack(t):
	var state = BoardGenerator.create_fixture_state()
	state.enemy.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	state.enemy.countdown = 1
	state.board.toggle_flag(Vector2i(1, 1))
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.equal(state.phase, CombatState.PHASE_VICTORY, "enemy death sets victory")
	t.equal(state.enemy.countdown, 1, "victory skips countdown decrement")
	t.equal(state.player.hp, Balance.PLAYER_MAX_HP, "enemy does not attack on death turn")
	t.check(_has_event(events, "victory"), "victory event emitted")
	t.check(not _has_event(events, "enemy_attacked"), "enemy attack event skipped on victory")


func _test_victory_priority_over_defeat(t):
	var state = BoardGenerator.create_fixture_state()
	state.player.hp = Balance.ACCIDENTAL_MINE_DAMAGE
	state.enemy.hp = Balance.EXPLOSION_ADJACENT_DAMAGE
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 1)})
	t.equal(state.player.hp, 0, "accidental mine can reduce player to zero")
	t.equal(state.enemy.hp, 0, "same explosion can kill enemy")
	t.equal(state.phase, CombatState.PHASE_VICTORY, "victory takes priority over simultaneous defeat")
	t.check(_has_event(events, "victory"), "simultaneous result emits victory")
	t.check(not _has_event(events, "defeat"), "simultaneous result does not emit defeat")


func _test_player_death_defeat(t):
	var state = BoardGenerator.create_fixture_state()
	state.player.hp = Balance.ENEMY_ATTACK
	state.enemy.countdown = 1
	TurnResolver.resolve(state, {"type": TurnResolver.ACTION_REVEAL, "cell": Vector2i(1, 4)})
	t.equal(state.player.hp, 0, "enemy attack can reduce player to zero")
	t.equal(state.phase, CombatState.PHASE_DEFEAT, "player zero hp sets defeat")


func _test_detonate_requires_flag(t):
	var state = BoardGenerator.create_fixture_state()
	var events = TurnResolver.resolve(state, {"type": TurnResolver.ACTION_DETONATE, "cell": Vector2i(1, 1)})
	t.check(_has_event(events, "turn_rejected"), "detonate unflagged cell is rejected")
	t.equal(state.turn_count, 0, "rejected detonate does not advance turn")


func _test_retry_resets_same_seed(t):
	var controller = BattleController.new()
	controller.set_mode(CombatState.MODE_RANDOM, 24680)
	var before = _coord_keys(controller.state.board.get_mine_coords())
	controller.tap(controller.state.board.get_all_cells()[0].coord)
	controller.notify_effects_done()
	controller.retry()
	var after = _coord_keys(controller.state.board.get_mine_coords())
	t.equal(after, before, "retry keeps random board for same seed")
	t.equal(controller.state.seed, 24680, "retry keeps seed")
	t.equal(controller.state.player.hp, Balance.PLAYER_MAX_HP, "retry resets player hp")
	t.equal(controller.state.enemy.hp, Balance.ENEMY_MAX_HP, "retry resets enemy hp")
	t.equal(controller.state.enemy.countdown, Balance.ENEMY_COUNTDOWN, "retry resets countdown")
	t.equal(controller.state.turn_count, 0, "retry resets turn")
	t.equal(controller.state.action_log.size(), 0, "retry clears action log")


func _has_event(events, event_type):
	for event in events:
		if event.get("type", "") == event_type:
			return true
	return false


func _coord_keys(coords):
	var result = []
	for coord in coords:
		result.append("%d,%d" % [coord.x, coord.y])
	result.sort()
	return result
