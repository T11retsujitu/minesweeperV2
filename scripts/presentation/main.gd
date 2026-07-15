extends Control

const BattleScreenScene = preload("res://scenes/battle/battle_screen.tscn")

var battle_screen = null
var debug_screenshot_path = ""
var debug_quit_frames = -1
var debug_actions_text = ""


func _ready():
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
	elif command.begins_with("wait:"):
		var frames = int(command.substr("wait:".length()))
		for _frame_index in range(frames):
			await get_tree().process_frame


func _parse_coord(text):
	var comma_index = text.find(",")
	if comma_index < 0:
		return Vector2i.ZERO
	return Vector2i(int(text.substr(0, comma_index)), int(text.substr(comma_index + 1)))


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
