extends Node2D

const W = 1920
const H = 1080

const CARD_W = 210.0
const CARD_H = 360.0
const CARD_Y = 180.0
const GAP    = 18.0

# left section (player): three cards centered in left half (0..960)
# right section (bot): three cards centered in right half (960..1920)
const _TOTAL_W = CARD_W * 3 + GAP * 2   # 210*3 + 18*2 = 666

var player_cards_x := [
	W * 0.25 - _TOTAL_W * 0.5,
	W * 0.25 - _TOTAL_W * 0.5 + CARD_W + GAP,
	W * 0.25 - _TOTAL_W * 0.5 + (CARD_W + GAP) * 2,
]
var bot_cards_x := [
	W * 0.75 - _TOTAL_W * 0.5,
	W * 0.75 - _TOTAL_W * 0.5 + CARD_W + GAP,
	W * 0.75 - _TOTAL_W * 0.5 + (CARD_W + GAP) * 2,
]

# 0=Duelist 1=Mage 2=Bruiser; default: player=Duelist, bot=Mage
var player_sel := 0
var bot_sel    := 1
var hovered    := Vector2i(-1, -1)  # x=side (0=player,1=bot), y=card idx

const MELEE_COLOR  = Color(0.37, 0.88, 0.75)
const RANGED_COLOR = Color(0.72, 0.4,  1.0)

const BRUISER_COLOR = Color(0.95, 0.55, 0.15)

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
]

func _ready():
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
		# fight button
		if _fight_btn_rect().has_point(event.position):
			_start()

func _card_under(pos: Vector2) -> Vector2i:
	for i in 3:
		var r = Rect2(player_cards_x[i], CARD_Y, CARD_W, CARD_H)
		if r.has_point(pos):
			return Vector2i(0, i)
	for i in 3:
		var r = Rect2(bot_cards_x[i], CARD_Y, CARD_W, CARD_H)
		if r.has_point(pos):
			return Vector2i(1, i)
	return Vector2i(-1, -1)

func _fight_btn_rect() -> Rect2:
	return Rect2(W * 0.5 - 100, CARD_Y + CARD_H + 40, 200, 52)

func _start():
	get_tree().root.set_meta("player_class", CLASSES[player_sel]["key"])
	get_tree().root.set_meta("bot_class",    CLASSES[bot_sel]["key"])
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _draw():
	draw_rect(Rect2(0, 0, W, H), Color(0.07, 0.08, 0.11))

	_draw_text("ARENA PROTOTYPE", Vector2(W * 0.5, 48), 22, Color(1, 1, 1, 0.5), true)
	_draw_text("CHOOSE YOUR FIGHTERS", Vector2(W * 0.5, 82), 34, Color(1, 1, 1, 0.92), true)

	# section headers
	_draw_text("YOU", Vector2(W * 0.25, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)
	_draw_text("BOT", Vector2(W * 0.75, 148), 18, Color(0.8, 0.8, 0.9, 0.7), true)

	# center divider
	var mid = W * 0.5
	draw_line(Vector2(mid, CARD_Y - 10), Vector2(mid, CARD_Y + CARD_H + 10),
		Color(1, 1, 1, 0.08), 1.0)
	_draw_text("VS", Vector2(mid, CARD_Y + CARD_H * 0.5), 26, Color(0.5, 0.5, 0.6, 0.4), true)

	# draw all six cards
	tooltip_text = ""
	var mouse_pos = get_viewport().get_mouse_position()
	for i in 3:
		_draw_card(player_cards_x[i], i, player_sel == i, hovered == Vector2i(0, i), mouse_pos)
	for i in 3:
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
	_draw_text("%s  vs  %s (bot)" % [p_name, b_name],
		Vector2(W * 0.5, btn.position.y + btn.size.y + 28), 15, Color(0.55, 0.55, 0.65, 0.7), true)

	if tooltip_text != "":
		_draw_tooltip()

func _draw_tooltip():
	var font    = ThemeDB.fallback_font
	var size    = 13
	var padding = 10.0
	var max_w   = 320.0

	# wrap the description into lines that fit max_w
	var words = tooltip_text.split(" ")
	var wrapped: Array[String] = []
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

	draw_rect(Rect2(pos, Vector2(box_w, box_h)), Color(0.05, 0.06, 0.09, 0.96))
	draw_rect(Rect2(pos, Vector2(box_w, box_h)), Color(tooltip_col.r, tooltip_col.g, tooltip_col.b, 0.6), false, 1.5)

	var ty = pos.y + padding
	for line in wrapped:
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

	# character preview
	var pcx = cx + CARD_W * 0.5
	var pcy = CARD_Y + 72
	var r = 30.0
	draw_circle(Vector2(pcx + 2, pcy + 3), r, Color(0, 0, 0, 0.2))
	draw_circle(Vector2(pcx, pcy), r, col)
	draw_circle(Vector2(pcx, pcy), r * 0.52, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.7))
	draw_arc(Vector2(pcx, pcy), r + 5, -PI/2, -PI/2 + TAU, 48, Color(col.r, col.g, col.b, 0.6), 2.0)

	# name + hp
	_draw_text(c["label"], Vector2(pcx, CARD_Y + 126), 22, col, true)
	_draw_text(c["hp"],    Vector2(pcx, CARD_Y + 152), 14, Color(col.r, col.g, col.b, 0.65), true)

	# ability lines — first 3 entries are flavor text/blank, the rest are
	# abilities in order (aligned with ability_descs)
	var ly = CARD_Y + 178.0
	var ability_i = 0
	var descs: Array = c.get("ability_descs", [])
	for j in c["lines"].size():
		var line: String = c["lines"][j]
		if line == "":
			ly += 6
			continue
		var is_ability = j >= 3
		var line_rect = Rect2(cx + 10, ly - 3, CARD_W - 20, 17)
		var line_hot = is_ability and line_rect.has_point(mouse_pos)
		if line_hot:
			draw_rect(line_rect, Color(col.r, col.g, col.b, 0.14))
			if ability_i < descs.size():
				tooltip_text = descs[ability_i]
				tooltip_pos  = Vector2(cx + CARD_W + 6, ly - 6)
				tooltip_col  = col
		var txt_col = Color(1, 1, 1, 0.95) if line_hot else Color(0.78, 0.78, 0.85, 0.8)
		_draw_text(line, Vector2(cx + 14, ly), 13, txt_col, false)
		ly += 19
		if is_ability:
			ability_i += 1

	# selected badge
	if selected:
		_draw_text("SELECTED", Vector2(pcx, CARD_Y + CARD_H - 18), 13, Color(col.r, col.g, col.b, 0.9), true)

func _draw_text(text: String, pos: Vector2, size: int, col: Color, centered: bool):
	var font = ThemeDB.fallback_font
	if centered:
		var sw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(pos.x - sw * 0.5, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	else:
		draw_string(font, Vector2(pos.x, pos.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
