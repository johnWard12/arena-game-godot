extends Node2D

const W = 1920
const H = 1080

# CARD_W/GAP shrink automatically if there isn't room for CLASSES.size()
# cards side by side (see _ready()) — these are the "up to 4 cards" sizes.
var CARD_W := 210.0
const CARD_H = 250.0
const CARD_Y = 220.0
var GAP := 18.0
const MAX_SIDE_WIDTH := 900.0

# left section (player): N cards centered in left half (0..960)
# right section (bot): N cards centered in right half (960..1920)
# N is derived from CLASSES.size() so adding a class just means adding an
# entry below — no layout constants to hand-update.
var player_cards_x: Array = []
var bot_cards_x: Array = []

var hovered    := Vector2i(-1, -1)  # x=side (0=player,1=bot), y=card idx

# Team size (1v1/2v2/3v3). Each side now picks a class PER SLOT so 2v2/3v3
# can field mixed comps (a Cleric behind two bruisers, etc.), not just N
# copies of one class. player_slots[i]/bot_slots[i] are class indices into
# CLASSES; only the first `team_size` entries are used. Clicking a class
# card fills the currently-active slot and advances to the next, so you can
# fill a whole team by clicking classes left-to-right.
const TEAM_SIZES = [1, 2, 3]
var team_size := 1

var player_slots := [0, 4, 2]  # Duelist, Cleric, Bruiser
var bot_slots    := [1, 3, 4]  # Mage, Ranger, Cleric
var player_active_slot := 0
var bot_active_slot    := 0

const MELEE_COLOR  = Color(0.37, 0.88, 0.75)
const RANGED_COLOR = Color(0.72, 0.4,  1.0)

const BRUISER_COLOR = Color(0.95, 0.55, 0.15)
const RANGER_COLOR  = Color(0.45, 0.75, 0.35)
const CLERIC_COLOR  = Color(0.95, 0.88, 0.6)

const CLASSES = [
	{
		"label": "DUELIST",
		"color": MELEE_COLOR,
		"key":   "melee",
		"hp":    "HP  203",
		"lines": ["Melee glass cannon.", "Blood-lust on parry.", "", "Auto       LMB", "Strike     E", "Lunge      Q", "Throw      F", "Iron Resolve Shift", "Bladestorm R"],
		"ability_descs": [
			"7.5 dmg. 0.55s cooldown, 150 range. Basic swing, hold to auto-repeat.",
			"17.25 dmg stab. Slows 30% for 2s and reduces their healing received 25% for 3s. 2.5s cooldown, 145 range, 0.09s wind-up.",
			"Dash up to 270, strike for 29.3 dmg and stun 0.75s. Landing it grants 30% attack speed for 2s. 6.5s cooldown, 150 range.",
			"9.5 dmg (up to 22.15 vs a low-HP target), boosted up to 48% more by combo stacks. Slows 30% for 2s. 4s cooldown.",
			"Converts current combo stacks into damage reduction (10% per stack, up to 30%) for 3s, consuming them. 9s cooldown.",
			"Spin 1.5s, hitting foes within 170 range for 17.1 dmg every 0.3s (up to 5 hits, 85.5 total). Slow-immune while active. Builds on a 14s charge meter.",
		]
	},
	{
		"label": "MAGE",
		"color": RANGED_COLOR,
		"key":   "ranged",
		"hp":    "HP  162",
		"lines": ["Ranged burst mage.", "Kite and punish.", "", "Auto Shot  LMB", "Bolt       E", "Burst      Q", "Arcane Fan F", "Barrier    Shift", "Void Collapse R"],
		"ability_descs": [
			"6.75 dmg bolt. 0.75s cooldown. Basic shot, hold to auto-repeat.",
			"22 dmg piercing bolt. Slows 25% for 1.5s. 3.5s cooldown, 0.25s wind-up.",
			"AoE nova: 20 dmg + 1s stun to foes within 190 range. 4.5s cooldown, 0.2s wind-up.",
			"3-bolt spread, 12 dmg each (36 total if all land). 5s cooldown. Best up close.",
			"35 HP shield that absorbs incoming damage for 1.5s. 7s cooldown.",
			"Pulls the target in over 1.5s, then deals 45-92 dmg (more the closer they were) + 1s stun if within 90 range. 0.35s wind-up.",
		]
	},
	{
		"label": "BRUISER",
		"color": BRUISER_COLOR,
		"key":   "bruiser",
		"hp":    "HP  223",
		"lines": ["Tanky melee brawler.", "CC chains + survive.", "", "Smash      LMB", "Shatter    E", "Tremor     Q", "Warcry     F", "Unbreakable Shift", "Seismic Slam R"],
		"ability_descs": [
			"2.7 dmg. 0.7s cooldown, 167 range. Basic swing, hold to auto-repeat.",
			"19.8 dmg shield slam, stuns 0.7s. 5.5s cooldown, 151 range. Instant, no wind-up.",
			"Ground stomp: 16.2 dmg + 50% slow for 2s to foes within 180 range. 8s cooldown. Instant.",
			"You take 15% less damage; the opponent deals 10% less damage. Both for 4s, enemy debuff needs them within 210 range. 8s cooldown.",
			"Cleanses all CC, grants CC immunity, 25% damage reduction, and +30% move speed for 2.5s. 8.5s cooldown. Usable even while stunned.",
			"Lunge in (up to 280) and slam for 49.5 dmg, launching the target airborne for 1s — still damageable while up. 198 range.",
		]
	},
	{
		"label": "RANGER",
		"color": RANGER_COLOR,
		"key":   "ranger",
		"hp":    "HP  176",
		"lines": ["Mobile skirmisher.", "Kite, snare, vanish.", "", "QuickShot  LMB", "Pierce     E", "Snare      Q", "Disengage  F", "Camouflage Shift", "Rain of Arrows R"],
		"ability_descs": [
			"7.5 dmg. 0.5s cooldown. Landing shots builds Momentum: +4% move speed per stack (up to 5), resets on a miss.",
			"22.4 dmg, pierces through the first target and keeps going. Slows 20% for 1s. 4s cooldown, 0.18s wind-up.",
			"Throws a large trap 110 out that arms in 0.5s, then roots the first enemy to cross it for 1.2s. Invisible to the enemy team. 7s cooldown.",
			"15 dmg shot that also recoils you sharply backward — damage and real distance in one button. 6s cooldown.",
			"Turn fully invisible to the enemy team for 3s (allies still see you as a ghost). Attacking breaks it. 10s cooldown.",
			"Targets a zone that rains arrows for 2s, ticking 13.1 dmg every 0.4s to anyone standing in it. 130 radius, 0.3s wind-up.",
		]
	},
	{
		"label": "CLERIC",
		"color": CLERIC_COLOR,
		"key":   "cleric",
		"hp":    "HP  176",
		"lines": ["Team support/healer.", "Protects & empowers allies.", "", "Smite      LMB", "Mending    E", "Consecrate Q", "Purify     F", "Guardian Ward Shift", "Guardian's Bond R"],
		"ability_descs": [
			"6 dmg holy bolt. 0.6s cooldown. Builds combo stacks (boosts your healing, not damage).",
			"Skill-shot heal toward your lowest-HP ally within 400 range (self if none). Heals 32.4 (+10% per combo stack). An enemy body in its path takes 12 dmg and is slowed 30% for 1s instead. 3s cooldown, 0.2s wind-up.",
			"Instant zone placed at your cursor (up to 350 range): 8 dmg to enemies, 10.8 heal to allies standing in it, ticking every 1s for 3s. 225 radius. 8s cooldown.",
			"Rectangle cast (300 long, 180 wide) — cleanses CC/debuffs from every ally it hits (including you), adds a small heal-over-time (8.1/tick), and heals you for 12 instantly. 10s cooldown.",
			"Shields your lowest-HP ally within 400 range (self if none): 25 HP + 7.5 per banked combo stack (stacks aren't consumed). 9s cooldown.",
			"Links you with your lowest-HP ally in range for 4s: damage either takes splits 50/50, both take 20% less damage and heal over time. No ally in range -> self-only (still get the reduction + healing). Usable even while stunned.",
		]
	},
]

func _ready():
	var n = CLASSES.size()
	var total_w = CARD_W * n + GAP * (n - 1)
	if total_w > MAX_SIDE_WIDTH:
		var s = MAX_SIDE_WIDTH / total_w
		CARD_W *= s
		GAP *= s
		total_w = MAX_SIDE_WIDTH
	for i in n:
		player_cards_x.append(W * 0.25 - total_w * 0.5 + i * (CARD_W + GAP))
		bot_cards_x.append(W * 0.75 - total_w * 0.5 + i * (CARD_W + GAP))
	queue_redraw()

var tooltip_text := ""
var tooltip_pos  := Vector2.ZERO
var tooltip_col  := Color.WHITE

# Scratch stylebox for every rounded element on this screen — mutated right
# before each draw, which is safe because canvas draws are immediate.
var _sb := StyleBoxFlat.new()

# Emboldened fallback font (see Main.gd's _hud_font) — lazily built since
# ThemeDB may not be ready at member-init time.
var _font: FontVariation

func _ui_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.5
	return _font

func _round_rect(rect: Rect2, bg: Color, border: Color, border_w: int, radius: int):
	_sb.bg_color = bg
	_sb.set_corner_radius_all(radius)
	_sb.border_color = border
	_sb.set_border_width_all(border_w)
	draw_style_box(_sb, rect)

func _input(event):
	if event is InputEventMouseMotion:
		var prev = hovered
		hovered = _card_under(event.position)
		if hovered != prev:
			queue_redraw()
		queue_redraw()  # tooltip tracks the cursor within a card too
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# team size
		for i in TEAM_SIZES.size():
			if _team_size_btn_rect(i).has_point(event.position):
				team_size = TEAM_SIZES[i]
				player_active_slot = min(player_active_slot, team_size - 1)
				bot_active_slot = min(bot_active_slot, team_size - 1)
				queue_redraw()
				return
		# slot chips — click to choose which slot the next class pick fills
		for s in team_size:
			if _slot_chip_rect(0, s).has_point(event.position):
				player_active_slot = s
				queue_redraw()
				return
			if _slot_chip_rect(1, s).has_point(event.position):
				bot_active_slot = s
				queue_redraw()
				return
		# class cards — assign to the active slot, then advance to the next
		var c = _card_under(event.position)
		if c.x == 0:
			player_slots[player_active_slot] = c.y
			player_active_slot = (player_active_slot + 1) % team_size
			queue_redraw()
			return
		elif c.x == 1:
			bot_slots[bot_active_slot] = c.y
			bot_active_slot = (bot_active_slot + 1) % team_size
			queue_redraw()
			return
		# fight button
		if _fight_btn_rect().has_point(event.position):
			_start()

# One class chip per team slot, in a row centered under each side's header.
func _slot_chip_rect(side: int, slot_idx: int) -> Rect2:
	var chip_w = 88.0
	var chip_h = 26.0
	var gap = 8.0
	var total = chip_w * team_size + gap * (team_size - 1)
	var center_x = W * 0.25 if side == 0 else W * 0.75
	var start_x = center_x - total * 0.5
	return Rect2(start_x + slot_idx * (chip_w + gap), 176, chip_w, chip_h)

func _team_size_btn_rect(i: int) -> Rect2:
	var w = 64.0
	var h = 32.0
	var gap = 10.0
	var total_w = w * TEAM_SIZES.size() + gap * (TEAM_SIZES.size() - 1)
	var start_x = W * 0.5 - total_w * 0.5
	return Rect2(start_x + i * (w + gap), 108, w, h)

func _card_under(pos: Vector2) -> Vector2i:
	for i in CLASSES.size():
		var r = Rect2(player_cards_x[i], CARD_Y, CARD_W, CARD_H)
		if r.has_point(pos):
			return Vector2i(0, i)
	for i in CLASSES.size():
		var r = Rect2(bot_cards_x[i], CARD_Y, CARD_W, CARD_H)
		if r.has_point(pos):
			return Vector2i(1, i)
	return Vector2i(-1, -1)

func _fight_btn_rect() -> Rect2:
	return Rect2(W * 0.5 - 100, CARD_Y + CARD_H + 40, 200, 52)

func _start():
	var pkeys := []
	var bkeys := []
	for s in team_size:
		pkeys.append(CLASSES[player_slots[s]]["key"])
		bkeys.append(CLASSES[bot_slots[s]]["key"])
	get_tree().root.set_meta("player_classes", pkeys)
	get_tree().root.set_meta("bot_classes",    bkeys)
	# Legacy single-key meta kept for any reader that still expects it; slot 0
	# is the human-controlled fighter on the player side.
	get_tree().root.set_meta("player_class", pkeys[0])
	get_tree().root.set_meta("bot_class",    bkeys[0])
	get_tree().root.set_meta("team_size",    team_size)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _draw():
	# Vertical gradient backdrop — deep blue falling to near-black — far less
	# flat than the old single fill.
	var top_col = Color(0.10, 0.11, 0.17)
	var bot_col = Color(0.045, 0.05, 0.08)
	var strips = 36
	for i in strips:
		var t0 = float(i) / strips
		draw_rect(Rect2(0, H * t0, W, H / float(strips) + 1.0), top_col.lerp(bot_col, t0))

	_draw_text("ARENA PROTOTYPE", Vector2(W * 0.5, 46), 20, Color(0.85, 0.72, 0.45, 0.75), true)
	_draw_text("CHOOSE YOUR FIGHTERS", Vector2(W * 0.5, 82), 36, Color(0.96, 0.97, 1.0), true)
	draw_rect(Rect2(W * 0.5 - 130, 98, 260, 2), Color(0.85, 0.72, 0.45, 0.45))

	# team size selector
	for i in TEAM_SIZES.size():
		var size_val = TEAM_SIZES[i]
		var r = _team_size_btn_rect(i)
		var is_sel = team_size == size_val
		var is_hot = r.has_point(get_viewport().get_mouse_position())
		var bg_a = 0.26 if is_sel else (0.14 if is_hot else 0.06)
		_round_rect(r, Color(1, 1, 1, bg_a), Color(1, 1, 1, 0.9 if is_sel else 0.28), 2 if is_sel else 1, 7)
		_draw_text("%dv%d" % [size_val, size_val], r.position + r.size * 0.5,
			14, Color(1, 1, 1, 0.95 if is_sel else 0.6), true)

	# section headers
	_draw_text("YOU", Vector2(W * 0.25, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)
	_draw_text("BOT", Vector2(W * 0.75, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)

	# per-slot class chips (one row per side)
	_draw_slot_chips(0, player_slots, player_active_slot)
	_draw_slot_chips(1, bot_slots, bot_active_slot)

	# center divider
	var mid = W * 0.5
	draw_line(Vector2(mid, CARD_Y - 10), Vector2(mid, CARD_Y + CARD_H + 10),
		Color(1, 1, 1, 0.08), 1.0)
	_draw_text("VS", Vector2(mid, CARD_Y + CARD_H * 0.5), 26, Color(0.5, 0.5, 0.6, 0.4), true)

	# draw all cards
	tooltip_text = ""
	var mouse_pos = get_viewport().get_mouse_position()
	# A card reads as "selected" when it's the class currently in the active
	# slot, so it always reflects what the next pick would replace.
	for i in CLASSES.size():
		_draw_card(player_cards_x[i], i, player_slots[player_active_slot] == i, hovered == Vector2i(0, i), mouse_pos)
	for i in CLASSES.size():
		_draw_card(bot_cards_x[i], i, bot_slots[bot_active_slot] == i, hovered == Vector2i(1, i), mouse_pos)

	# fight button — rounded with a drop shadow, glow ring on hover
	var btn = _fight_btn_rect()
	var btn_hot = btn.has_point(get_viewport().get_mouse_position())
	_round_rect(Rect2(btn.position + Vector2(0, 5), btn.size), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 12)
	var btn_col = Color(0.37, 0.88, 0.75) if btn_hot else Color(0.24, 0.62, 0.52)
	_round_rect(btn, btn_col, Color(1, 1, 1, 0.5 if btn_hot else 0.18), 1, 12)
	if btn_hot:
		_round_rect(btn.grow(4), Color(0, 0, 0, 0), Color(0.37, 0.88, 0.75, 0.35), 2, 14)
	_draw_text("FIGHT", Vector2(btn.position.x + btn.size.x * 0.5, btn.position.y + btn.size.y * 0.5 + 2),
		22, Color(0.03, 0.10, 0.09), true)

	# matchup summary below button — lists each side's comp
	var p_names := []
	var b_names := []
	for s in team_size:
		p_names.append(CLASSES[player_slots[s]]["label"].capitalize())
		b_names.append(CLASSES[bot_slots[s]]["label"].capitalize())
	var summary = "%s  vs  %s (bot)" % [" / ".join(p_names), " / ".join(b_names)]
	_draw_text(summary,
		Vector2(W * 0.5, btn.position.y + btn.size.y + 28), 15, Color(0.55, 0.55, 0.65, 0.7), true)

	if tooltip_text != "":
		_draw_tooltip()

# A row of class chips, one per team slot, showing each slot's current class
# in its class color. The active slot (the one the next class click fills)
# is outlined brighter. Clicking a chip makes that slot active.
func _draw_slot_chips(side: int, slots: Array, active: int):
	if team_size <= 1:
		return  # a single slot is already fully conveyed by the card highlight
	for s in team_size:
		var r = _slot_chip_rect(side, s)
		var cls = CLASSES[slots[s]]
		var col: Color = cls["color"]
		var is_active = s == active
		_round_rect(r, Color(col.r, col.g, col.b, 0.28 if is_active else 0.14),
			Color(col.r, col.g, col.b, 1.0 if is_active else 0.4), 2 if is_active else 1, 6)
		_draw_text(cls["label"].capitalize(), r.position + r.size * 0.5, 12,
			Color(1, 1, 1, 0.95 if is_active else 0.7), true)

func _draw_tooltip():
	var font    = _ui_font()
	var size    = 13
	var padding = 12.0
	var max_w   = 340.0

	# Word-wrap each "\n"-separated paragraph independently, so forced
	# breaks (between abilities) survive alongside natural wrapping within
	# a single ability's description.
	var wrapped: Array[String] = []
	for para in tooltip_text.split("\n"):
		if para == "":
			wrapped.append("")
			continue
		var words = para.split(" ")
		var cur = ""
		for w in words:
			var trial = w if cur == "" else cur + " " + w
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w and cur != "":
				wrapped.append(cur)
				cur = w
			else:
				cur = trial
		if cur != "":
			wrapped.append(cur)

	var line_h = 17.0
	var box_w  = max_w + padding * 2
	var box_h  = wrapped.size() * line_h + padding * 2

	var pos = tooltip_pos
	if pos.x + box_w > W - 10:
		pos.x = W - 10 - box_w
	if pos.y + box_h > H - 10:
		pos.y = H - 10 - box_h

	_round_rect(Rect2(pos + Vector2(3, 4), Vector2(box_w, box_h)), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 10)
	_round_rect(Rect2(pos, Vector2(box_w, box_h)), Color(0.05, 0.06, 0.10, 0.97),
		Color(tooltip_col.r, tooltip_col.g, tooltip_col.b, 0.55), 1, 10)

	var ty = pos.y + padding
	for line in wrapped:
		if line != "":
			draw_string(font, Vector2(pos.x + padding, ty + size * 0.85), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.9, 0.95, 0.95))
		ty += line_h

func _draw_card(cx: float, class_idx: int, selected: bool, hot: bool, mouse_pos: Vector2):
	var c = CLASSES[class_idx]
	var col: Color = c["color"]

	var card = Rect2(cx, CARD_Y, CARD_W, CARD_H)
	# drop shadow (deeper when hovered), then a solid dark base, then the
	# class-color tint + border on top — reads as a real elevated card.
	_round_rect(Rect2(card.position + Vector2(0, 6), card.size),
		Color(0, 0, 0, 0.32 if hot else 0.18), Color(0, 0, 0, 0), 0, 12)
	_round_rect(card, Color(0.07, 0.08, 0.12, 0.94), Color(0, 0, 0, 0), 0, 12)
	var bg_alpha = 0.20 if selected else (0.13 if hot else 0.06)
	_round_rect(card, Color(col.r, col.g, col.b, bg_alpha),
		Color(col.r, col.g, col.b, 1.0 if selected else (0.55 if hot else 0.22)),
		2 if selected else 1, 12)

	if selected:
		# top accent bar, inset to follow the rounded corners
		_round_rect(Rect2(cx + 10, CARD_Y, CARD_W - 20, 3), Color(col.r, col.g, col.b, 0.9), Color(0, 0, 0, 0), 0, 2)

	# character preview — bigger now that the full ability list lives in
	# the hover tooltip instead of being crammed onto the card itself.
	var pcx = cx + CARD_W * 0.5
	var pcy = CARD_Y + CARD_H * 0.4
	var r = 42.0
	draw_circle(Vector2(pcx + 2, pcy + 3), r, Color(0, 0, 0, 0.2))
	draw_circle(Vector2(pcx, pcy), r, col)
	draw_circle(Vector2(pcx, pcy), r * 0.52, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.7))
	draw_arc(Vector2(pcx, pcy), r + 6, -PI/2, -PI/2 + TAU, 48, Color(col.r, col.g, col.b, 0.6), 2.0)

	# name + hp
	_draw_text(c["label"], Vector2(pcx, pcy + r + 28), 22, col, true)
	_draw_text(c["hp"],    Vector2(pcx, pcy + r + 52), 14, Color(col.r, col.g, col.b, 0.65), true)

	var hint_col = Color(1, 1, 1, 0.6) if hot else Color(1, 1, 1, 0.3)
	_draw_text("hover for full kit", Vector2(pcx, CARD_Y + CARD_H - 28), 12, hint_col, true)

	# selected badge
	if selected:
		_draw_text("SELECTED", Vector2(pcx, CARD_Y + CARD_H - 10), 12, Color(col.r, col.g, col.b, 0.9), true)

	if hot:
		tooltip_text = _build_kit_tooltip(c)
		tooltip_pos  = Vector2(cx + CARD_W + 6, CARD_Y)
		tooltip_col  = col

# Consolidates a class's flavor text + full ability list (name/key + full
# description) into one block for the hover tooltip — this used to be
# drawn statically on every card at once (10 cards x 9 lines of tiny text
# on screen simultaneously), which is what made the screen feel cluttered.
func _build_kit_tooltip(c: Dictionary) -> String:
	var parts: Array[String] = []
	var lines: Array = c["lines"]
	if lines.size() > 0 and lines[0] != "":
		parts.append(lines[0])
	if lines.size() > 1 and lines[1] != "":
		parts.append(lines[1])

	var descs: Array = c.get("ability_descs", [])
	var ability_i = 0
	for j in lines.size():
		if j < 3:
			continue
		var line: String = lines[j]
		if line == "":
			continue
		var tokens = line.split(" ", false)
		var key = tokens[-1]
		var name = " ".join(tokens.slice(0, tokens.size() - 1))
		var desc = descs[ability_i] if ability_i < descs.size() else ""
		parts.append("[%s] %s\n%s" % [key, name, desc])
		ability_i += 1

	return "\n\n".join(parts)

func _draw_text(text: String, pos: Vector2, size: int, col: Color, centered: bool):
	var font = _ui_font()
	if centered:
		var sw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(pos.x - sw * 0.5, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	else:
		draw_string(font, Vector2(pos.x, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
