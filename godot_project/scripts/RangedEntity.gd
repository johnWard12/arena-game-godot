extends "res://scripts/Entity.gd"
class_name RangedEntity

# Ranged-specific constants
const RANGED_MAX_HP = 95.0

const RPROJ_SPEED  = 1360.0
const RPROJ_RADIUS = 28.0
const RPROJ_DMG    = 8.0
const RPROJ_CD     = 0.5

const BOLT_CAST     = 0.25
const BOLT_RECOVERY = 0.18
const BOLT_CD       = 2.5
const BOLT_SPEED    = 1800.0
const BOLT_RADIUS   = 20.0
const BOLT_DMG      = 22.0

const BLINK_DIST = 210.0
const BLINK_CD   = 5.0

const DASH_CHARGES_MAX  = 2
const DASH_CHARGE_REGEN = 2.5   # seconds per charge

const RULT_CAST     = 0.55
const RULT_RECOVERY = 0.3
const RULT_SPEED    = 380.0
const RULT_RADIUS   = 44.0
const RULT_DMG_BASE = 42.0
const RULT_DMG_MISSING_BONUS = 48.0

var dash_charges := DASH_CHARGES_MAX
var dash_charge_timer := 0.0

func _ready():
	hp     = RANGED_MAX_HP
	max_hp = RANGED_MAX_HP
	base_color = Color(0.72, 0.4, 1.0)

# ---- Dash charge system ----
func _physics_process(delta):
	if alive and dash_charges < DASH_CHARGES_MAX:
		dash_charge_timer += delta
		if dash_charge_timer >= DASH_CHARGE_REGEN:
			dash_charge_timer -= DASH_CHARGE_REGEN
			dash_charges += 1
	super._physics_process(delta)

func try_dash(dir: Vector2):
	if not alive or dashing or dir.length() < 0.01 or dash_charges <= 0:
		return
	dash_charges -= 1
	if dash_charges == 0:
		dash_charge_timer = 0.0
	dash_dir = dir.normalized()
	dashing = true
	dash_time_left = DASH_DUR
	dash_cd_left = 0.0
	if recovering != null:
		recovering = null

# ---- No combo system for ranged ----
func combo_mult() -> float:
	return 1.0

func add_combo_stack():
	pass

# ---- Ability overrides ----

func try_auto(opp: Entity):
	if not alive or cd_auto > 0 or casting != null or opp == null:
		return
	cd_auto = RPROJ_CD
	facing = get_aim_dir(opp)
	_fire(facing, RPROJ_SPEED, RPROJ_RADIUS, RPROJ_DMG, opp, Color(1.0, 0.85, 0.3), 8.0)

func try_a1(opp: Entity):
	if not alive or cd_a1 > 0 or casting != null or recovering != null or opp == null:
		return
	casting = {"type": "a1", "time_left": BOLT_CAST, "total": BOLT_CAST, "opp": opp}

func resolve_a1(opp: Entity):
	facing = get_aim_dir(opp)
	var dmg = round(BOLT_DMG * combo_mult())
	_fire(facing, BOLT_SPEED, BOLT_RADIUS, dmg, opp, Color(0.4, 0.85, 1.0), 11.0)
	add_combo_stack()
	cd_a1 = BOLT_CD
	recovering = {"type": "a1", "time_left": BOLT_RECOVERY, "total": BOLT_RECOVERY}

func try_a2(_opp: Entity):
	if not alive or cd_a2 > 0 or stunned_time_left > 0:
		return
	var input_vec = get_movement_input()
	var blink_dir: Vector2
	if input_vec.length() > 0.01:
		blink_dir = input_vec.normalized()
	elif opponent != null:
		blink_dir = (global_position - opponent.global_position).normalized()
	else:
		blink_dir = -facing
	# trail burst at origin before blink
	for i in 6:
		push_trail()
	global_position += blink_dir * BLINK_DIST
	clamp_to_arena()
	facing = -blink_dir
	velocity *= 0.2
	cd_a2 = BLINK_CD

func try_ult(opp: Entity):
	if not alive or ult_charge < ULT_CHARGE_MAX or casting != null or recovering != null or opp == null:
		return
	casting = {"type": "ult", "time_left": RULT_CAST, "total": RULT_CAST, "opp": opp}

func resolve_ult(opp: Entity):
	facing = get_aim_dir(opp)
	var missing_ratio = 1.0 - (opp.hp / opp.max_hp) if opp != null and opp.alive else 0.0
	var dmg = round(RULT_DMG_BASE + missing_ratio * RULT_DMG_MISSING_BONUS)
	_fire(facing, RULT_SPEED, RULT_RADIUS, dmg, opp, Color(1.0, 0.3, 0.85), 16.0)
	ult_charge = 0.0
	recovering = {"type": "ult", "time_left": RULT_RECOVERY, "total": RULT_RECOVERY}

func _fire(dir: Vector2, speed: float, radius: float, dmg: float, tgt: Entity, col: Color, vis_r: float):
	var proj = load("res://scripts/Projectile.gd").new()
	proj.global_position = global_position + dir * (RADIUS + vis_r + 2.0)
	proj.velocity = dir * speed
	proj.damage = dmg
	proj.hit_radius = radius
	proj.owner_entity = self
	proj.target = tgt
	proj.proj_color = col
	proj.proj_radius_visual = vis_r
	projectile_spawned.emit(proj)

# ---- Drawing override ----
func _draw():
	var now = Time.get_ticks_msec()
	for p in trail:
		var age = (now - p["time"]) / 200.0
		if age < 1.0:
			draw_circle(to_local(p["pos"]), RADIUS * 0.85,
				Color(base_color.r, base_color.g, base_color.b, (1.0 - age) * 0.28))

	if not alive:
		draw_circle(Vector2.ZERO, RADIUS, Color(0.3, 0.3, 0.3, 0.4))
		return

	var color = base_color
	if stunned_time_left > 0:
		color = Color(0.9, 0.9, 0.3)
	elif parrying:
		color = Color(0.3, 0.7, 1.0)
	elif dashing:
		color = Color(1, 0.36, 0.48)
	elif casting != null:
		color = Color(1, 0.82, 0.4)
	elif recovering != null:
		color = Color(0.78, 0.61, 1)

	# dash charge pips below character
	for i in DASH_CHARGES_MAX:
		var px = (i - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
		var filled = i < dash_charges
		var pip_col = Color(0.6, 0.9, 1.0, 0.9) if filled else Color(0.3, 0.3, 0.4, 0.5)
		draw_circle(Vector2(px, RADIUS + 12), 4.0, pip_col)
		if filled:
			# partial fill for the charge currently regenerating
			pass
	# partial regen pip
	if dash_charges < DASH_CHARGES_MAX:
		var px = (dash_charges - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
		var regen_pct = dash_charge_timer / DASH_CHARGE_REGEN
		draw_arc(Vector2(px, RADIUS + 12), 4.0, -PI / 2, -PI / 2 + TAU * regen_pct, 16,
			Color(0.6, 0.9, 1.0, 0.7), 2.0)

	# blink ready indicator — faint ring when blink is off cooldown
	if cd_a2 <= 0:
		draw_arc(Vector2.ZERO, RADIUS + 10, 0, TAU, 32, Color(0.72, 0.4, 1.0, 0.3), 1.5)

	# staff — line extending from body in facing direction
	var staff_root = facing * (RADIUS - 2)
	var staff_tip  = facing * (RADIUS + 28)
	draw_line(staff_root, staff_tip, Color(0.55, 0.35, 0.8, 0.9), 4.0)
	# orb at tip
	var orb_color = Color(1.0, 0.85, 0.3) if cd_auto <= 0 else Color(0.4, 0.4, 0.5, 0.5)
	draw_circle(staff_tip, 5.5, orb_color)

	# cast charge glow
	if casting != null:
		var pct = 1.0 - (casting["time_left"] / casting["total"])
		draw_circle(staff_tip, 5.5 + pct * 14.0, Color(1, 0.9, 0.4, pct * 0.5))

	# shadow
	draw_circle(Vector2(2, 3), RADIUS, Color(0, 0, 0, 0.22))
	# body
	draw_circle(Vector2.ZERO, RADIUS, color)
	# inner core
	draw_circle(Vector2.ZERO, RADIUS * 0.52, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.7))

	# hit flash
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

	pass  # no combo pips for ranged
