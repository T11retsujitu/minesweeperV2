extends Control

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const DamageFloat = preload("res://scripts/presentation/damage_float.gd")
const FIREBALL_TEXTURES = [
	preload("res://assets/textures/fx/fireball_f1.png"),
	preload("res://assets/textures/fx/fireball_f2.png"),
	preload("res://assets/textures/fx/fireball_f3.png"),
]

var fx_generation = 0
var camera_rig = null


class VignetteFlash:
	extends Control

	var base_color = Color.WHITE
	var intensity = 0.0:
		set(value):
			intensity = value
			queue_redraw()

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		if intensity <= 0.0:
			return
		var draw_size = size
		if draw_size.x <= 0.0 or draw_size.y <= 0.0:
			draw_size = get_viewport_rect().size
		var max_margin = min(draw_size.x, draw_size.y) * 0.38
		var rings = 18
		var step = max_margin / float(rings)
		for index in range(rings):
			var t = 1.0 - float(index) / float(rings)
			var color = Color(base_color.r, base_color.g, base_color.b, intensity * t * t)
			var rect = Rect2(Vector2.ONE * step * float(index), draw_size - Vector2.ONE * step * float(index) * 2.0)
			draw_rect(rect, color, false, step + 1.0)


class ShockwaveRing:
	extends Control

	var center = Vector2.ZERO
	var base_color = Color.WHITE
	var radius = 0.0:
		set(value):
			radius = value
			queue_redraw()
	var line_width = 1.0:
		set(value):
			line_width = value
			queue_redraw()
	var alpha = 0.0:
		set(value):
			alpha = value
			queue_redraw()

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		if alpha <= 0.0 or radius <= 0.0 or line_width <= 0.0:
			return
		draw_arc(center, radius, 0.0, TAU, 96, Color(base_color.r, base_color.g, base_color.b, alpha), line_width, true)


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_camera_rig(value):
	camera_rig = value


func spawn_damage_float(global_pos, label_text, color):
	var damage_float = DamageFloat.new()
	damage_float.setup(label_text, color)
	var label_size = _estimate_damage_float_size(str(label_text))
	damage_float.size = label_size
	damage_float.custom_minimum_size = label_size
	damage_float.position = _clamped_damage_float_position(global_pos, label_size)
	add_child(damage_float)


func _estimate_damage_float_size(label_text):
	var width = max(FxConfig.FLOAT_FONT_SIZE, label_text.length() * FxConfig.FLOAT_FONT_SIZE * FxConfig.FLOAT_CHAR_WIDTH_RATIO)
	var height = FxConfig.FLOAT_FONT_SIZE + 10.0
	return Vector2(width, height)


func _clamped_damage_float_position(global_pos, label_size):
	var local_pos = get_global_transform().affine_inverse() * global_pos
	var layer_size = size
	if layer_size.x <= 0.0:
		layer_size = get_viewport_rect().size
	var min_x = FxConfig.FLOAT_EDGE_MARGIN
	var max_x = max(min_x, layer_size.x - label_size.x - FxConfig.FLOAT_EDGE_MARGIN)
	var x = clamp(local_pos.x - label_size.x * 0.5, min_x, max_x)
	return Vector2(x, local_pos.y - label_size.y * 0.5)


func fire_projectile(from_global, to_global):
	var projectile = ColorRect.new()
	projectile.color = FxConfig.COLOR_DAMAGE_DEALT
	projectile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	projectile.size = Vector2(FxConfig.PROJECTILE_SIZE, FxConfig.PROJECTILE_SIZE)
	var half_size = projectile.size * 0.5
	var local_from = get_global_transform().affine_inverse() * from_global
	var local_to = get_global_transform().affine_inverse() * to_global
	projectile.position = local_from - half_size
	add_child(projectile)

	var tween = create_tween()
	tween.tween_property(projectile, "position", local_to - half_size, FxConfig.PROJECTILE_TIME)
	tween.finished.connect(projectile.queue_free)
	await get_tree().create_timer(FxConfig.PROJECTILE_TIME).timeout


func shake(amplitude_scale := 1.0):
	if camera_rig != null:
		await camera_rig.shake(amplitude_scale)
	else:
		await get_tree().create_timer(FxConfig.SHAKE_DURATION).timeout


func hit_stop():
	Engine.time_scale = FxConfig.HIT_STOP_TIME_SCALE
	await get_tree().create_timer(FxConfig.HIT_STOP_SEC, true, false, true).timeout
	Engine.time_scale = 1.0


func spawn_explosion_particles(global_pos, is_center, color_override = null, intense_center := false):
	var particles = CPUParticles2D.new()
	particles.one_shot = true
	particles.amount = FxConfig.EXPLOSION_PARTICLE_LEGACY_CENTER_COUNT
	if is_center and intense_center:
		particles.amount = FxConfig.EXPLOSION_PARTICLE_CENTER_COUNT
	if not is_center:
		particles.amount = FxConfig.EXPLOSION_PARTICLE_RING_COUNT
	particles.lifetime = 0.38
	particles.explosiveness = 0.9
	particles.randomness = 0.35
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 240)
	particles.initial_velocity_min = FxConfig.EXPLOSION_LEGACY_PARTICLE_VELOCITY_MIN
	particles.initial_velocity_max = FxConfig.EXPLOSION_LEGACY_PARTICLE_VELOCITY_MAX
	if is_center and intense_center:
		particles.initial_velocity_min = FxConfig.EXPLOSION_CENTER_PARTICLE_VELOCITY_MIN
		particles.initial_velocity_max = FxConfig.EXPLOSION_CENTER_PARTICLE_VELOCITY_MAX
	if not is_center:
		particles.initial_velocity_min = FxConfig.EXPLOSION_RING_PARTICLE_VELOCITY_MIN
		particles.initial_velocity_max = FxConfig.EXPLOSION_RING_PARTICLE_VELOCITY_MAX
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = FxConfig.COLOR_DAMAGE_MINE
	if is_center:
		particles.color = FxConfig.COLOR_DAMAGE_DEALT
	if color_override != null:
		particles.color = color_override
	particles.position = get_global_transform().affine_inverse() * global_pos
	particles.finished.connect(particles.queue_free)
	add_child(particles)
	particles.emitting = true


func flash_explosion_vignette():
	var vignette = VignetteFlash.new()
	vignette.name = "ExplosionVignette"
	vignette.base_color = FxConfig.COLOR_EXPLOSION_VIGNETTE
	add_child(vignette)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.intensity = 0.35
	var tween = vignette.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(vignette, "intensity", 0.0, FxConfig.EXPLOSION_VIGNETTE_SEC)
	tween.finished.connect(vignette.queue_free)


func spawn_fireball(global_pos):
	var generation = fx_generation
	var sprite = Sprite2D.new()
	sprite.name = "Fireball"
	sprite.centered = true
	sprite.texture = FIREBALL_TEXTURES[0]
	sprite.position = get_global_transform().affine_inverse() * global_pos
	sprite.scale = _sprite_scale_for_texture(sprite.texture, FxConfig.FIREBALL_SIZE_PX)
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = material
	add_child(sprite)
	_animate_fireball(sprite, generation)


func spawn_shockwave(global_pos):
	var ring = ShockwaveRing.new()
	ring.name = "ShockwaveRing"
	ring.base_color = FxConfig.COLOR_EXPLOSION_SHOCKWAVE
	ring.center = get_global_transform().affine_inverse() * global_pos
	add_child(ring)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.radius = FxConfig.SHOCKWAVE_START_RADIUS_PX
	ring.line_width = FxConfig.SHOCKWAVE_START_WIDTH_PX
	ring.alpha = 0.75
	var tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "radius", FxConfig.SHOCKWAVE_END_RADIUS_PX, FxConfig.SHOCKWAVE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "line_width", FxConfig.SHOCKWAVE_END_WIDTH_PX, FxConfig.SHOCKWAVE_SEC)
	tween.tween_property(ring, "alpha", 0.0, FxConfig.SHOCKWAVE_SEC)
	tween.finished.connect(ring.queue_free)


func spawn_smoke(global_pos):
	var particles = CPUParticles2D.new()
	particles.name = "ExplosionSmoke"
	particles.one_shot = true
	particles.amount = FxConfig.SMOKE_PARTICLE_COUNT
	particles.lifetime = FxConfig.SMOKE_DURATION_SEC
	particles.explosiveness = 0.55
	particles.randomness = 0.7
	particles.direction = Vector2.UP
	particles.spread = 110.0
	particles.gravity = Vector2(0, FxConfig.SMOKE_GRAVITY_Y)
	particles.initial_velocity_min = FxConfig.SMOKE_INITIAL_VELOCITY_MIN
	particles.initial_velocity_max = FxConfig.SMOKE_INITIAL_VELOCITY_MAX
	particles.scale_amount_min = 5.0
	particles.scale_amount_max = 12.0
	particles.color = FxConfig.COLOR_SMOKE
	particles.position = get_global_transform().affine_inverse() * global_pos
	particles.finished.connect(particles.queue_free)
	add_child(particles)
	particles.emitting = true


func clear_all():
	fx_generation += 1
	if camera_rig != null:
		camera_rig.reset_shake()
		camera_rig.reset_punch()
	for child in get_children():
		child.queue_free()
	Engine.time_scale = 1.0


func _sprite_scale_for_texture(texture, target_size):
	if texture == null:
		return Vector2.ONE
	var texture_size = texture.get_size()
	var max_side = max(texture_size.x, texture_size.y)
	if max_side <= 0.0:
		return Vector2.ONE
	return Vector2.ONE * (target_size / max_side)


func _animate_fireball(sprite, generation):
	for texture in FIREBALL_TEXTURES:
		if generation != fx_generation or not is_instance_valid(sprite):
			return
		sprite.texture = texture
		sprite.scale = _sprite_scale_for_texture(texture, FxConfig.FIREBALL_SIZE_PX)
		await get_tree().create_timer(FxConfig.FIREBALL_FRAME_SEC).timeout
	if is_instance_valid(sprite):
		sprite.queue_free()
