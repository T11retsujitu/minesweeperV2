extends Node2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var coord = Vector2i.ZERO
var flagged_display = false
var revealed = false
var flagged = false
var detonated = false
var adjacent_count = 0
var territory = false
var movable = false
var revealable = false
var bumpable = false
var previewed = false
var preview_center = false
var preview_damage = ""
var debug_mine = false
var highlight_border_visible = false
var highlight_border_color = FxConfig.COLOR_HIGHLIGHT_MOVABLE_BORDER

var overlay_draw = null
var reveal_pop_rect = null
var flag_pop_rect = null
var flash_rect = null
var flash_tween = null
var reveal_pop_tween = null
var flag_pop_tween = null
var state_key = {}


class FillLayer:
	extends Node2D

	var fill_color = Color.WHITE:
		set(value):
			fill_color = value
			queue_redraw()

	func _draw():
		var inset = ViewConfig.CELL_INSET_PX
		var size = ViewConfig.CELL_SIZE_PX
		draw_rect(Rect2(Vector2(-size * 0.5 + inset, -size * 0.5 + inset), Vector2(size - inset * 2.0, size - inset * 2.0)), fill_color)


class OverlayLayer:
	extends Node2D

	var owner_cell = null

	func _draw():
		if owner_cell == null:
			return
		if owner_cell.flagged_display:
			owner_cell._draw_bomb(self)
		if owner_cell.highlight_border_visible:
			owner_cell._draw_highlight_border(self)


func _ready():
	_build_layers()


func set_coord(value):
	coord = value


func set_display(cell_data, options):
	var next_revealed = cell_data["reveal_state"] == "revealed"
	var next_flagged = cell_data["flag_state"] == "flagged"
	var next_detonated = cell_data["detonation_state"] == "detonated"
	var next_adjacent_count = int(cell_data["adjacent_mine_count"])
	var next_flagged_display = next_flagged and not next_detonated
	var next_movable = bool(options.get("movable", false))
	var next_revealable = bool(options.get("revealable", false))
	var next_bumpable = bool(options.get("bumpable", false))
	var next_previewed = bool(options.get("previewed", false))
	var next_key = {
		"revealed": next_revealed,
		"flagged": next_flagged,
		"detonated": next_detonated,
		"adjacent_count": next_adjacent_count,
		"flagged_display": next_flagged_display,
		"territory": bool(options.get("territory", false)),
		"movable": next_movable,
		"revealable": next_revealable,
		"bumpable": next_bumpable,
		"previewed": next_previewed,
		"preview_center": bool(options.get("preview_center", false)),
		"preview_damage": str(options.get("preview_damage", "")),
		"debug_mine": bool(options.get("debug_mine", false)),
	}
	if next_key == state_key:
		return

	state_key = next_key
	revealed = next_revealed
	flagged = next_flagged
	detonated = next_detonated
	adjacent_count = next_adjacent_count
	flagged_display = next_flagged_display
	territory = bool(next_key["territory"])
	movable = next_movable
	revealable = next_revealable
	bumpable = next_bumpable
	previewed = next_previewed
	preview_center = bool(next_key["preview_center"])
	preview_damage = str(next_key["preview_damage"])
	debug_mine = bool(next_key["debug_mine"])

	highlight_border_visible = movable or revealable or bumpable
	if bumpable:
		highlight_border_color = FxConfig.COLOR_HIGHLIGHT_BUMPABLE_BORDER
	elif movable:
		highlight_border_color = FxConfig.COLOR_HIGHLIGHT_MOVABLE_BORDER
	elif revealable:
		highlight_border_color = FxConfig.COLOR_HIGHLIGHT_REVEALABLE_BORDER

	queue_redraw()
	if overlay_draw != null:
		overlay_draw.queue_redraw()


func flash(color, duration):
	if flash_tween != null:
		flash_tween.kill()
		flash_tween = null
	flash_rect.visible = true
	flash_rect.fill_color = color
	flash_rect.modulate = Color(1, 1, 1, 0.85)
	flash_rect.queue_redraw()
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
	flash_tween.finished.connect(_on_flash_finished)


func flash_attack_glow(duration):
	if flash_tween != null:
		flash_tween.kill()
		flash_tween = null
	flash_rect.visible = true
	flash_rect.fill_color = FxConfig.COLOR_ENEMY_ATTACK_GLOW_START
	flash_rect.modulate = Color.WHITE
	flash_rect.queue_redraw()
	flash_tween = create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash_rect, "fill_color", FxConfig.COLOR_ENEMY_ATTACK_GLOW_END, duration)
	flash_tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
	flash_tween.finished.connect(_on_flash_finished)


func play_reveal_pop():
	if reveal_pop_tween != null:
		reveal_pop_tween.kill()
		reveal_pop_tween = null
	reveal_pop_rect.visible = true
	reveal_pop_rect.fill_color = FxConfig.COLOR_REVEAL_POP
	reveal_pop_rect.scale = Vector2.ONE * FxConfig.REVEAL_POP_START_SCALE
	reveal_pop_rect.modulate = Color.WHITE
	reveal_pop_rect.queue_redraw()
	reveal_pop_tween = create_tween()
	reveal_pop_tween.set_parallel(true)
	reveal_pop_tween.tween_property(reveal_pop_rect, "scale", Vector2.ONE, FxConfig.REVEAL_POP_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reveal_pop_tween.tween_property(reveal_pop_rect, "modulate:a", 0.0, FxConfig.REVEAL_POP_SEC)
	reveal_pop_tween.finished.connect(_on_reveal_pop_finished)


func play_flag_pop(is_flagged):
	if flag_pop_tween != null:
		flag_pop_tween.kill()
		flag_pop_tween = null
	overlay_draw.scale = Vector2.ONE
	overlay_draw.modulate = Color.WHITE
	flag_pop_rect.visible = true
	flag_pop_rect.fill_color = _flag_pop_color(is_flagged)
	flag_pop_rect.modulate = Color.WHITE
	flag_pop_rect.scale = Vector2.ONE
	flag_pop_rect.queue_redraw()
	if is_flagged:
		flag_pop_rect.scale = Vector2.ONE * FxConfig.FLAG_POP_START_SCALE
		overlay_draw.scale = Vector2.ONE * FxConfig.FLAG_POP_START_SCALE
	flag_pop_tween = create_tween()
	flag_pop_tween.set_parallel(true)
	flag_pop_tween.tween_property(flag_pop_rect, "scale", Vector2.ONE, FxConfig.FLAG_POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flag_pop_tween.tween_property(flag_pop_rect, "modulate:a", 0.0, FxConfig.FLAG_POP_SEC)
	flag_pop_tween.tween_property(overlay_draw, "scale", Vector2.ONE, FxConfig.FLAG_POP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flag_pop_tween.finished.connect(_on_flag_pop_finished)


func kill_tweens():
	if flash_tween != null:
		flash_tween.kill()
		flash_tween = null
	if reveal_pop_tween != null:
		reveal_pop_tween.kill()
		reveal_pop_tween = null
	if flag_pop_tween != null:
		flag_pop_tween.kill()
		flag_pop_tween = null


func _draw():
	var rect = _tile_rect()
	draw_style_box(_background_style(), rect)
	if territory:
		draw_rect(rect, FxConfig.COLOR_TERRITORY)
	if movable or revealable or bumpable:
		draw_rect(rect, _highlight_fill_color())
	if previewed:
		draw_rect(rect, _preview_fill_color())
	if revealed and adjacent_count > 0 and not detonated:
		_draw_centered_text(str(adjacent_count), 34, _number_color(adjacent_count))
	if detonated:
		_draw_centered_text("X", 36, Color(1.0, 0.35, 0.22))
	if debug_mine:
		_draw_top_left_text("*", 18, Color(1.0, 0.55, 0.22), Vector2(6.0, 4.0))
	if previewed and preview_damage != "":
		_draw_bottom_right_text(preview_damage, 16, Color(0.08, 0.06, 0.02), Vector2(5.0, 3.0))


func _build_layers():
	overlay_draw = OverlayLayer.new()
	overlay_draw.owner_cell = self
	overlay_draw.position = Vector2.ONE * ViewConfig.CELL_SIZE_PX * 0.5
	add_child(overlay_draw)

	reveal_pop_rect = FillLayer.new()
	reveal_pop_rect.position = Vector2.ONE * ViewConfig.CELL_SIZE_PX * 0.5
	reveal_pop_rect.fill_color = FxConfig.COLOR_REVEAL_POP
	reveal_pop_rect.visible = false
	add_child(reveal_pop_rect)

	flag_pop_rect = FillLayer.new()
	flag_pop_rect.position = Vector2.ONE * ViewConfig.CELL_SIZE_PX * 0.5
	flag_pop_rect.fill_color = FxConfig.COLOR_FLAG_POP
	flag_pop_rect.visible = false
	add_child(flag_pop_rect)

	flash_rect = FillLayer.new()
	flash_rect.position = Vector2.ONE * ViewConfig.CELL_SIZE_PX * 0.5
	flash_rect.visible = false
	add_child(flash_rect)


func _on_flash_finished():
	flash_tween = null
	flash_rect.visible = false
	flash_rect.modulate = Color.WHITE


func _on_reveal_pop_finished():
	reveal_pop_tween = null
	reveal_pop_rect.visible = false
	reveal_pop_rect.modulate = Color.WHITE
	reveal_pop_rect.scale = Vector2.ONE


func _on_flag_pop_finished():
	flag_pop_tween = null
	flag_pop_rect.visible = false
	flag_pop_rect.modulate = Color.WHITE
	flag_pop_rect.scale = Vector2.ONE
	overlay_draw.scale = Vector2.ONE
	overlay_draw.modulate = Color.WHITE


func _background_style():
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	if detonated and not revealed:
		style.bg_color = Color(0.12, 0.13, 0.15)
		style.border_color = Color(0.03, 0.03, 0.04)
	elif revealed:
		style.bg_color = _heat_color(adjacent_count)
		style.border_color = Color(0.48, 0.52, 0.53)
	elif flagged:
		style.bg_color = Color(0.48, 0.16, 0.16)
		style.border_color = Color(0.98, 0.74, 0.18)
	else:
		style.bg_color = Color(0.23, 0.34, 0.40)
		style.border_color = Color(0.45, 0.57, 0.62)
		style.shadow_color = Color(0.04, 0.06, 0.07, 0.35)
		style.shadow_size = 3
	return style


func _tile_rect():
	var inset = ViewConfig.CELL_INSET_PX
	var size = ViewConfig.CELL_SIZE_PX
	return Rect2(Vector2(inset, inset), Vector2(size - inset * 2.0, size - inset * 2.0))


func _centered_tile_rect():
	var inset = ViewConfig.CELL_INSET_PX
	var size = ViewConfig.CELL_SIZE_PX
	return Rect2(Vector2(-size * 0.5 + inset, -size * 0.5 + inset), Vector2(size - inset * 2.0, size - inset * 2.0))


func _highlight_fill_color():
	if bumpable:
		return FxConfig.COLOR_HIGHLIGHT_BUMPABLE
	if movable:
		return FxConfig.COLOR_HIGHLIGHT_MOVABLE
	return FxConfig.COLOR_HIGHLIGHT_REVEALABLE


func _preview_fill_color():
	if preview_center:
		return Color(1.0, 0.36, 0.12, 0.62)
	return Color(1.0, 0.78, 0.22, 0.42)


func _heat_color(value):
	var max_index = FxConfig.COLOR_HEAT_LEVELS.size() - 1
	var index = int(clamp(value, 0, max_index))
	return FxConfig.COLOR_HEAT_LEVELS[index]


func _flag_pop_color(is_flagged):
	var color = FxConfig.COLOR_FLAG_POP
	if not is_flagged:
		color.a *= 0.45
	return color


func _draw_bomb(canvas):
	var side = ViewConfig.CELL_SIZE_PX
	var center = Vector2.ZERO
	var radius = side * 0.27
	var fuse_width = side * 0.045
	var fuse_start = center + Vector2(radius * 0.58, -radius * 0.72)
	var fuse_mid = center + Vector2(radius * 0.92, -radius * 1.08)
	var fuse_end = center + Vector2(radius * 1.18, -radius * 1.26)
	var spark_center = fuse_end + Vector2(radius * 0.16, -radius * 0.08)

	canvas.draw_circle(center, radius, FxConfig.COLOR_BOMB_BODY_RIM)
	canvas.draw_circle(center + Vector2(radius * 0.05, radius * 0.06), radius * 0.91, FxConfig.COLOR_BOMB_BODY)
	canvas.draw_arc(center, radius * 0.68, deg_to_rad(206.0), deg_to_rad(286.0), 16, FxConfig.COLOR_BOMB_HIGHLIGHT, side * 0.025, true)
	canvas.draw_line(fuse_start, fuse_mid, FxConfig.COLOR_BOMB_FUSE, fuse_width, true)
	canvas.draw_line(fuse_mid, fuse_end, FxConfig.COLOR_BOMB_FUSE, fuse_width, true)
	canvas.draw_circle(spark_center, radius * 0.17, FxConfig.COLOR_BOMB_SPARK)


func _draw_highlight_border(canvas):
	var border_width = FxConfig.HIGHLIGHT_BORDER_WIDTH
	var rect = _centered_tile_rect().grow(-border_width * 0.5)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	canvas.draw_rect(rect, highlight_border_color, false, border_width)


func _draw_centered_text(text, font_size, color):
	var font = ThemeDB.fallback_font
	var size = ViewConfig.CELL_SIZE_PX
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline = (size - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var pos = Vector2((size - text_size.x) * 0.5, baseline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_top_left_text(text, font_size, color, offset):
	var font = ThemeDB.fallback_font
	var pos = Vector2(offset.x, offset.y + font.get_ascent(font_size))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_bottom_right_text(text, font_size, color, padding):
	var font = ThemeDB.fallback_font
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos = Vector2(
		ViewConfig.CELL_SIZE_PX - padding.x - text_size.x,
		ViewConfig.CELL_SIZE_PX - padding.y - font.get_descent(font_size)
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _number_color(value):
	if value == 1:
		return Color(0.05, 0.20, 0.78)
	if value == 2:
		return Color(0.00, 0.45, 0.18)
	if value == 3:
		return Color(0.75, 0.06, 0.05)
	if value == 4:
		return Color(0.30, 0.10, 0.64)
	if value == 5:
		return Color(0.58, 0.22, 0.00)
	return Color(0.08, 0.08, 0.08)
