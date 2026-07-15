extends RefCounted

const BoardModel = preload("res://scripts/domain/board_model.gd")
const EnemyModel = preload("res://scripts/domain/enemy_model.gd")
const PlayerModel = preload("res://scripts/domain/player_model.gd")

const MODE_FIXED = "fixed"
const MODE_RANDOM = "random"
const PHASE_PLAYING = "playing"
const PHASE_VICTORY = "victory"
const PHASE_DEFEAT = "defeat"

var board = null
var enemy = null
var player = null
var turn_count = 0
var seed = 0
var mode = MODE_FIXED
var fixture_id = ""
var phase = PHASE_PLAYING
var action_log = []
var used_fixture_fallback = false
var first_reveal_done = false
var last_first_reveal_relocation = {}


func _init(p_board = null, p_enemy = null, p_player = null, p_seed = 0, p_mode = MODE_FIXED):
	board = p_board
	enemy = p_enemy
	player = p_player
	seed = p_seed
	mode = p_mode
	phase = PHASE_PLAYING


func is_playing():
	return phase == PHASE_PLAYING


func is_terminal():
	return phase == PHASE_VICTORY or phase == PHASE_DEFEAT


func record_log(line):
	action_log.append(line)


func seed_label():
	if mode == MODE_FIXED:
		return "fixture: " + fixture_id
	return str(seed)


func to_snapshot():
	var board_cells = []
	if board != null:
		for cell in board.get_all_cells():
			board_cells.append(cell.to_dictionary())
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
	}
