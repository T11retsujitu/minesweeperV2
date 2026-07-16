extends RefCounted

const Balance = preload("res://scripts/config/game_balance.gd")
const CellModel = preload("res://scripts/domain/cell_model.gd")

# マインスイーパーの隣接8マスはルール定義であり、爆発半径の調整値とは独立。
const ADJACENCY_RADIUS = 1

var width = Balance.BOARD_W
var height = Balance.BOARD_H
var cells = {}
var enemy_position = null


func setup(p_width, p_height, mine_coords, initial_revealed):
	width = p_width
	height = p_height
	cells.clear()
	for y in range(height):
		for x in range(width):
			var coord = Vector2i(x, y)
			cells[coord] = CellModel.new(coord, false)
	for mine_coord in mine_coords:
		if is_in_bounds(mine_coord):
			get_cell(mine_coord).contains_mine = true
	recalculate_adjacent_mine_counts()
	for revealed_coord in initial_revealed:
		if is_in_bounds(revealed_coord):
			get_cell(revealed_coord).force_reveal()


func set_enemy_position(p_enemy_position):
	enemy_position = p_enemy_position


func is_in_bounds(coord):
	return coord.x >= 0 and coord.y >= 0 and coord.x < width and coord.y < height


func get_cell(coord):
	if not is_in_bounds(coord):
		return null
	return cells.get(coord)


func get_all_cells():
	var result = []
	for y in range(height):
		for x in range(width):
			result.append(get_cell(Vector2i(x, y)))
	return result


func get_neighbor_coords(coord):
	var result = []
	for dy in range(-ADJACENCY_RADIUS, ADJACENCY_RADIUS + 1):
		for dx in range(-ADJACENCY_RADIUS, ADJACENCY_RADIUS + 1):
			if dx == 0 and dy == 0:
				continue
			var neighbor = Vector2i(coord.x + dx, coord.y + dy)
			if is_in_bounds(neighbor):
				result.append(neighbor)
	return result


func recalculate_adjacent_mine_counts():
	for cell in get_all_cells():
		cell.adjacent_mine_count = count_adjacent_mines(cell.coord)


func count_adjacent_mines(coord):
	var count = 0
	for neighbor in get_neighbor_coords(coord):
		var neighbor_cell = get_cell(neighbor)
		if neighbor_cell != null and neighbor_cell.contains_mine:
			count += 1
	return count


func get_mine_coords():
	var result = []
	for cell in get_all_cells():
		if cell.contains_mine:
			result.append(cell.coord)
	return result


func mine_count():
	return get_mine_coords().size()


func safe_cell_counts():
	var total = 0
	var revealed = 0
	for cell in get_all_cells():
		if cell.contains_mine:
			continue
		total += 1
		if cell.is_revealed():
			revealed += 1
	return {
		"total": total,
		"revealed": revealed,
	}


func all_safe_cells_revealed():
	for cell in get_all_cells():
		if not cell.contains_mine and not cell.is_revealed():
			return false
	return true


func toggle_flag(coord):
	var cell = get_cell(coord)
	if cell == null:
		return {"accepted": false, "reason": "out_of_bounds", "cell": coord}
	if not cell.toggle_flag():
		return {"accepted": false, "reason": "cell_not_flaggable", "cell": coord}
	return {
		"accepted": true,
		"cell": coord,
		"flagged": cell.is_flagged(),
	}


func set_flag(coord, flagged):
	var cell = get_cell(coord)
	if cell == null:
		return {"accepted": false, "reason": "out_of_bounds", "cell": coord}
	if not cell.set_flagged(flagged):
		return {"accepted": false, "reason": "cell_not_flaggable", "cell": coord}
	return {
		"accepted": true,
		"cell": coord,
		"flagged": cell.is_flagged(),
	}


func is_flagged(coord):
	var cell = get_cell(coord)
	return cell != null and cell.is_flagged()


func reveal_cell(coord):
	var cell = get_cell(coord)
	if cell == null:
		return {"accepted": false, "reason": "out_of_bounds", "cell": coord}
	if not cell.can_reveal():
		return {"accepted": false, "reason": "cell_not_revealable", "cell": coord}
	if cell.contains_mine:
		cell.detonate(true)
		return {
			"accepted": true,
			"kind": "accidental_mine",
			"cell": coord,
			"cells_revealed": [coord],
			"explosion": build_explosion_result(coord),
		}
	var revealed = reveal_safe_area(coord)
	return {
		"accepted": true,
		"kind": "safe",
		"cell": coord,
		"cells_revealed": revealed,
		"adjacent": cell.adjacent_mine_count,
	}


func detonate_flagged_cell(coord):
	var cell = get_cell(coord)
	if cell == null:
		return {"accepted": false, "reason": "out_of_bounds", "cell": coord}
	if not cell.is_flagged() or cell.is_detonated():
		return {"accepted": false, "reason": "cell_not_detonatable", "cell": coord}
	if not cell.contains_mine:
		cell.flag_state = CellModel.FLAG_NONE
		var revealed = reveal_safe_area(coord)
		return {
			"accepted": true,
			"kind": "dud",
			"cell": coord,
			"cells_revealed": revealed,
			"adjacent": cell.adjacent_mine_count,
		}
	cell.detonate(false)
	return {
		"accepted": true,
		"kind": "mine",
		"cell": coord,
		"explosion": build_explosion_result(coord),
	}


func reveal_safe_area(start_coord):
	var revealed = []
	var queued = {}
	var queue = [start_coord]
	queued[start_coord] = true
	while queue.size() > 0:
		var coord = queue.pop_front()
		var cell = get_cell(coord)
		if cell == null or not cell.can_reveal() or cell.contains_mine:
			continue
		cell.reveal()
		revealed.append(coord)
		if cell.adjacent_mine_count != 0:
			continue
		for neighbor in get_neighbor_coords(coord):
			if queued.has(neighbor):
				continue
			var neighbor_cell = get_cell(neighbor)
			if neighbor_cell != null and neighbor_cell.can_reveal() and not neighbor_cell.contains_mine:
				queued[neighbor] = true
				queue.append(neighbor)
	return revealed


func get_cells_in_explosion_range(center):
	var result = []
	for dy in range(-Balance.EXPLOSION_RADIUS_CHEBYSHEV, Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
		for dx in range(-Balance.EXPLOSION_RADIUS_CHEBYSHEV, Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
			var coord = Vector2i(center.x + dx, center.y + dy)
			if is_in_bounds(coord):
				result.append(coord)
	return result


func explosion_damage_at(center, target):
	if not is_in_bounds(center) or not is_in_bounds(target):
		return 0
	var dx = abs(center.x - target.x)
	var dy = abs(center.y - target.y)
	var distance = max(dx, dy)
	if distance > Balance.EXPLOSION_RADIUS_CHEBYSHEV:
		return 0
	if distance == 0:
		return Balance.EXPLOSION_CENTER_DAMAGE
	return Balance.EXPLOSION_ADJACENT_DAMAGE


func preview_detonation(coord):
	var cells_in_range = get_cells_in_explosion_range(coord)
	var damage_map = {}
	for target in cells_in_range:
		damage_map[target] = explosion_damage_at(coord, target)
	var expected_enemy_damage = 0
	var enemy_hit = false
	if enemy_position != null:
		expected_enemy_damage = explosion_damage_at(coord, enemy_position)
		enemy_hit = expected_enemy_damage > 0
	return {
		"cells_in_range": cells_in_range,
		"damage_map": damage_map,
		"enemy_hit": enemy_hit,
		"expected_enemy_damage": expected_enemy_damage,
	}


func build_explosion_result(coord):
	return {
		"center": coord,
		"preview": preview_detonation(coord),
	}
