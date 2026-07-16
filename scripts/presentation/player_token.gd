extends Node2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var state_key = {}


func set_display(is_visible, coord):
	var next_key = {
		"visible": bool(is_visible),
		"coord": coord,
	}
	if next_key == state_key:
		return
	state_key = next_key
	visible = bool(is_visible)
	position = ViewConfig.entity_anchor(coord)
	queue_redraw()


func _draw():
	if not visible:
		return
	var center = Vector2(0.0, -ViewConfig.CELL_SIZE_PX * 0.5)
	_draw_diamond(center, FxConfig.PLAYER_MARKER_OUTLINE_SIZE, Color(1.0, 1.0, 1.0, 0.88))
	_draw_diamond(center, FxConfig.PLAYER_MARKER_SIZE, FxConfig.COLOR_PLAYER_MARKER)


func _draw_diamond(center, square_size, color):
	var radius = square_size / sqrt(2.0)
	var points = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)
