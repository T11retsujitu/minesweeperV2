extends RefCounted

const BoardModel = preload("res://scripts/domain/board_model.gd")
const EnemyModel = preload("res://scripts/domain/enemy_model.gd")
const PlayerModel = preload("res://scripts/domain/player_model.gd")

const MODE_FIXED = "fixed"
const MODE_RANDOM = "random"
const RULESET_PHASE1 = "phase1"
const RULESET_AVATAR = "phase2_avatar"
const PHASE_PLAYING = "playing"
const PHASE_RECOVERY = "recovery"
const PHASE_VICTORY = "victory"
const PHASE_DEFEAT = "defeat"

var board = null
var enemy = null
var player = null
var turn_count = 0
var seed = 0
var mode = MODE_FIXED
var ruleset = RULESET_PHASE1
var fixture_id = ""
var phase = PHASE_PLAYING
var action_log = []
var used_fixture_fallback = false
var first_reveal_done = false
var last_first_reveal_relocation = {}
var accidental_mine_count = 0


func _init(p_board = null, p_enemy = null, p_player = null, p_seed = 0, p_mode = MODE_FIXED):
	board = p_board
	enemy = p_enemy
	player = p_player
	seed = p_seed
	mode = p_mode
	phase = PHASE_PLAYING


func is_playing():
	return phase == PHASE_PLAYING


func is_active():
	return phase == PHASE_PLAYING or phase == PHASE_RECOVERY


func is_terminal():
	return phase == PHASE_VICTORY or phase == PHASE_DEFEAT


func record_log(line):
	action_log.append(line)


func seed_label():
	if mode == MODE_FIXED:
		return "fixture: " + fixture_id
	return str(seed)


func avatar_can_move_to(cell):
	if ruleset != RULESET_AVATAR or not _is_adjacent_to_player(cell):
		return false
	if enemy != null and not enemy.is_dead() and cell == enemy.position:
		return false
	var target = board.get_cell(cell) if board != null else null
	return target != null and target.is_revealed() and not target.is_detonated()


func avatar_can_reveal(cell):
	if ruleset != RULESET_AVATAR or not _is_adjacent_to_player(cell):
		return false
	var target = board.get_cell(cell) if board != null else null
	return target != null and target.can_reveal()


func avatar_movable_cells():
	var result = []
	if ruleset != RULESET_AVATAR or board == null:
		return result
	for y in range(board.height):
		for x in range(board.width):
			var coord = Vector2i(x, y)
			if avatar_can_move_to(coord):
				result.append(coord)
	return result


func avatar_revealable_cells():
	var result = []
	if ruleset != RULESET_AVATAR or board == null:
		return result
	for y in range(board.height):
		for x in range(board.width):
			var coord = Vector2i(x, y)
			if avatar_can_reveal(coord):
				result.append(coord)
	return result


func _is_adjacent_to_player(cell):
	if player == null:
		return false
	var dx = abs(cell.x - player.position.x)
	var dy = abs(cell.y - player.position.y)
	return max(dx, dy) == BoardModel.ADJACENCY_RADIUS


func to_snapshot():
	var board_cells = []
	var safe_counts = {"total": 0, "revealed": 0}
	if board != null:
		for cell in board.get_all_cells():
			board_cells.append(cell.to_dictionary())
		safe_counts = board.safe_cell_counts()
	return {
		"turn_count": turn_count,
		"seed": seed,
		"seed_label": seed_label(),
		"mode": mode,
		"phase": phase,
		"player_hp": player.hp if player != null else 0,
		"enemy_hp": enemy.hp if enemy != null else 0,
		"enemy_countdown": enemy.countdown if enemy != null else 0,
		"enemy_position": enemy.position if enemy != null else Vector2i.ZERO,
		"cells": board_cells,
		"action_log": action_log.duplicate(),
		"used_fixture_fallback": used_fixture_fallback,
		"first_reveal_done": first_reveal_done,
		"accidental_mine_count": accidental_mine_count,
		"safe_cells_total": safe_counts["total"],
		"safe_cells_revealed": safe_counts["revealed"],
		"ruleset": ruleset,
		"player_position": player.position if player != null else Vector2i.ZERO,
		"movable_cells": avatar_movable_cells() if ruleset == RULESET_AVATAR else [],
		"revealable_cells": avatar_revealable_cells() if ruleset == RULESET_AVATAR else [],
	}
