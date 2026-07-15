extends Control

const FxConfig = preload("res://scripts/presentation/fx_config.gd")
const DamageFloat = preload("res://scripts/presentation/damage_float.gd")

var fx_generation = 0


func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func spawn_damage_float(global_pos, label_text, color):
	var damage_float = DamageFloat.new()
	damage_float.setup(label_text, color)
	damage_float.position = get_global_transform().affine_inverse() * global_pos
	add_child(damage_float)


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
	var generation = fx_generation
	var elapsed = 0.0
	var step_sec = 0.025
	var rng = RandomNumberGenerator.new()
	var viewport = get_viewport()
	while elapsed < FxConfig.SHAKE_DURATION and generation == fx_generation:
		var transform = viewport.canvas_transform
		transform.origin = Vector2(
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE),
			rng.randf_range(-FxConfig.SHAKE_AMPLITUDE, FxConfig.SHAKE_AMPLITUDE)
		) * amplitude_scale
		viewport.canvas_transform = transform
		var wait_sec = min(step_sec, FxConfig.SHAKE_DURATION - elapsed)
		await get_tree().create_timer(wait_sec).timeout
		elapsed += wait_sec
	if generation == fx_generation:
		var final_transform = viewport.canvas_transform
		final_transform.origin = Vector2.ZERO
		viewport.canvas_transform = final_transform


func hit_stop():
	Engine.time_scale = FxConfig.HIT_STOP_TIME_SCALE
	await get_tree().create_timer(FxConfig.HIT_STOP_SEC, true, false, true).timeout
	Engine.time_scale = 1.0


func spawn_explosion_particles(global_pos, is_center):
	var particles = CPUParticles2D.new()
	particles.one_shot = true
	particles.amount = 16
	if not is_center:
		particles.amount = 10
	particles.lifetime = 0.38
	particles.explosiveness = 0.9
	particles.randomness = 0.35
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 240)
	particles.initial_velocity_min = 55.0
	particles.initial_velocity_max = 135.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = FxConfig.COLOR_DAMAGE_MINE
	if is_center:
		particles.color = FxConfig.COLOR_DAMAGE_DEALT
	particles.position = get_global_transform().affine_inverse() * global_pos
	particles.finished.connect(particles.queue_free)
	add_child(particles)
	particles.emitting = true


func clear_all():
	fx_generation += 1
	for child in get_children():
		child.queue_free()
	Engine.time_scale = 1.0
	get_viewport().canvas_transform = Transform2D.IDENTITY
