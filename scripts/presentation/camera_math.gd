extends RefCounted


static func fit_zoom(board_px, slot_px, margin):
	if board_px.x <= 0.0 or board_px.y <= 0.0:
		return 0.0
	var usable = slot_px - Vector2.ONE * margin * 2.0
	if usable.x <= 0.0 or usable.y <= 0.0:
		return 0.0
	return min(usable.x / board_px.x, usable.y / board_px.y)


static func clamp_center(center, zoom_value, board_rect, slot_size):
	var zoom = max(0.001, zoom_value)
	var visible_size = slot_size / zoom
	var result = center
	var board_center = board_rect.position + board_rect.size * 0.5
	var board_end = board_rect.position + board_rect.size

	if visible_size.x >= board_rect.size.x:
		result.x = board_center.x
	else:
		result.x = clamp(result.x, board_rect.position.x + visible_size.x * 0.5, board_end.x - visible_size.x * 0.5)

	if visible_size.y >= board_rect.size.y:
		result.y = board_center.y
	else:
		result.y = clamp(result.y, board_rect.position.y + visible_size.y * 0.5, board_end.y - visible_size.y * 0.5)

	return result


static func zoom_at_point(old_zoom, new_zoom, anchor_screen, view_center, slot_center):
	var world_anchor = (anchor_screen - slot_center) / old_zoom + view_center
	return world_anchor - (anchor_screen - slot_center) / new_zoom


static func pan_center(view_center, screen_delta, zoom_value):
	return view_center - screen_delta / zoom_value
