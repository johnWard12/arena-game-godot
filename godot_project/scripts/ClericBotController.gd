extends "res://scripts/ClericEntity.gd"
class_name ClericBotController

const BotSteering = preload("res://scripts/BotSteering.gd")

const PREFERRED_RANGE = 300.0
const FLEE_RANGE = 140.0

var ai_timer := 0.0
var ai_target := Vector2.ZERO
var ai_move := Vector2.ZERO

func _ready():
	super._ready()
	is_player = false
	base_color = Color(0.85, 0.78, 0.5)

func get_movement_input() -> Vector2:
	return steer_around_obstacles(ai_move)

func _physics_process(delta):
	if alive and opponent != null and opponent.alive:
		try_dodge_dash()
		ai_timer -= delta
		if ai_timer <= 0:
			ai_decide()
			ai_timer = 0.3 + randf() * 0.2
		ai_move = ai_move.lerp(ai_target, min(1.0, delta * 5.0))
	super._physics_process(delta)

func try_dodge_dash():
	if dashing or dash_charges <= 0 or casting != null:
		return
	var d = global_position.distance_to(opponent.global_position)
	var threat_cast = opponent.casting != null and d < 260.0
	var point_blank = d < 130.0
	if threat_cast or point_blank:
		try_dash((global_position - opponent.global_position).normalized())

# Anyone (self or ally) currently affected by a CC/debuff worth cleansing.
func _find_cc_ally() -> Entity:
	for a in get_allies_in_range(PURIFY_LENGTH):
		if a.stunned_time_left > 0 or a.rooted_time_left > 0 or a.slowed_time_left > 0 \
			or a.freeze_time_left > 0 or a.outgoing_dmg_debuff_time_left > 0:
			return a
	return null

func ai_decide():
	if not alive or opponent == null or not opponent.alive:
		return
	var d = global_position.distance_to(opponent.global_position)

	if casting != null or recovering != null:
		ai_target = Vector2.ZERO
		return

	# Offensive dash, healer-flavored two ways: close in on a critically hurt
	# ally to actually reach them with a heal in time (dash as a rescue tool,
	# not just an escape), or — failing that — close in on a fleeing,
	# near-dead enemy to secure the kill with Smite.
	var hurt_ally = get_lowest_hp_ally(BOND_TARGET_RADIUS)
	if dash_charges > 0 and not dashing and casting == null:
		if hurt_ally != self and hurt_ally.hp <= hurt_ally.max_hp * 0.3:
			var ally_d = global_position.distance_to(hurt_ally.global_position)
			if ally_d > 200 and ally_d < 550 and randf() < 0.7:
				try_dash((hurt_ally.global_position - global_position).normalized())
				return
		elif opponent.hp <= opponent.max_hp * 0.25 and d > 200 and d < 550 and randf() < 0.6:
			try_dash((opponent.global_position - global_position).normalized())
			return

	# Guardian's Bond — usable even while stunned, so lean on it hard when
	# either the Cleric or a nearby ally is in real danger.
	var lowest = get_lowest_hp_ally(BOND_TARGET_RADIUS)
	if ult_charge >= ULT_CHARGE_MAX and lowest.hp < lowest.max_hp * 0.4 and randf() < 0.8:
		try_ult(opponent)
		return

	# Purify — cleanse whoever's CC'd
	var cc_ally = _find_cc_ally()
	if cc_ally != null and cd_a3 <= 0:
		facing = (cc_ally.global_position - global_position).normalized() if cc_ally != self else facing
		try_a3(opponent)
		return

	# Guardian Ward — shield whoever's hurting most, especially with combo
	# stacks banked (they make the shield much bigger)
	if lowest.hp < lowest.max_hp * 0.55 and cd_shift <= 0 and randf() < 0.6:
		try_shift(opponent)
		return

	# Mending Light — top off whoever needs it
	if lowest.hp < lowest.max_hp * 0.75 and cd_a1 <= 0 and randf() < 0.7:
		try_a1(opponent)
		return

	# Consecrate — AoE heal/damage zone, use when in the thick of a fight
	if d <= CONSECRATE_RADIUS * 1.3 and cd_a2 <= 0 and randf() < 0.5:
		try_a2(opponent)
		return

	# Smite — poke to build combo stacks and chip damage
	if d <= 500 and cd_auto <= 0:
		try_auto(opponent)
		return

	# movement: hang back at range, strafe, don't overextend
	var to_opp = (opponent.global_position - global_position).normalized()
	if d < FLEE_RANGE:
		ai_target = -to_opp
	elif d < PREFERRED_RANGE - 40:
		ai_target = -to_opp * 0.5
	elif d > PREFERRED_RANGE + 60:
		ai_target = to_opp * 0.6
	else:
		var perp = Vector2(-to_opp.y, to_opp.x) * (1 if randf() < 0.5 else -1)
		ai_target = perp

	ai_target = BotSteering.apply_wall_repulsion(global_position, arena_rect, ai_target)
