extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const BoardModel = preload("res://scripts/domain/board_model.gd")
const EnemyModel = preload("res://scripts/domain/enemy_model.gd")
const PlayerModel = preload("res://scripts/domain/player_model.gd")
const CombatState = preload("res://scripts/domain/combat_state.gd")
const Fixtures = preload("res://scripts/generation/fixtures.gd")


static func create_fixture_state(fixture_id = Fixtures.PHASE1_CORE_DEMO, ruleset = CombatState.RULESET_PHASE1):
	var data = Fixtures.get_phase1_core_demo()
	var board_size = data["board_size"]
	var board = BoardModel.new()
	board.setup(board_size.x, board_size.y, data["mines"], data["initial_revealed"])
	board.set_enemy_position(data["enemy_position"])
	var enemy = EnemyModel.new(data["enemy_position"], data["enemy_hp"])
	var player = PlayerModel.new()
	var state = CombatState.new(board, enemy, player, 0, CombatState.MODE_FIXED)
	state.fixture_id = fixture_id
	state.ruleset = ruleset
	if ruleset == CombatState.RULESET_AVATAR and data.has("player_start"):
		state.player.position = data["player_start"]
	return state


static func create_state(mode, seed_value, first_reveal_cell = null, ruleset = CombatState.RULESET_PHASE1):
	if mode == CombatState.MODE_RANDOM:
		return create_random_state(seed_value, first_reveal_cell, null, ruleset)
	return create_fixture_state(Fixtures.PHASE1_CORE_DEMO, ruleset)


static func ensure_first_reveal_safe(state, cell):
	if state == null or state.mode != CombatState.MODE_RANDOM or state.first_reveal_done:
		return false
	var target = state.board.get_cell(cell)
	if target == null or not target.contains_mine:
		return false

	var rng = RandomNumberGenerator.new()
	rng.seed = hash("first_reveal:%d:%d,%d" % [state.seed, cell.x, cell.y])
	var relocation_pool = _first_reveal_relocation_pool(state, cell)
	if relocation_pool.is_empty():
		return false

	var relocation = relocation_pool[rng.randi_range(0, relocation_pool.size() - 1)]
	target.contains_mine = false
	state.board.get_cell(relocation).contains_mine = true
	state.board.recalculate_adjacent_mine_counts()
	state.last_first_reveal_relocation = {
		"from": cell,
		"to": relocation,
	}
	state.record_log(
		"First reveal safety: mine relocated (%d, %d) -> (%d, %d)"
		% [cell.x, cell.y, relocation.x, relocation.y]
	)
	return true


static func create_random_state(seed_value, first_reveal_cell = null, max_tries = null, ruleset = CombatState.RULESET_PHASE1):
	var tries = Balance.GENERATION_MAX_TRIES
	if max_tries != null:
		tries = max_tries
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	for _attempt in range(tries):
		var enemy_position = _random_enemy_position(rng)
		var zone_coords = _zone_coords(enemy_position)
		var zone_mines = _take_random(rng, _without_coord(zone_coords, enemy_position), Balance.ENEMY_ZONE_MINES)
		var outside_mines = _take_random(rng, _outside_zone_coords(zone_coords), Balance.MINE_COUNT - Balance.ENEMY_ZONE_MINES)
		var mines = []
		mines.append_array(zone_mines)
		mines.append_array(outside_mines)
		if mines.size() != Balance.MINE_COUNT:
			continue
		if first_reveal_cell != null:
			if not _apply_first_reveal_safety(rng, mines, first_reveal_cell, enemy_position):
				continue
		var state = _state_from_random_data(seed_value, enemy_position, mines)
		if _is_valid_random_state(state):
			state.ruleset = ruleset
			if ruleset == CombatState.RULESET_AVATAR:
				_apply_random_avatar_start(state, rng)
			return state
	var fallback = create_fixture_state(Fixtures.PHASE1_CORE_DEMO, ruleset)
	fallback.mode = CombatState.MODE_RANDOM
	fallback.seed = seed_value
	fallback.used_fixture_fallback = true
	return fallback


static func _state_from_random_data(seed_value, enemy_position, mines):
	var board = BoardModel.new()
	board.setup(Balance.BOARD_W, Balance.BOARD_H, mines, [enemy_position])
	board.set_enemy_position(enemy_position)
	var enemy = EnemyModel.new(enemy_position, Balance.ENEMY_MAX_HP)
	var player = PlayerModel.new()
	return CombatState.new(board, enemy, player, seed_value, CombatState.MODE_RANDOM)


static func _is_valid_random_state(state):
	if state.board.mine_count() != Balance.MINE_COUNT:
		return false
	var enemy_cell = state.board.get_cell(state.enemy.position)
	if enemy_cell == null or enemy_cell.contains_mine or not enemy_cell.is_revealed():
		return false
	return _count_zone_mines(state.board.get_mine_coords(), state.enemy.position) == Balance.ENEMY_ZONE_MINES


static func _apply_random_avatar_start(state, rng):
	var candidates = _avatar_start_candidates(state)
	var selected = _take_random(rng, candidates, 1)
	if selected.is_empty():
		return
	state.player.position = selected[0]
	state.board.reveal_cell(state.player.position)


static func _avatar_start_candidates(state):
	var result = []
	var zone_coords = _zone_coords(state.enemy.position)
	for coord in _all_coords():
		if coord == state.enemy.position or zone_coords.has(coord):
			continue
		var cell = state.board.get_cell(coord)
		if cell != null and not cell.contains_mine:
			result.append(coord)
	return result


static func _random_enemy_position(rng):
	var min_coord = Balance.EXPLOSION_RADIUS_CHEBYSHEV
	var max_x = Balance.BOARD_W - Balance.EXPLOSION_RADIUS_CHEBYSHEV - 1
	var max_y = Balance.BOARD_H - Balance.EXPLOSION_RADIUS_CHEBYSHEV - 1
	return Vector2i(rng.randi_range(min_coord, max_x), rng.randi_range(min_coord, max_y))


static func _all_coords():
	var result = []
	for y in range(Balance.BOARD_H):
		for x in range(Balance.BOARD_W):
			result.append(Vector2i(x, y))
	return result


static func _zone_coords(enemy_position):
	var result = []
	for dy in range(-Balance.EXPLOSION_RADIUS_CHEBYSHEV, Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
		for dx in range(-Balance.EXPLOSION_RADIUS_CHEBYSHEV, Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
			result.append(Vector2i(enemy_position.x + dx, enemy_position.y + dy))
	return result


static func _outside_zone_coords(zone_coords):
	var result = []
	for coord in _all_coords():
		if not zone_coords.has(coord):
			result.append(coord)
	return result


static func _without_coord(coords, excluded):
	var result = []
	for coord in coords:
		if coord != excluded:
			result.append(coord)
	return result


static func _take_random(rng, source_coords, count):
	var pool = source_coords.duplicate()
	var result = []
	while result.size() < count and pool.size() > 0:
		var index = rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result


static func _apply_first_reveal_safety(rng, mines, first_reveal_cell, enemy_position):
	if not mines.has(first_reveal_cell):
		return true

	var zone_coords = _zone_coords(enemy_position)
	var relocation_pool = []
	if zone_coords.has(first_reveal_cell):
		for coord in _without_coord(zone_coords, enemy_position):
			if coord != first_reveal_cell and not mines.has(coord):
				relocation_pool.append(coord)
	else:
		for coord in _outside_zone_coords(zone_coords):
			if coord != first_reveal_cell and not mines.has(coord):
				relocation_pool.append(coord)

	if relocation_pool.is_empty():
		return false

	mines.erase(first_reveal_cell)
	var relocation = relocation_pool[rng.randi_range(0, relocation_pool.size() - 1)]
	mines.append(relocation)
	return true


static func _first_reveal_relocation_pool(state, first_reveal_cell):
	var zone_coords = _zone_coords(state.enemy.position)
	var source_coords = []
	if zone_coords.has(first_reveal_cell):
		source_coords = _without_coord(zone_coords, state.enemy.position)
	else:
		source_coords = _outside_zone_coords(zone_coords)

	var relocation_pool = []
	for coord in source_coords:
		if coord == first_reveal_cell or coord == state.enemy.position:
			continue
		var candidate = state.board.get_cell(coord)
		if candidate == null or candidate.contains_mine or candidate.is_revealed():
			continue
		relocation_pool.append(coord)
	return relocation_pool


static func _count_zone_mines(mine_coords, enemy_position):
	var zone_coords = _zone_coords(enemy_position)
	var count = 0
	for coord in mine_coords:
		if zone_coords.has(coord):
			count += 1
	return count
