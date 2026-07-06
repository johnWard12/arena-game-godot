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

# 0=Duelist 1=Mage 2=Bruiser; default: player=Duelist, bot=Mage
var player_sel := 0
var bot_sel    := 1
var hovered    := Vector2i(-1, -1)  # x=side (0=player,1=bot), y=card idx

# Team size (1v1/2v2/3v3). The chosen class fills every slot on a side for
# now — teammates/enemies beyond the human player are AI-controlled copies
# of that same class. A per-slot class picker is a natural follow-up.
const TEAM_SIZES = [1, 2, 3]
var team_size := 1

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
		"hp":    "HP  150",
		"lines": ["Melee glass cannon.", "Blood-lust on parry.", "", "Auto       LMB", "Strike     E", "Lunge      Q", "Throw      F", "IronResolve Shift", "Bladestorm R"],
		"ability_descs": [
			"4 dmg. 0.55s cooldown, 150 range. Basic swing, hold to auto-repeat.",
			"12 dmg stab. Slows 30% for 2s. 1.8s cooldown, 145 range, 0.09s wind-up.",
			"Dash up to 270, strike for 20.4 dmg and stun 0.5s. 6.5s cooldown, 150 range.",
			"6 dmg (up to 14 vs a low-HP target). Slows 30% for 2s. 4s cooldown.",
			"Converts current combo stacks into damage reduction (10% per stack, up to 30%) for 2s, consuming them. 7s cooldown.",
			"Spin 1.5s, hitting foes within 170 range for 14 dmg every 0.3s (up to 5 hits, 70 total). Slow-immune while active. Builds on a 14s charge meter.",
		]
	},
	{
		"label": "MAGE",
		"color": RANGED_COLOR,
		"key":   "ranged",
		"hp":    "HP  120",
		"lines": ["Ranged burst mage.", "Kite and punish.", "", "Auto Shot  LMB", "Bolt       E", "Burst      Q", "ArcaneFan  F", "Barrier    Shift", "VoidColl   R"],
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
		"hp":    "HP  180",
		"lines": ["Tanky melee brawler.", "CC chains + survive.", "", "Smash      LMB", "Shatter    E", "Tremor     Q", "Warcry     F", "Unbreakable Shift", "Seismic    R"],
		"ability_descs": [
			"3 dmg. 0.7s cooldown, 167 range. Basic swing, hold to auto-repeat.",
			"22 dmg shield slam, stuns 0.7s. 5.5s cooldown, 151 range. Instant, no wind-up.",
			"Ground stomp: 18 dmg + 50% slow for 2s to foes within 180 range. 8s cooldown. Instant.",
			"You take 15% less damage; the opponent deals 10% less damage. Both for 4s, enemy debuff needs them within 210 range. 8s cooldown.",
			"Cleanses all CC, grants CC immunity, 25% damage reduction, and +40% move speed for 3s. 8.5s cooldown. Usable even while stunned.",
			"Lunge in (up to 280) and slam for 55 dmg, launching the target airborne for 1s — still damageable while up. 198 range.",
		]
	},
	{
		"label": "RANGER",
		"color": RANGER_COLOR,
		"key":   "ranger",
		"hp":    "HP  130",
		"lines": ["Mobile skirmisher.", "Kite, snare, vanish.", "", "QuickShot  LMB", "Pierce     E", "Snare      Q", "Disengage  F", "Camouflage Shift", "RainArrows R"],
		"ability_descs": [
			"8 dmg. 0.5s cooldown. Landing shots builds Momentum: +4% move speed per stack (up to 5), resets on a miss.",
			"24 dmg, pierces through the first target and keeps going. Slows 20% for 1s. 4s cooldown, 0.18s wind-up.",
			"Throws a trap 110 out that arms in 0.6s, then roots the first enemy to cross it for 1.2s. 7s cooldown.",
			"16 dmg shot that also recoils you sharply backward — damage and real distance in one button. 6s cooldown.",
			"Vanish from AI targeting for 3s (a human player tracking you can still hit you). 10s cooldown.",
			"Targets a zone that rains arrows for 2s, ticking 9 dmg every 0.4s to anyone standing in it. 130 radius, 0.3s wind-up.",
		]
	},
	{
		"label": "CLERIC",
		"color": CLERIC_COLOR,
		"key":   "cleric",
		"hp":    "HP  130",
		"lines": ["Team support/healer.", "Protects & empowers allies.", "", "Smite      LMB", "Mending    E", "Consecrate Q", "Purify     F", "Guardian Ward Shift", "Guardian's Bond R"],
		"ability_descs": [
			"7 dmg holy bolt. 0.6s cooldown. Builds combo stacks (boosts your healing, not damage).",
			"Skill-shot heal toward your lowest-HP ally within 400 range (self if none). Heals 24 (+10% per combo stack). 3s cooldown, 0.2s wind-up.",
			"Instant zone at your feet: damages enemies and heals allies standing in it, ticking every 1s for 3s. 150 radius. 8s cooldown.",
			"Rectangle cast (300 long, 180 wide) — cleanses CC/debuffs from every ally it hits (including you) and adds a small heal-over-time. 10s cooldown.",
			"Shields your lowest-HP ally within 400 range (self if none): 30 HP + 8 per banked combo stack, consuming them. 9s cooldown.",
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

func _input(event):
	if event is InputEventMouseMotion:
		var prev = hovered
		hovered = _card_under(event.position)
		if hovered != prev:
			queue_redraw()
		queue_redraw()  # tooltip tracks the cursor within a card too
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c = _card_under(event.position)
		if c.x == 0:
			player_sel = c.y
			queue_redraw()
		elif c.x == 1:
			bot_sel = c.y
			queue_redraw()
		for i in TEAM_SIZES.size():
			if _team_size_btn_rect(i).has_point(event.position):
				team_size = TEAM_SIZES[i]
				queue_redraw()
		# fight button
		if _fight_btn_rect().has_point(event.position):
			_start()

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
	get_tree().root.set_meta("player_class", CLASSES[player_sel]["key"])
	get_tree().root.set_meta("bot_class",    CLASSES[bot_sel]["key"])
	get_tree().root.set_meta("team_size",    team_size)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _draw():
	draw_rect(Rect2(0, 0, W, H), Color(0.07, 0.08, 0.11))

	_draw_text("ARENA PROTOTYPE", Vector2(W * 0.5, 48), 22, Color(1, 1, 1, 0.5), true)
	_draw_text("CHOOSE YOUR FIGHTERS", Vector2(W * 0.5, 82), 34, Color(1, 1, 1, 0.92), true)

	# team size selector
	for i in TEAM_SIZES.size():
		var size_val = TEAM_SIZES[i]
		var r = _team_size_btn_rect(i)
		var is_sel = team_size == size_val
		var is_hot = r.has_point(get_viewport().get_mouse_position())
		var bg_a = 0.30 if is_sel else (0.16 if is_hot else 0.08)
		draw_rect(r, Color(1, 1, 1, bg_a))
		draw_rect(r, Color(1, 1, 1, 0.9 if is_sel else 0.3), false, 1.5)
		_draw_text("%dv%d" % [size_val, size_val], r.position + r.size * 0.5,
			14, Color(1, 1, 1, 0.95 if is_sel else 0.6), true)

	# section headers
	_draw_text("YOU", Vector2(W * 0.25, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)
	_draw_text("BOT", Vector2(W * 0.75, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)

	# center divider
	var mid = W * 0.5
	draw_line(Vector2(mid, CARD_Y - 10), Vector2(mid, CARD_Y + CARD_H + 10),
		Color(1, 1, 1, 0.08), 1.0)
	_draw_text("VS", Vector2(mid, CARD_Y + CARD_H * 0.5), 26, Color(0.5, 0.5, 0.6, 0.4), true)

	# draw all cards
	tooltip_text = ""
	var mouse_pos = get_viewport().get_mouse_position()
	for i in CLASSES.size():
		_draw_card(player_cards_x[i], i, player_sel == i, hovered == Vector2i(0, i), mouse_pos)
	for i in CLASSES.size():
		_draw_card(bot_cards_x[i], i, bot_sel == i, hovered == Vector2i(1, i), mouse_pos)

	# fight button
	var btn = _fight_btn_rect()
	var btn_hot = btn.has_point(get_viewport().get_mouse_position())
	var btn_col = Color(0.37, 0.88, 0.75, 0.9) if btn_hot else Color(0.25, 0.6, 0.5, 0.8)
	draw_rect(btn, btn_col)
	draw_rect(btn, Color(1, 1, 1, 0.2), false, 1.5)
	_draw_text("FIGHT", Vector2(btn.position.x + btn.size.x * 0.5, btn.position.y + btn.size.y * 0.5 + 2),
		22, Color(0.05, 0.08, 0.1), true)

	# matchup summary below button
	var p_name = CLASSES[player_sel]["label"]
	var b_name = CLASSES[bot_sel]["label"]
	var summary = ("%s  vs  %s (bot)" % [p_name, b_name]) if team_size == 1 \
		else ("%s x%d  vs  %s x%d (bot)" % [p_name, team_size, b_name, team_size])
	_draw_text(summary,
		Vector2(W * 0.5, btn.position.y + btn.size.y + 28), 15, Color(0.55, 0.55, 0.65, 0.7), true)

	if tooltip_text != "":
		_draw_tooltip()

func _draw_tooltip():
	var font    = ThemeDB.fallback_font
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

	draw_rect(Rect2(pos, Vector2(box_w, box_h)), Color(0.05, 0.06, 0.09, 0.97))
	draw_rect(Rect2(pos, Vector2(box_w, box_h)), Color(tooltip_col.r, tooltip_col.g, tooltip_col.b, 0.6), false, 1.5)

	var ty = pos.y + padding
	for line in wrapped:
		if line != "":
			draw_string(font, Vector2(pos.x + padding, ty + size * 0.85), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.9, 0.95, 0.95))
		ty += line_h

func _draw_card(cx: float, class_idx: int, selected: bool, hot: bool, mouse_pos: Vector2):
	var c = CLASSES[class_idx]
	var col: Color = c["color"]

	var bg_alpha = 0.22 if selected else (0.14 if hot else 0.07)
	draw_rect(Rect2(cx, CARD_Y, CARD_W, CARD_H), Color(col.r, col.g, col.b, bg_alpha))

	var border_alpha = 1.0 if selected else (0.55 if hot else 0.25)
	var border_w = 2.5 if selected else 1.5
	draw_rect(Rect2(cx, CARD_Y, CARD_W, CARD_H), Color(col.r, col.g, col.b, border_alpha), false, border_w)

	if selected:
		# top highlight bar
		draw_rect(Rect2(cx, CARD_Y, CARD_W, 3), Color(col.r, col.g, col.b, 0.9))

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
	var font = ThemeDB.fallback_font
	if centered:
		var sw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(pos.x - sw * 0.5, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	else:
		draw_string(font, Vector2(pos.x, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
