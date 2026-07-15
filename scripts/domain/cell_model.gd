extends RefCounted

const REVEAL_HIDDEN = "hidden"
const REVEAL_REVEALED = "revealed"
const FLAG_NONE = "none"
const FLAG_FLAGGED = "flagged"
const DETONATION_INTACT = "intact"
const DETONATION_DETONATED = "detonated"

var coord = Vector2i.ZERO
var contains_mine = false
var adjacent_mine_count = 0
var reveal_state = REVEAL_HIDDEN
var flag_state = FLAG_NONE
var detonation_state = DETONATION_INTACT


func _init(p_coord = Vector2i.ZERO, p_contains_mine = false):
	coord = p_coord
	contains_mine = p_contains_mine


func is_hidden():
	return reveal_state == REVEAL_HIDDEN


func is_revealed():
	return reveal_state == REVEAL_REVEALED


func is_flagged():
	return flag_state == FLAG_FLAGGED


func is_detonated():
	return detonation_state == DETONATION_DETONATED


func can_reveal():
	return is_hidden() and not is_flagged() and not is_detonated()


func can_toggle_flag():
	return is_hidden() and not is_detonated()


func reveal():
	if not can_reveal():
		return false
	reveal_state = REVEAL_REVEALED
	return true


func force_reveal():
	reveal_state = REVEAL_REVEALED
	flag_state = FLAG_NONE


func set_flagged(flagged):
	if not can_toggle_flag():
		return false
	flag_state = FLAG_FLAGGED if flagged else FLAG_NONE
	return true


func toggle_flag():
	if not can_toggle_flag():
		return false
	flag_state = FLAG_NONE if is_flagged() else FLAG_FLAGGED
	return true


func detonate(mark_revealed):
	if is_detonated():
		return false
	flag_state = FLAG_NONE
	detonation_state = DETONATION_DETONATED
	if mark_revealed:
		reveal_state = REVEAL_REVEALED
	return true


func to_dictionary():
	return {
		"coord": coord,
		"contains_mine": contains_mine,
		"adjacent_mine_count": adjacent_mine_count,
		"reveal_state": reveal_state,
		"flag_state": flag_state,
		"detonation_state": detonation_state,
	}
