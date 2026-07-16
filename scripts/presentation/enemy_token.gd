extends Node2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var countdown = 0
var pulse_tween = null
var pulse_active = false
var state_key = {}


func set_display(is_visible, coord, next_countdown):
	var next_key = {
		"visible": bool(is_visible),
		"coord": coord,
		"countdown": int(next_countdown),
	}
	if next_key == state_key:
		return
	state_key = next_key
	visible = bool(is_visible)
	countdown = int(next_countdown)
	position = ViewConfig.entity_anchor(coord)
	if visible and countdown == 1:
		_start_pulse()
	else:
		_stop_pulse()
	queue_redraw()


func _draw():
	if not visible:
		return
	var rect = _badge_rect()
	var color = FxConfig.COLOR_ENEMY_BADGE
	var text = str(countdown)
	if countdown == 1:
		color = FxConfig.COLOR_ENEMY_BADGE_DANGER
		text = "1!"
	draw_rect(rect, color)
	_draw_badge_text(rect, text)


func _badge_rect():
	return Rect2(
		Vector2(
			ViewConfig.CELL_SIZE_PX * 0.5 - FxConfig.ENEMY_BADGE_MARGIN_RIGHT - FxConfig.ENEMY_BADGE_SIZE,
			-ViewConfig.CELL_SIZE_PX + FxConfig.ENEMY_BADGE_MARGIN_TOP
		),
		Vector2(FxConfig.ENEMY_BADGE_SIZE, FxConfig.ENEMY_BADGE_SIZE)
	)


func _draw_badge_text(rect, text):
	var font = ThemeDB.fallback_font
	var font_size = FxConfig.ENEMY_BADGE_FONT_SIZE
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline = rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	var pos = Vector2(rect.position.x + (rect.size.x - text_size.x) * 0.5, baseline)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _start_pulse():
	if pulse_active:
		return
	_stop_pulse()
	pulse_active = true
	pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(self, "modulate:a", FxConfig.ENEMY_BADGE_PULSE_ALPHA, FxConfig.ENEMY_BADGE_PULSE_SEC)
	pulse_tween.tween_property(self, "modulate:a", 1.0, FxConfig.ENEMY_BADGE_PULSE_SEC)


func _stop_pulse():
	pulse_active = false
	if pulse_tween != null:
		pulse_tween.kill()
		pulse_tween = null
	modulate = Color.WHITE
