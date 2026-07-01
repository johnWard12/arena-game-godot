extends "res://scripts/Entity.gd"
class_name BruiserEntity

const BRUISER_MAX_HP     = 180.0
const BRUISER_MAX_SPEED  = 370.0
const BRUISER_ACCEL      = 2800.0
const BRUISER_FRICTION   = 1400.0

const BRUISER_AUTO_CD    = 0.70
const BRUISER_AUTO_DMG   = 3.0
const BRUISER_AUTO_RANGE = 185.0

# E — Shatter: shield slam + stun (instant)
const SHATTER_RECOVERY = 0.25
const SHATTER_CD       = 4.5
const SHATTER_DMG      = 22.0
const SHATTER_RANGE    = 168.0
const SHATTER_STUN     = 0.70

# Q — Tremor: ground stomp AoE + slow (instant)
const TREMOR_RECOVERY = 0.25
const TREMOR_CD       = 7.0
const TREMOR_DMG      = 18.0
const TREMOR_RADIUS   = 200.0
const TREMOR_SLOW     = 2.0

# Ult — Seismic Slam: lunge + ground slam, knockup
const SEISMIC_LUNGE_DUR  = 0.14
const SEISMIC_LUNGE_DIST = 280.0
const SEISMIC_RANGE      = 220.0
const SEISMIC_DMG        = 55.0
const SEISMIC_KNOCKUP    = 1.0
const SEISMIC_RECOVERY   = 0.65

# F — Unbreakable: CC cleanse + immunity + damage reduction
const UNBREAKABLE_CD           = 7.0
const UNBREAKABLE_DUR          = 3.0
const UNBREAKABLE_DMG_REDUCE   = 0.25
const UNBREAKABLE_MOVE_MULT    = 1.40

var tremor_fx_left        := 0.0
var unbreakable_time_left := 0.0
var seismic_slam_fx_left  := 0.0
var seismic_lunge_pending := false

func _ready():
	hp             = BRUISER_MAX_HP
	max_hp         = BRUISER_MAX_HP
	base_color     = Color(0.95, 0.55, 0.15)
	speed_override = BRUISER_MAX_SPEED
	stun_resist_mult = 0.85
	recovery_slows_movement = false  # Steady Footing: 15% less duration on incoming stuns/freezes

func _physics_process(delta):
	tremor_fx_left     = max(0.0, tremor_fx_left - delta)
	seismic_slam_fx_left = max(0.0, seismic_slam_fx_left - delta)
	if unbreakable_time_left > 0:
		unbreakable_time_left = max(0.0, unbreakable_time_left - delta)
		if unbreakable_time_left <= 0:
			cc_immune      = false
			dmg_reduction  = 0.0
			speed_override = BRUISER_MAX_SPEED
	super._physics_process(delta)

# Blood-lust is a Duelist-only passive.
func on_landed_parry():
	pass

# ---- Ability overrides ----

func try_auto(opp: Entity):
	if not can_start_ability() or cd_auto > 0 or opp == null:
		return
	cd_auto = BRUISER_AUTO_CD
	facing = get_aim_dir(opp)
	start_swing(80.0, 0.15)
	if global_position.distance_to(opp.global_position) <= BRUISER_AUTO_RANGE:
		deal_damage(opp, BRUISER_AUTO_DMG * combo_mult())
		add_combo_stack()

func try_a1(opp: Entity):
	if not alive or cd_a1 > 0 or recovering != null or lunging or opp == null:
		return
	facing = get_aim_dir(opp)
	start_swing(100.0, 0.22)
	if opp.alive and global_position.distance_to(opp.global_position) <= SHATTER_RANGE:
		var dmg = round(SHATTER_DMG * combo_mult())
		deal_damage(opp, dmg)
		if opp.alive:
			opp.apply_stun(SHATTER_STUN)
		add_combo_stack()
	cd_a1 = SHATTER_CD
	recovering = {"type": "a1", "time_left": SHATTER_RECOVERY, "total": SHATTER_RECOVERY}

func resolve_a1(_opp: Entity):
	pass

func try_a2(opp: Entity):
	if not alive or cd_a2 > 0 or recovering != null or lunging or opp == null:
		return
	tremor_fx_left = 0.4
	if opp.alive and global_position.distance_to(opp.global_position) <= TREMOR_RADIUS:
		var dmg = round(TREMOR_DMG * combo_mult())
		deal_damage(opp, dmg)
		if opp.alive:
			opp.apply_slow(TREMOR_SLOW, 0.5)
		add_combo_stack()
	cd_a2 = TREMOR_CD
	recovering = {"type": "a2", "time_left": TREMOR_RECOVERY, "total": TREMOR_RECOVERY}

func resolve_a2(_opp: Entity):
	pass

func try_ult(opp: Entity):
	if not alive or ult_charge < ULT_CHARGE_MAX or recovering != null or lunging or opp == null:
		return
	ult_charge = 0.0
	facing = get_aim_dir(opp)
	seismic_lunge_pending = true
	lunging = true
	lunge_time_left = SEISMIC_LUNGE_DUR
	lunge_speed = SEISMIC_LUNGE_DIST / SEISMIC_LUNGE_DUR
	lunge_reach = SEISMIC_RANGE
	lunge_dir = facing
	lunge_opponent = opp

func resolve_ult(_opp: Entity):
	pass

func resolve_lunge_strike(opp: Entity):
	if seismic_lunge_pending:
		seismic_lunge_pending = false
		_do_seismic_slam(opp)

func _do_seismic_slam(opp: Entity):
	start_swing(360.0, 0.45)
	seismic_slam_fx_left = 0.70
	if opp != null and opp.alive and global_position.distance_to(opp.global_position) <= SEISMIC_RANGE:
		if deal_damage(opp, SEISMIC_DMG):
			add_combo_stack()
			if opp.alive:
				opp.knockup_time_left = SEISMIC_KNOCKUP
	screen_shake.emit(14.0, 0.45)

func try_a3(_opp: Entity):
	# Usable even while stunned — that's the point
	if not alive or cd_a3 > 0 or unbreakable_time_left > 0:
		return
	stunned_time_left = 0.0
	slowed_time_left  = 0.0
	cc_immune         = true
	dmg_reduction     = UNBREAKABLE_DMG_REDUCE
	speed_override    = BRUISER_MAX_SPEED * UNBREAKABLE_MOVE_MULT
	unbreakable_time_left = UNBREAKABLE_DUR
	cd_a3 = UNBREAKABLE_CD

func resolve_a3(_opp: Entity):
	pass

# ---- Drawing ----
func _draw():
	var now = Time.get_ticks_msec()

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
		draw_set_transform(Vector2(0, ku_y))

	_draw_bruiser(now, accent)

	if ku_y != 0.0:
		draw_set_transform(Vector2.ZERO)

	_draw_hud(now, accent)

func _draw_bruiser(now: int, accent: Color):
	var perp   = Vector2(-facing.y, facing.x)
	var armor  = _col_dark(accent, 0.5)
	var dark   = Color(0.10, 0.11, 0.14)
	var skin   = Color(0.88, 0.72, 0.56)
	var boot   = Color(0.18, 0.14, 0.10)

	var spd_pct = clamp(velocity.length() / BRUISER_MAX_SPEED, 0.0, 1.0)
	var stride  = spd_pct * 8.0
	var bob_y   = sin(walk_phase * 2.0) * spd_pct * 1.2

	# Unbreakable — white flash rings
	if unbreakable_time_left > 0:
		var t     = Time.get_ticks_msec() * 0.006
		var pulse = 0.55 + 0.45 * sin(t * 5.0)
		draw_circle(Vector2.ZERO, RADIUS + 3, Color(1, 1, 1, pulse * 0.30))
		draw_arc(Vector2.ZERO, RADIUS + 5,  0, TAU, 48, Color(1, 1, 1, pulse * 0.90), 4.0)
		draw_arc(Vector2.ZERO, RADIUS + 13, 0, TAU, 36, Color(1, 1, 1, pulse * 0.45), 2.0)

	# Seismic Slam — expanding crack ring + radiating lines
	if seismic_slam_fx_left > 0:
		var sp = seismic_slam_fx_left / 0.70
		var ring_r = (1.0 - sp) * SEISMIC_RANGE * 0.9 + RADIUS
		draw_arc(Vector2.ZERO, ring_r,       0, TAU, 64, Color(0.95, 0.55, 0.1, sp * 0.85), 5.0 * sp)
		draw_arc(Vector2.ZERO, ring_r * 0.6, 0, TAU, 48, Color(1.0, 0.8, 0.3,  sp * 0.45), 2.5)
		for i in 8:
			var a = i * TAU / 8.0
			var crack_end = Vector2(cos(a), sin(a)) * (RADIUS + (1.0 - sp) * 170.0)
			draw_line(Vector2(cos(a), sin(a)) * RADIUS, crack_end,
				Color(0.85, 0.45, 0.05, sp * 0.9), 3.5 * sp, true)

	# tremor shockwave ring
	if tremor_fx_left > 0:
		var pct = 1.0 - (tremor_fx_left / 0.4)
		var r   = TREMOR_RADIUS * pct
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(accent.r, accent.g, accent.b, (1.0 - pct) * 0.85), 4.0)
		draw_circle(Vector2.ZERO, r * 0.25, Color(accent.r, accent.g, accent.b, (1.0 - pct) * 0.2))

	# ground shadow
	draw_circle(Vector2(2, RADIUS - 4), 18, Color(0, 0, 0, 0.22))

	# --- LEGS (stockier) ---
	var lleg_end = Vector2(perp * -7 + facing * sin(walk_phase) * stride + Vector2(0, RADIUS - 2 + bob_y))
	var rleg_end = Vector2(perp *  7 - facing * sin(walk_phase) * stride + Vector2(0, RADIUS - 2 + bob_y))
	draw_line(Vector2(perp * -5 + facing * 2), lleg_end, armor, 8.0, true)
	draw_line(Vector2(perp *  5 + facing * 2), rleg_end, armor, 8.0, true)
	draw_circle(lleg_end, 6.5, boot)
	draw_circle(rleg_end, 6.5, boot)

	# --- HAMMER at rest (right side, behind body) ---
	if swing_time_left <= 0:
		var ham_dir = (facing * 0.2 - perp * 0.7).normalized()
		var hb = ham_dir * (RADIUS - 4)
		var ht = ham_dir * (RADIUS + 52.0)
		draw_line(hb, ht, Color(0.35, 0.28, 0.20, 0.65), 7.0, true)
		# hammer head
		draw_circle(ht, 10.0, Color(0.55, 0.55, 0.65, 0.6))
		draw_line(ht + perp * 10, ht - perp * 10, Color(0.65, 0.65, 0.75, 0.65), 7.0)

	# --- BODY (wide, stocky) ---
	var body = PackedVector2Array([
		facing * -14 + perp * -12,
		facing * -14 + perp *  12,
		facing *  10 + perp *  11,
		facing *  10 + perp * -11,
	])
	draw_colored_polygon(body, armor)
	# chest plate — heavy reinforced look
	var chest = PackedVector2Array([
		facing * -12 + perp * -7,
		facing * -12 + perp *  7,
		facing *   3 + perp *  6,
		facing *   3 + perp * -6,
	])
	draw_colored_polygon(chest, Color(accent.r, accent.g, accent.b, 0.6))
	# center ridge on chest
	draw_line(facing * -10, facing * 2, Color(accent.r * 1.2, accent.g * 1.2, accent.b * 1.2, 0.4), 2.5)

	# --- SHIELD (left arm, front-facing) ---
	var shield_center = facing * -2 + perp * -14
	var shield_verts = PackedVector2Array([
		shield_center + facing * -9 + perp * -6,
		shield_center + facing * -9 + perp *  4,
		shield_center + facing *  9 + perp *  5,
		shield_center + facing *  9 + perp * -7,
	])
	draw_colored_polygon(shield_verts, armor)
	draw_colored_polygon(shield_verts, Color(0, 0, 0, 0.0))
	draw_polyline(PackedVector2Array([
		shield_verts[0], shield_verts[1], shield_verts[2], shield_verts[3], shield_verts[0]
	]), Color(accent.r, accent.g, accent.b, 0.7), 2.0)
	# shield emblem dot
	draw_circle(shield_center + facing * 0 + perp * -1, 3.5, Color(accent.r, accent.g, accent.b, 0.55))

	# --- PAULDRONS (larger than duelist) ---
	draw_circle(facing * -11 + perp * -13, 9.0, armor)
	draw_circle(facing * -11 + perp *  13, 9.0, armor)
	draw_circle(facing * -11 + perp * -13, 5.5, _col_dark(accent, 0.4))
	draw_circle(facing * -11 + perp *  13, 5.5, _col_dark(accent, 0.4))

	# --- HEAD ---
	var head = facing * -22 + Vector2(0, bob_y)
	draw_circle(head, 11.0, skin)
	# full helm — more coverage than duelist
	var helm = PackedVector2Array([
		head + facing * -13 + perp * -10,
		head + facing * -13 + perp *  10,
		head + facing *   6 + perp *   9,
		head + facing *   6 + perp *  -9,
	])
	draw_colored_polygon(helm, armor)
	# visor slit (narrower, more menacing)
	draw_line(head + perp * -4 + facing * -1,
			  head + perp *  4 + facing * -1,
			  Color(accent.r, accent.g, accent.b, 0.95), 3.0)
	# helm war crest (prominent)
	draw_line(head + facing * -13, head + facing * 5,
			  Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 0.95), 6.0)
	draw_line(head + facing * -13, head + facing * 5,
			  Color(accent.r, accent.g, accent.b, 0.65), 2.5)

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

	# --- HAMMER SWING ---
	if swing_time_left > 0 and swing_total > 0:
		var t         = 1.0 - (swing_time_left / swing_total)
		var cur_angle = swing_start_angle + swing_arc_span * t
		var sdir      = Vector2(cos(cur_angle), sin(cur_angle))
		var sperp     = Vector2(-sdir.y, sdir.x)
		var sroot     = sdir * RADIUS
		var stip      = sdir * (RADIUS + 52.0)
		var alpha     = 0.95 * (swing_time_left / swing_total)

		# arc fill
		var arc_start = swing_start_angle
		var arc_end   = cur_angle
		if abs(arc_end - arc_start) > 0.05:
			var fan: PackedVector2Array = []
			fan.append(Vector2.ZERO)
			for i in 19:
				var a = arc_start + (arc_end - arc_start) * float(i) / 18.0
				fan.append(Vector2(cos(a), sin(a)) * (RADIUS + 52.0))
			draw_colored_polygon(fan, Color(accent.r, accent.g, accent.b, alpha * 0.18))

		# shaft
		draw_line(sroot, stip, Color(0.35, 0.28, 0.20, alpha), 7.0, true)
		# head
		draw_circle(stip, 11.0, Color(0.7, 0.7, 0.8, alpha))
		draw_line(stip + sperp * 11, stip - sperp * 11,
			Color(0.8, 0.8, 0.9, alpha), 8.0)
		# impact glow at tip
		draw_circle(stip, 14.0, Color(accent.r, accent.g, accent.b, alpha * 0.35))
