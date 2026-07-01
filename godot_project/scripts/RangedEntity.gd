extends "res://scripts/Entity.gd"
class_name RangedEntity

# Ranged-specific constants
const RANGED_MAX_HP = 120.0

const RPROJ_SPEED  = 1360.0
const RPROJ_RADIUS = 28.0
const RPROJ_DMG    = 6.75
const RPROJ_CD     = 0.75

const BOLT_CAST     = 0.25
const BOLT_RECOVERY = 0.18
const BOLT_CD       = 3.5
const BOLT_SPEED    = 1800.0
const BOLT_RADIUS   = 20.0
const BOLT_DMG      = 22.0
const BOLT_SLOW_DUR = 1.5
const BOLT_SLOW_PCT = 0.25

const NOVA_CAST     = 0.2
const NOVA_RECOVERY = 0.25
const NOVA_CD       = 4.5
const NOVA_RADIUS   = 155.0
const NOVA_DMG      = 20.0
const NOVA_FREEZE   = 1.0

const BARRIER_CD  = 7.0
const BARRIER_HP  = 35.0
const BARRIER_DUR = 1.5


const RULT_CAST     = 0.55
const RULT_RECOVERY = 0.3
const RULT_SPEED    = 380.0
const RULT_RADIUS   = 44.0
const RULT_DMG_BASE = 42.0
const RULT_DMG_MISSING_BONUS = 48.0

var nova_fx_left := 0.0

# Overcharge: landing 2 damaging abilities (Bolt/Burst/Ult) in a row without
# missing shaves a bit off Bolt's and Burst's current cooldowns.
var overcharge_streak := 0
const OVERCHARGE_CD_REDUCTION := 0.3

func _ready():
	hp     = RANGED_MAX_HP
	max_hp = RANGED_MAX_HP
	base_color = Color(0.72, 0.4, 1.0)

func _physics_process(delta):
	nova_fx_left = max(0.0, nova_fx_left - delta)
	super._physics_process(delta)

# Blood-lust is a Duelist-only passive.
func on_landed_parry():
	pass

func register_ability_result(landed: bool):
	if landed:
		overcharge_streak += 1
		if overcharge_streak >= 2:
			overcharge_streak = 0
			cd_a1 = max(0.0, cd_a1 - OVERCHARGE_CD_REDUCTION)
			cd_a2 = max(0.0, cd_a2 - OVERCHARGE_CD_REDUCTION)
	else:
		overcharge_streak = 0

# ---- No combo system for ranged ----
func combo_mult() -> float:
	return 1.0

func add_combo_stack():
	pass

# ---- Ability overrides ----

func try_auto(opp: Entity):
	if not can_start_ability() or cd_auto > 0 or opp == null:
		return
	cd_auto = RPROJ_CD
	facing = get_aim_dir(opp)
	_fire(facing, RPROJ_SPEED, RPROJ_RADIUS, RPROJ_DMG, opp, Color(1.0, 0.85, 0.3), 8.0)

func try_a1(opp: Entity):
	if not can_start_ability() or cd_a1 > 0 or opp == null:
		return
	casting = {"type": "a1", "time_left": BOLT_CAST, "total": BOLT_CAST, "opp": opp}

func resolve_a1(opp: Entity):
	facing = get_aim_dir(opp)
	var dmg = round(BOLT_DMG * combo_mult())
	_fire(facing, BOLT_SPEED, BOLT_RADIUS, dmg, opp, Color(0.4, 0.85, 1.0), 11.0, BOLT_SLOW_DUR, BOLT_SLOW_PCT, true)
	add_combo_stack()
	cd_a1 = BOLT_CD
	recovering = {"type": "a1", "time_left": BOLT_RECOVERY, "total": BOLT_RECOVERY}

func try_a2(opp: Entity):
	if not can_start_ability() or cd_a2 > 0 or opp == null:
		return
	casting = {"type": "a2", "time_left": NOVA_CAST, "total": NOVA_CAST, "opp": opp}

func resolve_a2(opp: Entity):
	if opp != null:
		facing = get_aim_dir(opp)
	nova_fx_left = 0.35
	var landed := false
	if opp != null and opp.alive and global_position.distance_to(opp.global_position) <= NOVA_RADIUS:
		var dmg = round(NOVA_DMG * combo_mult())
		if deal_damage(opp, dmg):
			landed = true
			opp.apply_stun(NOVA_FREEZE)
			add_combo_stack()
	register_ability_result(landed)
	cd_a2 = NOVA_CD
	recovering = {"type": "a2", "time_left": NOVA_RECOVERY, "total": NOVA_RECOVERY}

func try_ult(opp: Entity):
	if not can_start_ability() or ult_charge < ULT_CHARGE_MAX or opp == null:
		return
	casting = {"type": "ult", "time_left": RULT_CAST, "total": RULT_CAST, "opp": opp}

func resolve_ult(opp: Entity):
	facing = get_aim_dir(opp)
	var missing_ratio = 1.0 - (opp.hp / opp.max_hp) if opp != null and opp.alive else 0.0
	var dmg = round(RULT_DMG_BASE + missing_ratio * RULT_DMG_MISSING_BONUS)
	_fire(facing, RULT_SPEED, RULT_RADIUS, dmg, opp, Color(1.0, 0.3, 0.85), 16.0, 0.0, 0.5, true)
	ult_charge = 0.0
	recovering = {"type": "ult", "time_left": RULT_RECOVERY, "total": RULT_RECOVERY}

func try_a3(_opp: Entity):
	if not can_start_ability() or cd_a3 > 0:
		return
	barrier_hp_left   = BARRIER_HP
	barrier_time_left = BARRIER_DUR
	cd_a3 = BARRIER_CD

func resolve_a3(_opp: Entity):
	pass

# ---- Drawing override ----
func _draw():
	var now = Time.get_ticks_msec()

	for p in trail:
		var age = (now - p["time"]) / 200.0
		if age < 1.0:
			draw_circle(to_local(p["pos"]), RADIUS * 0.85,
				Color(base_color.r, base_color.g, base_color.b, (1.0 - age) * 0.25))

	if not alive:
		draw_circle(Vector2.ZERO, RADIUS + 2, Color(0.25, 0.25, 0.28, 0.5))
		return

	var accent = get_status_accent(base_color)

	var perp     = Vector2(-facing.y, facing.x)
	var robe_col = _col_dark(accent, 0.6)
	var trim_col = Color(accent.r, accent.g, accent.b, 0.85)
	var skin_col = Color(0.88, 0.72, 0.56)

	# hover bob
	var hover_y = sin(Time.get_ticks_msec() * 0.0025) * 2.0

	# ground shadow (ellipse via circle + scale trick using polygon)
	draw_circle(Vector2(0, RADIUS - 2), 13, Color(0, 0, 0, 0.15))

	# --- ROBE (main body — wide trapezoid) ---
	var robe = PackedVector2Array([
		facing * -14 + perp * -8  + Vector2(0, hover_y),
		facing * -14 + perp *  8  + Vector2(0, hover_y),
		facing *  10 + perp *  13 + Vector2(0, hover_y),
		facing *  10 + perp * -13 + Vector2(0, hover_y),
	])
	draw_colored_polygon(robe, robe_col)
	# robe trim / hem highlight
	var hem = PackedVector2Array([
		facing * 6  + perp * -13 + Vector2(0, hover_y),
		facing * 6  + perp *  13 + Vector2(0, hover_y),
		facing * 10 + perp *  13 + Vector2(0, hover_y),
		facing * 10 + perp * -13 + Vector2(0, hover_y),
	])
	draw_colored_polygon(hem, Color(accent.r, accent.g, accent.b, 0.35))
	# robe center line detail
	draw_line(facing * -10 + Vector2(0, hover_y), facing * 8 + Vector2(0, hover_y),
		Color(accent.r, accent.g, accent.b, 0.25), 2.0)

	# --- STAFF ARM ---
	var arm_base = facing * -4 + perp * 9 + Vector2(0, hover_y)
	var staff_tip = facing * (RADIUS + 30) + perp * 8
	draw_line(arm_base, staff_tip, Color(0.42, 0.28, 0.18), 4.5, true)
	# staff shaft detail line
	draw_line(arm_base, staff_tip, Color(0.58, 0.42, 0.26, 0.5), 1.5)

	# staff head / crystal
	var orb_charged = cd_auto <= 0
	var orb_col     = Color(1.0, 0.88, 0.35) if orb_charged else Color(0.5, 0.4, 0.65, 0.6)
	var orb_r       = 7.5
	if casting != null:
		var pct = 1.0 - (casting["time_left"] / casting["total"])
		orb_r  += pct * 10.0
		orb_col = Color(1, 0.92, 0.4, 0.9)
	# glow ring
	draw_circle(staff_tip, orb_r * 1.8, Color(orb_col.r, orb_col.g, orb_col.b, 0.18))
	# orb
	draw_circle(staff_tip, orb_r, orb_col)
	draw_circle(staff_tip, orb_r * 0.45, Color(1, 1, 1, 0.75))
	# prongs around orb
	for i in 4:
		var a  = facing.angle() + i * PI / 2.0
		var p0 = staff_tip + Vector2(cos(a), sin(a)) * (orb_r + 1)
		var p1 = staff_tip + Vector2(cos(a), sin(a)) * (orb_r + 7)
		draw_line(p0, p1, Color(accent.r, accent.g, accent.b, 0.7), 2.0)

	# floating sparkles (idle particles)
	if stunned_time_left <= 0 and not dashing:
		var t = Time.get_ticks_msec() * 0.002
		for i in 4:
			var a   = t * 1.3 + i * TAU / 4.0
			var r   = RADIUS + 6.0 + sin(t * 2.0 + i) * 3.0
			var sp  = Vector2(cos(a), sin(a)) * r
			var sal = 0.3 + 0.2 * sin(t * 3.0 + i * 1.5)
			draw_circle(sp, 2.2, Color(accent.r, accent.g, accent.b, sal))

	# --- HEAD / HOOD ---
	var head_pos = facing * -18 + Vector2(0, hover_y - 2)
	draw_circle(head_pos, 9.5, skin_col)
	# hood cowl — rounded triangle on top of head
	var hood_tip  = head_pos + facing * -16
	var hood_verts = PackedVector2Array([
		head_pos + facing * -2 + perp * -9,
		head_pos + facing * -2 + perp *  9,
		hood_tip + perp *  4,
		hood_tip + perp * -4,
	])
	draw_colored_polygon(hood_verts, robe_col)
	# hood shadow on face
	draw_circle(head_pos + facing * -2, 7.5, Color(robe_col.r, robe_col.g, robe_col.b, 0.5))
	# eyes — two small glowing dots
	var eye_l = head_pos + perp * -3 + facing * -1
	var eye_r = head_pos + perp *  3 + facing * -1
	draw_circle(eye_l, 2.5, Color(accent.r, accent.g, accent.b, 0.9))
	draw_circle(eye_r, 2.5, Color(accent.r, accent.g, accent.b, 0.9))

	# barrier shield visual
	if barrier_hp_left > 0:
		var bpct = barrier_hp_left / BARRIER_HP
		draw_arc(Vector2.ZERO, RADIUS + 14, 0, TAU, 48, Color(0.3, 0.7, 1.0, 0.35 + bpct * 0.5), 4.0)
		draw_arc(Vector2.ZERO, RADIUS + 19, 0, TAU, 32, Color(0.6, 0.9, 1.0, bpct * 0.3), 2.0)

	# arcane burst visual
	if nova_fx_left > 0:
		var pct = 1.0 - (nova_fx_left / 0.35)
		var r   = NOVA_RADIUS * pct
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(accent.r, accent.g, accent.b, (1.0 - pct) * 0.8), 3.0)
		draw_circle(Vector2.ZERO, r * 0.3, Color(accent.r, accent.g, accent.b, (1.0 - pct) * 0.25))

	# dash charge pips below
	for i in DASH_CHARGES_MAX:
		var px  = (i - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
		var col = Color(0.6, 0.9, 1.0, 0.9) if i < dash_charges else Color(0.25, 0.25, 0.35, 0.5)
		draw_circle(Vector2(px, RADIUS + 14), 4.0, col)
	if dash_charges < DASH_CHARGES_MAX:
		var px = (dash_charges - (DASH_CHARGES_MAX - 1) * 0.5) * 14.0
		draw_arc(Vector2(px, RADIUS + 14), 4.5, -PI/2,
			-PI/2 + TAU * (dash_charge_timer / DASH_CHARGE_REGEN), 16,
			Color(0.6, 0.9, 1.0, 0.8), 2.0)

	_draw_hud(now, accent)
