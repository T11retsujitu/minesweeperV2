extends SceneTree

const MANIFEST_PATH = "res://tools/asset_manifest.json"
const CHROMA_HARD_THRESHOLD = 0.22
const CHROMA_SOFT_THRESHOLD = 0.35
const ALPHA_CUTOFF = 8
const BOTTOM_MARGIN_PX = 4


func _initialize():
	quit(_run())


func _run():
	var args = _parse_args()
	if args["error"] != "":
		print("ERROR: " + args["error"])
		return 1

	var manifest_result = _load_manifest()
	if manifest_result["error"] != "":
		print("ERROR: " + manifest_result["error"])
		return 1

	var manifest = manifest_result["manifest"]
	var palette = _parse_palette(manifest.get("palette", []))
	var assets = manifest.get("assets", [])
	var processed = 0
	var skipped = 0
	var errors = []
	var found_only = args["only"] == ""

	for asset in assets:
		var id = str(asset.get("id", ""))
		if args["only"] != "" and id != args["only"]:
			continue
		found_only = true

		if args["placeholders"]:
			var placeholder_error = _write_placeholder(asset, palette)
			if placeholder_error == "":
				processed += 1
				print("PLACEHOLDER " + id + " -> " + str(asset.get("target", "")))
			else:
				errors.append(id + ": " + placeholder_error)
			continue

		var source_path = _project_path(str(asset.get("source", "")))
		if not FileAccess.file_exists(source_path):
			skipped += 1
			print("SKIP " + id + " missing source " + str(asset.get("source", "")))
			continue

		var process_error = _process_asset(asset, palette)
		if process_error == "":
			processed += 1
			print("PROCESSED " + id + " -> " + str(asset.get("target", "")))
		else:
			errors.append(id + ": " + process_error)

	if not found_only:
		errors.append("unknown --only id: " + args["only"])

	print("ASSET PIPELINE SUMMARY: processed=%d skipped=%d errors=%d" % [processed, skipped, errors.size()])
	for error in errors:
		print("ERROR: " + error)
	return 0 if errors.is_empty() else 1


func _parse_args():
	var result = {
		"placeholders": false,
		"only": "",
		"error": "",
	}
	var args = OS.get_cmdline_user_args()
	var index = 0
	while index < args.size():
		var arg = str(args[index])
		if arg == "--":
			pass
		elif arg == "--placeholders":
			result["placeholders"] = true
		elif arg == "--only":
			index += 1
			if index >= args.size():
				result["error"] = "--only requires an asset id"
				return result
			result["only"] = str(args[index])
		elif arg.begins_with("--only="):
			result["only"] = arg.substr("--only=".length())
		else:
			result["error"] = "unknown argument: " + arg
			return result
		index += 1
	return result


func _load_manifest():
	var result = {
		"manifest": {},
		"error": "",
	}
	if not FileAccess.file_exists(MANIFEST_PATH):
		result["error"] = "manifest not found: " + MANIFEST_PATH
		return result
	var file = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		result["error"] = "failed to open manifest: " + MANIFEST_PATH
		return result
	var text = file.get_as_text()
	var json = JSON.new()
	var parse_error = json.parse(text)
	if parse_error != OK:
		result["error"] = "manifest JSON parse failed at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result["error"] = "manifest root must be an object"
		return result
	result["manifest"] = json.data
	return result


func _process_asset(asset, palette):
	var source_path = _project_path(str(asset.get("source", "")))
	var image = Image.new()
	var load_error = image.load(source_path)
	if load_error != OK:
		return "failed to load source %s error=%d" % [source_path, load_error]
	image.convert(Image.FORMAT_RGBA8)

	var chroma = asset.get("chroma", null)
	if chroma != null:
		_apply_chroma_key(image, Color.html(str(chroma)))

	if str(asset.get("anchor", "fill")) != "fill":
		image = _trim_alpha(image)
		image = _pad_bottom_for_anchor(image, asset)

	var pixel_grid = _vector2i_from_array(asset.get("pixel_grid", [1, 1]))
	image.resize(pixel_grid.x, pixel_grid.y, Image.INTERPOLATE_LANCZOS)
	if bool(asset.get("remap", false)):
		_remap_to_palette(image, palette)

	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [1, 1]))
	image.resize(pixel_grid.x * 2, pixel_grid.y * 2, Image.INTERPOLATE_NEAREST)
	var canvas = _compose_canvas(image, asset, canvas_px)
	if str(asset.get("anchor", "fill")) == "bottom_center":
		_clear_bottom_margin(canvas)

	return _save_image(canvas, str(asset.get("target", "")))


func _apply_chroma_key(image, chroma):
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x, y)
			var distance = _rgb_distance(color, chroma)
			if distance < CHROMA_HARD_THRESHOLD:
				color.a = 0.0
			elif distance < CHROMA_SOFT_THRESHOLD:
				var alpha_scale = (distance - CHROMA_HARD_THRESHOLD) / (CHROMA_SOFT_THRESHOLD - CHROMA_HARD_THRESHOLD)
				color.a *= clamp(alpha_scale, 0.0, 1.0)
			image.set_pixel(x, y, color)


func _trim_alpha(image):
	var min_x = image.get_width()
	var min_y = image.get_height()
	var max_x = -1
	var max_y = -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if int(round(image.get_pixel(x, y).a * 255.0)) >= ALPHA_CUTOFF:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	if max_x < min_x or max_y < min_y:
		return _create_image(1, 1)

	var trimmed = _create_image(max_x - min_x + 1, max_y - min_y + 1)
	trimmed.blit_rect(image, Rect2i(min_x, min_y, trimmed.get_width(), trimmed.get_height()), Vector2i.ZERO)
	return trimmed


func _pad_bottom_for_anchor(image, asset):
	if str(asset.get("anchor", "fill")) != "bottom_center":
		return image
	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [image.get_width(), image.get_height()]))
	var available = max(1.0, float(canvas_px.y - BOTTOM_MARGIN_PX))
	var pad_h = int(ceil(float(image.get_height()) * float(BOTTOM_MARGIN_PX) / available))
	if pad_h <= 0:
		return image
	var padded = _create_image(image.get_width(), image.get_height() + pad_h)
	padded.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	return padded


func _remap_to_palette(image, palette):
	if palette.is_empty():
		return
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color = image.get_pixel(x, y)
			if int(round(color.a * 255.0)) < ALPHA_CUTOFF:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var nearest = _nearest_palette_color(color, palette)
			image.set_pixel(x, y, Color(nearest.r, nearest.g, nearest.b, color.a))


func _nearest_palette_color(color, palette):
	var best = palette[0]
	var best_distance = INF
	for candidate in palette:
		var distance = _rgb_distance(color, candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _compose_canvas(image, asset, canvas_px):
	var canvas = _create_image(canvas_px.x, canvas_px.y)
	var anchor = str(asset.get("anchor", "fill"))
	var position = Vector2i.ZERO
	if anchor == "bottom_center":
		position.x = int(round(float(canvas_px.x - image.get_width()) * 0.5))
		position.y = max(0, canvas_px.y - BOTTOM_MARGIN_PX - image.get_height())
	canvas.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), position)
	return canvas


func _write_placeholder(asset, _palette):
	var canvas_px = _vector2i_from_array(asset.get("canvas_px", [1, 1]))
	var image = _create_image(canvas_px.x, canvas_px.y)
	var id = str(asset.get("id", ""))
	var anchor = str(asset.get("anchor", "fill"))

	match id:
		"tile_hidden":
			_draw_placeholder_hidden_tile(image, false)
		"tile_hidden_b":
			_draw_placeholder_hidden_tile(image, true)
		"tile_floor":
			_draw_placeholder_floor_tile(image, false)
		"tile_floor_b":
			_draw_placeholder_floor_tile(image, true)
		"tile_floor_crater":
			_draw_placeholder_crater_tile(image)
		"overlay_barrel":
			_draw_placeholder_barrel(image)
		"overlay_flag":
			_draw_placeholder_flag(image)
		"player_idle_f1":
			_draw_placeholder_player(image, 0)
		"player_idle_f2":
			_draw_placeholder_player(image, 2)
		"slime_idle_f1":
			_draw_placeholder_slime(image, false)
		"slime_idle_f2":
			_draw_placeholder_slime(image, true)
		"bg_dungeon":
			_draw_placeholder_bg_dungeon(image)
		"hud_panel":
			_draw_placeholder_hud_panel(image)
		"hud_button":
			_draw_placeholder_hud_button(image, false)
		"hud_button_pressed":
			_draw_placeholder_hud_button(image, true)
		"icon_mine":
			_draw_placeholder_icon_mine(image)
		"icon_flag":
			_draw_placeholder_icon_flag(image)
		"fireball_f1":
			_draw_placeholder_fireball(image, 1)
		"fireball_f2":
			_draw_placeholder_fireball(image, 2)
		"fireball_f3":
			_draw_placeholder_fireball(image, 3)
		"smoke_f1":
			_draw_placeholder_smoke(image, 1)
		"smoke_f2":
			_draw_placeholder_smoke(image, 2)
		"smoke_f3":
			_draw_placeholder_smoke(image, 3)
		_:
			_draw_placeholder_floor_tile(image, false)

	if bool(asset.get("seamless_x", false)):
		_enforce_seamless_x_placeholder(image)
	if anchor == "bottom_center":
		_clear_bottom_margin(image)

	return _save_image(image, str(asset.get("target", "")))


func _draw_placeholder_hidden_tile(image, variant_b):
	var w = image.get_width()
	var h = image.get_height()
	var band_h = min(10, h)
	var top_h = h - band_h
	_fill_rect(image, Rect2i(0, 0, w, top_h), _p("#4a4a66"))
	_fill_rect(image, Rect2i(0, 0, w, min(3, top_h)), _p("#8b8ca8"))
	_fill_rect(image, Rect2i(0, top_h, w, band_h), _p("#222234"))
	_fill_rect(image, Rect2i(18, 24, 3, 2), _p("#33334d"))
	_fill_rect(image, Rect2i(54, 34, 2, 2), _p("#33334d"))
	_fill_rect(image, Rect2i(36, 61, 4, 1), _p("#33334d"))
	if variant_b:
		_fill_rect(image, Rect2i(58, 17, 12, 6), _p("#3d5a2e"))
		_fill_rect(image, Rect2i(63, 23, 7, 4), _p("#3d5a2e"))
	_fill_rect(image, Rect2i(0, 0, 1, h), _p("#33334d"))
	_fill_rect(image, Rect2i(w - 1, 0, 1, h), _p("#33334d"))


func _draw_placeholder_floor_tile(image, variant_b):
	var w = image.get_width()
	var h = image.get_height()
	_fill_rect(image, Rect2i(0, 0, w, h), _p("#222234"))
	_fill_rect(image, Rect2i(w / 2, 0, 1, h), _p("#151521"))
	_fill_rect(image, Rect2i(0, h / 2, w, 1), _p("#151521"))
	if variant_b:
		_fill_rect(image, Rect2i(21, 18, 2, 2), _p("#33334d"))
		_fill_rect(image, Rect2i(63, 59, 2, 2), _p("#33334d"))
	_fill_floor_side_mortar(image)


func _draw_placeholder_crater_tile(image):
	_draw_placeholder_floor_tile(image, false)
	var center = Vector2(image.get_width(), image.get_height()) * 0.5
	var radius = min(image.get_width(), image.get_height()) / 3.0
	_fill_circle(image, center, radius, _p("#0a0a10"))
	_fill_circle(image, center + Vector2(-18, -7), radius * 0.28, _p("#151521"))
	_fill_circle(image, center + Vector2(17, 10), radius * 0.22, _p("#151521"))
	_fill_circle(image, center + Vector2(3, -21), radius * 0.18, _p("#151521"))
	_fill_floor_side_mortar(image)


func _fill_floor_side_mortar(image):
	var w = image.get_width()
	var h = image.get_height()
	_fill_rect(image, Rect2i(0, 0, 1, h), _p("#0a0a10"))
	_fill_rect(image, Rect2i(w - 1, 0, 1, h), _p("#0a0a10"))


func _draw_placeholder_barrel(image):
	var center = Vector2(image.get_width(), image.get_height()) * 0.5 + Vector2(0, 3)
	_fill_ellipse(image, center, Vector2(22, 29), _p("#6e5230"))
	_fill_rect(image, Rect2i(int(center.x - 22), int(center.y - 21), 44, 42), _p("#6e5230"))
	_fill_ellipse(image, center + Vector2(0, -21), Vector2(22, 7), _p("#97744a"))
	_fill_ellipse(image, center + Vector2(0, 21), Vector2(22, 7), _p("#4a3623"))
	_fill_rect(image, Rect2i(int(center.x - 22), int(center.y - 13), 44, 5), _p("#33334d"))
	_fill_rect(image, Rect2i(int(center.x - 22), int(center.y + 11), 44, 5), _p("#33334d"))
	_draw_line(image, Vector2(center.x + 7, center.y - 31), Vector2(center.x + 18, center.y - 39), _p("#97744a"), 2)
	_fill_circle(image, Vector2(center.x + 20, center.y - 41), 2.0, _p("#f2b02c"))


func _draw_placeholder_flag(image):
	var center_x = image.get_width() / 2
	_fill_rect(image, Rect2i(center_x - 12, 24, 24, 17), _p("#f5f2e6"))
	_fill_rect(image, Rect2i(center_x - 2, 41, 4, 26), _p("#97744a"))
	_fill_rect(image, Rect2i(center_x - 7, 31, 3, 3), _p("#0a0a10"))
	_fill_rect(image, Rect2i(center_x + 4, 31, 3, 3), _p("#0a0a10"))
	_fill_rect(image, Rect2i(center_x - 2, 37, 4, 2), _p("#0a0a10"))


func _draw_placeholder_player(image, y_offset):
	var foot_y = image.get_height() - BOTTOM_MARGIN_PX + y_offset
	var center_x = image.get_width() / 2
	_fill_circle(image, Vector2(center_x, foot_y - 82), 13.0, _p("#66678a"))
	_fill_rect(image, Rect2i(center_x - 15, foot_y - 69, 30, 43), _p("#66678a"))
	_fill_rect(image, Rect2i(center_x - 18, foot_y - 44, 9, 26), _p("#4a4a66"))
	_fill_rect(image, Rect2i(center_x + 9, foot_y - 44, 9, 26), _p("#4a4a66"))
	_fill_rect(image, Rect2i(center_x - 10, foot_y - 26, 8, 24), _p("#33334d"))
	_fill_rect(image, Rect2i(center_x + 2, foot_y - 26, 8, 24), _p("#33334d"))
	_fill_rect(image, Rect2i(center_x - 2, foot_y - 52, 4, 4), _p("#f2b02c"))


func _draw_placeholder_slime(image, squashed):
	var foot_y = image.get_height() - BOTTOM_MARGIN_PX
	var center = Vector2(image.get_width() * 0.5, foot_y - 20)
	var radius = Vector2(24, 24)
	if squashed:
		radius = Vector2(27, 20)
		center.y += 4
	_fill_ellipse(image, center, radius, _p("#5f8a3d"))
	_fill_rect(image, Rect2i(int(center.x - radius.x), int(center.y), int(radius.x * 2.0), int(radius.y)), _p("#5f8a3d"))
	_fill_rect(image, Rect2i(int(center.x - 9), int(center.y - 4), 4, 4), _p("#0a0a10"))
	_fill_rect(image, Rect2i(int(center.x + 6), int(center.y - 4), 4, 4), _p("#0a0a10"))
	_fill_rect(image, Rect2i(int(center.x - 11), int(center.y - 15), 4, 3), _p("#b3e05e"))


func _draw_placeholder_bg_dungeon(image):
	var top = _p("#0a0a10")
	var bottom = _p("#151521")
	for y in range(image.get_height()):
		var t = float(y) / float(max(1, image.get_height() - 1))
		var color = top.lerp(bottom, t)
		_fill_rect(image, Rect2i(0, y, image.get_width(), 1), color)
	var glow = _p("#7a3b12")
	glow.a = 0.25
	_blend_ellipse(image, Vector2(image.get_width() * 0.25, image.get_height() * 0.34), Vector2(70, 210), glow)
	_blend_ellipse(image, Vector2(image.get_width() * 0.75, image.get_height() * 0.34), Vector2(70, 210), glow)


func _draw_placeholder_hud_panel(image):
	_fill_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), _p("#33334d"))
	_fill_rect(image, Rect2i(24, 24, image.get_width() - 48, image.get_height() - 48), _p("#151521"))


func _draw_placeholder_hud_button(image, pressed):
	var border = _p("#33334d")
	var inner = _p("#222234")
	if pressed:
		border = _p("#222234")
		inner = _p("#151521")
	_fill_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), border)
	_fill_rect(image, Rect2i(12, 10, image.get_width() - 24, image.get_height() - 20), inner)


func _draw_placeholder_icon_mine(image):
	var center = Vector2(image.get_width() * 0.5, image.get_height() * 0.58)
	_fill_circle(image, center, 12.0, _p("#0a0a10"))
	_draw_line(image, center + Vector2(7, -9), center + Vector2(16, -18), _p("#97744a"), 2)
	_fill_circle(image, center + Vector2(18, -20), 2.0, _p("#f2b02c"))


func _draw_placeholder_icon_flag(image):
	var center_x = image.get_width() / 2
	_fill_rect(image, Rect2i(center_x - 7, 9, 14, 10), _p("#f5f2e6"))
	_fill_rect(image, Rect2i(center_x - 1, 19, 2, 14), _p("#97744a"))
	_fill_rect(image, Rect2i(center_x - 4, 13, 2, 2), _p("#0a0a10"))
	_fill_rect(image, Rect2i(center_x + 3, 13, 2, 2), _p("#0a0a10"))


func _draw_placeholder_fireball(image, frame):
	var center = Vector2(image.get_width(), image.get_height()) * 0.5
	if frame == 1:
		_fill_circle(image, center, image.get_width() * 0.25, _p("#f5f2e6"))
	elif frame == 2:
		_fill_circle(image, center, image.get_width() * 0.34, _p("#7a3b12"))
		_fill_circle(image, center, image.get_width() * 0.25, _p("#d97b28"))
	else:
		for point in [Vector2(-30, -10), Vector2(-8, 24), Vector2(22, -24), Vector2(35, 18), Vector2(2, -4)]:
			_fill_circle(image, center + point, 5.0, _p("#d97b28"))


func _draw_placeholder_smoke(image, frame):
	var center = Vector2(image.get_width(), image.get_height()) * 0.5
	var color = _p("#4a4a66")
	color.a = 0.72
	var radius = 18.0
	if frame == 2:
		color.a = 0.50
		radius = 25.0
	elif frame == 3:
		color.a = 0.32
		radius = 31.0
	_fill_circle(image, center, radius, color)


func _enforce_seamless_x_placeholder(image):
	for y in range(image.get_height()):
		var edge_color = image.get_pixel(0, y)
		image.set_pixel(image.get_width() - 1, y, edge_color)


func _fill_rect(image, rect, color):
	var start_x = int(clamp(rect.position.x, 0, image.get_width()))
	var start_y = int(clamp(rect.position.y, 0, image.get_height()))
	var end_x = int(clamp(rect.position.x + rect.size.x, 0, image.get_width()))
	var end_y = int(clamp(rect.position.y + rect.size.y, 0, image.get_height()))
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			image.set_pixel(x, y, color)


func _fill_circle(image, center, radius, color):
	_fill_ellipse(image, center, Vector2(radius, radius), color)


func _fill_ellipse(image, center, radius, color):
	if radius.x <= 0.0 or radius.y <= 0.0:
		return
	var start_x = int(max(0, floor(center.x - radius.x)))
	var end_x = int(min(image.get_width() - 1, ceil(center.x + radius.x)))
	var start_y = int(max(0, floor(center.y - radius.y)))
	var end_y = int(min(image.get_height() - 1, ceil(center.y + radius.y)))
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var dx = (float(x) + 0.5 - center.x) / radius.x
			var dy = (float(y) + 0.5 - center.y) / radius.y
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(x, y, color)


func _blend_ellipse(image, center, radius, color):
	if radius.x <= 0.0 or radius.y <= 0.0:
		return
	var start_x = int(max(0, floor(center.x - radius.x)))
	var end_x = int(min(image.get_width() - 1, ceil(center.x + radius.x)))
	var start_y = int(max(0, floor(center.y - radius.y)))
	var end_y = int(min(image.get_height() - 1, ceil(center.y + radius.y)))
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var dx = (float(x) + 0.5 - center.x) / radius.x
			var dy = (float(y) + 0.5 - center.y) / radius.y
			var distance = dx * dx + dy * dy
			if distance <= 1.0:
				var alpha = color.a * (1.0 - distance)
				_blend_pixel(image, x, y, Color(color.r, color.g, color.b, alpha))


func _draw_line(image, from_pos, to_pos, color, width):
	var distance = from_pos.distance_to(to_pos)
	var steps = int(max(1.0, ceil(distance)))
	var radius = max(0.5, float(width) * 0.5)
	for step in range(steps + 1):
		var t = float(step) / float(steps)
		_fill_circle(image, from_pos.lerp(to_pos, t), radius, color)


func _blend_pixel(image, x, y, color):
	var dst = image.get_pixel(x, y)
	var a = clamp(color.a, 0.0, 1.0)
	var out_alpha = a + dst.a * (1.0 - a)
	if out_alpha <= 0.0:
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var out = Color(
		(color.r * a + dst.r * dst.a * (1.0 - a)) / out_alpha,
		(color.g * a + dst.g * dst.a * (1.0 - a)) / out_alpha,
		(color.b * a + dst.b * dst.a * (1.0 - a)) / out_alpha,
		out_alpha
	)
	image.set_pixel(x, y, out)


func _clear_bottom_margin(image):
	for y in range(max(0, image.get_height() - BOTTOM_MARGIN_PX), image.get_height()):
		for x in range(image.get_width()):
			image.set_pixel(x, y, Color(0, 0, 0, 0))


func _save_image(image, target):
	if target == "":
		return "target is empty"
	var target_path = _project_path(target)
	var target_dir = target_path.get_base_dir()
	var mkdir_error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	if mkdir_error != OK:
		return "failed to create target dir %s error=%d" % [target_dir, mkdir_error]
	var save_error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		return "failed to save %s error=%d" % [target, save_error]
	return ""


func _parse_palette(values):
	var palette = []
	for value in values:
		palette.append(Color.html(str(value)))
	return palette


func _p(hex):
	var color = Color.html(hex)
	color.a = 1.0
	return color


func _rgb_distance(a, b):
	var dr = a.r - b.r
	var dg = a.g - b.g
	var db = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _vector2i_from_array(value):
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return Vector2i.ONE
	return Vector2i(int(value[0]), int(value[1]))


func _create_image(width, height):
	var image = Image.create(max(1, width), max(1, height), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _project_path(path):
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path
