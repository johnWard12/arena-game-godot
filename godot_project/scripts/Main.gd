extends Node2D

const FX = preload("res://scripts/FX.gd")
const Arena3D = preload("res://scripts/Arena3D.gd")
const EntityView3D = preload("res://scripts/EntityView3D.gd")
const ProjectileView3D = preload("res://scripts/ProjectileView3D.gd")
const CoordUtil = preload("res://scripts/CoordUtil.gd")

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

var world_3d: Node3D
var camera3d: Camera3D
var camera3d_base_pos := Vector3.ZERO

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
	player.visible = false  # 2D vector art replaced by EntityView3D
	player.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		p.visible = false  # 2D vector art replaced by ProjectileView3D
		add_child(p)
		var pv = ProjectileView3D.new()
		world_3d.add_child(pv)
		pv.setup(p)
	)

	match bot_class:
		"ranged":  bot = RangedBotController.new()
		"bruiser": bot = BruiserBotController.new()
		_:         bot = BotController.new()
	add_child(bot)
	bot.global_position = Vector2(1470, 540)
	bot.arena_rect = arena_rect
	bot.obstacle_rects = map_obstacles
	bot.visible = false  # 2D vector art replaced by EntityView3D
	bot.projectile_spawned.connect(func(p):
		p.obstacle_rects = map_obstacles
		p.visible = false  # 2D vector art replaced by ProjectileView3D
		add_child(p)
		var pv = ProjectileView3D.new()
		world_3d.add_child(pv)
		pv.setup(p)
	)

	player.opponent = bot
	bot.opponent = player
	player.screen_shake.connect(start_shake)
	bot.screen_shake.connect(start_shake)

	player.died.connect(func(): _on_died(player))
	bot.died.connect(func(): _on_died(bot))

	build_3d_world()
	build_ui()
	queue_redraw()

func build_3d_world():
	world_3d = Node3D.new()
	add_child(world_3d)

	var arena3d = Arena3D.new()
	world_3d.add_child(arena3d)
	arena3d.setup(arena_rect, map_obstacles, health_packs)

	var player_view = EntityView3D.new()
	world_3d.add_child(player_view)
	player_view.setup(player)

	var bot_view = EntityView3D.new()
	world_3d.add_child(bot_view)
	bot_view.setup(bot)

	camera3d = Camera3D.new()
	camera3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera3d.keep_aspect = Camera3D.KEEP_HEIGHT
	var center = arena_rect.position + arena_rect.size * 0.5
	var target = CoordUtil.to_world(center)
	var arena_span = max(arena_rect.size.x, arena_rect.size.y) / CoordUtil.SIM_SCALE
	# 45 degree down-angle (MOBA-style, not top-down) — height:back ratio
	# controls the pitch; equal parts is exactly 45 degrees.
	var height = arena_span * 0.7
	var back = arena_span * 0.7
	camera3d.position = target + Vector3(0, height, back)
	camera3d.add_to_group("game_camera")
	world_3d.add_child(camera3d)
	camera3d.look_at(target, Vector3.UP)
	_fit_camera_to_arena()
	# window/stretch/mode="canvas_items" only rescales 2D UI — it does not
	# lock the actual Viewport (and thus this 3D camera) to a fixed
	# 1920x1080 size. In fullscreen the real viewport takes on the OS
	# window's actual resolution/aspect, which may not be 16:9 and may not
	# be settled yet when _ready() runs, so re-fit whenever it changes.
	get_viewport().size_changed.connect(_fit_camera_to_arena)

# Frames the ENTIRE arena so no part of the play area can ever be off-screen
# (a player must never be able to walk into an unseen zone). Fits both width
# and height for the current viewport aspect, then pans the camera along its
# own right/up axes so the arena's true projected midpoint sits at screen
# center — the old version centered on the ground-level arena center, but the
# angled projection makes the real vertical bounds asymmetric around that,
# which cut off the near (bottom) edge where the player walks.
func _fit_camera_to_arena():
	# Re-derive the un-panned "look at arena center" pose first so repeated
	# calls (viewport resize) don't accumulate pan offsets.
	var center = arena_rect.position + arena_rect.size * 0.5
	var target = CoordUtil.to_world(center)
	var arena_span = max(arena_rect.size.x, arena_rect.size.y) / CoordUtil.SIM_SCALE
	camera3d.position = target + Vector3(0, arena_span * 0.7, arena_span * 0.7)
	camera3d.look_at(target, Vector3.UP)

	var basis = camera3d.global_transform.basis
	var right = basis.x
	var up = basis.y
	var margin = 40.0  # sim units of padding around the play area
	var rect = arena_rect.grow(margin)
	# Include a modest content height (character-scale, ~2.2m) rather than the
	# full wall height so tall back walls don't eat vertical framing budget.
	const CONTENT_HEIGHT := 2.2
	var corners_2d = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + Vector2(0, rect.size.y),
		rect.position + rect.size,
	]
	var min_r = INF
	var max_r = -INF
	var min_u = INF
	var max_u = -INF
	for c2d in corners_2d:
		for h in [0.0, CONTENT_HEIGHT]:
			var c = CoordUtil.to_world(c2d, h)
			min_r = min(min_r, c.dot(right))
			max_r = max(max_r, c.dot(right))
			min_u = min(min_u, c.dot(up))
			max_u = max(max_u, c.dot(up))

	var needed_width = max_r - min_r
	var needed_height = max_u - min_u
	var viewport_size = get_viewport().get_visible_rect().size
	var aspect = viewport_size.x / max(1.0, viewport_size.y)
	# KEEP_HEIGHT: visible height == size, visible width == size * aspect.
	# Cover whichever dimension binds so nothing clips on any aspect ratio.
	camera3d.size = max(needed_height, needed_width / aspect) * 1.04

	# Pan the camera so the projected bbox midpoint lands at screen center,
	# correcting the asymmetry the look-at pose leaves along the up axis.
	var mid_r = (min_r + max_r) * 0.5
	var mid_u = (min_u + max_u) * 0.5
	var off_r = mid_r - target.dot(right)
	var off_u = mid_u - target.dot(up)
	camera3d.position += right * off_r + up * off_u
	camera3d_base_pos = camera3d.position

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
	hint.text = "WASD move  |  Space dash  |  LMB auto (hold)  |  E  Q  F  Shift  R abilities  |  RMB/G parry  |  Backspace = char select"
	hint.position = Vector2(20, 1050)
	hint.add_theme_font_size_override("font_size", 12)
	canvas.add_child(hint)

	# cooldown HUD — custom drawn node
	cd_hud = Node2D.new()
	canvas.add_child(cd_hud)

func _get_ability_defs() -> Array:
	if player is BruiserEntity:
		return [
			{"key": "LMB",   "name": "Smash",   "cd": player.cd_auto,  "max": BruiserEntity.BRUISER_AUTO_CD, "col": Color(0.95, 0.55, 0.15)},
			{"key": "E",     "name": "Shatter", "cd": player.cd_a1,    "max": BruiserEntity.SHATTER_CD,      "col": Color(1.0, 0.7, 0.2)},
			{"key": "Q",     "name": "Tremor",  "cd": player.cd_a2,    "max": BruiserEntity.TREMOR_CD,       "col": Color(0.9, 0.4, 0.1)},
			{"key": "F",     "name": "Warcry",  "cd": player.cd_a3,    "max": BruiserEntity.WARCRY_CD,       "col": Color(0.9, 0.25, 0.1)},
			{"key": "Shift", "name": "Unbrkbl", "cd": player.cd_shift, "max": BruiserEntity.UNBREAKABLE_CD,  "col": Color(1.0, 1.0, 1.0)},
			{"key": "R",     "name": "Seismic", "cd": 0.0,             "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                            "col": Color(1.0, 0.25, 0.1)},
			{"key": "RMB",   "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,         "col": Color(0.3, 0.7, 1.0)},
		]
	elif player is RangedEntity:
		return [
			{"key": "LMB",   "name": "Shot",    "cd": player.cd_auto,  "max": RangedEntity.RPROJ_CD,        "col": Color(1.0, 0.85, 0.3)},
			{"key": "E",     "name": "Bolt",    "cd": player.cd_a1,    "max": RangedEntity.BOLT_CD,         "col": Color(0.4, 0.85, 1.0)},
			{"key": "Q",     "name": "Burst",   "cd": player.cd_a2,    "max": RangedEntity.NOVA_CD,         "col": Color(0.72, 0.4, 1.0)},
			{"key": "F",     "name": "ArcFan",  "cd": player.cd_a3,    "max": RangedEntity.ARCANE_FAN_CD,   "col": Color(0.6, 0.3, 1.0)},
			{"key": "Shift", "name": "Barrier", "cd": player.cd_shift, "max": RangedEntity.BARRIER_CD,      "col": Color(0.3, 0.7, 1.0)},
			{"key": "R",     "name": "VoidColl","cd": 0.0,             "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                            "col": Color(1.0, 0.3, 0.85)},
			{"key": "RMB",   "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,         "col": Color(0.3, 0.7, 1.0)},
		]
	else:
		return [
			{"key": "LMB",   "name": "Auto",    "cd": player.cd_auto,  "max": Entity.AUTO_CD,               "col": Color(0.37, 0.88, 0.75)},
			{"key": "E",     "name": "Strike",  "cd": player.cd_a1,    "max": Entity.A1_CD,                 "col": Color(0.37, 0.88, 0.75)},
			{"key": "Q",     "name": "Lunge",   "cd": player.cd_a2,    "max": Entity.A2_CD,                 "col": Color(1.0, 0.5, 0.2)},
			{"key": "F",     "name": "Throw",   "cd": player.cd_a3,    "max": Entity.SWORD_THROW_CD,        "col": Color(0.8, 0.85, 0.95)},
			{"key": "Shift", "name": "IronRes", "cd": player.cd_shift, "max": Entity.IRON_RESOLVE_CD,       "col": Color(0.55, 0.75, 1.0)},
			{"key": "R",     "name": "Storm",   "cd": 0.0,             "max": 1.0, "charge": true,
				"pct": player.ult_charge / Entity.ULT_CHARGE_MAX,                                            "col": Color(1.0, 0.3, 0.48)},
			{"key": "RMB",   "name": "Parry",   "cd": player.parry_cd_left, "max": Entity.PARRY_CD,         "col": Color(0.3, 0.7, 1.0)},
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
		if camera3d != null:
			if shake_time_left > 0:
				var off = Vector3(randf_range(-shake_intensity, shake_intensity),
					randf_range(-shake_intensity, shake_intensity), 0) * 0.02
				camera3d.position = camera3d_base_pos + off
			else:
				camera3d.position = camera3d_base_pos
				shake_intensity = 0.0
		elif shake_time_left <= 0:
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
	# Arena is rendered by Arena3D (see build_3d_world()); this remaining
	# 2D draw pass only handles the cooldown HUD overlay.
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
