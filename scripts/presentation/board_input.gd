extends Node

signal tapped(coord)
signal long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

const STATE_IDLE = 0
const STATE_PRESSED = 1
const STATE_PANNING = 2
const STATE_PINCHING = 3
const STATE_CONSUMED = 4

var board_world = null
var enabled = true
var state = STATE_IDLE
var press_elapsed = 0.0
var press_coord = Vector2i.ZERO
var press_has_cell = false
var press_move_total = 0.0
var touch_points = {}
var pinch_start_distance = 0.0
var pinch_start_zoom = 1.0


func _ready():
	board_world = get_parent()
	set_process(false)


func set_enabled(value):
	enabled = bool(value)
	if not enabled:
		_clear_gesture()


func _unhandled_input(event):
	if not enabled:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _process(delta):
	if state != STATE_PRESSED or not press_has_cell:
		return
	press_elapsed += delta
	if press_elapsed >= Balance.LONG_PRESS_SEC:
		state = STATE_CONSUMED
		set_process(false)
		long_pressed.emit(press_coord)


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


func _handle_mouse_button(event):
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if _is_wheel_button(event.button_index):
		if event.pressed:
			_zoom_from_wheel(event.button_index, event.position)
			get_viewport().set_input_as_handled()
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
		_start_press(event.position, screen_to_cell(event.position))
		get_viewport().set_input_as_handled()
	else:
		if state in [STATE_PRESSED, STATE_PANNING, STATE_CONSUMED]:
			_finish_press()
			get_viewport().set_input_as_handled()


func _handle_mouse_motion(event):
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	if state == STATE_PRESSED:
		_update_pressed_motion(event.relative)
		if state == STATE_PANNING:
			_pan_by_relative(event.relative)
		get_viewport().set_input_as_handled()
	elif state == STATE_PANNING:
		_pan_by_relative(event.relative)
		get_viewport().set_input_as_handled()
	elif state == STATE_CONSUMED:
		get_viewport().set_input_as_handled()


func _handle_screen_touch(event):
	if event.pressed:
		touch_points[event.index] = event.position
		if touch_points.size() >= 2:
			_begin_pinch()
			get_viewport().set_input_as_handled()
		elif event.index == 0:
			_start_press(event.position, screen_to_cell(event.position))
			get_viewport().set_input_as_handled()
	else:
		var was_pinching = state == STATE_PINCHING
		touch_points.erase(event.index)
		if was_pinching:
			if touch_points.size() == 1:
				state = STATE_PANNING
				set_process(false)
			else:
				_clear_gesture()
			get_viewport().set_input_as_handled()
		elif state in [STATE_PRESSED, STATE_PANNING, STATE_CONSUMED]:
			_finish_press()
			get_viewport().set_input_as_handled()


func _handle_screen_drag(event):
	touch_points[event.index] = event.position
	if state == STATE_PINCHING:
		_update_pinch()
		get_viewport().set_input_as_handled()
	elif state == STATE_PRESSED and event.index == 0:
		_update_pressed_motion(event.relative)
		if state == STATE_PANNING:
			_pan_by_relative(event.relative)
		get_viewport().set_input_as_handled()
	elif state == STATE_PANNING and touch_points.has(event.index):
		_pan_by_relative(event.relative)
		get_viewport().set_input_as_handled()
	elif state == STATE_CONSUMED:
		get_viewport().set_input_as_handled()


func _start_press(_screen_pos, coord):
	state = STATE_PRESSED
	press_elapsed = 0.0
	press_move_total = 0.0
	press_has_cell = coord != null
	if press_has_cell:
		press_coord = coord
	set_process(press_has_cell)


func _update_pressed_motion(relative):
	press_move_total += relative.length()
	if press_move_total <= Balance.DRAG_TAP_CANCEL_PX:
		return
	state = STATE_PANNING
	press_has_cell = false
	set_process(false)


func _finish_press():
	var should_tap = state == STATE_PRESSED and press_has_cell
	var coord = press_coord
	_clear_gesture()
	if should_tap:
		tapped.emit(coord)


func _begin_pinch():
	state = STATE_PINCHING
	press_has_cell = false
	set_process(false)
	var points = _first_two_touch_points()
	if points.size() < 2:
		return
	pinch_start_distance = max(1.0, points[0].distance_to(points[1]))
	pinch_start_zoom = _camera_zoom()


func _update_pinch():
	var points = _first_two_touch_points()
	if points.size() < 2:
		return
	var distance = max(1.0, points[0].distance_to(points[1]))
	var ratio = distance / pinch_start_distance
	var anchor = (points[0] + points[1]) * 0.5
	var camera = _camera_rig()
	if camera != null:
		camera.zoom_at(anchor, pinch_start_zoom * ratio)


func _zoom_from_wheel(button_index, anchor):
	var next_zoom = _camera_zoom()
	if button_index == MOUSE_BUTTON_WHEEL_UP:
		next_zoom *= ViewConfig.ZOOM_WHEEL_STEP
	else:
		next_zoom /= ViewConfig.ZOOM_WHEEL_STEP
	var camera = _camera_rig()
	if camera != null:
		camera.zoom_at(anchor, next_zoom)


func _pan_by_relative(relative):
	var camera = _camera_rig()
	if camera != null:
		camera.pan_by_screen_delta(relative)


func _camera_zoom():
	var camera = _camera_rig()
	if camera == null:
		return ViewConfig.DEFAULT_ZOOM
	return camera.get_zoom_scalar()


func _camera_rig():
	if board_world == null:
		return null
	return board_world.get_camera_rig()


func _first_two_touch_points():
	var keys = touch_points.keys()
	keys.sort()
	var points = []
	for key in keys:
		points.append(touch_points[key])
		if points.size() >= 2:
			break
	return points


func _is_wheel_button(button_index):
	return button_index == MOUSE_BUTTON_WHEEL_UP or button_index == MOUSE_BUTTON_WHEEL_DOWN


func _clear_gesture():
	state = STATE_IDLE
	press_elapsed = 0.0
	press_move_total = 0.0
	press_has_cell = false
	touch_points = {}
	pinch_start_distance = 0.0
	set_process(false)
