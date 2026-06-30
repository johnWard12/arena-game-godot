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
	return ai_move

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		ai_timer -= delta
		if strafe_timer > 0:
			strafe_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = 0.35 + randf() * 0.2
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 6.0))
	super._physics_process(delta)

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)

	if casting != null or recovering != null or lunging:
		ai_target = Vector2.ZERO
		return

	# parry: if opponent just started a cast and we're in melee range, try to parry instead of dodge
	if opponent.casting != null and opponent.casting["time_left"] > opponent.casting["total"] * 0.6 \
		and d < 120 and parry_cd_left <= 0 and randf() < 0.25:
		try_parry()
		return

	# dodge: if the opponent just started a long cast and we're close, dash away
	if opponent.casting != null and opponent.casting["time_left"] > opponent.casting["total"] * 0.5 \
		and d < 180 and dash_cd_left <= 0 and randf() < 0.3:
		var away = (global_position - opponent.global_position).normalized()
		try_dash(away)
		return

	if ult_charge >= ULT_CHARGE_MAX and d <= ULT_RANGE and randf() < 0.3:
		try_ult(opponent)
		return

	if d <= A1_RANGE and cd_a1 <= 0 and randf() < 0.4:
		try_a1(opponent)
		return

	if d > 100 and d < 420 and cd_a2 <= 0 and randf() < 0.3:
		try_a2(opponent)
		return

	if d <= AUTO_RANGE and cd_auto <= 0:
		try_auto(opponent)
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
