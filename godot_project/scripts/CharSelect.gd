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
		"lines": ["Melee glass cannon.", "Blood-lust on parry.", "", "Auto       LMB", "Strike     E", "Lunge      Q", "Throw      F", "IronResolve Shift", "Bladestorm R"]
	},
	{
		"label": "MAGE",
		"color": RANGED_COLOR,
		"key":   "ranged",
		"hp":    "HP  120",
		"lines": ["Ranged burst mage.", "Kite and punish.", "", "Auto Shot  LMB", "Bolt       E", "Burst      Q", "ArcaneFan  F", "Barrier    Shift", "VoidColl   R"]
	},
	{
		"label": "BRUISER",
		"color": BRUISER_COLOR,
		"key":   "bruiser",
		"hp":    "HP  180",
		"lines": ["Tanky melee brawler.", "CC chains + survive.", "", "Smash      LMB", "Shatter    E", "Tremor     Q", "Warcry     F", "Unbreakable Shift", "Seismic    R"]
	},
]

func _ready():
	queue_redraw()

func _input(event):
	if event is InputEventMouseMotion:
		var prev = hovered
		hovered = _card_under(event.position)
		if hovered != prev:
			queue_redraw()
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
	for i in 3:
		_draw_card(player_cards_x[i], i, player_sel == i, hovered == Vector2i(0, i))
	for i in 3:
		_draw_card(bot_cards_x[i], i, bot_sel == i, hovered == Vector2i(1, i))

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

func _draw_card(cx: float, class_idx: int, selected: bool, hot: bool):
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

	# ability lines
	var ly = CARD_Y + 178.0
	for line in c["lines"]:
		if line == "":
			ly += 6
			continue
		_draw_text(line, Vector2(cx + 14, ly), 13, Color(0.78, 0.78, 0.85, 0.8), false)
		ly += 19

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
