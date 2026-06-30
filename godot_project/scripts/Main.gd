extends Node2D

var player: Entity
var bot: Entity
var arena_rect := Rect2(Vector2(60, 60), Vector2(1800, 960))
var map_obstacles: Array[Rect2] = []
var health_packs := []

var hp_me: ProgressBar
var hp_bot: ProgressBar
var win_label: Label
var cd_hud: Node2D   # custom-drawn cooldown panel

const HEALTH_PACK_HEAL = 28.0
const HEALTH_PACK_RADIUS = 34.0
const HEALTH_PACK_RESPAWN = 12.0

func _ready():
	build_map()
	var player_class = get_tree().root.get_meta("player_class", "melee")
	var bot_class    = get_tree().root.get_meta("bot_class",    "melee")

	match player_class:
		"ranged": player = RangedPlayerController.new()
		_:        player = PlayerController.new()
	add_child(player)
	player.global_position = Vector2(510, 540)
	player.arena_rect = arena_rect
	player.obstacle_rects = map_obstacles
	player.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		add_child(p)
	)

	match bot_class:
		"ranged": bot = RangedBotController.new()
		_:        bot = BotController.new()
	add_child(bot)
	bot.global_position = Vector2(1350, 540)
	bot.arena_rect = arena_rect
	bot.obstacle_rects = map_obstacles
	bot.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		add_child(p)
	)

	player.opponent = bot
	bot.opponent = player

	player.died.connect(func(): _on_died(player))
	bot.died.connect(func(): _on_died(bot))

	build_ui()
	queue_redraw()

func build_map():
	map_obstacles = [
		Rect2(Vector2(860, 245), Vector2(200, 70)),
		Rect2(Vector2(860, 765), Vector2(200, 70)),
		Rect2(Vector2(445, 455), Vector2(80, 170)),
		Rect2(Vector2(1395, 455), Vector2(80, 170)),
		Rect2(Vector2(735, 505), Vector2(110, 70)),
		Rect2(Vector2(1075, 505), Vector2(110, 70)),
	]
	health_packs = [
		{"pos": Vector2(960, 405), "active": true, "respawn_left": 0.0},
		{"pos": Vector2(960, 675), "active": true, "respawn_left": 0.0},
	]

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

func _process(delta):
	update_health_packs(delta)
	if is_instance_valid(player):
		hp_me.value = player.hp
	if is_instance_valid(bot):
		hp_bot.value = bot.hp
	queue_redraw()

func update_health_packs(delta: float):
	for pack in health_packs:
		if not pack["active"]:
			pack["respawn_left"] = max(0.0, pack["respawn_left"] - delta)
			if pack["respawn_left"] <= 0.0:
				pack["active"] = true
		else:
			if try_pickup_health_pack(pack, player):
				continue
			try_pickup_health_pack(pack, bot)

func try_pickup_health_pack(pack: Dictionary, entity: Entity) -> bool:
	if entity == null or not is_instance_valid(entity) or not entity.alive or entity.hp >= entity.max_hp:
		return false
	if entity.global_position.distance_to(pack["pos"]) > HEALTH_PACK_RADIUS + Entity.RADIUS:
		return false
	entity.hp = min(entity.max_hp, entity.hp + HEALTH_PACK_HEAL)
	entity.hit_flash_left = 0.18
	pack["active"] = false
	pack["respawn_left"] = HEALTH_PACK_RESPAWN
	return true

func _on_died(who):
	win_label.visible = true
	win_label.text = "BOT WINS" if who == player else "YOU WIN"
	win_label.add_theme_color_override("font_color",
		Color(1, 0.36, 0.48) if who == player else Color(0.37, 0.88, 0.75))

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().change_scene_to_file("res://scenes/CharSelect.tscn")

func _draw():
	draw_map()
	# draw cooldown HUD directly here since we have player reference
	if is_instance_valid(player) and player.alive:
		_draw_cooldown_hud()

func draw_map():
	draw_rect(arena_rect, Color(0.045, 0.052, 0.072), true)
	draw_soft_floor_washes()
	draw_stone_mosaic()
	draw_magic_paths()
	draw_spawn_pad(Vector2(510, 540), Color(0.37, 0.88, 0.75))
	draw_spawn_pad(Vector2(1350, 540), Color(1.0, 0.54, 0.36))

	var center = arena_rect.position + arena_rect.size * 0.5
	draw_center_emblem(center)
	draw_arena_runes(center)

	var cx = arena_rect.position.x + arena_rect.size.x * 0.5
	draw_line(Vector2(cx, arena_rect.position.y), Vector2(cx, arena_rect.position.y + arena_rect.size.y),
		Color(1, 1, 1, 0.055), 1.0)
	draw_corner_props()
	for obstacle in map_obstacles:
		draw_obstacle(obstacle)
	for pack in health_packs:
		draw_health_pack(pack)
	draw_arena_border()

func draw_soft_floor_washes():
	var center = arena_rect.position + arena_rect.size * 0.5
	draw_filled_ellipse(center + Vector2(-430, -180), Vector2(520, 270), Color(0.37, 0.88, 0.75, 0.035), 56)
	draw_filled_ellipse(center + Vector2(430, 180), Vector2(520, 270), Color(1.0, 0.3, 0.48, 0.03), 56)
	draw_filled_ellipse(center, Vector2(760, 430), Color(0.72, 0.4, 1.0, 0.022), 72)

func draw_stone_mosaic():
	var center = arena_rect.position + arena_rect.size * 0.5
	for ring in 3:
		var radius = 235.0 + ring * 150.0
		var pieces = 14 + ring * 4
		for i in pieces:
			var a = i * TAU / pieces + ring * 0.13
			var p = center + Vector2(cos(a), sin(a)) * radius
			var scale = 18.0 + ring * 3.0 + float(i % 3) * 2.0
			var alpha = 0.035 + ring * 0.008
			draw_stone_chip(p, scale, a + PI * 0.25, Color(0.72, 0.77, 0.88, alpha))

	for i in 18:
		var side = -1.0 if i % 2 == 0 else 1.0
		var x = 250.0 + float(i % 9) * 170.0
		var y = 215.0 if i < 9 else 865.0
		var p = Vector2(x, y) + Vector2(28.0 * sin(i * 1.7), side * 18.0)
		draw_stone_chip(p, 16.0 + float(i % 4) * 3.0, i * 0.41, Color(0.7, 0.75, 0.86, 0.04))

func draw_magic_paths():
	var top_pack = Vector2(960, 405)
	var bottom_pack = Vector2(960, 675)
	draw_energy_curve(Vector2(510, 540), top_pack, Vector2(725, 345), Color(0.37, 0.88, 0.75, 0.12), 3.0)
	draw_energy_curve(Vector2(510, 540), bottom_pack, Vector2(725, 735), Color(0.37, 0.88, 0.75, 0.09), 2.0)
	draw_energy_curve(Vector2(1350, 540), top_pack, Vector2(1195, 345), Color(1.0, 0.3, 0.48, 0.09), 2.0)
	draw_energy_curve(Vector2(1350, 540), bottom_pack, Vector2(1195, 735), Color(1.0, 0.3, 0.48, 0.12), 3.0)
	draw_energy_curve(top_pack, bottom_pack, Vector2(1002, 540), Color(0.72, 0.4, 1.0, 0.14), 3.0)

func draw_spawn_pad(pos: Vector2, col: Color):
	draw_filled_ellipse(pos + Vector2(0, 8), Vector2(112, 58), Color(0, 0, 0, 0.16), 48)
	draw_filled_ellipse(pos, Vector2(104, 66), Color(col.r, col.g, col.b, 0.055), 48)
	draw_arc(pos, 78, 0.18, TAU - 0.18, 72, Color(col.r, col.g, col.b, 0.18), 2.5)
	draw_arc(pos, 42, PI + 0.3, TAU * 1.5 - 0.3, 56, Color(col.r, col.g, col.b, 0.13), 1.5)
	for i in 6:
		var a = i * TAU / 6.0 + PI / 6.0
		var dir = Vector2(cos(a), sin(a))
		draw_line(pos + dir * 52, pos + dir * 73, Color(col.r, col.g, col.b, 0.22), 2.0)

func draw_center_emblem(center: Vector2):
	draw_filled_ellipse(center + Vector2(0, 10), Vector2(175, 110), Color(0, 0, 0, 0.18), 72)
	draw_circle(center, 148, Color(0.37, 0.88, 0.75, 0.035))
	draw_arc(center, 148, 0, TAU, 96, Color(0.37, 0.88, 0.75, 0.18), 2.5)
	draw_arc(center, 105, PI * 0.12, TAU * 0.62, 72, Color(0.72, 0.4, 1.0, 0.18), 2.0)
	draw_arc(center, 67, PI * 1.02, TAU * 1.42, 64, Color(1.0, 0.3, 0.48, 0.18), 2.0)
	draw_circle(center, 30, Color(0.72, 0.4, 1.0, 0.08))

func draw_arena_runes(center: Vector2):
	for i in 12:
		var a = i * TAU / 12.0
		var dir = Vector2(cos(a), sin(a))
		var tangent = Vector2(-dir.y, dir.x)
		var p = center + dir * 118
		draw_line(p - tangent * 13, p + tangent * 13, Color(1, 1, 1, 0.11), 2.0)
		draw_line(p, p - dir * 16, Color(1, 1, 1, 0.075), 1.5)

func draw_corner_props():
	var points = [
		arena_rect.position + Vector2(112, 112),
		arena_rect.position + Vector2(arena_rect.size.x - 112, 112),
		arena_rect.position + Vector2(112, arena_rect.size.y - 112),
		arena_rect.position + Vector2(arena_rect.size.x - 112, arena_rect.size.y - 112),
	]
	for p in points:
		draw_filled_ellipse(p + Vector2(4, 6), Vector2(34, 22), Color(0, 0, 0, 0.18), 32)
		draw_obelisk(p, 30.0, Color(0.25, 0.28, 0.36, 0.78), Color(0.37, 0.88, 0.75, 0.26))

func draw_obstacle(rect: Rect2):
	var center = rect.position + rect.size * 0.5
	draw_filled_ellipse(center + Vector2(8, 12), rect.size * 0.72, Color(0, 0, 0, 0.2), 36)
	var shard_col = Color(0.21, 0.23, 0.30, 0.95)
	var edge_col = Color(0.65, 0.72, 0.86, 0.24)
	var glow_col = Color(0.72, 0.4, 1.0, 0.16)
	if rect.size.x > rect.size.y:
		draw_crystal_slab(center, rect.size, 0.0, shard_col, edge_col, glow_col)
		draw_crystal_slab(center + Vector2(-rect.size.x * 0.22, 4), rect.size * 0.44, -0.18, Color(0.28, 0.30, 0.38, 0.88), edge_col, Color(0.37, 0.88, 0.75, 0.12))
		draw_crystal_slab(center + Vector2(rect.size.x * 0.24, -2), rect.size * 0.36, 0.16, Color(0.17, 0.19, 0.26, 0.9), edge_col, Color(1.0, 0.54, 0.36, 0.12))
	else:
		draw_crystal_slab(center, rect.size, PI * 0.5, shard_col, edge_col, glow_col)
		draw_crystal_slab(center + Vector2(0, -rect.size.y * 0.24), rect.size * 0.42, PI * 0.5 - 0.12, Color(0.28, 0.30, 0.38, 0.88), edge_col, Color(0.37, 0.88, 0.75, 0.12))
		draw_crystal_slab(center + Vector2(0, rect.size.y * 0.23), rect.size * 0.36, PI * 0.5 + 0.15, Color(0.17, 0.19, 0.26, 0.9), edge_col, Color(1.0, 0.54, 0.36, 0.12))

func draw_health_pack(pack: Dictionary):
	var pos: Vector2 = pack["pos"]
	draw_health_station(pos)
	if pack["active"]:
		var pulse = 0.65 + 0.18 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(pos, 32, Color(0.2, 0.9, 0.5, 0.12 * pulse))
		draw_circle(pos, 18, Color(0.08, 0.18, 0.14))
		draw_arc(pos, 23, 0, TAU, 40, Color(0.2, 0.95, 0.55, 0.75), 2.5)
		draw_rect(Rect2(pos + Vector2(-4, -12), Vector2(8, 24)), Color(0.25, 1.0, 0.55), true)
		draw_rect(Rect2(pos + Vector2(-12, -4), Vector2(24, 8)), Color(0.25, 1.0, 0.55), true)
	else:
		var pct = 1.0 - (pack["respawn_left"] / HEALTH_PACK_RESPAWN)
		draw_circle(pos, 15, Color(0.12, 0.14, 0.16, 0.75))
		draw_arc(pos, 21, -PI / 2, -PI / 2 + TAU * pct, 36, Color(0.2, 0.95, 0.55, 0.35), 2.0)

func draw_health_station(pos: Vector2):
	draw_filled_ellipse(pos + Vector2(4, 8), Vector2(52, 34), Color(0, 0, 0, 0.2), 40)
	draw_filled_ellipse(pos, Vector2(47, 31), Color(0.08, 0.16, 0.13, 0.82), 40)
	draw_arc(pos, 38, 0, TAU, 48, Color(0.25, 1.0, 0.55, 0.18), 2.0)
	for i in 3:
		var a = -PI * 0.5 + i * TAU / 3.0
		var dir = Vector2(cos(a), sin(a))
		draw_line(pos + dir * 28, pos + dir * 42, Color(0.25, 1.0, 0.55, 0.15), 2.0)

func draw_arena_border():
	var inner = Rect2(arena_rect.position + Vector2(18, 18), arena_rect.size - Vector2(36, 36))
	draw_rect(arena_rect, Color(0.37, 0.88, 0.75, 0.24), false, 2.0)
	draw_rect(inner, Color(1.0, 0.3, 0.48, 0.10), false, 1.5)
	for i in 10:
		var t = float(i) / 9.0
		var top = Vector2(lerp(inner.position.x + 120, inner.position.x + inner.size.x - 120, t), inner.position.y)
		var bottom = Vector2(top.x, inner.position.y + inner.size.y)
		draw_circle(top, 3.0, Color(0.37, 0.88, 0.75, 0.22))
		draw_circle(bottom, 3.0, Color(1.0, 0.3, 0.48, 0.18))

func draw_stone_chip(center: Vector2, radius: float, rot: float, col: Color):
	var points := PackedVector2Array()
	for i in 6:
		var a = rot + i * TAU / 6.0
		var r = radius * (0.72 + 0.18 * float((i * 5) % 4))
		points.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(points, col)

func draw_obelisk(center: Vector2, size: float, col: Color, glow: Color):
	var points = PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size * 0.48, -size * 0.2),
		center + Vector2(size * 0.35, size * 0.65),
		center + Vector2(-size * 0.35, size * 0.65),
		center + Vector2(-size * 0.48, -size * 0.2),
	])
	draw_colored_polygon(points, col)
	draw_line(center + Vector2(0, -size * 0.72), center + Vector2(0, size * 0.48), glow, 2.0)
	draw_arc(center + Vector2(0, -size * 0.1), size * 0.55, 0, TAU, 24, glow, 1.5)

func draw_crystal_slab(center: Vector2, size: Vector2, rot: float, col: Color, edge: Color, glow: Color):
	var half = size * 0.5
	var local = [
		Vector2(-half.x * 0.92, -half.y * 0.28),
		Vector2(-half.x * 0.55, -half.y * 0.82),
		Vector2(half.x * 0.62, -half.y * 0.72),
		Vector2(half.x * 0.96, -half.y * 0.18),
		Vector2(half.x * 0.72, half.y * 0.7),
		Vector2(-half.x * 0.68, half.y * 0.82),
	]
	var points := PackedVector2Array()
	for p in local:
		points.append(center + p.rotated(rot))
	draw_colored_polygon(points, col)
	for i in points.size():
		draw_line(points[i], points[(i + 1) % points.size()], edge, 1.5)
	draw_line(center + Vector2(-half.x * 0.55, 0).rotated(rot), center + Vector2(half.x * 0.55, 0).rotated(rot), glow, 2.0)

func draw_energy_curve(start: Vector2, end: Vector2, control: Vector2, col: Color, width: float):
	var points := PackedVector2Array()
	for i in 25:
		var t = float(i) / 24.0
		var inv = 1.0 - t
		points.append(start * inv * inv + control * 2.0 * inv * t + end * t * t)
	draw_polyline(points, col, width, true)

func draw_filled_ellipse(center: Vector2, radii: Vector2, col: Color, segments: int = 48):
	var points := PackedVector2Array()
	for i in segments:
		var a = float(i) * TAU / float(segments)
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, col)

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
