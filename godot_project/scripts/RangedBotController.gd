extends "res://scripts/RangedEntity.gd"
class_name RangedBotController

const PREFERRED_RANGE = 320.0
const FLEE_RANGE = 160.0

var ai_timer := 0.0
var ai_target := Vector2.ZERO
var ai_move := Vector2.ZERO

func _ready():
	super._ready()
	is_player = false
	base_color = Color(0.85, 0.4, 1.0)

func get_movement_input() -> Vector2:
	return steer_around_obstacles(ai_move)

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		try_dodge_dash()
		ai_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = 0.38 + randf() * 0.22
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 5.0))
	super._physics_process(delta)

# Checked every physics frame (not gated by the ai_timer decision cadence) because
# melee cast windows (~0.12-0.25s) and instant autos are shorter than our decision
# interval (~0.4-0.6s) — a periodic check would usually miss the telegraph entirely.
func try_dodge_dash():
	if dashing or dash_charges <= 0 or casting != null:
		return
	var d = global_position.distance_to(opponent.global_position)
	var threat_cast = opponent.casting != null and d < 280.0
	var point_blank = d < 140.0
	if threat_cast or point_blank:
		try_dash((global_position - opponent.global_position).normalized())

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)

	if casting != null or recovering != null:
		ai_target = Vector2.ZERO
		return

	# barrier when low HP
	if hp < max_hp * 0.45 and cd_a3 <= 0 and randf() < 0.5:
		try_a3(opponent)
		return

	# arcane burst when opponent is in close/melee range
	if d < FLEE_RANGE and cd_a2 <= 0 and casting == null and randf() < 0.85:
		try_a2(opponent)
		return

	# parry if opponent is casting close
	if opponent.casting != null and d < 200 and parry_cd_left <= 0 and randf() < 0.3:
		try_parry()
		return

	# ult when charged and in medium range
	if ult_charge >= ULT_CHARGE_MAX and d < 500 and randf() < 0.5:
		try_ult(opponent)
		return

	# charged bolt
	if cd_a1 <= 0 and d < 480 and randf() < 0.45:
		try_a1(opponent)
		return

	# auto shot
	if cd_auto <= 0 and d < 500:
		try_auto(opponent)
		return

	# movement: maintain preferred range, strafe laterally
	var to_opp = (opponent.global_position - global_position).normalized()
	if d < PREFERRED_RANGE - 40:
		ai_target = -to_opp
	elif d > PREFERRED_RANGE + 60:
		ai_target = to_opp * 0.6
	else:
		var perp = Vector2(-to_opp.y, to_opp.x) * (1 if randf() < 0.5 else -1)
		ai_target = perp

	# wall repulsion — push away from arena edges so bot doesn't get cornered
	var wall_margin = 120.0
	var repulse := Vector2.ZERO
	var ar = arena_rect
	repulse.x += max(0.0, wall_margin - (global_position.x - ar.position.x)) / wall_margin
	repulse.x -= max(0.0, wall_margin - (ar.position.x + ar.size.x - global_position.x)) / wall_margin
	repulse.y += max(0.0, wall_margin - (global_position.y - ar.position.y)) / wall_margin
	repulse.y -= max(0.0, wall_margin - (ar.position.y + ar.size.y - global_position.y)) / wall_margin
	if repulse.length() > 0.01:
		ai_target = (ai_target + repulse * 2.0).normalized()
