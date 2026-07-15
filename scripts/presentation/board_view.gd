extends Control

signal cell_tapped(coord)
signal cell_long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")
const CellViewScene = preload("res://scenes/battle/cell_view.tscn")

var grid = null
var cells = {}
var input_enabled = true
var preview_center = null
var preview_damage_map = {}
var preview_cells = []


func _ready():
	_build_grid()


func update_from_snapshot(snapshot, debug_show_mines):
	var enemy_position = snapshot["enemy_position"]
	var enemy_visible = int(snapshot["enemy_hp"]) > 0
	for cell_data in snapshot["cells"]:
		var coord = cell_data["coord"]
		if not cells.has(coord):
			continue
		var previewed = preview_cells.has(coord)
		var options = {
			"enemy_visible": enemy_visible and coord == enemy_position,
			"debug_mine": debug_show_mines and cell_data["contains_mine"] and cell_data["reveal_state"] == "hidden",
			"previewed": previewed,
			"preview_center": preview_center != null and coord == preview_center,
			"preview_damage": preview_damage_map.get(coord, ""),
		}
		cells[coord].set_display(cell_data, options)


func set_input_enabled(value):
	input_enabled = value
	for coord in cells.keys():
		cells[coord].set_input_enabled(value)


func set_preview(center, preview):
	preview_center = center
	preview_damage_map = preview["damage_map"]
	preview_cells = preview["cells_in_range"]


func clear_preview():
	preview_center = null
	preview_damage_map = {}
	preview_cells = []


func flash_explosion(center):
	var targets = []
	for y in range(center.y - Balance.EXPLOSION_RADIUS_CHEBYSHEV, center.y + Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
		for x in range(center.x - Balance.EXPLOSION_RADIUS_CHEBYSHEV, center.x + Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
			var coord = Vector2i(x, y)
			if cells.has(coord):
				targets.append(coord)
	for coord in targets:
		var color = Color(1.0, 0.78, 0.20, 0.76)
		if coord == center:
			color = Color(1.0, 0.24, 0.10, 0.88)
		cells[coord].flash(color, 0.42)
	await get_tree().create_timer(0.42).timeout


func _build_grid():
	var frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.10, 0.13, 0.15)
	frame_style.border_color = Color(0.30, 0.37, 0.40)
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.corner_radius_top_left = 6
	frame_style.corner_radius_top_right = 6
	frame_style.corner_radius_bottom_left = 6
	frame_style.corner_radius_bottom_right = 6
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	frame.add_child(margin)

	grid = GridContainer.new()
	grid.columns = Balance.BOARD_W
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	margin.add_child(grid)

	for y in range(Balance.BOARD_H):
		for x in range(Balance.BOARD_W):
			var coord = Vector2i(x, y)
			var cell_view = CellViewScene.instantiate()
			cell_view.set_coord(coord)
			cell_view.tapped.connect(_on_cell_tapped)
			cell_view.long_pressed.connect(_on_cell_long_pressed)
			grid.add_child(cell_view)
			cells[coord] = cell_view


func _on_cell_tapped(coord):
	if input_enabled:
		cell_tapped.emit(coord)


func _on_cell_long_pressed(coord):
	if input_enabled:
		cell_long_pressed.emit(coord)
