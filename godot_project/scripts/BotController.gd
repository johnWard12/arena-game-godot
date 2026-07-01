extends "res://scripts/Entity.gd"
class_name BotController

var ai_timer := 0.0
var ai_target := Vector2.ZERO
var ai_move := Vector2.ZERO
var strafe_sign := 1
var strafe_timer := 0.0

func _ready():
	is_player = false
	base_color = Color(1, 0.54, 0.36)

func get_movement_input() -> Vector2:
	return steer_around_obstacles(ai_move)

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		var is_kiter = opponent is RangedEntity
		ai_timer -= delta
		if strafe_timer > 0:
			strafe_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = (0.22 + randf() * 0.12) if is_kiter else (0.35 + randf() * 0.2)
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 6.0))
	super._physics_process(delta)

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)
	var is_kiter = opponent is RangedEntity

	if casting != null or recovering != null or lunging:
		ai_target = Vector2.ZERO
		return

	# parry: if opponent just started a cast and we're in melee range, try to parry instead of dodge
	if opponent.casting != null and opponent.casting["time_left"] > opponent.casting["total"] * 0.6 \
		and d < 120 and parry_cd_left <= 0 and randf() < 0.25:
		try_parry()
		return

	# dodge: if the opponent just started a long cast and we're close, dash away
	if not is_kiter and opponent.casting != null and opponent.casting["time_left"] > opponent.casting["total"] * 0.5 \
		and d < 180 and dash_charges > 0 and randf() < 0.3:
		var away = (global_position - opponent.global_position).normalized()
		try_dash(away)
		return

	if ult_charge >= ULT_CHARGE_MAX and d <= ULT_RANGE and randf() < 0.3:
		try_ult(opponent)
		return

	# Iron Resolve — cash in combo stacks for damage reduction when under threat
	if cd_shift <= 0 and combo_stacks >= 2 and (hp < max_hp * 0.5 or opponent.casting != null) and randf() < 0.5:
		try_shift(opponent)
		return

	if d <= A1_RANGE and cd_a1 <= 0 and randf() < 0.4:
		try_a1(opponent)
		return

	# Sword Throw — ranged poke/slow while not yet in melee range
	if d > AUTO_RANGE and d <= 500 and cd_a3 <= 0 and randf() < 0.35:
		try_a3(opponent)
		return

	# lunge as a gap-closer — much more eager to use it on a kiting ranged opponent
	if is_kiter:
		if d > 90 and d < 460 and cd_a2 <= 0 and randf() < 0.75:
			try_a2(opponent)
			return
	else:
		if d > 100 and d < 420 and cd_a2 <= 0 and randf() < 0.3:
			try_a2(opponent)
			return

	if d <= AUTO_RANGE and cd_auto <= 0:
		try_auto(opponent)
		return

	# dash to close distance fast when kiting opponent is out of lunge range
	if is_kiter and d > 460 and dash_charges > 0:
		var toward = (opponent.global_position - global_position).normalized()
		try_dash(toward)
		return

	if d > 90:
		ai_target = (opponent.global_position - global_position).normalized()
	else:
		if strafe_timer <= 0:
			strafe_sign = 1 if randf() < 0.5 else -1
			strafe_timer = 0.7 + randf() * 0.7
		var t = (opponent.global_position - global_position).normalized()
		var perp = Vector2(-t.y, t.x) * strafe_sign
		ai_target = t * 0.4 + perp * 0.9
