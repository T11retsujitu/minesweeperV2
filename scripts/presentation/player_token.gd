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
	_draw_shadow(Vector2(0.0, -2.0), Vector2(24.0, 7.0), Color(0.0, 0.0, 0.0, 0.24))
	_draw_body()
	var center = Vector2(0.0, -ViewConfig.TOKEN_HEIGHT_PX + 18.0)
	_draw_diamond(center, FxConfig.PLAYER_MARKER_OUTLINE_SIZE, Color(1.0, 1.0, 1.0, 0.88))
	_draw_diamond(center, FxConfig.PLAYER_MARKER_SIZE, FxConfig.COLOR_PLAYER_MARKER)


func _draw_body():
	var outline = PackedVector2Array([
		Vector2(-21.0, -16.0),
		Vector2(-17.0, -60.0),
		Vector2(0.0, -72.0),
		Vector2(17.0, -60.0),
		Vector2(21.0, -16.0),
		Vector2(10.0, -8.0),
		Vector2(-10.0, -8.0),
	])
	var fill = PackedVector2Array([
		Vector2(-16.0, -18.0),
		Vector2(-13.0, -56.0),
		Vector2(0.0, -65.0),
		Vector2(13.0, -56.0),
		Vector2(16.0, -18.0),
		Vector2(7.0, -13.0),
		Vector2(-7.0, -13.0),
	])
	draw_colored_polygon(outline, Color(1.0, 1.0, 1.0, 0.86))
	draw_colored_polygon(fill, FxConfig.COLOR_PLAYER_MARKER)
	draw_line(Vector2(-10.0, -34.0), Vector2(10.0, -34.0), Color(1.0, 1.0, 1.0, 0.30), 2.0, true)


func _draw_shadow(center, scale, color):
	draw_set_transform(center, 0.0, scale)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_diamond(center, square_size, color):
	var radius = square_size / sqrt(2.0)
	var points = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)
