extends "res://scripts/RangedEntity.gd"
class_name RangedBotController

const BotSteering = preload("res://scripts/BotSteering.gd")

const PREFERRED_RANGE = 320.0
const FLEE_RANGE = 160.0

var ai_timer := 0.0
var ai_target := Vector2.ZERO
var ai_move := Vector2.ZERO
var strafe_sign := 1
var strafe_timer := 0.0

func _ready():
	super._ready()
	is_player = false
	base_color = Color(0.85, 0.4, 1.0)

func get_movement_input() -> Vector2:
	return steer_around_obstacles(ai_move)

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		try_dodge_dash()
		# Flip strafe direction on a slow timer so kiting weaves instead of
		# committing to one arc (which walks straight into a wall/corner).
		strafe_timer -= delta
		if strafe_timer <= 0:
			strafe_sign = 1 if randf() < 0.5 else -1
			strafe_timer = 1.1 + randf() * 1.3
		ai_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = 0.22 + randf() * 0.14
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 6.0))
	super._physics_process(delta)

# Checked every physics frame (not gated by the ai_timer decision cadence) because
# melee cast windows (~0.12-0.25s) and instant autos are shorter than our decision
# interval — a periodic check would usually miss the telegraph entirely.
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

	# Movement is decided FIRST and unconditionally, so firing an instant
	# ability below (which returns early) never leaves the kite frozen on a
	# stale target for a whole decision cycle — that was the core reason
	# ranged bots kept walking into melee instead of kiting.
	ai_target = BotSteering.apply_wall_repulsion(global_position, arena_rect, _kite_move(d))

	# Barrier when low HP
	if hp < max_hp * 0.45 and cd_shift <= 0 and randf() < 0.6:
		try_shift(opponent)
		return

	# Arcane Fan — close-range burst spread when the enemy has closed in
	if d < FLEE_RANGE and cd_a3 <= 0 and randf() < 0.6:
		try_a3(opponent)
		return

	# Nova — AoE freeze when the enemy is in point-blank range
	if d < FLEE_RANGE + 40 and cd_a2 <= 0 and randf() < 0.85:
		try_a2(opponent)
		return

	# parry if opponent is casting close
	if opponent.casting != null and d < 200 and parry_cd_left <= 0 and randf() < 0.3:
		try_parry()
		return

	# ult when charged and in range
	if ult_charge >= ULT_CHARGE_MAX and d < 520 and randf() < 0.6:
		try_ult(opponent)
		return

	# charged bolt — main poke
	if cd_a1 <= 0 and d < 500 and randf() < 0.6:
		try_a1(opponent)
		return

	# auto shot — fire near-constantly while kiting
	if cd_auto <= 0 and d < 520:
		try_auto(opponent)
		return

# Kiting movement: hold PREFERRED_RANGE, always weaving perpendicular so the
# path is evasive rather than a straight retreat/approach a melee can predict.
func _kite_move(d: float) -> Vector2:
	var to_opp = (opponent.global_position - global_position).normalized()
	var perp = Vector2(-to_opp.y, to_opp.x) * strafe_sign
	if d < PREFERRED_RANGE - 60:
		# too close: back off at an angle
		return (-to_opp + perp * 0.5).normalized()
	elif d > PREFERRED_RANGE + 80:
		# too far: close some distance, still weaving
		return (to_opp * 0.7 + perp * 0.4).normalized()
	# in the pocket: strafe with a slight backpedal bias to hold range
	return (perp * 0.9 - to_opp * 0.25).normalized()
