extends Node2D
class_name Entity

# ---- Tunables ----
const MAX_SPEED = 435.0
const ACCEL = 3450.0
const FRICTION = 1650.0
const DASH_SPEED = 1275.0
const DASH_DUR = 0.13
const DASH_CD = 0.45
const CARRY = 0.7

const AUTO_CD = 0.55
const AUTO_DMG = 4.0
const AUTO_RANGE = 130.0

const A1_CAST = 0.09
const A1_RECOVERY = 0.13
const A1_CD = 1.8
const A1_DMG = 14.0
const A1_RANGE = 125.0

const A2_CAST = 0.14
const A2_RECOVERY = 0.22
const A2_CD = 4.5
const A2_DMG = 24.0
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

const RADIUS = 18.0

# sword swing tunables
const SWORD_LEN = 56.0
const SWORD_WIDTH = 9.0

# ---- State ----
var is_player := false
var base_color := Color(0.37, 0.88, 0.75)
var velocity := Vector2.ZERO
var facing := Vector2.RIGHT

var dashing := false
var dash_time_left := 0.0
var dash_cd_left := 0.0
var dash_dir := Vector2.ZERO

var lunging := false
var lunge_time_left := 0.0
var lunge_dir := Vector2.ZERO
var lunge_opponent: Entity = null

var hp := 120.0
var max_hp := 120.0
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

# sword swing: arc sweep from start_angle to start_angle+arc_span over swing_total seconds
var swing_time_left := 0.0
var swing_total := 0.0
var swing_start_angle := 0.0
var swing_arc_span := 0.0

# hit flash on this entity when it receives damage
var hit_flash_left := 0.0

var opponent: Entity = null
var arena_rect := Rect2(Vector2.ZERO, Vector2(1000, 600))
var trail := []

signal died
signal projectile_spawned(proj)

func _physics_process(delta):
	if not alive:
		return
	cd_auto = max(0.0, cd_auto - delta)
	cd_a1 = max(0.0, cd_a1 - delta)
	cd_a2 = max(0.0, cd_a2 - delta)
	dash_cd_left = max(0.0, dash_cd_left - delta)
	parry_cd_left = max(0.0, parry_cd_left - delta)
	hit_flash_left = max(0.0, hit_flash_left - delta)
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

	if recovering != null:
		recovering["time_left"] -= delta
		if recovering["time_left"] <= 0:
			recovering = null

	var input_vec := get_movement_input()
	var locked = casting != null
	var slowed = recovering != null

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
		var speed_mult = 0.5 if slowed else 1.0
		var has_input = input_vec.length() > 0.01
		if has_input:
			facing = input_vec.normalized()
			var target_v = facing * MAX_SPEED * speed_mult
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

func push_trail():
	trail.append({"pos": global_position, "time": Time.get_ticks_msec()})

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

func deal_damage(target: Entity, amount: float):
	if target == null or not target.alive:
		return
	if target.parrying:
		target.parrying = false
		stunned_time_left = PARRY_STUN_DUR
		casting = null
		lunging = false
		return
	if target.casting != null:
		target.casting = null
		target.stunned_time_left = STUN_DUR
	target.hp = max(0.0, target.hp - amount)
	target.hit_flash_left = 0.25
	if target.hp <= 0 and target.alive:
		target.alive = false
		target.died.emit()

func try_auto(opp: Entity):
	if not alive or cd_auto > 0 or casting != null or opp == null:
		return
	cd_auto = AUTO_CD
	facing = get_aim_dir(opp)
	start_swing(70.0, 0.12)
	if global_position.distance_to(opp.global_position) <= AUTO_RANGE:
		deal_damage(opp, AUTO_DMG)
		add_combo_stack()

func try_a1(opp: Entity):
	if not alive or cd_a1 > 0 or casting != null or recovering != null or opp == null:
		return
	casting = {"type": "a1", "time_left": A1_CAST, "total": A1_CAST, "opp": opp}

func resolve_a1(opp: Entity):
	facing = get_aim_dir(opp)
	start_swing(110.0, 0.2)
	if global_position.distance_to(opp.global_position) <= A1_RANGE:
		var dmg = round(A1_DMG * combo_mult())
		deal_damage(opp, dmg)
		add_combo_stack()
	cd_a1 = A1_CD
	recovering = {"type": "a1", "time_left": A1_RECOVERY, "total": A1_RECOVERY}

func try_a2(opp: Entity):
	if not alive or cd_a2 > 0 or casting != null or recovering != null or opp == null:
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
	if opp != null and is_instance_valid(opp) and opp.alive and global_position.distance_to(opp.global_position) <= A2_RANGE:
		var dmg = round(A2_DMG * combo_mult())
		deal_damage(opp, dmg)
		if opp.alive:
			opp.stunned_time_left = 0.5
		add_combo_stack()
	recovering = {"type": "a2", "time_left": A2_RECOVERY, "total": A2_RECOVERY}

func try_ult(opp: Entity):
	if not alive or ult_charge < ULT_CHARGE_MAX or casting != null or recovering != null or opp == null:
		return
	casting = {"type": "ult", "time_left": ULT_CAST, "total": ULT_CAST, "opp": opp}

func resolve_ult(opp: Entity):
	start_swing(160.0, 0.35)
	if opp != null and opp.alive and global_position.distance_to(opp.global_position) <= ULT_RANGE:
		var missing_ratio = 1.0 - (opp.hp / opp.max_hp)
		var dmg = round(ULT_DMG_BASE + missing_ratio * ULT_DMG_MISSING_BONUS)
		deal_damage(opp, dmg)
		add_combo_stack()
	ult_charge = 0.0
	recovering = {"type": "ult", "time_left": ULT_RECOVERY, "total": ULT_RECOVERY}

func try_dash(dir: Vector2):
	if not alive or dash_cd_left > 0 or dashing or dir.length() < 0.01:
		return
	dash_dir = dir.normalized()
	dashing = true
	dash_time_left = DASH_DUR
	dash_cd_left = DASH_CD
	if recovering != null:
		recovering = null

func try_parry():
	if not alive or parry_cd_left > 0 or casting != null or dashing or lunging or stunned_time_left > 0:
		return
	parrying = true
	parry_time_left = PARRY_DUR
	parry_cd_left = PARRY_CD

# ---- Drawing ----
func _draw():
	var now = Time.get_ticks_msec()
	for p in trail:
		var age = (now - p["time"]) / 200.0
		if age < 1.0:
			draw_circle(to_local(p["pos"]), RADIUS * 0.85, Color(base_color.r, base_color.g, base_color.b, (1.0 - age) * 0.28))

	if not alive:
		draw_circle(Vector2.ZERO, RADIUS, Color(0.3, 0.3, 0.3, 0.4))
		return

	var color = base_color
	if stunned_time_left > 0:
		color = Color(0.9, 0.9, 0.3)
	elif parrying:
		color = Color(0.3, 0.7, 1.0)
	elif lunging:
		color = Color(1, 0.24, 0.24)
	elif dashing:
		color = Color(1, 0.36, 0.48)
	elif casting != null:
		color = Color(1, 0.82, 0.4)
	elif recovering != null:
		color = Color(0.78, 0.61, 1)

	# sword swing — drawn behind the body
	if swing_time_left > 0 and swing_total > 0:
		var t = 1.0 - (swing_time_left / swing_total)
		var cur_angle = swing_start_angle + swing_arc_span * t
		var swing_dir = Vector2(cos(cur_angle), sin(cur_angle))
		var perp = Vector2(-swing_dir.y, swing_dir.x)
		var blade_root = swing_dir * RADIUS
		var blade_tip = swing_dir * (RADIUS + SWORD_LEN)
		var half_w = SWORD_WIDTH * 0.5
		var alpha = 0.95 * (swing_time_left / swing_total)

		# slash arc fill — wide fan from start to current angle
		var arc_start = swing_start_angle
		var arc_end = cur_angle
		var arc_steps = 18
		if abs(arc_end - arc_start) > 0.05:
			# filled fan polygon for the slash zone
			var fan_verts: PackedVector2Array = []
			fan_verts.append(Vector2.ZERO)
			for i in (arc_steps + 1):
				var a = arc_start + (arc_end - arc_start) * float(i) / arc_steps
				fan_verts.append(Vector2(cos(a), sin(a)) * (RADIUS + SWORD_LEN))
			draw_colored_polygon(fan_verts, Color(1.0, 1.0, 1.0, alpha * 0.18))
			# bright edge line along the arc tip
			for i in arc_steps:
				var a0 = arc_start + (arc_end - arc_start) * float(i) / arc_steps
				var a1 = arc_start + (arc_end - arc_start) * float(i + 1) / arc_steps
				var p0 = Vector2(cos(a0), sin(a0)) * (RADIUS + SWORD_LEN)
				var p1 = Vector2(cos(a1), sin(a1)) * (RADIUS + SWORD_LEN)
				var edge_alpha = alpha * (1.0 - float(i) / arc_steps) * 0.7
				draw_line(p0, p1, Color(1.0, 1.0, 1.0, edge_alpha), 3.0)

		# blade polygon — wide at guard, sharp at tip
		var verts = PackedVector2Array([
			blade_root + perp * half_w,
			blade_root - perp * half_w,
			blade_tip
		])
		draw_colored_polygon(verts, Color(0.95, 0.97, 1.0, alpha))
		# bright blade edge highlight
		draw_line(blade_root + perp * half_w, blade_tip, Color(1, 1, 1, alpha), 1.5)

		# crossguard
		var guard = swing_dir * (RADIUS + 7)
		draw_line(guard + perp * 11, guard - perp * 11, Color(0.75, 0.78, 1.0, alpha), 4.0)

	# shadow
	draw_circle(Vector2(2, 3), RADIUS, Color(0, 0, 0, 0.22))

	# body
	draw_circle(Vector2.ZERO, RADIUS, color)

	# inner core
	draw_circle(Vector2.ZERO, RADIUS * 0.52, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.7))

	# facing nub (small dot instead of triangle, sword is the directional indicator now)
	draw_circle(facing * (RADIUS - 4), 4.5, Color(1, 1, 1, 0.7))

	# hit flash — bright white overlay that fades
	if hit_flash_left > 0:
		var flash_alpha = (hit_flash_left / 0.25) * 0.85
		draw_circle(Vector2.ZERO, RADIUS + 4, Color(1, 1, 1, flash_alpha))

	# HP ring
	var hp_pct = hp / max_hp
	var ring_r = RADIUS + 5.0
	draw_arc(Vector2.ZERO, ring_r, -PI / 2, -PI / 2 + TAU * hp_pct, 40,
		Color(color.r, color.g, color.b, 0.9), 2.5)
	draw_arc(Vector2.ZERO, ring_r, -PI / 2 + TAU * hp_pct, -PI / 2 + TAU, 20,
		Color(0.15, 0.15, 0.18, 0.5), 2.5)

	# parry ring
	if parrying:
		var pulse = 0.7 + 0.3 * sin(now * 0.03)
		draw_arc(Vector2.ZERO, RADIUS + 8, 0, TAU, 40, Color(0.3, 0.7, 1.0, pulse), 3.5)

	# stun orbiting dots
	if stunned_time_left > 0:
		var t = now * 0.006
		for i in 3:
			var angle = t + i * TAU / 3.0
			var sp = Vector2(cos(angle), sin(angle)) * (RADIUS + 11)
			draw_circle(sp, 4.0, Color(1.0, 0.9, 0.2))

	# cast bar
	if casting != null:
		var pct = 1.0 - (casting["time_left"] / casting["total"])
		draw_rect(Rect2(Vector2(-22, -42), Vector2(44, 5)), Color(0.08, 0.08, 0.12))
		draw_rect(Rect2(Vector2(-22, -42), Vector2(44 * pct, 5)), Color(1, 0.82, 0.4))

	# combo stack pips
	if combo_stacks > 0:
		for i in combo_stacks:
			var px = (i - (combo_stacks - 1) * 0.5) * 10.0
			draw_circle(Vector2(px, -RADIUS - 12), 3.5, Color(1, 0.85, 0.3))
