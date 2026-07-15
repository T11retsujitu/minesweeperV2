extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const BoardGenerator = preload("res://scripts/generation/board_generator.gd")


func run(t):
	_test_fixture_grid(t)
	_test_flood_reveals_expected_cells(t)
	_test_flood_respects_flags(t)
	_test_flag_and_reveal_guards(t)
	_test_fixture_basics(t)


func _test_fixture_grid(t):
	var state = BoardGenerator.create_fixture_state()
	var expected = [
		[2, 2, 1, 1, 1, 2, 1],
		[-1, -1, 1, 1, -1, 2, -1],
		[3, 3, 1, 1, 1, 3, 2],
		[-1, 1, 1, 1, 1, 1, -1],
		[1, 1, 1, -1, 2, 3, 3],
		[0, 0, 1, 1, 2, -1, -1],
		[0, 0, 0, 0, 1, 2, 2],
	]
	for y in range(Balance.BOARD_H):
		for x in range(Balance.BOARD_W):
			var cell = state.board.get_cell(Vector2i(x, y))
			if expected[y][x] == -1:
				t.check(cell.contains_mine, "fixture mine at (%d,%d)" % [x, y])
			else:
				t.check(not cell.contains_mine, "fixture safe at (%d,%d)" % [x, y])
				t.equal(cell.adjacent_mine_count, expected[y][x], "fixture adjacent at (%d,%d)" % [x, y])


func _test_flood_reveals_expected_cells(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.reveal_cell(Vector2i(1, 4))
	state.board.reveal_cell(Vector2i(2, 4))
	var result = state.board.reveal_cell(Vector2i(1, 5))
	var expected = _keys([
		Vector2i(0, 4),
		Vector2i(0, 5),
		Vector2i(0, 6),
		Vector2i(1, 5),
		Vector2i(1, 6),
		Vector2i(2, 5),
		Vector2i(2, 6),
		Vector2i(3, 5),
		Vector2i(3, 6),
		Vector2i(4, 5),
		Vector2i(4, 6),
	])
	t.check(result["accepted"], "zero flood reveal accepted")
	t.equal(_keys(result["cells_revealed"]), expected, "zero flood reveals 11 fixed cells")
	t.equal(result["cells_revealed"].size(), 11, "zero flood reveal count")


func _test_flood_respects_flags(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.reveal_cell(Vector2i(1, 4))
	state.board.reveal_cell(Vector2i(2, 4))
	state.board.toggle_flag(Vector2i(0, 5))
	var result = state.board.reveal_cell(Vector2i(1, 5))
	var flagged_cell = state.board.get_cell(Vector2i(0, 5))
	t.check(result["accepted"], "flood with flagged neighbor accepted")
	t.check(flagged_cell.is_flagged(), "flag remains after flood")
	t.check(flagged_cell.is_hidden(), "flagged flood cell remains hidden")
	t.check(not result["cells_revealed"].has(Vector2i(0, 5)), "flood result excludes flagged cell")


func _test_flag_and_reveal_guards(t):
	var state = BoardGenerator.create_fixture_state()
	state.board.toggle_flag(Vector2i(4, 2))
	var flagged_reveal = state.board.reveal_cell(Vector2i(4, 2))
	t.check(not flagged_reveal["accepted"], "flagged cell cannot be revealed")

	var revealed_flag = state.board.toggle_flag(Vector2i(1, 2))
	t.check(not revealed_flag["accepted"], "revealed enemy cell cannot be flagged")

	var revealed_tap = state.board.reveal_cell(Vector2i(1, 2))
	t.check(not revealed_tap["accepted"], "revealed cell tap is ignored")


func _test_fixture_basics(t):
	var state = BoardGenerator.create_fixture_state()
	var enemy_cell = state.board.get_cell(state.enemy.position)
	t.equal(state.board.mine_count(), Balance.MINE_COUNT, "fixture mine count")
	t.check(not enemy_cell.contains_mine, "enemy cell is safe")
	t.check(enemy_cell.is_revealed(), "enemy cell is initially revealed")


func _keys(coords):
	var result = []
	for coord in coords:
		result.append("%d,%d" % [coord.x, coord.y])
	result.sort()
	return result
