extends "res://scripts/Entity.gd"
class_name RangerEntity
# Mobile skirmisher/trapper. Weaker burst than Mage, no hard defensive
# cooldown like Barrier — survives by not being where the enemy expects,
# via the highest move speed in the roster, a snare that punishes
# predictable pathing, a recoiling peel shot, and a stealth escape.

const RANGER_MAX_HP    = 130.0
const RANGER_MAX_SPEED = 465.0

# LMB — Quick Shot: fast low-damage poke, builds Momentum on hit
const QUICKSHOT_CD     = 0.5
const QUICKSHOT_DMG    = 8.0
const QUICKSHOT_SPEED  = 1500.0
const QUICKSHOT_RADIUS = 18.0

# E — Piercing Shot: skill-shot that punches through the first target
const PIERCE_CAST      = 0.18
const PIERCE_RECOVERY  = 0.18
const PIERCE_CD        = 4.0
const PIERCE_SPEED     = 1700.0
const PIERCE_RADIUS    = 18.0
const PIERCE_DMG       = 24.0
const PIERCE_SLOW_DUR  = 1.0
const PIERCE_SLOW_PCT  = 0.20

# Q — Snare Trap: thrown trap, arms after a delay, roots on trigger
const SNARE_CD          = 7.0
const SNARE_PLACE_DIST  = 110.0
const SNARE_RADIUS      = 30.0
const SNARE_ARM_DELAY   = 0.6
const SNARE_LIFETIME    = 8.0
const SNARE_ROOT_DUR    = 1.2

# F — Disengage Shot: fire forward, recoil backward — peel tool
const DISENGAGE_CD     = 6.0
const DISENGAGE_DMG    = 16.0
const DISENGAGE_SPEED  = 1400.0
const DISENGAGE_RADIUS = 16.0
const DISENGAGE_RECOIL = 1400.0
const DISENGAGE_RECOIL_DUR = 0.14

# Shift — Camouflage: brief stealth from AI targeting
const CAMO_CD  = 10.0
const CAMO_DUR = 3.0

# R — Rain of Arrows: zone that ticks damage to anyone standing in it
const RAIN_CAST          = 0.3
const RAIN_RECOVERY      = 0.3
const RAIN_DUR           = 2.0
const RAIN_TICK_INTERVAL = 0.4
const RAIN_TICK_DMG      = 14.0
const RAIN_RADIUS        = 130.0

# Passive — Momentum: consecutive landed Quick Shots build stacking move
# speed, reset by a miss or by going quiet for a bit. Rewards sustained
# accurate kiting rather than one burst then reset, distinct from Duelist's
# combo multiplier, Mage's Overcharge cooldown refund, or Bruiser's flat
# CC resist.
const MOMENTUM_STACK_SPEED = 0.04
const MOMENTUM_MAX_STACKS  = 5
const MOMENTUM_TIMEOUT     = 2.5
var momentum_stacks := 0
var momentum_timeout_left := 0.0

var rain_pos := Vector2.ZERO
var rain_time_left := 0.0
var rain_tick_timer := 0.0
var rain_fx_left := 0.0

func _ready():
	hp     = RANGER_MAX_HP
	max_hp = RANGER_MAX_HP
	base_color = Color(0.45, 0.75, 0.35)
	speed_override = RANGER_MAX_SPEED

func _physics_process(delta):
	momentum_timeout_left = max(0.0, momentum_timeout_left - delta)
	if momentum_timeout_left <= 0:
		momentum_stacks = 0
	speed_override = RANGER_MAX_SPEED * (1.0 + momentum_stacks * MOMENTUM_STACK_SPEED)

	rain_fx_left = max(0.0, rain_fx_left - delta)
	if rain_time_left > 0:
		rain_time_left -= delta
		rain_tick_timer -= delta
		if rain_tick_timer <= 0:
			rain_tick_timer = RAIN_TICK_INTERVAL
			FX.impact_burst(get_parent(), rain_pos, Color(0.5, 0.9, 0.3), 12, 160.0)
			for target in get_enemies_in_range(RAIN_RADIUS, rain_pos):
				deal_damage(target, RAIN_TICK_DMG)
	super._physics_process(delta)

# No combo system — Momentum already provides an escalation mechanic and
# stacking both would be redundant/confusing.
func combo_mult() -> float:
	return 1.0

func add_combo_stack():
	pass

func on_landed_parry():
	pass

# Only Quick Shot reports through this (see try_auto's track=true), so
# Momentum specifically tracks auto-shot accuracy, not general ability use.
func register_ability_result(landed: bool):
	if landed:
		momentum_stacks = min(MOMENTUM_MAX_STACKS, momentum_stacks + 1)
		momentum_timeout_left = MOMENTUM_TIMEOUT
	else:
		momentum_stacks = 0

# ---- Ability overrides ----

func try_auto(opp: Entity):
	if not can_start_ability() or cd_auto > 0 or opp == null:
		return
	cd_auto = QUICKSHOT_CD
	facing = get_aim_dir(opp)
	_fire(facing, QUICKSHOT_SPEED, QUICKSHOT_RADIUS, QUICKSHOT_DMG, opp, Color(0.6, 1.0, 0.4), 7.0, 0.0, 0.5, true, false, "arrow")

func try_a1(opp: Entity):
	if not can_start_ability() or cd_a1 > 0 or opp == null:
		return
	casting = {"type": "a1", "time_left": PIERCE_CAST, "total": PIERCE_CAST, "opp": opp}

func resolve_a1(opp: Entity):
	facing = get_aim_dir(opp)
	_fire(facing, PIERCE_SPEED, PIERCE_RADIUS, PIERCE_DMG, opp, Color(0.85, 1.0, 0.5), 9.0,
		PIERCE_SLOW_DUR, PIERCE_SLOW_PCT, false, true, "arrow")
	cd_a1 = PIERCE_CD
	recovering = {"type": "a1", "time_left": PIERCE_RECOVERY, "total": PIERCE_RECOVERY}

func try_a2(opp: Entity):
	if not can_start_ability() or cd_a2 > 0 or opp == null:
		return
	facing = get_aim_dir(opp)
	var pos = global_position + facing * SNARE_PLACE_DIST
	_place_trap(pos, SNARE_RADIUS, SNARE_ARM_DELAY, SNARE_LIFETIME, SNARE_ROOT_DUR, Color(0.4, 0.9, 0.3))
	cd_a2 = SNARE_CD

func resolve_a2(_opp: Entity):
	pass

func try_a3(opp: Entity):
	if not can_start_ability() or cd_a3 > 0 or opp == null:
		return
	facing = get_aim_dir(opp)
	_fire(facing, DISENGAGE_SPEED, DISENGAGE_RADIUS, DISENGAGE_DMG, opp, Color(0.3, 0.85, 0.55), 8.0, 0.0, 0.5, false, false, "arrow")
	# A plain one-frame velocity nudge got immediately overridden by normal
	# movement acceleration the instant any direction key was held (which is
	# most of the time — this is a reactive peel tool). Reusing `lunging`
	# forces velocity every frame for its duration regardless of input,
	# exactly like a dash, giving a real, guaranteed shove backward.
	lunging = true
	lunge_dir = -facing
	lunge_speed = DISENGAGE_RECOIL
	lunge_time_left = DISENGAGE_RECOIL_DUR
	lunge_reach = 0.0
	lunge_opponent = null
	cd_a3 = DISENGAGE_CD

# The recoil already did its job via try_a3's forced lunge; the ranged
# damage already landed via the projectile fired there too, so arriving
# at the end of the recoil "lunge" does nothing further.
func resolve_lunge_strike(_opp: Entity):
	pass

func resolve_a3(_opp: Entity):
	pass

func try_shift(_opp: Entity):
	if not can_start_ability() or cd_shift > 0:
		return
	invisible_time_left = CAMO_DUR
	cd_shift = CAMO_CD

func try_ult(opp: Entity):
	if not can_start_ability() or ult_charge < ULT_CHARGE_MAX or opp == null:
		return
	casting = {"type": "ult", "time_left": RAIN_CAST, "total": RAIN_CAST, "opp": opp}

func resolve_ult(opp: Entity):
	ult_charge = 0.0
	rain_pos = opp.global_position if opp != null and opp.alive else global_position + facing * 200.0
	rain_time_left = RAIN_DUR
	rain_tick_timer = 0.0
	rain_fx_left = RAIN_DUR + 0.3
	recovering = {"type": "ult", "time_left": RAIN_RECOVERY, "total": RAIN_RECOVERY}

# ---- Drawing ----
func _draw():
	var now = Time.get_ticks_msec()

	if use_3d_view:
		if not alive:
			return
		var view_accent = get_status_accent(base_color)
		draw_set_transform(_get_hud_screen_correction())
		_draw_rain_zone()
		_draw_camo_ring(now)
		_draw_hud(now, view_accent)
		draw_set_transform(Vector2.ZERO)
		return

	for p in trail:
		var age = (now - p["time"]) / 200.0
		if age < 1.0:
			draw_circle(to_local(p["pos"]), RADIUS * 0.85,
				Color(base_color.r, base_color.g, base_color.b, (1.0 - age) * 0.25))

	if not alive:
		draw_circle(Vector2.ZERO, RADIUS + 2, Color(0.25, 0.25, 0.28, 0.5))
		return

	var accent = get_status_accent(base_color)
	if invisible_time_left > 0:
		accent = Color(accent.r, accent.g, accent.b, 0.35)
	_draw_rain_zone()
	_draw_camo_ring(now)
	_draw_hud(now, accent)

# Camouflage — soft green shimmer while cloaked
func _draw_camo_ring(now: int):
	if invisible_time_left > 0:
		var pulse = 0.4 + 0.3 * sin(now * 0.012)
		draw_arc(Vector2.ZERO, RADIUS + 13, 0, TAU, 40, Color(0.4, 0.9, 0.4, pulse), 2.0)

# Rain of Arrows — falling-arrow visual over the target zone
func _draw_rain_zone():
	if rain_time_left <= 0:
		return
	var local_center = to_local(rain_pos)
	var pulse = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.01)
	draw_arc(local_center, RAIN_RADIUS, 0, TAU, 48, Color(0.5, 0.9, 0.3, 0.35 * pulse), 3.0)
