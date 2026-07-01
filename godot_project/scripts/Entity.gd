extends Node2D
class_name Entity

# ---- Tunables ----
const MAX_SPEED = 435.0
const ACCEL = 3450.0
const FRICTION = 1650.0
const DASH_SPEED = 1275.0
const DASH_DUR = 0.13
const CARRY = 0.7

const AUTO_CD = 0.55
const AUTO_DMG = 4.0
const AUTO_RANGE = 130.0

const A1_CAST = 0.09
const A1_RECOVERY = 0.13
const A1_CD = 1.8
const A1_DMG = 12.0
const A1_RANGE = 125.0
const A1_SLOW_DUR = 2.0
const A1_SLOW_PCT = 0.30

const A2_CAST = 0.14
const A2_RECOVERY = 0.22
const A2_MISS_RECOVERY = 0.45
const A2_CD = 6.5
const A2_DMG = 20.4
const A2_RANGE = 130.0
const A2_LUNGE_DIST = 230.0
const A2_LUNGE_DUR = 0.13

const ULT_CAST = 0.45
const ULT_RECOVERY = 0.3
const ULT_DMG_BASE = 35.0
const ULT_DMG_MISSING_BONUS = 40.0
const ULT_RANGE = 135.0
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

const RADIUS = 24.0
const TRAIL_LIFETIME_MS = 220

# sword swing tunables
const SWORD_LEN = 72.0
const SWORD_WIDTH = 11.0

# ---- State ----
var is_player := false
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

var hp := 150.0
var max_hp := 150.0
var alive := true

var casting = null
var recovering = null

var cd_auto := 0.0
var cd_a1 := 0.0
var cd_a2 := 0.0
var ult_charge := 0.0

var combo_stacks := 0
var combo_time_left := 0.0

var parrying := false
var parry_time_left := 0.0
var parry_cd_left := 0.0

var stunned_time_left := 0.0
var slowed_time_left  := 0.0
var slow_pct          := 0.5

# Multiplier applied to any incoming stun/freeze duration (1.0 = no resistance).
# Subclasses override this in _ready() to grant CC resistance.
var stun_resist_mult  := 1.0
var recovery_slows_movement := true

# CC immunity — blocks apply_stun and apply_slow when true
var cc_immune := false

# Flat damage reduction (0.0 = none, 0.25 = 25% less damage taken)
var dmg_reduction := 0.0

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

var dash_charges := DASH_CHARGES_MAX
var dash_charge_timer := 0.0

var walk_phase := 0.0

var opponent: Entity = null
var arena_rect := Rect2(Vector2.ZERO, Vector2(1000, 600))
var obstacle_rects: Array[Rect2] = []
var trail := []

signal died
signal projectile_spawned(proj)

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
	parry_cd_left = max(0.0, parry_cd_left - delta)
	if dash_charges < DASH_CHARGES_MAX:
		dash_charge_timer += delta
		if dash_charge_timer >= DASH_CHARGE_REGEN:
			dash_charge_timer -= DASH_CHARGE_REGEN
			dash_charges += 1
	hit_flash_left   = max(0.0, hit_flash_left - delta)
	slowed_time_left = max(0.0, slowed_time_left - delta)
	if barrier_time_left > 0:
		barrier_time_left = max(0.0, barrier_time_left - delta)
		if barrier_time_left <= 0:
			barrier_hp_left = 0.0
	if swing_time_left > 0:
		swing_time_left = max(0.0, swing_time_left - delta)
	if ult_charge < ULT_CHARGE_MAX:
		ult_charge = min(ULT_CHARGE_MAX, ult_charge + delta)
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
	var slowed = recovering_slow or debuffed_slow

	if lunging:
		lunge_time_left -= delta
		var lspeed = A2_LUNGE_DIST / A2_LUNGE_DUR
		velocity = lunge_dir * lspeed
		push_trail()
		var reached = lunge_opponent != null and is_instance_valid(lunge_opponent) and lunge_opponent.alive \
			and global_position.distance_to(lunge_opponent.global_position) <= A2_RANGE
		if lunge_time_left <= 0 or reached:
			lunging = false
			velocity *= 0.3
			resolve_lunge_strike(lunge_opponent)
	elif dashing:
		dash_time_left -= delta
		velocity = dash_dir * DASH_SPEED
		push_trail()
		if dash_time_left <= 0:
			dashing = false
			velocity *= CARRY
	elif locked:
		var spd = velocity.length()
		if spd > 0:
			var dec = FRICTION * delta * 2.0
			var ns = max(0.0, spd - dec)
			velocity = velocity.normalized() * ns
	else:
		var speed_mult = 1.0
		if recovering_slow and debuffed_slow:
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

func deal_damage(target: Entity, amount: float) -> bool:
	if target == null or not target.alive:
		return false
	if target.parrying:
		target.parrying = false
		target.on_landed_parry()
		apply_stun(PARRY_STUN_DUR)
		casting = null
		lunging = false
		return false
	if target.barrier_hp_left > 0:
		var absorbed = min(amount, target.barrier_hp_left)
		target.barrier_hp_left -= absorbed
		amount -= absorbed
		target.hit_flash_left = 0.15
		if amount <= 0:
			return true
	if target.casting != null:
		target.casting = null
		target.apply_stun(STUN_DUR)
	amount *= (1.0 - target.dmg_reduction)
	target.hp = max(0.0, target.hp - amount)
	target.hit_flash_left = 0.25
	if target.hp <= 0 and target.alive:
		target.alive = false
		target.died.emit()
	return true

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
	casting = {"type": "ult", "time_left": ULT_CAST, "total": ULT_CAST, "opp": opp}

func resolve_ult(opp: Entity):
	start_swing(160.0, 0.35)
	if opp != null and opp.alive and global_position.distance_to(opp.global_position) <= ULT_RANGE:
		var missing_ratio = 1.0 - (opp.hp / opp.max_hp)
		var dmg = round(ULT_DMG_BASE + missing_ratio * ULT_DMG_MISSING_BONUS)
		if deal_damage(opp, dmg):
			add_combo_stack()
	ult_charge = 0.0
	recovering = {"type": "ult", "time_left": ULT_RECOVERY, "total": ULT_RECOVERY}

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

func _fire(dir: Vector2, speed: float, radius: float, dmg: float, tgt: Entity, col: Color, vis_r: float, slow: float = 0.0, slow_pct: float = 0.5, track: bool = false):
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
	proj.apply_slow_pct = slow_pct
	proj.report_result = track
	proj.obstacle_rects = obstacle_rects
	projectile_spawned.emit(proj)

# ---- Drawing helpers ----
func _draw_hud(now: int, accent: Color):
	# hit flash
	if hit_flash_left > 0:
		draw_circle(Vector2.ZERO, RADIUS + 5, Color(1, 1, 1, (hit_flash_left / 0.25) * 0.75))

	# Blood-lust aura (active for BLOODLUST_DUR after landing a parry)
	if bloodlust_time_left > 0:
		var pulse = 0.5 + 0.4 * sin(now * 0.025)
		draw_arc(Vector2.ZERO, RADIUS + 10, 0, TAU, 40, Color(0.9, 0.1, 0.15, pulse), 3.0)

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

	# slow ring
	if slowed_time_left > 0:
		var pulse = 0.5 + 0.3 * sin(now * 0.015)
		draw_arc(Vector2.ZERO, RADIUS + 11, 0, TAU, 40, Color(0.3, 0.6, 1.0, pulse), 2.5)

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

	# cast bar
	if casting != null:
		var pct = 1.0 - (casting["time_left"] / casting["total"])
		var bar_y = -RADIUS - 18.0
		draw_rect(Rect2(Vector2(-24, bar_y), Vector2(48, 5)), Color(0.06, 0.06, 0.10))
		draw_rect(Rect2(Vector2(-24, bar_y), Vector2(48 * pct, 5)), Color(1, 0.82, 0.4))

	# combo pips
	if combo_stacks > 0:
		for i in combo_stacks:
			var px = (i - (combo_stacks - 1) * 0.5) * 11.0
			draw_circle(Vector2(px, -RADIUS - 26), 4.0, Color(1, 0.85, 0.3))

func _col_dark(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)

func _draw_duelist(now: int, accent: Color):
	var perp    = Vector2(-facing.y, facing.x)
	var armor   = _col_dark(accent, 0.55)
	var dark    = Color(0.10, 0.11, 0.14)
	var skin    = Color(0.88, 0.72, 0.56)
	var boot    = Color(0.20, 0.16, 0.12)

	var spd_pct = clamp(velocity.length() / MAX_SPEED, 0.0, 1.0)
	var stride  = spd_pct * 9.0
	var bob_y   = sin(walk_phase * 2.0) * spd_pct * 1.5

	# ground shadow
	draw_circle(Vector2(2, RADIUS - 4), 14, Color(0, 0, 0, 0.18))

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

	# pauldrons
	draw_circle(facing * -10 + perp * -11, 7.0, armor)
	draw_circle(facing * -10 + perp *  11, 7.0, armor)
	draw_circle(facing * -10 + perp * -11, 4.0, _col_dark(accent, 0.4))
	draw_circle(facing * -10 + perp *  11, 4.0, _col_dark(accent, 0.4))

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
	for i in DASH_CHARGES_MAX:
		var px = (i - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
		var pip_col = Color(accent.r, accent.g, accent.b, 0.85) if i < dash_charges else Color(0.2, 0.2, 0.25, 0.5)
		draw_circle(Vector2(px, RADIUS + 14), 4.0, pip_col)
	if dash_charges < DASH_CHARGES_MAX:
		var px = (dash_charges - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
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
		# crossguard
		var guard = sdir * (RADIUS + 7)
		draw_line(guard + sperp * 11, guard - sperp * 11, Color(0.75, 0.78, 1.0, alpha), 4.0)

# ---- Drawing ----
func _draw():
	var now = Time.get_ticks_msec()

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

	_draw_duelist(now, accent)
	_draw_hud(now, accent)
