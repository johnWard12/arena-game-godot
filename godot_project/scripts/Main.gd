extends Node2D

var player: Entity
var bot: Entity
var arena_rect := Rect2(Vector2(60, 60), Vector2(1800, 960))

var hp_me: ProgressBar
var hp_bot: ProgressBar
var win_label: Label
var cd_hud: Node2D   # custom-drawn cooldown panel

func _ready():
	var player_class = get_tree().root.get_meta("player_class", "melee")
	var bot_class    = get_tree().root.get_meta("bot_class",    "melee")

	match player_class:
		"ranged": player = RangedPlayerController.new()
		_:        player = PlayerController.new()
	add_child(player)
	player.global_position = Vector2(510, 540)
	player.arena_rect = arena_rect
	player.projectile_spawned.connect(func(p): add_child(p))

	match bot_class:
		"ranged": bot = RangedBotController.new()
		_:        bot = BotController.new()
	add_child(bot)
	bot.global_position = Vector2(1350, 540)
	bot.arena_rect = arena_rect
	bot.projectile_spawned.connect(func(p): add_child(p))

	player.opponent = bot
	bot.opponent = player

	player.died.connect(func(): _on_died(player))
	bot.died.connect(func(): _on_died(bot))

	build_ui()
	queue_redraw()

func build_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# HP bars (top corners)
	hp_me = ProgressBar.new()
	hp_me.min_value = 0
	hp_me.max_value = player.max_hp
	hp_me.value = player.hp
	hp_me.position = Vector2(20, 20)
	hp_me.size = Vector2(220, 22)
	hp_me.show_percentage = false
	canvas.add_child(hp_me)

	hp_bot = ProgressBar.new()
	hp_bot.min_value = 0
	hp_bot.max_value = bot.max_hp
	hp_bot.value = bot.hp
	hp_bot.position = Vector2(1680, 20)
	hp_bot.size = Vector2(220, 22)
	hp_bot.show_percentage = false
	canvas.add_child(hp_bot)

	# class name labels
	var p_label = Label.new()
	p_label.text = "DUELIST" if not (player is RangedEntity) else "MAGE"
	p_label.position = Vector2(20, 46)
	p_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(p_label)

	var b_label = Label.new()
	b_label.text = "BOT  " + ("DUELIST" if not (bot is RangedEntity) else "MAGE")
	b_label.position = Vector2(1680, 46)
	b_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(b_label)

	# win label
	win_label = Label.new()
	win_label.position = Vector2(860, 465)
	win_label.add_theme_font_size_override("font_size", 36)
	win_label.visible = false
	canvas.add_child(win_label)

	# hint
	var hint = Label.new()
	hint.text = "WASD move  |  Shift/Space dash  |  LMB auto (hold)  |  E  Q  F abilities  |  RMB/G parry  |  R = char select"
	hint.position = Vector2(20, 1050)
	hint.add_theme_font_size_override("font_size", 12)
	canvas.add_child(hint)

	# cooldown HUD — custom drawn node
	cd_hud = Node2D.new()
	canvas.add_child(cd_hud)

func _get_ability_defs() -> Array:
	if player is RangedEntity:
		return [
			{"key": "LMB", "name": "Shot",    "cd": player.cd_auto, "max": RangedEntity.RPROJ_CD,   "col": Color(1.0, 0.85, 0.3)},
			{"key": "E",   "name": "Bolt",    "cd": player.cd_a1,   "max": RangedEntity.BOLT_CD,    "col": Color(0.4, 0.85, 1.0)},
			{"key": "Q",   "name": "Burst",   "cd": player.cd_a2,   "max": RangedEntity.NOVA_CD,    "col": Color(0.72, 0.4, 1.0)},
			{"key": "F",   "name": "Ult",     "cd": 0.0,            "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                    "col": Color(1.0, 0.3, 0.85)},
			{"key": "RMB", "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,   "col": Color(0.3, 0.7, 1.0)},
		]
	else:
		return [
			{"key": "LMB", "name": "Auto",    "cd": player.cd_auto, "max": Entity.AUTO_CD,          "col": Color(0.37, 0.88, 0.75)},
			{"key": "E",   "name": "Strike",  "cd": player.cd_a1,   "max": Entity.A1_CD,            "col": Color(0.37, 0.88, 0.75)},
			{"key": "Q",   "name": "Lunge",   "cd": player.cd_a2,   "max": Entity.A2_CD,            "col": Color(1.0, 0.5, 0.2)},
			{"key": "F",   "name": "Execute", "cd": 0.0,            "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                    "col": Color(1.0, 0.3, 0.48)},
			{"key": "RMB", "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,   "col": Color(0.3, 0.7, 1.0)},
		]

func _process(_delta):
	if is_instance_valid(player):
		hp_me.value = player.hp
	if is_instance_valid(bot):
		hp_bot.value = bot.hp
	queue_redraw()

func _on_died(who):
	win_label.visible = true
	win_label.text = "BOT WINS" if who == player else "YOU WIN"
	win_label.add_theme_color_override("font_color",
		Color(1, 0.36, 0.48) if who == player else Color(0.37, 0.88, 0.75))

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().change_scene_to_file("res://scenes/CharSelect.tscn")

func _draw():
	draw_rect(arena_rect, Color(0.09, 0.10, 0.14), true)
	var cx = arena_rect.position.x + arena_rect.size.x * 0.5
	draw_line(Vector2(cx, arena_rect.position.y), Vector2(cx, arena_rect.position.y + arena_rect.size.y),
		Color(1, 1, 1, 0.04), 1.0)
	draw_rect(arena_rect, Color(0.37, 0.88, 0.75, 0.35), false, 2.0)
	# draw cooldown HUD directly here since we have player reference
	if is_instance_valid(player) and player.alive:
		_draw_cooldown_hud()

func _draw_cooldown_hud():
	var font    = ThemeDB.fallback_font
	var defs    = _get_ability_defs()
	var n       = defs.size()
	var slot_w  = 110.0
	var slot_h  = 62.0
	var bar_h   = 8.0
	var pad     = 10.0
	var total_w = n * slot_w + (n - 1) * pad
	var start_x = (1920.0 - total_w) * 0.5
	var base_y  = 975.0

	for i in n:
		var d   = defs[i]
		var sx  = start_x + i * (slot_w + pad)
		var col: Color = d["col"]

		var is_charge = d.get("charge", false)
		var ready     = (d["cd"] <= 0.0 and not is_charge) or (is_charge and d["pct"] >= 1.0)
		var pct       = 1.0 - (d["cd"] / d["max"]) if not is_charge else d["pct"]
		pct           = clamp(pct, 0.0, 1.0)

		# slot background
		var bg_alpha = 0.18 if ready else 0.10
		draw_rect(Rect2(sx, base_y, slot_w, slot_h), Color(col.r, col.g, col.b, bg_alpha))
		draw_rect(Rect2(sx, base_y, slot_w, slot_h), Color(col.r, col.g, col.b, 0.35 if ready else 0.18), false, 1.5)

		# key label
		var key_str = d["key"]
		var ksz     = font.get_string_size(key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, Vector2(sx + (slot_w - ksz) * 0.5, base_y + 18),
			key_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(col.r, col.g, col.b, 0.9))

		# ability name
		var name_str = d["name"]
		var nsz      = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(sx + (slot_w - nsz) * 0.5, base_y + 35),
			name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.75, 0.82, 0.85))

		# cooldown bar
		var bar_x = sx + 8
		var bar_w = slot_w - 16
		var bar_y = base_y + slot_h - bar_h - 6
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.1, 0.1, 0.14))
		var fill_col = col if ready else Color(col.r * 0.6, col.g * 0.6, col.b * 0.6)
		draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), fill_col)

		# cooldown time text (only when on cooldown)
		if not ready:
			var cd_val  = d["cd"] if not is_charge else 0.0
			var cd_str  = "%.1fs" % cd_val if not is_charge else "%d%%" % int(d["pct"] * 100)
			var cd_sz   = font.get_string_size(cd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(sx + (slot_w - cd_sz) * 0.5, base_y + 48),
				cd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.95, 0.7))
