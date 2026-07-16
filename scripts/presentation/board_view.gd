extends Control

signal cell_tapped(coord)
signal cell_long_pressed(coord)

const Balance = preload("res://scripts/config/game_balance.gd")
const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const CellViewScene = preload("res://scenes/battle/cell_view.tscn")

var grid = null
var cells = {}
var input_enabled = true
var fx_layer = null
var preview_center = null
var preview_damage_map = {}
var preview_cells = []


func _ready():
	_build_grid()


func update_from_snapshot(snapshot, debug_show_mines):
	var enemy_position = snapshot["enemy_position"]
	var enemy_visible = int(snapshot["enemy_hp"]) > 0
	var is_avatar = str(snapshot.get("ruleset", "")) == "phase2_avatar"
	var player_position = snapshot.get("player_position", Vector2i.ZERO)
	var movable_cells = snapshot.get("movable_cells", [])
	var revealable_cells = snapshot.get("revealable_cells", [])
	var bumpable_cells = snapshot.get("bumpable_cells", [])
	var territory_cells = snapshot.get("territory_cells", [])
	for cell_data in snapshot["cells"]:
		var coord = cell_data["coord"]
		if not cells.has(coord):
			continue
		var previewed = preview_cells.has(coord)
		var options = {
			"enemy_visible": enemy_visible and coord == enemy_position,
			"enemy_countdown": int(snapshot["enemy_countdown"]),
			"debug_mine": debug_show_mines and cell_data["contains_mine"] and cell_data["reveal_state"] == "hidden",
			"previewed": previewed,
			"preview_center": preview_center != null and coord == preview_center,
			"preview_damage": preview_damage_map.get(coord, ""),
			"player_here": is_avatar and coord == player_position,
			"movable": is_avatar and movable_cells.has(coord),
			"revealable": is_avatar and revealable_cells.has(coord),
			"bumpable": is_avatar and bumpable_cells.has(coord),
			"territory": territory_cells.has(coord),
		}
		cells[coord].set_display(cell_data, options)


func set_input_enabled(value):
	input_enabled = value
	for coord in cells.keys():
		cells[coord].set_input_enabled(value)


func set_fx_layer(value):
	fx_layer = value


func set_preview(center, preview):
	preview_center = center
	preview_damage_map = preview["damage_map"]
	preview_cells = preview["cells_in_range"]


func clear_preview():
	preview_center = null
	preview_damage_map = {}
	preview_cells = []


func play_reveal_cascade(revealed_cells, trigger):
	var waves = _reveal_waves(revealed_cells, trigger)
	if waves.is_empty():
		return

	var wave_gap = _cascade_wave_gap(waves.size())
	for wave_index in range(waves.size()):
		for coord in waves[wave_index]:
			if cells.has(coord):
				cells[coord].play_reveal_pop()
		if wave_index < waves.size() - 1 and wave_gap > 0.0:
			await get_tree().create_timer(wave_gap).timeout

	if waves.size() == 1:
		await get_tree().create_timer(min(FxConfig.REVEAL_POP_SEC, FxConfig.FLOOD_CASCADE_MAX_SEC)).timeout


func play_flag_pop(coord, flagged):
	if cells.has(coord):
		cells[coord].play_flag_pop(flagged)


func play_explosion(center, accidental):
	if not cells.has(center):
		await get_tree().process_frame
		return

	var elapsed = 0.0
	_flash_explosion_cell(center, true)
	_spawn_explosion_particles(center, true)
	if fx_layer != null:
		await fx_layer.hit_stop()
		elapsed += FxConfig.HIT_STOP_SEC

	await get_tree().create_timer(FxConfig.EXPLOSION_RING_DELAY).timeout
	elapsed += FxConfig.EXPLOSION_RING_DELAY
	for coord in _explosion_ring_cells(center):
		_flash_explosion_cell(coord, false)
		_spawn_explosion_particles(coord, false)

	if fx_layer != null:
		var shake_scale = FxConfig.EXPLOSION_SHAKE_SCALE
		if accidental:
			shake_scale = FxConfig.ACCIDENTAL_EXPLOSION_SHAKE_SCALE
		await fx_layer.shake(shake_scale)
		elapsed += FxConfig.SHAKE_DURATION

	var remaining = max(0.0, FxConfig.EXPLOSION_TOTAL_BLOCK_SEC - elapsed)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout


func play_dud(center):
	if cells.has(center):
		cells[center].flash(Color(1.0, 0.78, 0.20, 0.42), FxConfig.DUD_FLASH_SEC)
	await get_tree().create_timer(FxConfig.DUD_FLASH_SEC).timeout


func play_enemy_attack_glow(coord):
	if cells.has(coord):
		cells[coord].flash_attack_glow(FxConfig.ENEMY_ATTACK_GLOW_SEC)
	await get_tree().create_timer(FxConfig.ENEMY_ATTACK_GLOW_SEC).timeout


func play_bump_flash(coord):
	if cells.has(coord):
		cells[coord].flash(FxConfig.COLOR_BUMP_FLASH, FxConfig.BUMP_FLASH_SEC)
	await get_tree().create_timer(FxConfig.BUMP_FLASH_SEC).timeout


func play_defuse_flash(coord, success):
	if cells.has(coord):
		var color = FxConfig.COLOR_DEFUSE_FLASH
		if not success:
			color = FxConfig.COLOR_DEFUSE_DUD_FLASH
		cells[coord].flash(color, FxConfig.DEFUSE_FLASH_SEC)
	await get_tree().create_timer(FxConfig.DEFUSE_FLASH_SEC).timeout


func _explosion_ring_cells(center):
	var targets = []
	for y in range(center.y - Balance.EXPLOSION_RADIUS_CHEBYSHEV, center.y + Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
		for x in range(center.x - Balance.EXPLOSION_RADIUS_CHEBYSHEV, center.x + Balance.EXPLOSION_RADIUS_CHEBYSHEV + 1):
			var coord = Vector2i(x, y)
			if coord != center and cells.has(coord):
				targets.append(coord)
	return targets


func _flash_explosion_cell(coord, is_center):
	var color = Color(1.0, 0.78, 0.20, 0.76)
	if is_center:
		color = Color(1.0, 0.24, 0.10, 0.88)
	cells[coord].flash(color, FxConfig.EXPLOSION_FLASH_SEC)


func _spawn_explosion_particles(coord, is_center):
	if fx_layer == null:
		return
	var global_pos = cells[coord].get_global_rect().get_center()
	fx_layer.spawn_explosion_particles(global_pos, is_center)


func debug_cell_canvas_position(coord):
	if not cells.has(coord):
		return Vector2.ZERO
	return cells[coord].get_global_rect().get_center()


func _reveal_waves(revealed_cells, trigger):
	var groups = {}
	for coord in revealed_cells:
		if not cells.has(coord):
			continue
		var distance = max(abs(coord.x - trigger.x), abs(coord.y - trigger.y))
		if not groups.has(distance):
			groups[distance] = []
		groups[distance].append(coord)

	var distances = groups.keys()
	distances.sort()
	var waves = []
	for distance in distances:
		waves.append(groups[distance])
	return waves


func _cascade_wave_gap(wave_count):
	if wave_count <= 1:
		return 0.0
	var gap_count = wave_count - 1
	return min(FxConfig.FLOOD_WAVE_SEC, FxConfig.FLOOD_CASCADE_MAX_SEC / float(gap_count))


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
