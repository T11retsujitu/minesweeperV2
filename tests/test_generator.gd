extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const BattleController = preload("res://scripts/application/battle_controller.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")


func run(t):
	_test_same_seed_same_layout(t)
	_test_random_constraints(t)
	_test_first_reveal_safety_relocation(t)
	_test_controller_first_reveal_safety(t)
	_test_controller_first_reveal_safety_is_deterministic(t)
	_test_second_reveal_mine_is_accidental(t)
	_test_generation_fallback(t)


func _test_same_seed_same_layout(t):
	var seeds = [11, 222, 3333]
	for seed_value in seeds:
		var a = BoardGenerator.create_random_state(seed_value)
		var b = BoardGenerator.create_random_state(seed_value)
		t.equal(_coord_keys(a.board.get_mine_coords()), _coord_keys(b.board.get_mine_coords()), "same seed mine layout %d" % seed_value)
		t.equal(a.enemy.position, b.enemy.position, "same seed enemy position %d" % seed_value)


func _test_random_constraints(t):
	var state = BoardGenerator.create_random_state(98765)
	var enemy_cell = state.board.get_cell(state.enemy.position)
	t.equal(state.board.mine_count(), Balance.MINE_COUNT, "random mine count")
	t.check(not enemy_cell.contains_mine, "random enemy cell is safe")
	t.check(enemy_cell.is_revealed(), "random enemy cell is initially revealed")
	t.equal(_count_zone_mines(state), Balance.ENEMY_ZONE_MINES, "random enemy zone has exactly three mines")
	t.equal(enemy_cell.adjacent_mine_count, Balance.ENEMY_ZONE_MINES, "random enemy number is three")


func _test_first_reveal_safety_relocation(t):
	var base = BoardGenerator.create_random_state(13579)
	var zone_mine = _first_zone_mine(base)
	var outside_mine = _first_outside_zone_mine(base)

	var zone_safe = BoardGenerator.create_random_state(13579, zone_mine)
	t.check(not zone_safe.board.get_cell(zone_mine).contains_mine, "zone first reveal mine is relocated")
	t.equal(zone_safe.board.mine_count(), Balance.MINE_COUNT, "zone relocation keeps mine count")
	t.equal(_count_zone_mines(zone_safe), Balance.ENEMY_ZONE_MINES, "zone relocation keeps zone mine count")

	var outside_safe = BoardGenerator.create_random_state(13579, outside_mine)
	t.check(not outside_safe.board.get_cell(outside_mine).contains_mine, "outside first reveal mine is relocated")
	t.equal(outside_safe.board.mine_count(), Balance.MINE_COUNT, "outside relocation keeps mine count")
	t.equal(_count_zone_mines(outside_safe), Balance.ENEMY_ZONE_MINES, "outside relocation keeps zone mine count")


func _test_generation_fallback(t):
	var fallback = BoardGenerator.create_random_state(2468, null, 0)
	var fixture = Fixtures.get_phase1_core_demo()
	t.check(fallback.used_fixture_fallback, "generator reports fixture fallback")
	t.equal(_coord_keys(fallback.board.get_mine_coords()), _coord_keys(fixture["mines"]), "fallback uses fixture mines")
	t.equal(fallback.seed, 2468, "fallback preserves requested seed")


func _test_controller_first_reveal_safety(t):
	var controller = BattleController.new()
	controller.set_mode(CombatState.MODE_RANDOM, 424242)
	var first_tap = _first_zone_mine(controller.state)
	var events = controller.tap(first_tap)
	t.check(_has_event(events, "mine_relocated"), "controller emits relocation event before first reveal")
	t.check(not _has_event(events, "mine_exploded"), "first reveal relocated mine does not explode")
	t.check(controller.state.board.get_cell(first_tap).is_revealed(), "first tapped mine becomes safe revealed cell")
	t.check(not controller.state.board.get_cell(first_tap).contains_mine, "first tapped mine is no longer a mine")
	t.equal(controller.state.player.hp, Balance.PLAYER_MAX_HP, "first reveal safety prevents accidental player damage")
	t.equal(controller.state.board.mine_count(), Balance.MINE_COUNT, "first reveal safety keeps mine count")
	t.equal(_count_zone_mines(controller.state), Balance.ENEMY_ZONE_MINES, "first reveal safety keeps zone mine count")
	t.check(controller.state.first_reveal_done, "first reveal marks first_reveal_done")


func _test_controller_first_reveal_safety_is_deterministic(t):
	var a = BattleController.new()
	a.set_mode(CombatState.MODE_RANDOM, 777777)
	var first_tap = _first_zone_mine(a.state)
	a.tap(first_tap)
	var a_mines = _coord_keys(a.state.board.get_mine_coords())

	var b = BattleController.new()
	b.set_mode(CombatState.MODE_RANDOM, 777777)
	b.tap(first_tap)
	var b_mines = _coord_keys(b.state.board.get_mine_coords())

	t.equal(a_mines, b_mines, "same seed and same first tap relocate deterministically")


func _test_second_reveal_mine_is_accidental(t):
	var controller = BattleController.new()
	controller.set_mode(CombatState.MODE_RANDOM, 888888)
	var safe_first = _first_safe_hidden_cell(controller.state)
	controller.tap(safe_first)
	controller.notify_effects_done()

	var second_mine = _first_hidden_mine(controller.state)
	var events = controller.tap(second_mine)
	t.check(_has_event(events, "mine_exploded"), "second reveal mine explodes normally")
	t.check(not _has_event(events, "mine_relocated"), "second reveal mine is not relocated")
	t.equal(controller.state.player.hp, Balance.PLAYER_MAX_HP - Balance.ACCIDENTAL_MINE_DAMAGE, "second reveal mine damages player")
	t.check(controller.state.board.get_cell(second_mine).is_detonated(), "second reveal mine is detonated")


func _count_zone_mines(state):
	var count = 0
	for coord in state.board.get_mine_coords():
		if abs(coord.x - state.enemy.position.x) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV and abs(coord.y - state.enemy.position.y) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV:
			count += 1
	return count


func _first_zone_mine(state):
	for coord in state.board.get_mine_coords():
		if abs(coord.x - state.enemy.position.x) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV and abs(coord.y - state.enemy.position.y) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV:
			return coord
	return Vector2i.ZERO


func _first_outside_zone_mine(state):
	for coord in state.board.get_mine_coords():
		if abs(coord.x - state.enemy.position.x) > Balance.EXPLOSION_RADIUS_CHEBYSHEV or abs(coord.y - state.enemy.position.y) > Balance.EXPLOSION_RADIUS_CHEBYSHEV:
			return coord
	return Vector2i.ZERO


func _first_safe_hidden_cell(state):
	for cell in state.board.get_all_cells():
		if not cell.contains_mine and cell.is_hidden():
			return cell.coord
	return Vector2i.ZERO


func _first_hidden_mine(state):
	for coord in state.board.get_mine_coords():
		var cell = state.board.get_cell(coord)
		if cell.is_hidden() and not cell.is_detonated():
			return coord
	return Vector2i.ZERO


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
