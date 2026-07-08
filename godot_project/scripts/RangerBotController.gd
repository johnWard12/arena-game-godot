extends "res://scripts/RangerEntity.gd"
class_name RangerBotController

const BotSteering = preload("res://scripts/BotSteering.gd")

const PREFERRED_RANGE = 340.0
const FLEE_RANGE = 150.0

var ai_timer := 0.0
var ai_target := Vector2.ZERO
var ai_move := Vector2.ZERO
var strafe_sign := 1
var strafe_timer := 0.0

func _ready():
	super._ready()
	is_player = false
	base_color = Color(0.35, 0.65, 0.28)

func get_movement_input() -> Vector2:
	return steer_around_obstacles(ai_move)

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		try_dodge_dash()
		strafe_timer -= delta
		if strafe_timer <= 0:
			strafe_sign = 1 if randf() < 0.5 else -1
			strafe_timer = 1.0 + randf() * 1.2
		ai_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = 0.16 + randf() * 0.1
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 6.0))
	super._physics_process(delta)

func try_dodge_dash():
	if dashing or dash_charges <= 0 or casting != null:
		return
	var d = global_position.distance_to(opponent.global_position)
	var threat_cast = opponent.casting != null and d < 260.0
	var point_blank = d < 130.0
	if threat_cast or point_blank:
		try_dash((global_position - opponent.global_position).normalized())

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)

	if casting != null or recovering != null:
		ai_target = Vector2.ZERO
		return

	# Movement decided first and unconditionally (see RangedBotController for
	# why) so poking never freezes the kite.
	ai_target = BotSteering.apply_wall_repulsion(global_position, arena_rect, _kite_move(d))

	# Offensive dash: close in to secure a kill on a fleeing, near-dead
	# opponent instead of dash staying purely an escape tool.
	if opponent.hp <= opponent.max_hp * 0.25 and d > 200 and d < 550 \
		and dash_charges > 0 and not dashing and casting == null and randf() < 0.7:
		try_dash((opponent.global_position - global_position).normalized())
		return

	# Camouflage to vanish and reposition when low HP
	if hp < max_hp * 0.35 and cd_shift <= 0 and randf() < 0.6:
		try_shift(opponent)
		return

	# Disengage Shot — peel when the opponent closes to melee range
	if d < FLEE_RANGE and cd_a3 <= 0 and randf() < 0.7:
		try_a3(opponent)
		return

	# Snare Trap — drop proactively at medium range to punish a chase
	if d > 120 and d < 400 and cd_a2 <= 0 and randf() < 0.4:
		try_a2(opponent)
		return

	# parry if opponent is casting close
	if opponent.casting != null and d < 200 and parry_cd_left <= 0 and randf() < 0.3:
		try_parry()
		return

	# ult when charged and in range
	if ult_charge >= ULT_CHARGE_MAX and d < 460 and randf() < 0.6:
		try_ult(opponent)
		return

	# Piercing Shot — main poke
	if cd_a1 <= 0 and d < 520 and randf() < 0.6:
		try_a1(opponent)
		return

	# Quick Shot — fire near-constantly to build Momentum while kiting
	if cd_auto <= 0 and d < 560:
		try_auto(opponent)
		return

# Kiting movement: hold PREFERRED_RANGE, always weaving so the path is
# evasive rather than a predictable straight line.
func _kite_move(d: float) -> Vector2:
	var to_opp = (opponent.global_position - global_position).normalized()
	var perp = Vector2(-to_opp.y, to_opp.x) * strafe_sign
	if d < PREFERRED_RANGE - 60:
		return (-to_opp + perp * 0.5).normalized()
	elif d > PREFERRED_RANGE + 80:
		return (to_opp * 0.7 + perp * 0.4).normalized()
	return (perp * 0.9 - to_opp * 0.25).normalized()
