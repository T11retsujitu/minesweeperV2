extends Camera2D

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const ViewConfig = preload("res://scripts/presentation/view_config.gd")

var shake_generation = 0


func _ready():
	position_smoothing_enabled = false
	offset = Vector2.ZERO
	make_current()


func refit(board_w, board_h, slot_rect):
	var board_px = Vector2(board_w, board_h) * ViewConfig.CELL_SIZE_PX
	if board_px.x <= 0.0 or board_px.y <= 0.0:
		return
	var usable = slot_rect.size - Vector2.ONE * ViewConfig.FIT_MARGIN_PX * 2.0
	if usable.x <= 1.0 or usable.y <= 1.0:
		return
	var zoom_scalar = min(
		ViewConfig.FIT_MAX_ZOOM,
		min(usable.x / board_px.x, usable.y / board_px.y)
	)
	zoom_scalar = max(0.01, zoom_scalar)
	zoom = Vector2.ONE * zoom_scalar
	var board_center = board_px * 0.5
	var slot_center = slot_rect.get_center()
	var viewport_size = get_viewport_rect().size
	position = board_center - (slot_center - viewport_size * 0.5) / zoom_scalar


func shake(amplitude_scale := 1.0):
	var generation = shake_generation
	var elapsed = 0.0
	var step_sec = 0.025
	var rng = RandomNumberGenerator.new()
	while elapsed < FxConfig.SHAKE_DURATION and generation == shake_generation:
		offset = Vector2(
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE),
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE)
		) * amplitude_scale
		var wait_sec = min(step_sec, FxConfig.SHAKE_DURATION - elapsed)
		await get_tree().create_timer(wait_sec).timeout
		elapsed += wait_sec
	if generation == shake_generation:
		offset = Vector2.ZERO


func reset_shake():
	shake_generation += 1
	offset = Vector2.ZERO
