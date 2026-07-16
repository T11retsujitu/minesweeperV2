extends Control

const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")
const Balance = preload("res://scripts/config/game_balance.gd")

var battle_screen = null
var debug_screenshot_path = ""
var debug_quit_frames = -1
var debug_actions_text = ""


func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_screen = BattleScreenScene.instantiate()
	battle_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(battle_screen)
	if OS.is_debug_build():
		_parse_debug_args()
		_run_debug_flow.call_deferred()


func _parse_debug_args():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--debug-screenshot="):
			debug_screenshot_path = arg.substr("--debug-screenshot=".length())
		elif arg.begins_with("--debug-quit-frames="):
			debug_quit_frames = int(arg.substr("--debug-quit-frames=".length()))
		elif arg.begins_with("--debug-actions="):
			debug_actions_text = arg.substr("--debug-actions=".length())


func _run_debug_flow():
	await get_tree().process_frame
	if debug_actions_text != "":
		await _run_debug_actions(debug_actions_text)
	if debug_screenshot_path != "":
		await _wait_for_screenshot_frames()
		_save_screenshot(debug_screenshot_path)
	if debug_quit_frames >= 0:
		for _frame_index in range(debug_quit_frames):
			await get_tree().process_frame
		get_tree().quit()


func _run_debug_actions(actions_text):
	var commands = actions_text.split(";", false)
	for command_text in commands:
		var command = command_text.strip_edges()
		if command == "":
			continue
		await _run_debug_command(command)
		await get_tree().process_frame
		await battle_screen.debug_wait_until_idle()


func _run_debug_command(command):
	if command.begins_with("tap:"):
		battle_screen.debug_tap(_parse_coord(command.substr("tap:".length())))
	elif command.begins_with("flag:"):
		battle_screen.debug_flag(_parse_coord(command.substr("flag:".length())))
	elif command.begins_with("click:"):
		await _push_mouse_click(_parse_coord(command.substr("click:".length())), MOUSE_BUTTON_LEFT)
	elif command.begins_with("rclick:"):
		await _push_mouse_click(_parse_coord(command.substr("rclick:".length())), MOUSE_BUTTON_RIGHT)
	elif command.begins_with("presshold:"):
		await _push_mouse_presshold(_parse_coord(command.substr("presshold:".length())))
	elif command.begins_with("drag:"):
		var points = _parse_drag_points(command.substr("drag:".length()))
		await _push_mouse_drag(points[0], points[1])
	elif command.begins_with("wheel:"):
		await _push_mouse_wheel(command.substr("wheel:".length()))
	elif command == "zoomstate":
		_print_zoomstate()
	elif command == "mode:fixed":
		battle_screen.debug_set_mode("fixed")
	elif command == "mode:random":
		battle_screen.debug_set_mode("random")
	elif command == "sameseed":
		battle_screen.debug_same_seed()
	elif command == "newseed":
		battle_screen.debug_new_seed()
	elif command == "help":
		battle_screen.debug_open_help()
	elif command == "mines:on":
		battle_screen.debug_set_show_mines(true)
	elif command == "mines:off":
		battle_screen.debug_set_show_mines(false)
	elif command == "confirm":
		battle_screen.debug_confirm()
	elif command == "cancel":
		battle_screen.debug_cancel()
	elif command == "retry":
		battle_screen.debug_retry()
	elif command == "finish":
		battle_screen.debug_finish()
	elif command.begins_with("wait:"):
		var frames = int(command.substr("wait:".length()))
		for _frame_index in range(frames):
			await get_tree().process_frame


func _push_mouse_click(coord, button_index):
	var canvas_position = battle_screen.debug_cell_canvas_position(coord)
	var press = InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = canvas_position
	press.global_position = canvas_position
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release = InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = canvas_position
	release.global_position = canvas_position
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _push_mouse_presshold(coord):
	var canvas_position = battle_screen.debug_cell_canvas_position(coord)
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = canvas_position
	press.global_position = canvas_position
	get_viewport().push_input(press, true)
	await get_tree().create_timer(Balance.LONG_PRESS_SEC + 0.1).timeout

	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = canvas_position
	release.global_position = canvas_position
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _push_mouse_drag(from_pos, to_pos):
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_pos
	press.global_position = from_pos
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var current = from_pos
	var steps = 5
	for step in range(1, steps + 1):
		var next_pos = from_pos.lerp(to_pos, float(step) / float(steps))
		var motion = InputEventMouseMotion.new()
		motion.position = next_pos
		motion.global_position = next_pos
		motion.relative = next_pos - current
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		current = next_pos
		await get_tree().process_frame

	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to_pos
	release.global_position = to_pos
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _push_mouse_wheel(command_text):
	var at_index = command_text.find("@")
	if at_index < 0:
		return
	var direction = command_text.substr(0, at_index)
	var button_index = MOUSE_BUTTON_WHEEL_UP
	if direction == "down":
		button_index = MOUSE_BUTTON_WHEEL_DOWN
	var position = _parse_screen_pos(command_text.substr(at_index + 1))

	var press = InputEventMouseButton.new()
	press.button_index = button_index
	press.pressed = true
	press.position = position
	press.global_position = position
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release = InputEventMouseButton.new()
	release.button_index = button_index
	release.pressed = false
	release.position = position
	release.global_position = position
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _print_zoomstate():
	var state = battle_screen.debug_camera_state()
	print("camera center=", state.get("center", Vector2.ZERO), " zoom=", state.get("zoom", 0.0))


func _parse_coord(text):
	var comma_index = text.find(",")
	if comma_index < 0:
		return Vector2i.ZERO
	return Vector2i(int(text.substr(0, comma_index)), int(text.substr(comma_index + 1)))


func _parse_drag_points(text):
	var parts = text.split(",", false)
	if parts.size() < 4:
		return [Vector2.ZERO, Vector2.ZERO]
	return [
		Vector2(float(parts[0]), float(parts[1])),
		Vector2(float(parts[2]), float(parts[3])),
	]


func _parse_screen_pos(text):
	var comma_index = text.find(",")
	if comma_index < 0:
		return Vector2.ZERO
	return Vector2(float(text.substr(0, comma_index)), float(text.substr(comma_index + 1)))


func _save_screenshot(path):
	if DisplayServer.get_name() == "headless":
		print("Debug screenshot skipped: headless display server")
		return
	var directory = path.get_base_dir()
	if directory != "":
		DirAccess.make_dir_recursive_absolute(directory)
	var image = get_viewport().get_texture().get_image()
	var error = image.save_png(path)
	if error != OK:
		push_error("Failed to save debug screenshot: %s" % path)


func _wait_for_screenshot_frames():
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
