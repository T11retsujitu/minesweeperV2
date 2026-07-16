extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")

const LARGE_CONFIG = {
	"w": 12,
	"h": 12,
	"mines": 26,
}


func run(t):
	_test_large_random_seeds(t)
	_test_large_first_reveal_safety(t)
	_test_avatar_create_state_uses_large_random_board(t)


func _test_large_random_seeds(t):
	for seed_value in range(1, 51):
		var a = BoardGenerator.create_random_state(seed_value, null, null, CombatState.RULESET_AVATAR, LARGE_CONFIG)
		var b = BoardGenerator.create_random_state(seed_value, null, null, CombatState.RULESET_AVATAR, LARGE_CONFIG)
		_assert_large_random_state(t, a, "seed %d" % seed_value)
		t.equal(_coord_keys(a.board.get_mine_coords()), _coord_keys(b.board.get_mine_coords()), "large random same seed mines %d" % seed_value)
		t.equal(a.enemy.position, b.enemy.position, "large random same seed enemy %d" % seed_value)
		t.equal(a.player.position, b.player.position, "large random same seed player %d" % seed_value)


func _test_large_first_reveal_safety(t):
	var base = BoardGenerator.create_random_state(314159, null, null, CombatState.RULESET_AVATAR, LARGE_CONFIG)
	var first_mine = base.board.get_mine_coords()[0]
	var safe = BoardGenerator.create_random_state(314159, first_mine, null, CombatState.RULESET_AVATAR, LARGE_CONFIG)
	t.check(not safe.used_fixture_fallback, "large first reveal does not fallback")
	t.check(not safe.board.get_cell(first_mine).contains_mine, "large first reveal relocates tapped mine")
	t.equal(safe.board.mine_count(), Balance.RANDOM_MINE_COUNT, "large first reveal keeps mine count")
	t.equal(_count_zone_mines(safe), Balance.ENEMY_ZONE_MINES, "large first reveal keeps zone mine count")


func _test_avatar_create_state_uses_large_random_board(t):
	var state = BoardGenerator.create_state(CombatState.MODE_RANDOM, 271828, null, CombatState.RULESET_AVATAR)
	t.check(not state.used_fixture_fallback, "avatar create_state random does not fallback")
	t.equal(state.board.width, Balance.RANDOM_BOARD_W, "avatar create_state random width")
	t.equal(state.board.height, Balance.RANDOM_BOARD_H, "avatar create_state random height")
	t.equal(state.board.mine_count(), Balance.RANDOM_MINE_COUNT, "avatar create_state random mine count")


func _assert_large_random_state(t, state, label):
	t.check(not state.used_fixture_fallback, label + " does not fallback")
	t.equal(state.board.width, 12, label + " width")
	t.equal(state.board.height, 12, label + " height")
	t.equal(state.board.mine_count(), 26, label + " mine count")
	t.equal(_count_zone_mines(state), Balance.ENEMY_ZONE_MINES, label + " enemy zone mines")
	t.check(state.enemy.position.x >= 1 and state.enemy.position.x <= 10, label + " enemy x inner")
	t.check(state.enemy.position.y >= 1 and state.enemy.position.y <= 10, label + " enemy y inner")

	var player_cell = state.board.get_cell(state.player.position)
	t.check(player_cell != null, label + " player in bounds")
	t.check(player_cell != null and not player_cell.contains_mine, label + " player not mine")
	t.check(player_cell != null and player_cell.is_revealed(), label + " player revealed")
	t.check(not _is_enemy_zone(state, state.player.position), label + " player outside enemy zone")
	t.check(state.player.position != state.enemy.position, label + " player not enemy")

	var snapshot = state.to_snapshot()
	t.equal(snapshot["board_width"], 12, label + " snapshot width")
	t.equal(snapshot["board_height"], 12, label + " snapshot height")
	t.equal(snapshot["safe_cells_total"], 144 - 26, label + " snapshot safe total")


func _count_zone_mines(state):
	var count = 0
	for coord in state.board.get_mine_coords():
		if _is_enemy_zone(state, coord):
			count += 1
	return count


func _is_enemy_zone(state, coord):
	return (
		abs(coord.x - state.enemy.position.x) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV
		and abs(coord.y - state.enemy.position.y) <= Balance.EXPLOSION_RADIUS_CHEBYSHEV
	)


func _coord_keys(coords):
	var result = []
	for coord in coords:
		result.append("%d,%d" % [coord.x, coord.y])
	result.sort()
	return result
