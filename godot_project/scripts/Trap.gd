extends Node2D
class_name Trap
# A stationary, delayed-trigger gameplay object — the first genuinely new
# object type since Projectile. Placed by an ability, arms after a short
# delay, then roots the first enemy that walks over it. Mirrors
# Projectile.gd's shape (owner_entity/all_fighters-based team filtering,
# spawned/tracked by Main.gd the same way) so it fits the existing pattern
# rather than inventing a new one.

const FX = preload("res://scripts/FX.gd")

var owner_entity: Entity = null
var radius := 26.0
var arm_delay := 0.6
var lifetime := 8.0
var root_duration := 1.2
var trap_color := Color(0.4, 0.9, 0.3)

var armed := false

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return

	if not armed:
		arm_delay -= delta
		if arm_delay <= 0:
			armed = true
		queue_redraw()
		return

	if owner_entity == null or not is_instance_valid(owner_entity):
		queue_free()
		return

	for e in owner_entity.all_fighters:
		if e == owner_entity or not is_instance_valid(e) or not e.alive or e.team_id == owner_entity.team_id:
			continue
		if global_position.distance_to(e.global_position) <= radius + e.RADIUS:
			e.apply_root(root_duration)
			FX.impact_burst(get_parent(), global_position, trap_color, 14, 140.0)
			queue_free()
			return
	queue_redraw()

func _draw():
	var pulse = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
	if armed:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(trap_color.r, trap_color.g, trap_color.b, 0.7 * pulse), 2.0)
		draw_circle(Vector2.ZERO, 5.0, Color(trap_color.r, trap_color.g, trap_color.b, 0.85))
	else:
		# dim and non-pulsing while arming, so it reads as "not live yet"
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(trap_color.r, trap_color.g, trap_color.b, 0.25), 1.5)
		draw_circle(Vector2.ZERO, 4.0, Color(trap_color.r, trap_color.g, trap_color.b, 0.4))
