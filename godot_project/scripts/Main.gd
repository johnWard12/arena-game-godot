extends Node2D

const FX = preload("res://scripts/FX.gd")

var player: Entity
var bot: Entity
var arena_rect := Rect2(Vector2(30, 30), Vector2(1860, 1020))
var map_obstacles: Array[Rect2] = []
var health_packs := []

var shake_time_left  := 0.0
var shake_intensity  := 0.0

var hp_me: ProgressBar
var hp_bot: ProgressBar
var win_label: Label
var cd_hud: Node2D   # custom-drawn cooldown panel

const HEALTH_PACK_HEAL = 28.0
const HEALTH_PACK_RADIUS = 44.0
const HEALTH_PACK_RESPAWN = 12.0

func _ready():
	build_map()
	var player_class = get_tree().root.get_meta("player_class", "melee")
	var bot_class    = get_tree().root.get_meta("bot_class",    "melee")

	match player_class:
		"ranged":  player = RangedPlayerController.new()
		"bruiser": player = BruiserPlayerController.new()
		_:         player = PlayerController.new()
	add_child(player)
	player.global_position = Vector2(450, 540)
	player.arena_rect = arena_rect
	player.obstacle_rects = map_obstacles
	player.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		add_child(p)
	)

	match bot_class:
		"ranged":  bot = RangedBotController.new()
		"bruiser": bot = BruiserBotController.new()
		_:         bot = BotController.new()
	add_child(bot)
	bot.global_position = Vector2(1470, 540)
	bot.arena_rect = arena_rect
	bot.obstacle_rects = map_obstacles
	bot.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		add_child(p)
	)

	player.opponent = bot
	bot.opponent = player
	player.screen_shake.connect(start_shake)
	bot.screen_shake.connect(start_shake)

	player.died.connect(func(): _on_died(player))
	bot.died.connect(func(): _on_died(bot))

	build_ui()
	queue_redraw()

func build_map():
	map_obstacles = [
		Rect2(Vector2(857, 227), Vector2(207, 74)),
		Rect2(Vector2(857, 779), Vector2(207, 74)),
		Rect2(Vector2(428, 450), Vector2(83, 181)),
		Rect2(Vector2(1410, 450), Vector2(83, 181)),
		Rect2(Vector2(728, 503), Vector2(114, 74)),
		Rect2(Vector2(1079, 503), Vector2(114, 74)),
	]
	health_packs = [
		{"pos": Vector2(960, 397), "active": true, "respawn_left": 0.0},
		{"pos": Vector2(960, 683), "active": true, "respawn_left": 0.0},
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
	p_label.text = "BRUISER" if player is BruiserEntity else ("MAGE" if player is RangedEntity else "DUELIST")
	p_label.position = Vector2(20, 46)
	p_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(p_label)

	var b_label = Label.new()
	b_label.text = "BOT  " + ("BRUISER" if bot is BruiserEntity else ("MAGE" if bot is RangedEntity else "DUELIST"))
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
	hint.text = "WASD move  |  Shift/Space dash  |  LMB auto (hold)  |  E  Q  F  R abilities  |  RMB/G parry  |  Backspace = char select"
	hint.position = Vector2(20, 1050)
	hint.add_theme_font_size_override("font_size", 12)
	canvas.add_child(hint)

	# cooldown HUD — custom drawn node
	cd_hud = Node2D.new()
	canvas.add_child(cd_hud)

func _get_ability_defs() -> Array:
	if player is BruiserEntity:
		return [
			{"key": "LMB", "name": "Smash",   "cd": player.cd_auto, "max": BruiserEntity.BRUISER_AUTO_CD,  "col": Color(0.95, 0.55, 0.15)},
			{"key": "E",   "name": "Shatter", "cd": player.cd_a1,   "max": BruiserEntity.SHATTER_CD,       "col": Color(1.0, 0.7, 0.2)},
			{"key": "Q",   "name": "Tremor",  "cd": player.cd_a2,   "max": BruiserEntity.TREMOR_CD,        "col": Color(0.9, 0.4, 0.1)},
			{"key": "F",   "name": "Unbrkbl", "cd": player.cd_a3,   "max": BruiserEntity.UNBREAKABLE_CD,  "col": Color(1.0, 1.0, 1.0)},
			{"key": "R",   "name": "Seismic", "cd": 0.0,            "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                           "col": Color(1.0, 0.25, 0.1)},
			{"key": "RMB", "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,          "col": Color(0.3, 0.7, 1.0)},
		]
	elif player is RangedEntity:
		return [
			{"key": "LMB", "name": "Shot",    "cd": player.cd_auto, "max": RangedEntity.RPROJ_CD,          "col": Color(1.0, 0.85, 0.3)},
			{"key": "E",   "name": "Bolt",    "cd": player.cd_a1,   "max": RangedEntity.BOLT_CD,           "col": Color(0.4, 0.85, 1.0)},
			{"key": "Q",   "name": "Burst",   "cd": player.cd_a2,   "max": RangedEntity.NOVA_CD,           "col": Color(0.72, 0.4, 1.0)},
			{"key": "F",   "name": "Barrier", "cd": player.cd_a3,   "max": RangedEntity.BARRIER_CD,        "col": Color(0.3, 0.7, 1.0)},
			{"key": "R",   "name": "VoidColl","cd": 0.0,            "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                           "col": Color(1.0, 0.3, 0.85)},
			{"key": "RMB", "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,          "col": Color(0.3, 0.7, 1.0)},
		]
	else:
		return [
			{"key": "LMB", "name": "Auto",    "cd": player.cd_auto, "max": Entity.AUTO_CD,                 "col": Color(0.37, 0.88, 0.75)},
			{"key": "E",   "name": "Strike",  "cd": player.cd_a1,   "max": Entity.A1_CD,                   "col": Color(0.37, 0.88, 0.75)},
			{"key": "Q",   "name": "Lunge",   "cd": player.cd_a2,   "max": Entity.A2_CD,                   "col": Color(1.0, 0.5, 0.2)},
			{"key": "F",   "name": "Throw",   "cd": player.cd_a3,   "max": Entity.SWORD_THROW_CD,          "col": Color(0.8, 0.85, 0.95)},
			{"key": "R",   "name": "Storm",   "cd": 0.0,            "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                           "col": Color(1.0, 0.3, 0.48)},
			{"key": "RMB", "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,          "col": Color(0.3, 0.7, 1.0)},
		]

func start_shake(intensity: float, duration: float):
	shake_intensity = max(shake_intensity, intensity)
	shake_time_left = max(shake_time_left, duration)

func _process(delta):
	update_health_packs(delta)
	if is_instance_valid(player):
		hp_me.value = player.hp
	if is_instance_valid(bot):
		hp_bot.value = bot.hp
	if shake_time_left > 0:
		shake_time_left -= delta
		if shake_time_left > 0:
			position = Vector2(randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity))
		else:
			position = Vector2.ZERO
			shake_intensity = 0.0
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
	FX.heal_sparkle(self, entity.global_position)
	pack["active"] = false
	pack["respawn_left"] = HEALTH_PACK_RESPAWN
	return true

func _on_died(who):
	win_label.visible = true
	win_label.text = "BOT WINS" if who == player else "YOU WIN"
	win_label.add_theme_color_override("font_color",
		Color(1, 0.36, 0.48) if who == player else Color(0.37, 0.88, 0.75))

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		get_tree().change_scene_to_file("res://scenes/CharSelect.tscn")

func _draw():
	draw_map()
	# draw cooldown HUD directly here since we have player reference
	if is_instance_valid(player) and player.alive:
		_draw_cooldown_hud()

func draw_map():
	draw_rect(arena_rect, Color(0.46, 0.38, 0.26), true)
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
		Color(0.30, 0.24, 0.16, 0.09), 1.0)
	draw_corner_props()
	for obstacle in map_obstacles:
		draw_obstacle(obstacle)
	for pack in health_packs:
		draw_health_pack(pack)
	draw_arena_border()

func draw_soft_floor_washes():
	var center = arena_rect.position + arena_rect.size * 0.5
	# Central worn sand patch
	draw_filled_ellipse(center, Vector2(640, 400), Color(0.52, 0.44, 0.30, 0.28), 72)
	# Spawn zone wear marks
	draw_filled_ellipse(Vector2(510, 540), Vector2(270, 185), Color(0.56, 0.48, 0.34, 0.20), 56)
	draw_filled_ellipse(Vector2(1350, 540), Vector2(270, 185), Color(0.56, 0.48, 0.34, 0.20), 56)
	# Subtle battle stains
	draw_filled_ellipse(center + Vector2(-85, 65), Vector2(95, 58), Color(0.28, 0.14, 0.12, 0.11), 32)
	draw_filled_ellipse(center + Vector2(145, -85), Vector2(72, 44), Color(0.28, 0.14, 0.12, 0.09), 28)
	draw_filled_ellipse(center + Vector2(-210, 160), Vector2(58, 38), Color(0.28, 0.14, 0.12, 0.08), 24)
	# Corner sand drifts
	draw_filled_ellipse(arena_rect.position + Vector2(220, 170), Vector2(190, 120), Color(0.55, 0.48, 0.34, 0.13), 40)
	draw_filled_ellipse(arena_rect.position + Vector2(arena_rect.size.x - 220, 170), Vector2(190, 120), Color(0.55, 0.48, 0.34, 0.13), 40)
	draw_filled_ellipse(arena_rect.position + Vector2(220, arena_rect.size.y - 170), Vector2(190, 120), Color(0.55, 0.48, 0.34, 0.13), 40)
	draw_filled_ellipse(arena_rect.position + Vector2(arena_rect.size.x - 220, arena_rect.size.y - 170), Vector2(190, 120), Color(0.55, 0.48, 0.34, 0.13), 40)

func draw_stone_mosaic():
	# Grout lines for stone tile grid
	var tile_w = 120.0
	var tile_h = 100.0
	var grout = Color(0.34, 0.27, 0.18, 0.55)
	var y = arena_rect.position.y + tile_h
	while y < arena_rect.position.y + arena_rect.size.y - 60:
		draw_line(Vector2(arena_rect.position.x + 62, y),
			Vector2(arena_rect.position.x + arena_rect.size.x - 62, y), grout, 1.5)
		y += tile_h
	var x = arena_rect.position.x + tile_w
	while x < arena_rect.position.x + arena_rect.size.x - 60:
		draw_line(Vector2(x, arena_rect.position.y + 62),
			Vector2(x, arena_rect.position.y + arena_rect.size.y - 62), grout, 1.5)
		x += tile_w

	# Stone chip texture scattered across the floor
	var center = arena_rect.position + arena_rect.size * 0.5
	for ring in 4:
		var radius = 185.0 + ring * 145.0
		var pieces = 10 + ring * 3
		for i in pieces:
			var a = i * TAU / pieces + ring * 0.21
			var p = center + Vector2(cos(a), sin(a)) * radius
			var sc = 11.0 + ring * 2.0 + float(i % 3) * 1.5
			var alpha = 0.055 + ring * 0.010
			draw_stone_chip(p, sc, a + PI * 0.15, Color(0.38, 0.30, 0.20, alpha))

func draw_magic_paths():
	# Worn sand grooves between spawn points and health packs
	var top_pack = Vector2(960, 405)
	var bottom_pack = Vector2(960, 675)
	draw_energy_curve(Vector2(510, 540), top_pack, Vector2(725, 345), Color(0.60, 0.52, 0.36, 0.13), 7.0)
	draw_energy_curve(Vector2(510, 540), bottom_pack, Vector2(725, 735), Color(0.58, 0.50, 0.34, 0.10), 5.5)
	draw_energy_curve(Vector2(1350, 540), top_pack, Vector2(1195, 345), Color(0.58, 0.50, 0.34, 0.10), 5.5)
	draw_energy_curve(Vector2(1350, 540), bottom_pack, Vector2(1195, 735), Color(0.60, 0.52, 0.36, 0.13), 7.0)
	draw_energy_curve(top_pack, bottom_pack, Vector2(1002, 540), Color(0.56, 0.48, 0.33, 0.14), 6.0)

func draw_spawn_pad(pos: Vector2, col: Color):
	# Stone gate circle
	draw_filled_ellipse(pos + Vector2(0, 10), Vector2(120, 66), Color(0, 0, 0, 0.22), 48)
	draw_filled_ellipse(pos, Vector2(112, 74), Color(0.36, 0.28, 0.18, 0.55), 48)
	draw_filled_ellipse(pos, Vector2(88, 58), Color(0.42, 0.34, 0.22, 0.40), 48)
	# Stone ring grooves
	draw_arc(pos, 84, 0, TAU, 72, Color(0.26, 0.20, 0.13, 0.65), 3.5)
	draw_arc(pos, 48, 0, TAU, 52, Color(0.26, 0.20, 0.13, 0.45), 2.0)
	# Class color accent ring
	draw_arc(pos, 78, 0.20, TAU - 0.20, 72, Color(col.r, col.g, col.b, 0.42), 3.5)
	draw_arc(pos, 42, PI + 0.35, TAU * 1.5 - 0.35, 52, Color(col.r, col.g, col.b, 0.25), 2.0)
	# Radial column marks (8 pillars around gate)
	for i in 8:
		var a = i * TAU / 8.0
		var dir = Vector2(cos(a), sin(a))
		var p0 = pos + dir * 86
		var p1 = pos + dir * 100
		draw_line(p0, p1, Color(0.26, 0.20, 0.13, 0.70), 5.0)
		draw_line(p0, p1, Color(col.r, col.g, col.b, 0.30), 2.5)

func draw_center_emblem(center: Vector2):
	# Carved gladiatorial sun emblem in stone
	draw_filled_ellipse(center + Vector2(0, 12), Vector2(188, 122), Color(0, 0, 0, 0.18), 72)
	draw_circle(center, 155, Color(0.36, 0.28, 0.18, 0.35))
	# Outer carved ring
	draw_arc(center, 155, 0, TAU, 96, Color(0.28, 0.21, 0.13, 0.80), 4.0)
	draw_arc(center, 110, 0, TAU, 80, Color(0.28, 0.21, 0.13, 0.60), 2.5)
	draw_arc(center, 68, 0, TAU, 60, Color(0.28, 0.21, 0.13, 0.50), 2.0)
	# Radial sun rays carved into stone
	for i in 16:
		var a = i * TAU / 16.0
		var dir = Vector2(cos(a), sin(a))
		var inner_r = 76.0 if i % 2 == 0 else 94.0
		draw_line(center + dir * inner_r, center + dir * 151,
			Color(0.26, 0.19, 0.12, 0.50), 2.0)
	# Center carved disc
	draw_circle(center, 34, Color(0.34, 0.26, 0.17, 0.65))
	draw_arc(center, 34, 0, TAU, 36, Color(0.24, 0.18, 0.11, 0.85), 3.0)
	# Inner cross marks
	for i in 4:
		var a = i * PI * 0.5
		var dir = Vector2(cos(a), sin(a))
		draw_line(center + dir * 14, center + dir * 30, Color(0.24, 0.18, 0.11, 0.70), 2.0)

func draw_arena_runes(center: Vector2):
	# Roman-style architectural markers around the emblem
	for i in 12:
		var a = i * TAU / 12.0
		var dir = Vector2(cos(a), sin(a))
		var tangent = Vector2(-dir.y, dir.x)
		var p = center + dir * 124
		draw_line(p - tangent * 11, p + tangent * 11, Color(0.25, 0.19, 0.12, 0.62), 3.5)
		draw_line(p - tangent * 11, p + tangent * 11, Color(0.50, 0.40, 0.26, 0.30), 1.5)
		draw_line(p, p - dir * 15, Color(0.25, 0.19, 0.12, 0.45), 2.0)
		# Extra notch at cardinal points (N/S/E/W)
		if i % 3 == 0:
			draw_line(p - tangent * 5, p + tangent * 5, Color(0.22, 0.16, 0.10, 0.70), 5.0)

func draw_corner_props():
	var points = [
		arena_rect.position + Vector2(112, 112),
		arena_rect.position + Vector2(arena_rect.size.x - 112, 112),
		arena_rect.position + Vector2(112, arena_rect.size.y - 112),
		arena_rect.position + Vector2(arena_rect.size.x - 112, arena_rect.size.y - 112),
	]
	for p in points:
		_draw_torch_column(p)

func _draw_torch_column(pos: Vector2):
	# Shadow
	draw_filled_ellipse(pos + Vector2(5, 9), Vector2(32, 20), Color(0, 0, 0, 0.25), 32)
	# Column base
	draw_circle(pos, 24.0, Color(0.38, 0.30, 0.20, 0.95))
	draw_arc(pos, 24, 0, TAU, 32, Color(0.22, 0.16, 0.10, 0.90), 3.0)
	# Column shaft ridges
	draw_line(pos + Vector2(-9, -24), pos + Vector2(-9, 18), Color(0.44, 0.36, 0.24, 0.40), 2.0)
	draw_line(pos + Vector2( 9, -24), pos + Vector2( 9, 18), Color(0.44, 0.36, 0.24, 0.40), 2.0)
	# Bowl
	var bowl = PackedVector2Array([
		pos + Vector2(-15, -22),
		pos + Vector2( 15, -22),
		pos + Vector2( 11, -13),
		pos + Vector2(-11, -13),
	])
	draw_colored_polygon(bowl, Color(0.28, 0.22, 0.14, 0.95))
	draw_polyline(PackedVector2Array([bowl[0], bowl[1], bowl[2], bowl[3], bowl[0]]),
		Color(0.18, 0.13, 0.08, 0.85), 1.5)
	# Animated fire
	var t   = Time.get_ticks_msec() * 0.004
	var ff  = sin(t * 3.8 + pos.x * 0.01) * 3.0
	var fy  = pos.y - 22
	draw_circle(Vector2(pos.x, fy), 15.0, Color(1.0, 0.50, 0.10, 0.10))
	var flame = PackedVector2Array([
		Vector2(pos.x - 7, fy),
		Vector2(pos.x + 7, fy),
		Vector2(pos.x + 3.5 + ff, fy - 17),
		Vector2(pos.x + ff * 0.5, fy - 24),
		Vector2(pos.x - 3.5 + ff, fy - 17),
	])
	draw_colored_polygon(flame, Color(1.0, 0.52, 0.08, 0.82))
	var inner_flame = PackedVector2Array([
		Vector2(pos.x - 4, fy),
		Vector2(pos.x + 4, fy),
		Vector2(pos.x + ff * 0.3, fy - 13),
	])
	draw_colored_polygon(inner_flame, Color(1.0, 0.92, 0.45, 0.92))

func draw_obstacle(rect: Rect2):
	var center = rect.position + rect.size * 0.5
	var half   = rect.size * 0.5
	# Shadow
	draw_filled_ellipse(center + Vector2(10, 14), rect.size * 0.80, Color(0, 0, 0, 0.28), 36)
	# Main stone block face
	var stone = Color(0.44, 0.35, 0.23, 0.97)
	var edge  = Color(0.22, 0.16, 0.10, 0.90)
	var highlight = Color(0.58, 0.48, 0.32, 0.65)
	var verts = PackedVector2Array([
		center + Vector2(-half.x * 0.97, -half.y * 0.94),
		center + Vector2( half.x * 0.96, -half.y * 0.97),
		center + Vector2( half.x * 0.98,  half.y * 0.95),
		center + Vector2(-half.x * 0.95,  half.y * 0.98),
	])
	draw_colored_polygon(verts, stone)
	draw_polyline(PackedVector2Array([verts[0], verts[1], verts[2], verts[3], verts[0]]), edge, 2.5)
	# Top highlight edge (3D illusion)
	draw_line(verts[0], verts[1], highlight, 2.5)
	draw_line(verts[0], verts[3], Color(0.52, 0.42, 0.28, 0.40), 1.5)
	# Stone crack
	draw_line(center + Vector2(-half.x * 0.32, -half.y * 0.45),
		center + Vector2( half.x * 0.22,  half.y * 0.55), Color(0.28, 0.21, 0.13, 0.55), 1.5)
	# Chiseled edge inset lines
	draw_line(center + Vector2(-half.x * 0.82, -half.y * 0.75),
		center + Vector2(-half.x * 0.82,  half.y * 0.75), Color(0.28, 0.21, 0.13, 0.35), 1.5)
	draw_line(center + Vector2( half.x * 0.82, -half.y * 0.75),
		center + Vector2( half.x * 0.82,  half.y * 0.75), highlight * Color(1,1,1,0.5), 1.5)

func draw_health_pack(pack: Dictionary):
	var pos: Vector2 = pack["pos"]
	draw_health_station(pos)
	if pack["active"]:
		var t       = Time.get_ticks_msec() * 0.005
		var pulse   = sin(t * 2.2) * 0.5 + 0.5
		var orb_r   = 16.0 + pulse * 3.0
		# Outer glow ring (bright green, hard to miss)
		draw_circle(pos, orb_r + 18.0, Color(0.15, 1.0, 0.45, 0.10 + pulse * 0.08))
		draw_circle(pos, orb_r + 8.0,  Color(0.15, 1.0, 0.45, 0.20 + pulse * 0.10))
		# Orb body
		draw_circle(pos, orb_r, Color(0.08, 0.72, 0.30, 0.95))
		draw_circle(pos, orb_r * 0.55, Color(0.35, 1.0, 0.60, 0.90))
		draw_circle(pos, orb_r * 0.22, Color(0.85, 1.0, 0.90, 0.95))
		# Bright green cross / plus symbol
		var cs = orb_r * 0.55
		var cw = orb_r * 0.22
		draw_rect(Rect2(pos + Vector2(-cw, -cs), Vector2(cw * 2, cs * 2)), Color(0.9, 1.0, 0.92, 0.95), true)
		draw_rect(Rect2(pos + Vector2(-cs, -cw), Vector2(cs * 2, cw * 2)), Color(0.9, 1.0, 0.92, 0.95), true)
		# Pulsing arc outline
		draw_arc(pos, orb_r + 2, 0, TAU, 48, Color(0.25, 1.0, 0.55, 0.55 + pulse * 0.35), 2.5)
	else:
		var pct = 1.0 - (pack["respawn_left"] / HEALTH_PACK_RESPAWN)
		draw_circle(pos, 14, Color(0.10, 0.16, 0.12, 0.85))
		draw_arc(pos, 22, -PI * 0.5, -PI * 0.5 + TAU * pct, 40, Color(0.25, 1.0, 0.55, 0.55), 3.0)

func draw_health_station(pos: Vector2):
	# Stone pedestal base
	draw_filled_ellipse(pos + Vector2(4, 10), Vector2(44, 26), Color(0, 0, 0, 0.25), 36)
	draw_filled_ellipse(pos + Vector2(0, 6), Vector2(36, 20), Color(0.32, 0.25, 0.16, 0.90), 36)
	draw_arc(pos + Vector2(0, 6), 24, PI * 0.08, PI * 0.92, 32, Color(0.48, 0.38, 0.24, 0.70), 3.0)
	# Pedestal column
	draw_rect(Rect2(pos + Vector2(-7, -12), Vector2(14, 18)), Color(0.36, 0.28, 0.18, 0.92), true)
	draw_rect(Rect2(pos + Vector2(-7, -12), Vector2(14, 18)), Color(0.22, 0.16, 0.10, 0.70), false, 1.5)
	# Cap stone
	draw_rect(Rect2(pos + Vector2(-10, -14), Vector2(20, 5)), Color(0.42, 0.34, 0.22, 0.95), true)
	draw_rect(Rect2(pos + Vector2(-10, -14), Vector2(20, 5)), Color(0.22, 0.16, 0.10, 0.70), false, 1.5)

func draw_arena_border():
	var WALL  = Color(0.40, 0.32, 0.21)
	var DARK  = Color(0.22, 0.16, 0.10)
	var W     = 1920.0
	var H     = 1080.0
	var ax    = arena_rect.position.x   # 60
	var ay    = arena_rect.position.y   # 60
	var aw    = arena_rect.size.x       # 1800
	var ah    = arena_rect.size.y       # 960

	# Fill all four margin strips with stone wall
	draw_rect(Rect2(0,      0,      W,  ay),      WALL, true)
	draw_rect(Rect2(0,      ay+ah,  W,  H-ay-ah), WALL, true)
	draw_rect(Rect2(0,      ay,     ax, ah),       WALL, true)
	draw_rect(Rect2(ax+aw,  ay,     W-ax-aw, ah),  WALL, true)

	# Horizontal stone courses on top/bottom margins
	for i in range(1, 4):
		var cy_t = ay * float(i) / 4.0
		var cy_b = ay + ah + ay * float(i) / 4.0
		draw_line(Vector2(0, cy_t), Vector2(W, cy_t), Color(0.28, 0.21, 0.13, 0.55), 1.5)
		draw_line(Vector2(0, cy_b), Vector2(W, cy_b), Color(0.28, 0.21, 0.13, 0.55), 1.5)
	# Vertical courses on side margins
	for i in range(1, 4):
		var cx_l = ax * float(i) / 4.0
		var cx_r = ax + aw + ax * float(i) / 4.0
		draw_line(Vector2(cx_l, 0), Vector2(cx_l, H), Color(0.28, 0.21, 0.13, 0.45), 1.5)
		draw_line(Vector2(cx_r, 0), Vector2(cx_r, H), Color(0.28, 0.21, 0.13, 0.45), 1.5)

	# Crenellations (battlements) along the inner wall edge
	var bw = 28.0
	var bh = 20.0
	var gap = 20.0
	var xc = ax + 14.0
	while xc + bw < ax + aw - 14:
		draw_rect(Rect2(xc, ay - bh, bw, bh), Color(0.46, 0.36, 0.23, 0.95), true)
		draw_rect(Rect2(xc, ay - bh, bw, bh), DARK, false, 1.5)
		draw_rect(Rect2(xc, ay + ah, bw, bh), Color(0.46, 0.36, 0.23, 0.95), true)
		draw_rect(Rect2(xc, ay + ah, bw, bh), DARK, false, 1.5)
		xc += bw + gap
	var yc = ay + 14.0
	while yc + bw < ay + ah - 14:
		draw_rect(Rect2(ax - bh, yc, bh, bw), Color(0.46, 0.36, 0.23, 0.95), true)
		draw_rect(Rect2(ax - bh, yc, bh, bw), DARK, false, 1.5)
		draw_rect(Rect2(ax + aw, yc, bh, bw), Color(0.46, 0.36, 0.23, 0.95), true)
		draw_rect(Rect2(ax + aw, yc, bh, bw), DARK, false, 1.5)
		yc += bw + gap

	# Inner wall edge: dark shadow then bright highlight
	draw_rect(arena_rect, DARK,                   false, 5.0)
	draw_rect(arena_rect, Color(0.60, 0.50, 0.34, 0.45), false, 2.0)

	# Arch openings on side walls (decorative)
	for i in 4:
		var t = (i + 1) * 0.2
		draw_arc(Vector2(ax + 30, ay + ah * t),    20, PI * 0.5, PI * 1.5, 24, Color(0.18, 0.13, 0.08, 0.55), 3.0)
		draw_arc(Vector2(ax + aw - 30, ay + ah * t), 20, -PI * 0.5, PI * 0.5, 24, Color(0.18, 0.13, 0.08, 0.55), 3.0)
	for i in 7:
		var t = (i + 1) / 8.0
		draw_arc(Vector2(ax + aw * t, ay + 30),      20, PI, TAU, 24, Color(0.18, 0.13, 0.08, 0.55), 3.0)
		draw_arc(Vector2(ax + aw * t, ay + ah - 30), 20, 0,  PI,  24, Color(0.18, 0.13, 0.08, 0.55), 3.0)

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
