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

# Which 3D shape ProjectileView3D builds for this projectile: "orb" (the
# original glowing-ball look, still the default), "icicle" (Mage), or
# "arrow" (Ranger). Purely a presentation switch — read once in
# ProjectileView3D.setup(), has no effect on gameplay/collision at all.
var visual_kind := "orb"

# When true, this projectile ignores `target` and instead checks against
# every living enemy on owner_entity.all_fighters as it travels, damaging
# each one once and continuing rather than despawning on first contact.
# Used by Ranger's Piercing Shot; every existing single-target ability is
# unaffected since this defaults to false.
var pierce := false
var hit_entities: Array = []

# When true, reports whether this projectile landed back to owner_entity via
# register_ability_result() — used for passives like Mage's Overcharge.
var report_result := false

# When true, this projectile heals its target instead of damaging it —
# used by Cleric's Mending Light. Everything else about it (travel,
# collision, obstacles, trail) is identical to a damage projectile.
var is_heal := false

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

	if pierce:
		_check_pierce_hits()
		return

	if target != null and is_instance_valid(target) and target.alive:
		if global_position.distance_to(target.global_position) <= hit_radius + target.RADIUS:
			_on_hit()

func _check_pierce_hits():
	if owner_entity == null or not is_instance_valid(owner_entity) or not owner_entity.alive:
		return
	for e in owner_entity.all_fighters:
		if e == owner_entity or not is_instance_valid(e) or not e.alive or e.team_id == owner_entity.team_id:
			continue
		if e in hit_entities:
			continue
		if global_position.distance_to(e.global_position) <= hit_radius + e.RADIUS:
			hit_entities.append(e)
			if owner_entity.deal_damage(e, damage):
				owner_entity.add_combo_stack()
				if apply_slow > 0 and e.alive:
					e.slowed_time_left = apply_slow
					e.slow_pct = apply_slow_pct

func _report_miss():
	if report_result and owner_entity != null and is_instance_valid(owner_entity) and owner_entity.has_method("register_ability_result"):
		owner_entity.register_ability_result(false)

func _on_hit():
	var landed := false
	if owner_entity != null and is_instance_valid(owner_entity) and owner_entity.alive:
		if is_heal:
			owner_entity.heal(target, damage)
			landed = true
		else:
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
