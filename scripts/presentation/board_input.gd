extends Node

signal tapped(coord)
signal long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var board_world = null
var enabled = true
var press_active = false
var long_press_sent = false
var press_elapsed = 0.0
var press_coord = Vector2i.ZERO


func _ready():
	board_world = get_parent()
	set_process(false)


func set_enabled(value):
	enabled = bool(value)
	if not enabled:
		_clear_press()


func _unhandled_input(event):
	if not enabled:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)


func _process(delta):
	if not press_active:
		return
	press_elapsed += delta
	if press_elapsed >= Balance.LONG_PRESS_SEC:
		long_press_sent = true
		press_active = false
		set_process(false)
		long_pressed.emit(press_coord)


func _handle_mouse_button(event):
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var coord = screen_to_cell(event.position)
			if coord == null:
				return
			long_pressed.emit(coord)
			get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var coord = screen_to_cell(event.position)
		if coord == null:
			return
		_start_press(coord)
		get_viewport().set_input_as_handled()
	else:
		if not press_active and not long_press_sent:
			return
		_finish_press()
		get_viewport().set_input_as_handled()


func _handle_screen_touch(event):
	if event.index != 0:
		return
	if event.pressed:
		var coord = screen_to_cell(event.position)
		if coord == null:
			return
		_start_press(coord)
		get_viewport().set_input_as_handled()
	else:
		if not press_active and not long_press_sent:
			return
		_finish_press()
		get_viewport().set_input_as_handled()


func screen_to_cell(screen_pos):
	if board_world == null:
		return null
	var world = board_world.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var coord = Vector2i(
		int(floor(world.x / ViewConfig.CELL_SIZE_PX)),
		int(floor(world.y / ViewConfig.CELL_SIZE_PX))
	)
	if not board_world.is_coord_on_board(coord):
		return null
	return coord


func _start_press(coord):
	press_active = true
	long_press_sent = false
	press_elapsed = 0.0
	press_coord = coord
	set_process(true)


func _finish_press():
	var should_tap = press_active and not long_press_sent
	var coord = press_coord
	_clear_press()
	if should_tap:
		tapped.emit(coord)


func _clear_press():
	press_active = false
	long_press_sent = false
	press_elapsed = 0.0
	set_process(false)
