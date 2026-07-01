extends "res://scripts/BruiserEntity.gd"
class_name BruiserBotController

var ai_timer    := 0.0
var ai_target   := Vector2.ZERO
var ai_move     := Vector2.ZERO
var strafe_sign := 1
var strafe_timer := 0.0

func _ready():
	super._ready()
	is_player = false
	base_color = Color(0.88, 0.45, 0.12)

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
			# slightly faster decisions when chasing a kiter
			ai_timer = (0.25 + randf() * 0.15) if is_kiter else (0.32 + randf() * 0.18)
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 5.5))
	super._physics_process(delta)

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)
	var is_kiter = opponent is RangedEntity

	if casting != null or recovering != null or lunging:
		ai_target = Vector2.ZERO
		return

	# parry if opponent cast just started and close
	if opponent.casting != null and opponent.casting["time_left"] > opponent.casting["total"] * 0.6 \
		and d < 130 and parry_cd_left <= 0 and randf() < 0.35:
		try_parry()
		return

	# ult when charged and in range
	if ult_charge >= ULT_CHARGE_MAX and d <= SEISMIC_RANGE * 1.3 and randf() < 0.5:
		try_ult(opponent)
		return

	# Unbreakable — pop when stunned or low HP to survive burst
	if cd_a3 <= 0 and unbreakable_time_left <= 0:
		if stunned_time_left > 0 or (hp < max_hp * 0.40 and randf() < 0.7):
			try_a3(opponent)
			return

	# Shatter (stun) — high priority at melee range
	if d <= SHATTER_RANGE and cd_a1 <= 0 and randf() < 0.65:
		try_a1(opponent)
		return

	# Tremor (AoE slow) — use when opponent is inside radius
	if d <= TREMOR_RADIUS * 0.75 and cd_a2 <= 0 and randf() < 0.55:
		try_a2(opponent)
		return

	# auto attack
	if d <= BRUISER_AUTO_RANGE and cd_auto <= 0:
		try_auto(opponent)
		return

	# dash to close gap when kiting
	if is_kiter and d > 420 and dash_charges > 0 and randf() < 0.6:
		var toward = (opponent.global_position - global_position).normalized()
		try_dash(toward)
		return

	# movement — always push toward opponent, bruiser doesn't hang back
	var to_opp = (opponent.global_position - global_position).normalized()
	if d > 80:
		ai_target = to_opp
	else:
		if strafe_timer <= 0:
			strafe_sign = 1 if randf() < 0.5 else -1
			strafe_timer = 0.6 + randf() * 0.6
		var perp = Vector2(-to_opp.y, to_opp.x) * strafe_sign
		ai_target = to_opp * 0.5 + perp * 0.8
