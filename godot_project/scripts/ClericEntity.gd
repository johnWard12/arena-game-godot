extends "res://scripts/Entity.gd"
class_name ClericEntity
# The team's anchor: protects and empowers allies while staying a real
# threat alone. Every ally-targeted ability falls back to self when no
# ally is close enough (or in 1v1, ever), via get_lowest_hp_ally().

const CLERIC_MAX_HP = 176.0

# LMB — Smite: fast holy bolt poke, builds combo stacks on hit
const SMITE_CD     = 0.6
const SMITE_DMG    = 6.0
const SMITE_SPEED  = 1500.0
const SMITE_RADIUS = 16.0

# E — Mending Light: skill-shot heal toward the lowest-HP ally in radius.
# Also punishes an enemy body it flies through on the way there — deals
# damage and applies a slow, so body-blocking a heal isn't free anymore.
const MENDING_CAST      = 0.2
const MENDING_RECOVERY  = 0.2
const MENDING_CD        = 3.0
const MENDING_SPEED     = 1400.0
const MENDING_RADIUS    = 18.0
const MENDING_HEAL      = 32.4
const MENDING_TARGET_RADIUS = 400.0
const MENDING_ENEMY_DMG      = 12.0
const MENDING_ENEMY_SLOW_DUR = 1.0
const MENDING_ENEMY_SLOW_PCT = 0.30

# Q — Consecrate: instant AoE zone at self's position — heals allies and
# damages enemies standing in it, ticking over its duration
const CONSECRATE_RADIUS         = 150.0
const CONSECRATE_DUR            = 3.0
const CONSECRATE_TICK           = 1.0
const CONSECRATE_DMG_PER_TICK   = 8.0
const CONSECRATE_HEAL_PER_TICK  = 10.8
const CONSECRATE_CD             = 8.0

# F — Purify: rectangle skill-shot, wide enough to catch two allies
# standing close together. Cleanses CC/debuffs + a small heal-over-time.
# Also lands a small instant heal on the Cleric itself (on top of the HoT it
# already gets from being caught in its own rect) — a support tool that
# leaves the healer completely empty-handed otherwise discourages using it
# proactively rather than only in a panic.
const PURIFY_LENGTH    = 300.0
const PURIFY_WIDTH     = 180.0
const PURIFY_HOT_DUR   = 4.0
const PURIFY_HOT_TICK  = 8.1
const PURIFY_SELF_HEAL = 12.0
const PURIFY_CD        = 10.0

# Shift — Guardian Ward: shields the lowest-HP ally in radius. Scales with
# current combo stacks but no longer consumes them (Smite/Consecrate still
# feed Guardian's Ward AND heal_mult() off the same stacks now) — nerfed
# down in base/scaling to compensate for stacks no longer being spent.
const WARD_TARGET_RADIUS = 400.0
const WARD_BASE_SHIELD   = 25.0
const WARD_PER_STACK     = 7.5
const WARD_DUR           = 3.0
const WARD_CD            = 9.0

# R — Guardian's Bond: links Cleric + lowest-HP ally in radius. Damage
# either takes is split between them, both get a damage-reduction buff
# and a small heal-over-time. No ally in range -> self-only (no split,
# still gets the reduction + HoT) — the "cleric got bursted" panic button.
const BOND_TARGET_RADIUS = 400.0
const BOND_DUR           = 4.0
const BOND_SPLIT_PCT     = 0.5
const BOND_DMG_REDUCE    = 0.20
const BOND_HOT_TICK      = 6.75

# Passive — Devotion: landing a heal/shield/cleanse on an ALLY (not self)
# grants a damage-reduction window. Rewards actually playing support.
const DEVOTION_DUR        = 4.0
const DEVOTION_DMG_REDUCE = 0.15
var devotion_time_left := 0.0

# Combo stacks (built by Smite/Consecrate landing on an enemy, same base
# mechanism Duelist/Bruiser use) don't boost Cleric's own damage — they
# boost healing output instead, and Guardian Ward cashes them in directly.
const HEAL_PER_STACK = 0.10

var consecrate_time_left := 0.0
var consecrate_tick_timer := 0.0
var consecrate_pos := Vector2.ZERO

func _ready():
	hp     = CLERIC_MAX_HP
	max_hp = CLERIC_MAX_HP
	base_color = Color(0.95, 0.88, 0.6)
	is_healer = true  # AI focus-targeting trains onto healers

func _physics_process(delta):
	devotion_time_left = max(0.0, devotion_time_left - delta)
	if consecrate_time_left > 0:
		consecrate_time_left -= delta
		consecrate_tick_timer -= delta
		if consecrate_tick_timer <= 0:
			consecrate_tick_timer = CONSECRATE_TICK
			for e in get_enemies_in_range(CONSECRATE_RADIUS, consecrate_pos):
				deal_damage(e, CONSECRATE_DMG_PER_TICK)
			for a in get_allies_in_range(CONSECRATE_RADIUS, consecrate_pos):
				heal(a, CONSECRATE_HEAL_PER_TICK * heal_mult())
				if a != self:
					devotion_time_left = DEVOTION_DUR
	# Devotion + Guardian's Bond are Cleric's only two damage-reduction
	# sources, recomputed fully each tick (same pattern Bruiser uses to
	# combine Unbreakable + Warcry) so neither can clobber the other.
	dmg_reduction = (DEVOTION_DMG_REDUCE if devotion_time_left > 0 else 0.0) \
		+ (BOND_DMG_REDUCE if bond_time_left > 0 else 0.0)
	super._physics_process(delta)

func heal_mult() -> float:
	return 1.0 + combo_stacks * HEAL_PER_STACK

# Damage doesn't scale with combo stacks for Cleric — they power healing
# instead (see heal_mult()) — but add_combo_stack() is NOT overridden, so
# Smite/Consecrate still build stacks the same way Duelist/Bruiser do.
func combo_mult() -> float:
	return 1.0

func on_landed_parry():
	pass

func get_shift_active() -> bool:
	return barrier_time_left > 0

# ---- Ability overrides ----

func try_auto(opp: Entity):
	if not can_start_ability() or cd_auto > 0 or opp == null:
		return
	cd_auto = SMITE_CD
	facing = get_aim_dir(opp)
	_fire(facing, SMITE_SPEED, SMITE_RADIUS, SMITE_DMG, opp, Color(0.95, 0.9, 0.6), 7.0)

func try_a1(_opp: Entity):
	if not can_start_ability() or cd_a1 > 0:
		return
	var target = get_lowest_hp_ally(MENDING_TARGET_RADIUS)
	casting = {"type": "a1", "time_left": MENDING_CAST, "total": MENDING_CAST, "opp": target}

func resolve_a1(target: Entity):
	if target == null or not is_instance_valid(target) or not target.alive:
		target = self
	facing = get_aim_dir(target)
	_fire(facing, MENDING_SPEED, MENDING_RADIUS, MENDING_HEAL * heal_mult(), target,
		Color(0.95, 0.85, 0.5), 9.0, 0.0, 0.5, false, false, "orb", true,
		MENDING_ENEMY_DMG, MENDING_ENEMY_SLOW_DUR, MENDING_ENEMY_SLOW_PCT)
	if target != self:
		devotion_time_left = DEVOTION_DUR
	cd_a1 = MENDING_CD
	recovering = {"type": "a1", "time_left": MENDING_RECOVERY, "total": MENDING_RECOVERY}
	commit_ability()

func try_a2(_opp: Entity):
	if not can_start_ability() or cd_a2 > 0:
		return
	consecrate_pos = global_position
	consecrate_time_left = CONSECRATE_DUR
	consecrate_tick_timer = 0.0
	FX.impact_burst(get_parent(), global_position, Color(0.95, 0.9, 0.55), 18, 180.0)
	_spawn_zone_fx(consecrate_pos, CONSECRATE_RADIUS, CONSECRATE_DUR, Color(0.95, 0.85, 0.4))
	cd_a2 = CONSECRATE_CD
	commit_ability()

func resolve_a2(_opp: Entity):
	pass

func try_a3(opp: Entity):
	if not can_start_ability() or cd_a3 > 0:
		return
	facing = get_aim_dir(opp)
	var hit_ally = false
	for a in get_allies_in_rect(PURIFY_LENGTH, PURIFY_WIDTH):
		a.cleanse_status()
		a.apply_heal_over_time(PURIFY_HOT_DUR, PURIFY_HOT_TICK * heal_mult())
		FX.heal_sparkle(get_parent(), a.global_position)
		if a != self:
			hit_ally = true
	if hit_ally:
		devotion_time_left = DEVOTION_DUR
	heal(self, PURIFY_SELF_HEAL * heal_mult())
	FX.impact_burst(get_parent(), global_position + facing * (PURIFY_LENGTH * 0.5), Color(0.95, 0.92, 0.7), 16, 180.0)
	_spawn_rect_fx(global_position, facing, PURIFY_LENGTH, PURIFY_WIDTH, 0.5, Color(0.95, 0.9, 0.55))
	cd_a3 = PURIFY_CD
	commit_ability()

func resolve_a3(_opp: Entity):
	pass

func try_shift(_opp: Entity):
	if not can_start_ability() or cd_shift > 0:
		return
	var target = get_lowest_hp_ally(WARD_TARGET_RADIUS)
	var shield_amt = WARD_BASE_SHIELD + combo_stacks * WARD_PER_STACK
	target.barrier_hp_left = shield_amt
	target.barrier_time_left = WARD_DUR
	if target != self:
		devotion_time_left = DEVOTION_DUR
	FX.impact_burst(get_parent(), target.global_position, Color(0.95, 0.9, 0.6), 14, 150.0)
	cd_shift = WARD_CD
	commit_ability()

func try_ult(_opp: Entity):
	# No can_start_ability() gate on purpose — this needs to work even
	# while stunned, since it's meant to be usable as an "I'm about to die"
	# panic button, not just a proactive team-fight tool. Also not gated on
	# ability_commit_time_left for the same reason (matches Bruiser's
	# Unbreakable) — it still SETS the timer below so there's a beat before
	# the next action, it just never lets a prior one block IT from firing.
	if not alive or ult_charge < ULT_CHARGE_MAX:
		return
	ult_charge = 0.0
	var partner = get_lowest_hp_ally(BOND_TARGET_RADIUS, false)
	apply_damage_bond(partner, BOND_DUR, BOND_SPLIT_PCT)
	apply_heal_over_time(BOND_DUR, BOND_HOT_TICK * heal_mult())
	if partner != null:
		partner.apply_damage_bond(self, BOND_DUR, BOND_SPLIT_PCT)
		partner.apply_heal_over_time(BOND_DUR, BOND_HOT_TICK * heal_mult())
		devotion_time_left = DEVOTION_DUR
	FX.impact_burst(get_parent(), global_position, Color(0.95, 0.9, 0.5), 22, 220.0)
	# Activation moment needs to read as clearly as a big ultimate should —
	# the persistent ring/beam (EntityView3D._update_bond_fx) shows it's
	# ongoing, but this marks the exact instant it went off.
	_spawn_zone_fx(global_position, 90.0, 0.6, Color(1.0, 0.92, 0.55))
	if partner != null:
		_spawn_zone_fx(partner.global_position, 90.0, 0.6, Color(1.0, 0.92, 0.55))
	commit_ability()

func resolve_ult(_opp: Entity):
	pass

# ---- Drawing ----
# No character body art (Cleric was added after the 3D migration, so it has
# no legacy procedural 2D form) — just the Consecrate zone fallback for the
# plain-2D path. In 3D-view mode the real telegraph is a proper
# AreaFxView3D effect spawned once from try_a2(), not drawn here.
func _draw_body(_now: int, _accent: Color):
	if consecrate_time_left > 0:
		var local_center = to_local(consecrate_pos)
		var pulse = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		draw_arc(local_center, CONSECRATE_RADIUS, 0, TAU, 48, Color(0.95, 0.9, 0.55, 0.3 * pulse), 3.0)

# Combo pip: a small holy cross, distinct from Duelist's sword/Bruiser's hammer.
func _draw_combo_pip(pos: Vector2):
	draw_line(pos + Vector2(0, -6), pos + Vector2(0, 6), Color(0.95, 0.9, 0.6, 0.95), 2.2)
	draw_line(pos + Vector2(-4, -1), pos + Vector2(4, -1), Color(0.95, 0.9, 0.6, 0.95), 2.2)
