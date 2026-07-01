extends Node2D
class_name Projectile

const FX = preload("res://scripts/FX.gd")

var velocity := Vector2.ZERO
var damage := 0.0
var hit_radius := 28.0
var owner_entity: Entity = null
var target: Entity = null
var lifetime := 3.0
var proj_color := Color(1.0, 0.85, 0.3)
var proj_radius_visual := 8.0
var apply_slow := 0.0
var apply_slow_pct := 0.5
var obstacle_rects: Array[Rect2] = []

# When true, reports whether this projectile landed back to owner_entity via
# register_ability_result() — used for passives like Mage's Overcharge.
var report_result := false

var trail: Array = []
const TRAIL_MAX_POINTS = 9
var spawn_fx_done := false

func _ready():
	FX.impact_burst(get_parent(), global_position, proj_color, 6, 90.0)

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		_report_miss()
		queue_free()
		return
	trail.append(global_position)
	if trail.size() > TRAIL_MAX_POINTS:
		trail.pop_front()
	global_position += velocity * delta
	queue_redraw()
	for obstacle in obstacle_rects:
		if obstacle.grow(proj_radius_visual).has_point(global_position):
			_report_miss()
			queue_free()
			return
	if target != null and is_instance_valid(target) and target.alive:
		if global_position.distance_to(target.global_position) <= hit_radius + target.RADIUS:
			_on_hit()

func _report_miss():
	if report_result and owner_entity != null and is_instance_valid(owner_entity) and owner_entity.has_method("register_ability_result"):
		owner_entity.register_ability_result(false)

func _on_hit():
	var landed := false
	if owner_entity != null and is_instance_valid(owner_entity) and owner_entity.alive:
		landed = owner_entity.deal_damage(target, damage)
		if landed:
			owner_entity.add_combo_stack()
	if landed and apply_slow > 0 and target != null and is_instance_valid(target) and target.alive:
		target.slowed_time_left = apply_slow
		target.slow_pct = apply_slow_pct
	if report_result and owner_entity != null and is_instance_valid(owner_entity) and owner_entity.has_method("register_ability_result"):
		owner_entity.register_ability_result(landed)
	queue_free()

func _draw():
	# tapered fading trail behind the projectile
	var n = trail.size()
	if n >= 2:
		for i in range(n - 1):
			var age = float(i) / float(n)
			var p0 = to_local(trail[i])
			var p1 = to_local(trail[i + 1])
			var w = lerp(1.0, proj_radius_visual * 1.3, age)
			draw_line(p0, p1, Color(proj_color.r, proj_color.g, proj_color.b, age * 0.55), w, true)

	# outer glow
	draw_circle(Vector2.ZERO, proj_radius_visual * 1.9,
		Color(proj_color.r, proj_color.g, proj_color.b, 0.15))
	draw_circle(Vector2.ZERO, proj_radius_visual * 1.4,
		Color(proj_color.r, proj_color.g, proj_color.b, 0.3))
	# core
	draw_circle(Vector2.ZERO, proj_radius_visual, proj_color)
	# rotating cross-glint for a "magic/energy" read
	var t = Time.get_ticks_msec() * 0.01
	for i in 2:
		var a = t + i * PI * 0.5
		var d = Vector2(cos(a), sin(a)) * proj_radius_visual * 0.9
		draw_line(-d, d, Color(1, 1, 1, 0.5), 1.4)
	# bright center
	draw_circle(Vector2.ZERO, proj_radius_visual * 0.45, Color(1, 1, 1, 0.85))
