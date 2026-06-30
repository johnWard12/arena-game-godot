extends Node2D
class_name Projectile

var velocity := Vector2.ZERO
var damage := 0.0
var hit_radius := 28.0
var owner_entity: Entity = null
var target: Entity = null
var lifetime := 3.0
var proj_color := Color(1.0, 0.85, 0.3)
var proj_radius_visual := 8.0
var apply_slow := 0.0

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	global_position += velocity * delta
	queue_redraw()
	if target != null and is_instance_valid(target) and target.alive:
		if global_position.distance_to(target.global_position) <= hit_radius + target.RADIUS:
			_on_hit()

func _on_hit():
	if owner_entity != null and is_instance_valid(owner_entity) and owner_entity.alive:
		owner_entity.deal_damage(target, damage)
		owner_entity.add_combo_stack()
	if apply_slow > 0 and target != null and is_instance_valid(target) and target.alive:
		target.slowed_time_left = apply_slow
	queue_free()

func _draw():
	# glow ring
	draw_circle(Vector2.ZERO, proj_radius_visual * 1.6,
		Color(proj_color.r, proj_color.g, proj_color.b, 0.25))
	# core
	draw_circle(Vector2.ZERO, proj_radius_visual, proj_color)
	# bright center
	draw_circle(Vector2.ZERO, proj_radius_visual * 0.45, Color(1, 1, 1, 0.8))
