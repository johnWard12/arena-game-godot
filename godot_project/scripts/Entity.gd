extends Node2D
class_name Entity

const FX = preload("res://scripts/FX.gd")
const CoordUtil = preload("res://scripts/CoordUtil.gd")

# ---- Tunables ----
const MAX_SPEED = 435.0
const ACCEL = 3450.0
const FRICTION = 1650.0
const DASH_SPEED = 1275.0
const DASH_DUR = 0.13
const CARRY = 0.7

const AUTO_CD = 0.55
const AUTO_DMG = 4.0
const AUTO_RANGE = 150.0

const A1_CAST = 0.09
const A1_RECOVERY = 0.13
const A1_CD = 1.8
const A1_DMG = 12.0
const A1_RANGE = 145.0
const A1_SLOW_DUR = 2.0
const A1_SLOW_PCT = 0.30

const A2_CAST = 0.14
const A2_RECOVERY = 0.22
const A2_MISS_RECOVERY = 0.45
const A2_CD = 6.5
const A2_DMG = 20.4
const A2_RANGE = 150.0
const A2_LUNGE_DIST = 270.0
const A2_LUNGE_DUR = 0.13

const ULT_CAST = 0.45
const ULT_RECOVERY = 0.3
const ULT_DMG_BASE = 35.0
const ULT_DMG_MISSING_BONUS = 40.0
const ULT_RANGE = 155.0
const ULT_CHARGE_MAX = 14.0

const COMBO_MAX = 3
const COMBO_DECAY = 2.4
const COMBO_DMG_PER_STACK = 0.16

const PARRY_DUR = 0.22
const PARRY_CD = 5.0
const PARRY_STUN_DUR = 0.65
const STUN_DUR = 0.5

const BLOODLUST_DUR          = 1.5
const BLOODLUST_ATKSPD_MULT  = 1.10
const BLOODLUST_MOVESPD_MULT = 1.10

# F — Sword Throw: thrown blade, low damage, slows on hit
const SWORD_THROW_CAST     = 0.12
const SWORD_THROW_RECOVERY = 0.18
const SWORD_THROW_CD       = 4.0
const SWORD_THROW_SPEED    = 1400.0
const SWORD_THROW_RADIUS   = 16.0
const SWORD_THROW_DMG_BASE          = 6.0
const SWORD_THROW_DMG_MISSING_BONUS = 8.0
const SWORD_THROW_SLOW_DUR = 2.0
const SWORD_THROW_SLOW_PCT = 0.30

const DASH_CHARGES_MAX  = 2
const DASH_CHARGE_REGEN = 2.5

const RADIUS = 34.0
const TRAIL_LIFETIME_MS = 220

# sword swing tunables
const SWORD_LEN = 100.0
const SWORD_WIDTH = 15.0

# Shared CC / knockup
const KNOCKUP_DUR = 1.0

# Bladestorm (Duelist R)
const BLADESTORM_DUR          = 1.5
const BLADESTORM_HIT_INTERVAL = 0.30
const BLADESTORM_DMG          = 14.0
const BLADESTORM_RANGE        = 170.0

# Iron Resolve (Duelist Shift) — converts current combo stacks into a
# temporary flat damage-reduction buff, consuming the stacks.
const IRON_RESOLVE_CD        = 7.0
const IRON_RESOLVE_DUR       = 2.0
const IRON_RESOLVE_PER_STACK = 0.10

# ---- State ----
var is_player := false

# When true, Main.gd is presenting this entity via EntityView3D instead of
# this node's own procedural 2D art, so _draw() skips the character-art
# pass entirely. It must NOT skip _draw_hud(): the entity node itself stays
# visible (only the body art is suppressed) specifically so the overhead
# HUD — HP bar, cast bar, combo pips, status rings, stun stars, knockup
# arrows — keeps rendering. None of that has a 3D equivalent; setting the
# whole node invisible (the original approach) silently killed all of it.
var use_3d_view := false

var base_color := Color(0.37, 0.88, 0.75)
var velocity := Vector2.ZERO
var facing := Vector2.RIGHT

var dashing := false
var dash_time_left := 0.0
var dash_dir := Vector2.ZERO

var lunging := false
var lunge_time_left := 0.0
var lunge_dir := Vector2.ZERO
var lunge_opponent: Entity = null
var lunge_speed := 0.0
var lunge_reach := 0.0

var hp := 150.0
var max_hp := 150.0
var alive := true

var casting = null
var recovering = null

var cd_auto := 0.0
var cd_a1 := 0.0
var cd_a2 := 0.0
var cd_shift := 0.0
var ult_charge := 0.0

# Ult charges faster while "engaged" — landing damage or a heal refreshes
# this window. Passive fill takes ULT_CHARGE_PASSIVE_TIME seconds; staying
# continuously engaged takes ULT_CHARGE_ACTIVE_TIME instead.
var ult_active_time_left := 0.0
const ULT_ACTIVE_WINDOW := 3.0
const ULT_CHARGE_PASSIVE_TIME := 30.0
const ULT_CHARGE_ACTIVE_TIME := 20.0

var combo_stacks := 0
var combo_time_left := 0.0

var parrying := false
var parry_time_left := 0.0
var parry_cd_left := 0.0

var stunned_time_left := 0.0
var slowed_time_left  := 0.0
var slow_pct          := 0.5

# A root locks movement but NOT abilities — distinct from a stun, which
# locks both. Introduced for Ranger's Snare Trap; nothing else uses it yet.
var rooted_time_left  := 0.0

# While > 0, this entity drops out of AI auto-targeting (see
# get_nearest_enemy/get_enemies_in_range). Introduced for Ranger's
# Camouflage; nothing else sets it yet.
var invisible_time_left := 0.0

# Heal-over-time — generic, so any future ability can use it the same way
# attacks all route through deal_damage(). Introduced for Cleric.
var hot_time_left := 0.0
var hot_tick_timer := 0.0
var hot_per_tick := 0.0
const HOT_TICK_INTERVAL := 1.0

func apply_heal_over_time(duration: float, per_tick: float):
	hot_time_left = max(hot_time_left, duration)
	hot_per_tick = max(hot_per_tick, per_tick)

# Resets every CC/debuff timer at once — Cleric's Purify uses this, but
# it's generically reusable for any future cleanse-type ability.
func cleanse_status():
	stunned_time_left = 0.0
	rooted_time_left = 0.0
	slowed_time_left = 0.0
	freeze_time_left = 0.0
	outgoing_dmg_debuff_time_left = 0.0
	outgoing_dmg_mult = 1.0

# Damage-sharing link (Cleric's Guardian's Bond). Only bond_partner/
# bond_time_left/bond_split_pct live here, for the split calculation in
# deal_damage() below — any incoming damage-reduction from being bonded is
# each class's own responsibility to fold into its own dmg_reduction
# computation (same pattern Bruiser already uses to combine Unbreakable +
# Warcry), so this can't accidentally clobber another class's other
# damage-reduction sources.
var bond_partner: Entity = null
var bond_time_left := 0.0
var bond_split_pct := 0.5

func apply_damage_bond(partner: Entity, duration: float, split_pct: float):
	bond_partner = partner
	bond_time_left = max(bond_time_left, duration)
	bond_split_pct = split_pct

# Cosmetic-only tag on top of stunned_time_left so the view layer can show a
# distinct ice-crystal effect for freeze (Mage's Nova) instead of the generic
# stun stars — set alongside stunned_time_left by apply_freeze(), never read
# by gameplay logic.
var freeze_time_left := 0.0

# Multiplier applied to any incoming stun/freeze duration (1.0 = no resistance).
# Subclasses override this in _ready() to grant CC resistance.
var stun_resist_mult  := 1.0
var recovery_slows_movement := true

# CC immunity — blocks apply_stun and apply_slow when true
var cc_immune := false

# Flat damage reduction (0.0 = none, 0.25 = 25% less damage taken)
var dmg_reduction := 0.0

# Outgoing damage multiplier on THIS entity's own attacks (1.0 = normal,
# 0.9 = deals 10% less). Set on an entity by a debuff like Bruiser's Warcry.
var outgoing_dmg_mult := 1.0
var outgoing_dmg_debuff_time_left := 0.0

# Iron Resolve (Duelist Shift) active-buff timer
var iron_resolve_time_left := 0.0

# Blood-lust: granted on a successful parry (see on_landed_parry())
var bloodlust_time_left := 0.0

var cd_a3             := 0.0
var barrier_hp_left   := 0.0
var barrier_time_left := 0.0
var speed_override    := -1.0

# sword swing: arc sweep from start_angle to start_angle+arc_span over swing_total seconds
var swing_time_left := 0.0
var swing_total := 0.0
var swing_start_angle := 0.0
var swing_arc_span := 0.0

# hit flash on this entity when it receives damage
var hit_flash_left := 0.0

var dash_charges_max := DASH_CHARGES_MAX
var dash_charges := DASH_CHARGES_MAX
var dash_charge_timer := 0.0

var walk_phase := 0.0

var knockup_time_left    := 0.0
var bladestorm_time_left := 0.0
var bladestorm_hit_timer := 0.0

var dash_fx_timer := 0.0

var opponent: Entity = null
var arena_rect := Rect2(Vector2.ZERO, Vector2(1000, 600))
var obstacle_rects: Array[Rect2] = []
var trail := []

# Full match roster (both teams), kept in sync by Main.gd alongside
# `opponent`. AoE abilities use this to hit every enemy in range instead of
# just the single primary `opponent` — in 1v1 it's the same one enemy
# either way, so no ability behavior changes there.
var all_fighters: Array = []

# Which side this entity is on. 1v1 never needs to touch this (default 0
# for everyone would make "nearest enemy" degenerate); Main.gd assigns 0
# to the player's team and 1 to the opposing team for any match size.
var team_id := 0

# Picks the closest living entity from `candidates` that isn't on this
# entity's team. Used by Main.gd to keep every fighter's `opponent`
# pointed at a sensible target in 2v2/3v3, and works unchanged for 1v1
# (a candidates list of exactly one enemy just returns that enemy).
#
# respect_invisibility=false lets a human player's own targeting see
# through a camouflaged enemy (they're expected to manually track/aim),
# while AI targeting (the only other caller) leaves it true so bots
# genuinely lose the trail — see Ranger's Camouflage.
func get_nearest_enemy(candidates: Array, respect_invisibility: bool = true) -> Entity:
	var nearest: Entity = null
	var nearest_d := INF
	for c in candidates:
		if c == self or not is_instance_valid(c) or not c.alive or c.team_id == team_id:
			continue
		if respect_invisibility and c.invisible_time_left > 0:
			continue
		var d = global_position.distance_to(c.global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = c
	return nearest

# Every living enemy within `radius` of `center` (defaults to this entity's
# own position) — what a real AoE ability should hit, as opposed to just
# `opponent` (the single nearest enemy). Always respects invisibility: an
# AoE hits what it can see, regardless of who cast it.
func get_enemies_in_range(radius: float, center = null) -> Array:
	var origin: Vector2 = global_position if center == null else center
	var result := []
	for c in all_fighters:
		if c == self or not is_instance_valid(c) or not c.alive or c.team_id == team_id:
			continue
		if c.invisible_time_left > 0:
			continue
		if origin.distance_to(c.global_position) <= radius:
			result.append(c)
	return result

# Whichever of (self, allies within radius) has the lower HP% — the
# standard targeting rule for Cleric's single-target support abilities.
# include_self=true means it always returns *something* (never null),
# degrading gracefully to "always self" in 1v1 or when no ally is close.
# Pass include_self=false when the caller specifically needs a separate
# partner (e.g. Guardian's Bond, which can't "bond" with itself).
func get_lowest_hp_ally(radius: float, include_self: bool = true) -> Entity:
	var best: Entity = self if include_self else null
	var best_pct = (hp / max_hp) if include_self else INF
	for c in all_fighters:
		if c == self or not is_instance_valid(c) or not c.alive or c.team_id != team_id:
			continue
		if global_position.distance_to(c.global_position) > radius:
			continue
		var pct = c.hp / c.max_hp
		if pct < best_pct:
			best_pct = pct
			best = c
	return best

# Every living ally within `radius` of `center` (self's position by
# default), self included — mirrors get_enemies_in_range for the ally
# side. Used by zone abilities that heal allies standing in them.
func get_allies_in_range(radius: float, center = null) -> Array:
	var origin: Vector2 = global_position if center == null else center
	var result := []
	for c in all_fighters:
		if not is_instance_valid(c) or not c.alive or c.team_id != team_id:
			continue
		if origin.distance_to(c.global_position) <= radius:
			result.append(c)
	return result

# Every living ally inside a rectangle extending `length` forward from
# self in the facing direction, `width` wide — the first non-circular AoE
# shape in the game. Self is included automatically (it's always at the
# rectangle's own origin corner). Used by Purify's line skill-shot.
func get_allies_in_rect(length: float, width: float) -> Array:
	var result := []
	var perp = Vector2(-facing.y, facing.x)
	var half_w = width * 0.5
	for c in all_fighters:
		if not is_instance_valid(c) or not c.alive or c.team_id != team_id:
			continue
		var rel = c.global_position - global_position
		var fwd_dist = rel.dot(facing)
		var lat_dist = rel.dot(perp)
		if fwd_dist >= 0.0 and fwd_dist <= length and abs(lat_dist) <= half_w:
			result.append(c)
	return result

signal died
signal projectile_spawned(proj)
signal trap_spawned(trap)
# Fire-and-forget ground-effect visual (a cast flash or a pulsing zone glow).
# Purely cosmetic — Main.gd is the only listener, so headless Simulate.gd
# runs are unaffected and gameplay never depends on this actually rendering.
signal area_fx_spawned(fx: Dictionary)
@warning_ignore("unused_signal") # emitted by subclasses (Bruiser/Mage), not the base class itself
signal screen_shake(intensity: float, duration: float)

func _physics_process(delta):
	var now = Time.get_ticks_msec()
	prune_trail(now)
	if not alive:
		return
	bloodlust_time_left = max(0.0, bloodlust_time_left - delta)
	var atkspd_mult = BLOODLUST_ATKSPD_MULT if bloodlust_time_left > 0 else 1.0
	cd_auto = max(0.0, cd_auto - delta * atkspd_mult)
	cd_a1 = max(0.0, cd_a1 - delta * atkspd_mult)
	cd_a2 = max(0.0, cd_a2 - delta * atkspd_mult)
	cd_a3 = max(0.0, cd_a3 - delta * atkspd_mult)
	cd_shift = max(0.0, cd_shift - delta)
	parry_cd_left = max(0.0, parry_cd_left - delta)
	if outgoing_dmg_debuff_time_left > 0:
		outgoing_dmg_debuff_time_left = max(0.0, outgoing_dmg_debuff_time_left - delta)
		if outgoing_dmg_debuff_time_left <= 0:
			outgoing_dmg_mult = 1.0
	if iron_resolve_time_left > 0:
		iron_resolve_time_left = max(0.0, iron_resolve_time_left - delta)
		if iron_resolve_time_left <= 0:
			dmg_reduction = 0.0
	if dash_charges < dash_charges_max:
		dash_charge_timer += delta
		if dash_charge_timer >= DASH_CHARGE_REGEN:
			dash_charge_timer -= DASH_CHARGE_REGEN
			dash_charges += 1
	hit_flash_left    = max(0.0, hit_flash_left - delta)
	slowed_time_left  = max(0.0, slowed_time_left - delta)
	rooted_time_left  = max(0.0, rooted_time_left - delta)
	invisible_time_left = max(0.0, invisible_time_left - delta)
	freeze_time_left  = max(0.0, freeze_time_left - delta)
	knockup_time_left = max(0.0, knockup_time_left - delta)
	if hot_time_left > 0:
		hot_time_left -= delta
		hot_tick_timer -= delta
		if hot_tick_timer <= 0:
			hot_tick_timer = HOT_TICK_INTERVAL
			hp = min(max_hp, hp + hot_per_tick)
	if bond_time_left > 0:
		bond_time_left = max(0.0, bond_time_left - delta)
		if bond_time_left <= 0:
			bond_partner = null
	if bladestorm_time_left > 0:
		bladestorm_time_left  = max(0.0, bladestorm_time_left - delta)
		bladestorm_hit_timer  = max(0.0, bladestorm_hit_timer - delta)
		if stunned_time_left <= 0 and bladestorm_hit_timer <= 0:
			# Spinning hits everyone in range, not just the primary target —
			# matters in 2v2/3v3 where more than one foe can be caught.
			var hit_someone := false
			for target in get_enemies_in_range(BLADESTORM_RANGE):
				deal_damage(target, BLADESTORM_DMG)
				add_combo_stack()
				hit_someone = true
			if hit_someone:
				start_swing(360.0, 0.25)
			bladestorm_hit_timer = BLADESTORM_HIT_INTERVAL
	if barrier_time_left > 0:
		barrier_time_left = max(0.0, barrier_time_left - delta)
		if barrier_time_left <= 0:
			barrier_hp_left = 0.0
	if swing_time_left > 0:
		swing_time_left = max(0.0, swing_time_left - delta)
	ult_active_time_left = max(0.0, ult_active_time_left - delta)
	if ult_charge < ULT_CHARGE_MAX:
		var fill_time = ULT_CHARGE_ACTIVE_TIME if ult_active_time_left > 0 else ULT_CHARGE_PASSIVE_TIME
		ult_charge = min(ULT_CHARGE_MAX, ult_charge + delta * (ULT_CHARGE_MAX / fill_time))
	if combo_time_left > 0:
		combo_time_left -= delta
		if combo_time_left <= 0:
			combo_stacks = 0

	if parrying:
		parry_time_left -= delta
		if parry_time_left <= 0:
			parrying = false

	if stunned_time_left > 0:
		stunned_time_left -= delta
		var spd = velocity.length()
		if spd > 0:
			velocity = velocity.normalized() * max(0.0, spd - FRICTION * 2.0 * delta)
		global_position += velocity * delta
		clamp_to_arena()
		queue_redraw()
		return

	if knockup_time_left > 0:
		var spd = velocity.length()
		if spd > 0:
			velocity = velocity.normalized() * max(0.0, spd - FRICTION * 2.5 * delta)
		global_position += velocity * delta
		clamp_to_arena()
		queue_redraw()
		return

	if casting != null:
		casting["time_left"] -= delta
		if casting["time_left"] <= 0:
			var t = casting["type"]
			var opp = casting["opp"]
			casting = null
			if t == "a1":
				resolve_a1(opp)
			elif t == "a2":
				resolve_a2(opp)
			elif t == "ult":
				resolve_ult(opp)
			elif t == "a3":
				resolve_a3(opp)

	if recovering != null:
		recovering["time_left"] -= delta
		if recovering["time_left"] <= 0:
			recovering = null

	var input_vec := get_movement_input()
	var locked = casting != null
	var recovering_slow = recovering != null and recovery_slows_movement
	var debuffed_slow = slowed_time_left > 0

	if lunging:
		lunge_time_left -= delta
		velocity = lunge_dir * lunge_speed
		push_trail()
		_emit_dash_fx(delta)
		var reached = lunge_opponent != null and is_instance_valid(lunge_opponent) and lunge_opponent.alive \
			and global_position.distance_to(lunge_opponent.global_position) <= lunge_reach
		if lunge_time_left <= 0 or reached:
			lunging = false
			velocity *= 0.3
			resolve_lunge_strike(lunge_opponent)
	elif dashing:
		dash_time_left -= delta
		velocity = dash_dir * DASH_SPEED
		push_trail()
		_emit_dash_fx(delta)
		if dash_time_left <= 0:
			dashing = false
			velocity *= CARRY
	elif locked or rooted_time_left > 0:
		var spd = velocity.length()
		if spd > 0:
			var dec = FRICTION * delta * 2.0
			var ns = max(0.0, spd - dec)
			velocity = velocity.normalized() * ns
	else:
		var speed_mult = 1.0
		if bladestorm_time_left > 0:
			speed_mult = 1.0  # immune to slows during bladestorm
		elif recovering_slow and debuffed_slow:
			speed_mult = min(0.5, 1.0 - slow_pct)
		elif recovering_slow:
			speed_mult = 0.5
		elif debuffed_slow:
			speed_mult = 1.0 - slow_pct
		if bloodlust_time_left > 0:
			speed_mult *= BLOODLUST_MOVESPD_MULT
		var has_input = input_vec.length() > 0.01
		if has_input:
			facing = input_vec.normalized()
			var eff_speed = speed_override if speed_override > 0.0 else MAX_SPEED
			var target_v = facing * eff_speed * speed_mult
			velocity = velocity.move_toward(target_v, ACCEL * delta)
		else:
			var spd = velocity.length()
			if spd > 0:
				var dec = FRICTION * delta
				var ns = max(0.0, spd - dec)
				velocity = velocity.normalized() * ns
		if not is_player and casting == null and opponent != null:
			facing = (opponent.global_position - global_position).normalized()

	global_position += velocity * delta
	clamp_to_arena()
	walk_phase += velocity.length() * delta * 0.055
	queue_redraw()

func get_movement_input() -> Vector2:
	return Vector2.ZERO

func get_aim_dir(opp: Entity) -> Vector2:
	if opp == null:
		return facing
	return (opp.global_position - global_position).normalized()

func is_facing_target(target: Entity, half_angle_deg: float) -> bool:
	if target == null:
		return false
	var dir = (target.global_position - global_position).normalized()
	return facing.dot(dir) >= cos(deg_to_rad(half_angle_deg))

func clamp_to_arena():
	var r = RADIUS
	var x = clamp(global_position.x, arena_rect.position.x + r, arena_rect.position.x + arena_rect.size.x - r)
	var y = clamp(global_position.y, arena_rect.position.y + r, arena_rect.position.y + arena_rect.size.y - r)
	if x != global_position.x:
		velocity.x = 0
	if y != global_position.y:
		velocity.y = 0
	global_position = Vector2(x, y)
	resolve_obstacle_collisions()

func resolve_obstacle_collisions():
	for obstacle in obstacle_rects:
		var closest = Vector2(
			clamp(global_position.x, obstacle.position.x, obstacle.position.x + obstacle.size.x),
			clamp(global_position.y, obstacle.position.y, obstacle.position.y + obstacle.size.y)
		)
		var offset = global_position - closest
		var dist = offset.length()
		if dist > 0.001 and dist < RADIUS:
			var normal = offset / dist
			global_position = closest + normal * RADIUS
			var into_wall = velocity.dot(normal)
			if into_wall < 0:
				velocity -= normal * into_wall
		elif obstacle.has_point(global_position):
			var left = abs(global_position.x - obstacle.position.x)
			var right = abs(obstacle.position.x + obstacle.size.x - global_position.x)
			var top = abs(global_position.y - obstacle.position.y)
			var bottom = abs(obstacle.position.y + obstacle.size.y - global_position.y)
			var min_push = min(min(left, right), min(top, bottom))
			if min_push == left:
				global_position.x = obstacle.position.x - RADIUS
				velocity.x = min(0.0, velocity.x)
			elif min_push == right:
				global_position.x = obstacle.position.x + obstacle.size.x + RADIUS
				velocity.x = max(0.0, velocity.x)
			elif min_push == top:
				global_position.y = obstacle.position.y - RADIUS
				velocity.y = min(0.0, velocity.y)
			else:
				global_position.y = obstacle.position.y + obstacle.size.y + RADIUS
				velocity.y = max(0.0, velocity.y)

func steer_around_obstacles(desired_dir: Vector2) -> Vector2:
	if desired_dir.length() < 0.01:
		return desired_dir
	var dir = desired_dir.normalized()
	var probe_dist = RADIUS + 34.0
	for obstacle in obstacle_rects:
		var grown = obstacle.grow(RADIUS + 16.0)
		if grown.has_point(global_position + dir * probe_dist):
			var closest = Vector2(
				clamp(global_position.x, obstacle.position.x, obstacle.position.x + obstacle.size.x),
				clamp(global_position.y, obstacle.position.y, obstacle.position.y + obstacle.size.y)
			)
			var normal = global_position - closest
			normal = normal.normalized() if normal.length() > 0.01 else -dir
			var tangent = Vector2(-normal.y, normal.x)
			if tangent.dot(dir) < 0:
				tangent = -tangent
			return (tangent + normal * 0.4).normalized()
	return desired_dir

func _emit_dash_fx(delta: float):
	dash_fx_timer -= delta
	if dash_fx_timer <= 0:
		dash_fx_timer = 0.03
		FX.dash_puff(get_parent(), global_position - velocity.normalized() * RADIUS * 0.6, base_color)

func push_trail():
	var now = Time.get_ticks_msec()
	trail.append({"pos": global_position, "time": now})
	prune_trail(now)

func prune_trail(now: int):
	var cutoff = now - TRAIL_LIFETIME_MS
	while trail.size() > 0 and trail[0]["time"] < cutoff:
		trail.pop_front()

func can_start_ability() -> bool:
	return alive and casting == null and recovering == null and not dashing and not lunging and not parrying and stunned_time_left <= 0

func can_dash(dir: Vector2) -> bool:
	return alive and casting == null and not dashing and not lunging and not parrying and stunned_time_left <= 0 \
		and dir.length() >= 0.01 and dash_charges > 0

func can_parry() -> bool:
	return alive and parry_cd_left <= 0 and casting == null and not dashing and not lunging and stunned_time_left <= 0

func get_status_accent(default_color: Color) -> Color:
	if stunned_time_left > 0:
		return Color(0.9, 0.9, 0.3)
	if knockup_time_left > 0:
		return Color(0.9, 0.6, 0.15)
	if bladestorm_time_left > 0:
		return Color(1.0, 0.82, 0.15)
	if bloodlust_time_left > 0:
		return Color(0.85, 0.1, 0.15)
	if parrying:
		return Color(0.3, 0.7, 1.0)
	if lunging:
		return Color(1, 0.24, 0.24)
	if dashing:
		return Color(1, 0.36, 0.48)
	if casting != null:
		return Color(1, 0.82, 0.4)
	if recovering != null:
		return Color(0.78, 0.61, 1)
	return default_color

func get_knockup_draw_offset() -> float:
	if knockup_time_left <= 0.0:
		return 0.0
	var t = (1.0 - knockup_time_left / KNOCKUP_DUR) * PI
	return -sin(t) * 130.0

# In use_3d_view mode, this Node2D's global_position is still raw
# simulation coordinates (gameplay math depends on that — distances,
# ranges, movement — so it must never change). But there's no Camera2D,
# so without correction the 2D HUD draws at that raw position 1:1 in
# screen pixels, while the 3D camera — tilted ~45 degrees, not top-down —
# renders the character at a different screen position entirely. This
# projects where the character's feet actually land on screen and returns
# the delta, so _draw() can shift just the HUD drawing to match without
# touching global_position itself.
func _get_hud_screen_correction() -> Vector2:
	var cam = get_tree().get_first_node_in_group("game_camera")
	if cam == null:
		return Vector2.ZERO
	var screen_pos = cam.unproject_position(CoordUtil.to_world(global_position, 0.0))
	return screen_pos - global_position

# ---- Sword swing ----
func start_swing(arc_span_deg: float, duration: float):
	swing_total = duration
	swing_time_left = duration
	swing_arc_span = deg_to_rad(arc_span_deg)
	# sweep from left-of-facing to right-of-facing
	swing_start_angle = facing.angle() - swing_arc_span * 0.5

# ---- Combat ----
func combo_mult() -> float:
	return 1.0 + combo_stacks * COMBO_DMG_PER_STACK

func add_combo_stack():
	combo_stacks = min(COMBO_MAX, combo_stacks + 1)
	combo_time_left = COMBO_DECAY

# Called on whoever successfully parried an attack. Base (Duelist) behavior
# grants Blood-lust; other classes override this to no-op.
func on_landed_parry():
	bloodlust_time_left = BLOODLUST_DUR

# Single choke point for applying a stun/freeze so per-class CC resistance
# (e.g. Bruiser's Steady Footing) only has to live in one place.
func apply_stun(duration: float):
	if cc_immune:
		return
	stunned_time_left = max(stunned_time_left, duration * stun_resist_mult)

func apply_slow(duration: float, pct: float = 0.5):
	if cc_immune:
		return
	slowed_time_left = max(slowed_time_left, duration)
	slow_pct = max(slow_pct, pct)

# Locks movement only — abilities/attacks still work. Used by traps.
func apply_root(duration: float):
	if cc_immune:
		return
	rooted_time_left = max(rooted_time_left, duration)

# Same lockup as apply_stun, but tagged as a freeze so the view layer can
# render ice shards instead of stun stars — used by Mage's Nova.
func apply_freeze(duration: float):
	if cc_immune:
		return
	apply_stun(duration)
	freeze_time_left = max(freeze_time_left, duration * stun_resist_mult)

# Whether this entity's Shift ability is currently in its active-buff window.
# Each class parks its Shift payoff in a different field (Iron Resolve,
# Barrier, Unbreakable, Camouflage...), so the view layer asks this instead
# of knowing the per-class field names. Also true whenever an ally-granted
# Guardian Ward barrier is active, regardless of whose Shift field this is,
# since that's a real, class-agnostic buff a player needs to see.
func get_shift_active() -> bool:
	return iron_resolve_time_left > 0 or barrier_time_left > 0

# Weakens THIS entity's own outgoing damage for a duration — e.g. Bruiser's
# Warcry debuffing the opponent. Not blocked by cc_immune since it isn't CC.
func apply_outgoing_dmg_debuff(duration: float, mult: float):
	outgoing_dmg_debuff_time_left = max(outgoing_dmg_debuff_time_left, duration)
	outgoing_dmg_mult = min(outgoing_dmg_mult, mult)

func deal_damage(target: Entity, amount: float) -> bool:
	if target == null or not target.alive:
		return false
	if target.parrying:
		target.parrying = false
		target.on_landed_parry()
		apply_stun(PARRY_STUN_DUR)
		casting = null
		lunging = false
		FX.parry_flash(get_parent(), target.global_position)
		return false
	var barrier_hit := false
	if target.barrier_hp_left > 0:
		var absorbed = min(amount, target.barrier_hp_left)
		target.barrier_hp_left -= absorbed
		amount -= absorbed
		target.hit_flash_left = 0.15
		barrier_hit = true
		if amount <= 0:
			FX.hit_spark(get_parent(), target.global_position, Color(0.4, 0.8, 1.0))
			ult_active_time_left = ULT_ACTIVE_WINDOW
			return true
	if target.casting != null:
		target.casting = null
		target.apply_stun(STUN_DUR)
	amount *= outgoing_dmg_mult * (1.0 - target.dmg_reduction)
	# Guardian's Bond — split the hit with the linked partner before it
	# lands, each side reduced by their own dmg_reduction independently.
	if target.bond_time_left > 0 and target.bond_partner != null and is_instance_valid(target.bond_partner) and target.bond_partner.alive:
		var partner = target.bond_partner
		var shared = amount * target.bond_split_pct
		amount -= shared
		shared *= (1.0 - partner.dmg_reduction)
		partner.hp = max(0.0, partner.hp - shared)
		partner.hit_flash_left = 0.25
		FX.hit_spark(get_parent(), partner.global_position, partner.base_color)
		if partner.hp <= 0 and partner.alive:
			partner.alive = false
			FX.death_shatter(get_parent(), partner.global_position, partner.base_color)
			partner.died.emit()
	target.hp = max(0.0, target.hp - amount)
	target.hit_flash_left = 0.25
	FX.hit_spark(get_parent(), target.global_position, Color(0.4, 0.8, 1.0) if barrier_hit else target.base_color)
	if target.hp <= 0 and target.alive:
		target.alive = false
		FX.death_shatter(get_parent(), target.global_position, target.base_color)
		target.died.emit()
	ult_active_time_left = ULT_ACTIVE_WINDOW
	return true

# Symmetric to deal_damage() — heals `target` and, like landing a hit,
# refreshes the CASTER's (self's) ult-charge active window. Used by
# Cleric's kit; any future healer-flavored ability should route through
# this instead of poking target.hp directly, for the same reason attacks
# route through deal_damage() instead of poking target.hp directly.
func heal(target: Entity, amount: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		return
	target.hp = min(target.max_hp, target.hp + amount)
	ult_active_time_left = ULT_ACTIVE_WINDOW

func try_auto(opp: Entity):
	if not can_start_ability() or cd_auto > 0 or opp == null:
		return
	cd_auto = AUTO_CD
	facing = get_aim_dir(opp)
	start_swing(70.0, 0.12)
	if global_position.distance_to(opp.global_position) <= AUTO_RANGE:
		if deal_damage(opp, AUTO_DMG):
			add_combo_stack()

func try_a1(opp: Entity):
	if not can_start_ability() or cd_a1 > 0 or opp == null:
		return
	casting = {"type": "a1", "time_left": A1_CAST, "total": A1_CAST, "opp": opp}

func resolve_a1(opp: Entity):
	facing = get_aim_dir(opp)
	start_swing(110.0, 0.2)
	if global_position.distance_to(opp.global_position) <= A1_RANGE:
		var dmg = round(A1_DMG * combo_mult())
		if deal_damage(opp, dmg):
			opp.apply_slow(A1_SLOW_DUR, A1_SLOW_PCT)
			add_combo_stack()
	cd_a1 = A1_CD
	recovering = {"type": "a1", "time_left": A1_RECOVERY, "total": A1_RECOVERY}

func try_a2(opp: Entity):
	if not can_start_ability() or cd_a2 > 0 or opp == null:
		return
	casting = {"type": "a2", "time_left": A2_CAST, "total": A2_CAST, "opp": opp}

func resolve_a2(opp: Entity):
	var dir = get_aim_dir(opp)
	facing = dir
	lunging = true
	lunge_time_left = A2_LUNGE_DUR
	lunge_speed = A2_LUNGE_DIST / A2_LUNGE_DUR
	lunge_reach = A2_RANGE
	lunge_dir = dir
	lunge_opponent = opp
	cd_a2 = A2_CD

func resolve_lunge_strike(opp: Entity):
	start_swing(80.0, 0.16)
	var landed := false
	if opp != null and is_instance_valid(opp) and opp.alive and global_position.distance_to(opp.global_position) <= A2_RANGE:
		var dmg = round(A2_DMG * combo_mult())
		if deal_damage(opp, dmg):
			landed = true
			if opp.alive:
				opp.apply_stun(0.5)
			add_combo_stack()
	var recovery_time = A2_RECOVERY if landed else A2_MISS_RECOVERY
	recovering = {"type": "a2", "time_left": recovery_time, "total": recovery_time}

func try_ult(opp: Entity):
	if not can_start_ability() or ult_charge < ULT_CHARGE_MAX or opp == null:
		return
	ult_charge = 0.0
	bladestorm_time_left = BLADESTORM_DUR
	bladestorm_hit_timer = 0.0

func resolve_ult(_opp: Entity):
	pass

# Iron Resolve (Shift) — cashes in current combo stacks for a brief flat
# damage-reduction buff. Consumes the stacks, so it's a spend, not a bonus.
func try_shift(_opp: Entity):
	if not can_start_ability() or cd_shift > 0 or combo_stacks <= 0:
		return
	dmg_reduction = combo_stacks * IRON_RESOLVE_PER_STACK
	iron_resolve_time_left = IRON_RESOLVE_DUR
	combo_stacks = 0
	combo_time_left = 0.0
	cd_shift = IRON_RESOLVE_CD
	FX.impact_burst(get_parent(), global_position, Color(0.55, 0.75, 1.0), 14, 150.0)

func try_dash(dir: Vector2):
	if not can_dash(dir):
		return
	dash_charges -= 1
	if dash_charges == 0:
		dash_charge_timer = 0.0
	dash_dir = dir.normalized()
	dashing = true
	dash_time_left = DASH_DUR
	if recovering != null:
		recovering = null

func try_parry():
	if not can_parry():
		return
	parrying = true
	parry_time_left = PARRY_DUR
	parry_cd_left = PARRY_CD

func try_a3(opp: Entity):
	if not can_start_ability() or cd_a3 > 0 or opp == null:
		return
	casting = {"type": "a3", "time_left": SWORD_THROW_CAST, "total": SWORD_THROW_CAST, "opp": opp}

func resolve_a3(opp: Entity):
	facing = get_aim_dir(opp)
	var missing_ratio = 1.0 - (opp.hp / opp.max_hp) if opp != null and opp.alive else 0.0
	var dmg = round(SWORD_THROW_DMG_BASE + missing_ratio * SWORD_THROW_DMG_MISSING_BONUS)
	_fire(facing, SWORD_THROW_SPEED, SWORD_THROW_RADIUS, dmg, opp,
		Color(0.8, 0.85, 0.95), 10.0, SWORD_THROW_SLOW_DUR, SWORD_THROW_SLOW_PCT)
	cd_a3 = SWORD_THROW_CD
	recovering = {"type": "a3", "time_left": SWORD_THROW_RECOVERY, "total": SWORD_THROW_RECOVERY}

func _fire(dir: Vector2, speed: float, radius: float, dmg: float, tgt: Entity, col: Color, vis_r: float, slow: float = 0.0, slow_amount: float = 0.5, track: bool = false, pierce: bool = false, kind: String = "orb", is_heal: bool = false):
	var proj = load("res://scripts/Projectile.gd").new()
	proj.global_position = global_position + dir * (RADIUS + vis_r + 2.0)
	proj.velocity = dir * speed
	proj.damage = dmg
	proj.hit_radius = radius
	proj.owner_entity = self
	proj.target = tgt
	proj.proj_color = col
	proj.proj_radius_visual = vis_r
	proj.apply_slow = slow
	proj.apply_slow_pct = slow_amount
	proj.report_result = track
	proj.pierce = pierce
	proj.visual_kind = kind
	proj.is_heal = is_heal
	proj.obstacle_rects = obstacle_rects
	projectile_spawned.emit(proj)

func _place_trap(pos: Vector2, radius: float, arm_delay: float, lifetime: float, root_duration: float, col: Color):
	var trap = load("res://scripts/Trap.gd").new()
	trap.global_position = pos
	trap.owner_entity = self
	trap.radius = radius
	trap.arm_delay = arm_delay
	trap.lifetime = lifetime
	trap.root_duration = root_duration
	trap.trap_color = col
	trap_spawned.emit(trap)

# A persistent glowing ground zone (e.g. Consecrate) — stays put at `pos`
# for `duration`, completely decoupled from the caster's own position from
# that point on. Fixes the class of bug where a ground effect visually drags
# along behind whoever cast it because it was rendered relative to their
# current position instead of where it was actually placed.
func _spawn_zone_fx(pos: Vector2, radius: float, duration: float, color: Color):
	area_fx_spawned.emit({
		"shape": "circle", "pos": pos, "facing": Vector2.RIGHT,
		"size": Vector2(radius, 0.0), "duration": duration, "color": color,
	})

# A brief rectangular cast flash (e.g. Purify) so a skill-shot's true hit
# area — and the fact that it actually connected — reads clearly on screen.
func _spawn_rect_fx(pos: Vector2, facing_dir: Vector2, length: float, width: float, duration: float, color: Color):
	area_fx_spawned.emit({
		"shape": "rect", "pos": pos, "facing": facing_dir,
		"size": Vector2(length, width), "duration": duration, "color": color,
	})

# ---- Drawing helpers ----
func _draw_hud(now: int, accent: Color):
	# hit flash
	if hit_flash_left > 0:
		draw_circle(Vector2.ZERO, RADIUS + 5, Color(1, 1, 1, (hit_flash_left / 0.25) * 0.75))

	# Blood-lust aura (active for BLOODLUST_DUR after landing a parry)
	if bloodlust_time_left > 0:
		var pulse = 0.5 + 0.4 * sin(now * 0.025)
		draw_arc(Vector2.ZERO, RADIUS + 10, 0, TAU, 40, Color(0.9, 0.1, 0.15, pulse), 3.0)

	# Iron Resolve — icy blue guard shimmer
	if iron_resolve_time_left > 0:
		var pulse = 0.5 + 0.4 * sin(now * 0.02)
		draw_arc(Vector2.ZERO, RADIUS + 9, 0, TAU, 40, Color(0.55, 0.75, 1.0, pulse), 3.0)

	# HP bar above head
	var hp_pct = hp / max_hp
	var bw = 54.0
	var bh = 7.0
	var bx = -bw * 0.5
	var by = -(RADIUS + 36.0)
	draw_rect(Rect2(bx - 1, by - 1, bw + 2, bh + 2), Color(0.04, 0.04, 0.07))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.15, 0.15, 0.2))
	var fill_col = accent if hp_pct > 0.35 else Color(0.9, 0.2, 0.15)
	draw_rect(Rect2(bx, by, bw * hp_pct, bh), fill_col)

	# Shield overlay (Barrier / Guardian Ward) — a bright segment tacked on
	# past the HP fill, same px-per-hp scale, so an ally can see exactly how
	# much absorb they were just given rather than only feeling it later.
	if barrier_time_left > 0 and barrier_hp_left > 0:
		var px_per_hp = bw / max_hp
		var shield_w = min(barrier_hp_left * px_per_hp, bw * 0.6)
		var shield_x = bx + bw * hp_pct
		var pulse = 0.7 + 0.3 * sin(now * 0.012)
		draw_rect(Rect2(shield_x, by - 1, shield_w, bh + 2),
			Color(0.6, 0.9, 1.0, 0.55 * pulse))
		draw_rect(Rect2(shield_x, by - 1, shield_w, 1.5),
			Color(0.85, 0.97, 1.0, 0.9 * pulse))

	# slow ring
	if slowed_time_left > 0:
		var pulse = 0.5 + 0.3 * sin(now * 0.015)
		draw_arc(Vector2.ZERO, RADIUS + 11, 0, TAU, 40, Color(0.3, 0.6, 1.0, pulse), 2.5)

	# root — small stakes/vines pinning the feet, distinct from the slow ring
	if rooted_time_left > 0:
		var pulse = 0.55 + 0.35 * sin(now * 0.018)
		for i in 4:
			var a = i * TAU / 4.0 + 0.4
			var p0 = Vector2(cos(a), sin(a)) * (RADIUS - 2)
			var p1 = Vector2(cos(a), sin(a)) * (RADIUS + 10)
			draw_line(p0, p1, Color(0.45, 0.3, 0.15, pulse), 2.5)

	# parry ring
	if parrying:
		var pulse = 0.65 + 0.35 * sin(now * 0.03)
		draw_arc(Vector2.ZERO, RADIUS + 12, 0, TAU, 48,
			Color(0.3, 0.7, 1.0, pulse), 3.5)

	# stun stars
	if stunned_time_left > 0:
		var t = now * 0.006
		for i in 3:
			var a = t + i * TAU / 3.0
			draw_circle(Vector2(cos(a), sin(a)) * (RADIUS + 14), 4.5, Color(1.0, 0.9, 0.2))

	# knockup — upward arrow indicators
	if knockup_time_left > 0:
		var pct = knockup_time_left / KNOCKUP_DUR
		for i in 3:
			var arrow_y = -RADIUS - 28 - i * 10
			var alpha = pct * (1.0 - float(i) / 3.0)
			draw_line(Vector2(0, arrow_y), Vector2(-6, arrow_y + 8), Color(0.95, 0.6, 0.1, alpha), 2.5)
			draw_line(Vector2(0, arrow_y), Vector2( 6, arrow_y + 8), Color(0.95, 0.6, 0.1, alpha), 2.5)

	# cast bar
	if casting != null:
		var pct = 1.0 - (casting["time_left"] / casting["total"])
		var bar_y = -RADIUS - 18.0
		draw_rect(Rect2(Vector2(-24, bar_y), Vector2(48, 5)), Color(0.06, 0.06, 0.10))
		draw_rect(Rect2(Vector2(-24, bar_y), Vector2(48 * pct, 5)), Color(1, 0.82, 0.4))

	# combo pips — one small icon per stack, below the feet (everything
	# above the head is already stacked with the HP bar/cast bar/status
	# rings, so there's no room up there without overlapping them)
	if combo_stacks > 0:
		for i in combo_stacks:
			var px = (i - (combo_stacks - 1) * 0.5) * 15.0
			_draw_combo_pip(Vector2(px, RADIUS + 22))

# Default combo pip: a tiny sword (blade + crossguard + pommel), point up.
# Overridden per-class where a different icon fits better (e.g. Bruiser).
func _draw_combo_pip(pos: Vector2):
	draw_line(pos + Vector2(0, 6), pos + Vector2(0, -6), Color(0.92, 0.94, 1.0, 0.95), 2.2)
	draw_line(pos + Vector2(-3.2, 2.2), pos + Vector2(3.2, 2.2), Color(1, 0.85, 0.3, 0.95), 1.8)
	draw_circle(pos + Vector2(0, 5.5), 1.4, Color(1, 0.85, 0.3, 0.9))

func _col_dark(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)

func _draw_duelist(now: int, accent: Color):
	var perp    = Vector2(-facing.y, facing.x)
	var armor   = _col_dark(accent, 0.55)
	var skin    = Color(0.88, 0.72, 0.56)
	var boot    = Color(0.20, 0.16, 0.12)

	var spd_pct = clamp(velocity.length() / MAX_SPEED, 0.0, 1.0)
	var stride  = spd_pct * 9.0
	var bob_y   = sin(walk_phase * 2.0) * spd_pct * 1.5

	# ground shadow
	draw_circle(Vector2(2, RADIUS - 4), 14, Color(0, 0, 0, 0.18))

	# --- CAPE (billows behind, opposite of facing) ---
	var cape_sway = sin(walk_phase * 1.7) * (4.0 + spd_pct * 6.0)
	var cape_back = -facing * (18.0 + spd_pct * 14.0)
	var cape = PackedVector2Array([
		facing * -9 + perp * -10,
		facing * -9 + perp *  10,
		cape_back + perp * (16.0 + cape_sway),
		cape_back + perp * -3.0,
		cape_back + perp * (-16.0 - cape_sway * 0.6),
	])
	draw_colored_polygon(cape, Color(0.55, 0.06, 0.05, 0.85))
	draw_colored_polygon(cape, Color(accent.r, accent.g, accent.b, 0.12))

	# --- LEGS ---
	var lleg_end = Vector2(perp * -6 + facing * sin(walk_phase)  * stride + Vector2(0, RADIUS - 2 + bob_y))
	var rleg_end = Vector2(perp *  6 - facing * sin(walk_phase)  * stride + Vector2(0, RADIUS - 2 + bob_y))
	draw_line(Vector2(perp * -4 + facing * 2), lleg_end, armor, 6.0, true)
	draw_line(Vector2(perp *  4 + facing * 2), rleg_end, armor, 6.0, true)
	draw_circle(lleg_end, 5.0, boot)
	draw_circle(rleg_end, 5.0, boot)

	# --- SWORD at rest (behind body) ---
	if swing_time_left <= 0 and not lunging:
		var rest = (facing * 0.3 + perp * 0.7).normalized()
		var sb   = rest * (RADIUS - 4)
		var st   = rest * (RADIUS + SWORD_LEN * 0.65)
		draw_line(sb, st, Color(0.75, 0.78, 0.9, 0.6), SWORD_WIDTH * 0.55, true)
		draw_line(sb + perp * 6, sb - perp * 6, Color(0.6, 0.62, 0.75, 0.7), 3.5)
		# idle glint sparkle traveling along the blade
		var glint_t = fmod(now * 0.0009, 1.0)
		draw_circle(sb.lerp(st, glint_t), 2.2, Color(1, 1, 1, 0.8))

	# --- BODY ---
	var body = PackedVector2Array([
		facing * -13 + perp * -9,
		facing * -13 + perp *  9,
		facing *   8 + perp *  8,
		facing *   8 + perp * -8,
	])
	draw_colored_polygon(body, armor)
	# chest plate
	var chest = PackedVector2Array([
		facing * -10 + perp * -5,
		facing * -10 + perp *  5,
		facing *   2 + perp *  4,
		facing *   2 + perp * -4,
	])
	draw_colored_polygon(chest, Color(accent.r, accent.g, accent.b, 0.55))
	# rim light along one edge of the torso for depth
	draw_line(facing * -13 + perp * -9, facing * 8 + perp * -8,
		Color(1, 1, 1, 0.30), 2.0)

	# pauldrons
	draw_circle(facing * -10 + perp * -11, 7.0, armor)
	draw_circle(facing * -10 + perp *  11, 7.0, armor)
	draw_circle(facing * -10 + perp * -11, 4.0, _col_dark(accent, 0.4))
	draw_circle(facing * -10 + perp *  11, 4.0, _col_dark(accent, 0.4))
	draw_arc(facing * -10 + perp * -11, 7.0, 0, PI, 10, Color(1, 1, 1, 0.35), 1.5)

	# --- HEAD ---
	var head = facing * -20 + Vector2(0, bob_y)
	draw_circle(head, 10.0, skin)
	# helmet shell
	var helm = PackedVector2Array([
		head + facing * -11 + perp * -9,
		head + facing * -11 + perp *  9,
		head + facing *   5 + perp *  8,
		head + facing *   5 + perp * -8,
	])
	draw_colored_polygon(helm, armor)
	# visor slit
	draw_line(head + perp * -5 + facing * -2,
			  head + perp *  5 + facing * -2,
			  Color(accent.r, accent.g, accent.b, 0.95), 3.5)

	# gladiator crest (red plume along helm ridge)
	draw_line(head + facing * -10, head + facing * 4,
		Color(0.70, 0.08, 0.06, 0.90), 5.5)
	draw_line(head + facing * -10, head + facing * 4,
		Color(1.00, 0.28, 0.16, 0.80), 2.5)

	# --- DASH CHARGE PIPS ---
	for i in dash_charges_max:
		var px = (i - (dash_charges_max - 1) * 0.5) * 14.0
		var pip_col = Color(accent.r, accent.g, accent.b, 0.85) if i < dash_charges else Color(0.2, 0.2, 0.25, 0.5)
		draw_circle(Vector2(px, RADIUS + 14), 4.0, pip_col)
	if dash_charges < dash_charges_max:
		var px = (dash_charges - (dash_charges_max - 1) * 0.5) * 14.0
		draw_arc(Vector2(px, RADIUS + 14), 4.5, -PI/2,
			-PI/2 + TAU * (dash_charge_timer / DASH_CHARGE_REGEN), 16,
			Color(accent.r, accent.g, accent.b, 0.8), 2.0)

	# --- SWORD SWING (on top of everything) ---
	if swing_time_left > 0 and swing_total > 0:
		var t         = 1.0 - (swing_time_left / swing_total)
		var cur_angle = swing_start_angle + swing_arc_span * t
		var sdir      = Vector2(cos(cur_angle), sin(cur_angle))
		var sperp     = Vector2(-sdir.y, sdir.x)
		var sroot     = sdir * RADIUS
		var stip      = sdir * (RADIUS + SWORD_LEN)
		var alpha     = 0.95 * (swing_time_left / swing_total)

		# arc fill
		var arc_start = swing_start_angle
		var arc_end   = cur_angle
		if abs(arc_end - arc_start) > 0.05:
			var fan: PackedVector2Array = []
			fan.append(Vector2.ZERO)
			for i in 19:
				var a = arc_start + (arc_end - arc_start) * float(i) / 18.0
				fan.append(Vector2(cos(a), sin(a)) * (RADIUS + SWORD_LEN))
			draw_colored_polygon(fan, Color(1, 1, 1, alpha * 0.15))
			for i in 18:
				var a0 = arc_start + (arc_end - arc_start) * float(i)     / 18.0
				var a1 = arc_start + (arc_end - arc_start) * float(i + 1) / 18.0
				draw_line(Vector2(cos(a0), sin(a0)) * (RADIUS + SWORD_LEN),
						  Vector2(cos(a1), sin(a1)) * (RADIUS + SWORD_LEN),
						  Color(1, 1, 1, alpha * (1.0 - float(i) / 18.0) * 0.65), 3.0)
		# blade
		var hw = SWORD_WIDTH * 0.5
		draw_colored_polygon(PackedVector2Array([sroot + sperp * hw, sroot - sperp * hw, stip]),
			Color(0.95, 0.97, 1.0, alpha))
		draw_line(sroot + sperp * hw, stip, Color(1, 1, 1, alpha), 1.5)
		# bright motion-streak core along the blade edge
		draw_line(sroot, stip, Color(1, 1, 0.85, alpha * 0.9), 2.0)
		# crossguard
		var guard = sdir * (RADIUS + 7)
		draw_line(guard + sperp * 11, guard - sperp * 11, Color(0.75, 0.78, 1.0, alpha), 4.0)

# ---- Drawing ----
func _draw():
	var now = Time.get_ticks_msec()

	if use_3d_view:
		if not alive:
			return
		draw_set_transform(_get_hud_screen_correction())
		_draw_hud(now, get_status_accent(base_color))
		draw_set_transform(Vector2.ZERO)
		return

	# trail
	for p in trail:
		var age = (now - p["time"]) / 200.0
		if age < 1.0:
			draw_circle(to_local(p["pos"]), RADIUS * 0.85,
				Color(base_color.r, base_color.g, base_color.b, (1.0 - age) * 0.28))

	if not alive:
		draw_circle(Vector2.ZERO, RADIUS + 2, Color(0.25, 0.25, 0.28, 0.5))
		return

	var accent = get_status_accent(base_color)
	var ku_y = get_knockup_draw_offset()
	if ku_y != 0.0:
		draw_circle(Vector2(0, RADIUS - 4), 16.0 - abs(ku_y) * 0.06, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2(0, ku_y))

	_draw_duelist(now, accent)

	# Bladestorm — 3 orbiting ghost swords
	if bladestorm_time_left > 0:
		var t = now * 0.003
		var pct = bladestorm_time_left / BLADESTORM_DUR
		for i in 3:
			var a = t * 4.0 + i * TAU / 3.0
			var sd = Vector2(cos(a), sin(a))
			var sp = Vector2(-sd.y, sd.x)
			var sr = RADIUS + 14.0
			var s0 = sd * sr
			var s1 = sd * (sr + SWORD_LEN * 0.85)
			var hw = SWORD_WIDTH * 0.45
			draw_colored_polygon(PackedVector2Array([s0 + sp * hw, s0 - sp * hw, s1]),
				Color(1.0, 0.88, 0.2, pct * 0.75))
			draw_line(s0 + sp * hw, s1, Color(1, 1, 0.7, pct * 0.5), 1.5)
		var pulse = 0.4 + 0.35 * sin(t * 6.0)
		draw_arc(Vector2.ZERO, RADIUS + SWORD_LEN * 0.9, 0, TAU, 64,
			Color(1.0, 0.8, 0.15, pct * pulse * 0.45), 3.0)

	if ku_y != 0.0:
		draw_set_transform(Vector2.ZERO)

	_draw_hud(now, accent)
