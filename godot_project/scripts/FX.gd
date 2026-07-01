extends RefCounted
class_name FX
# Shared particle-effect helpers. All functions are no-ops if `parent` is
# null, which keeps the headless balance simulator (Simulate.gd — entities
# there are never added to a scene tree) fast and crash-free.

static func _spawn(parent: Node, pos: Vector2, lifetime: float) -> CPUParticles2D:
	if parent == null:
		return null
	var p = CPUParticles2D.new()
	parent.add_child(p)
	p.global_position = pos
	p.z_index = 50
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var timer = parent.get_tree().create_timer(lifetime + 0.15)
	timer.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)
	return p

static func hit_spark(parent: Node, pos: Vector2, color: Color) -> void:
	var p = _spawn(parent, pos, 0.35)
	if p == null:
		return
	p.amount = 12
	p.lifetime = 0.32
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 280.0
	p.gravity = Vector2(0, 320)
	p.damping_min = 60.0
	p.damping_max = 130.0
	p.scale_amount_min = 2.2
	p.scale_amount_max = 4.0
	p.color = color
	p.emitting = true

static func death_shatter(parent: Node, pos: Vector2, color: Color) -> void:
	var p = _spawn(parent, pos, 0.85)
	if p == null:
		return
	p.amount = 26
	p.lifetime = 0.8
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 380)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.5
	p.color = color
	p.emitting = true
	# secondary pale dust puff for grit
	var d = _spawn(parent, pos, 0.6)
	if d != null:
		d.amount = 14
		d.lifetime = 0.55
		d.direction = Vector2.UP
		d.spread = 180.0
		d.initial_velocity_min = 20.0
		d.initial_velocity_max = 90.0
		d.gravity = Vector2(0, 40)
		d.scale_amount_min = 4.0
		d.scale_amount_max = 8.0
		d.color = Color(0.7, 0.65, 0.55, 0.5)
		d.emitting = true

static func parry_flash(parent: Node, pos: Vector2) -> void:
	var p = _spawn(parent, pos, 0.3)
	if p == null:
		return
	p.amount = 16
	p.lifetime = 0.28
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 160.0
	p.initial_velocity_max = 340.0
	p.damping_min = 90.0
	p.damping_max = 160.0
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.0
	p.color = Color(0.6, 0.85, 1.0)
	p.emitting = true

static func dash_puff(parent: Node, pos: Vector2, color: Color) -> void:
	var p = _spawn(parent, pos, 0.3)
	if p == null:
		return
	p.amount = 4
	p.lifetime = 0.28
	p.direction = Vector2.UP
	p.spread = 60.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 4.5
	p.color = Color(color.r, color.g, color.b, 0.45)
	p.emitting = true

static func impact_burst(parent: Node, pos: Vector2, color: Color, count: int = 20, speed: float = 320.0) -> void:
	var p = _spawn(parent, pos, 0.5)
	if p == null:
		return
	p.amount = count
	p.lifetime = 0.45
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = 80.0
	p.damping_max = 160.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	p.color = color
	p.emitting = true

static func heal_sparkle(parent: Node, pos: Vector2) -> void:
	var p = _spawn(parent, pos, 0.55)
	if p == null:
		return
	p.amount = 14
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 40.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, -60)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = Color(0.4, 1.0, 0.5)
	p.emitting = true
