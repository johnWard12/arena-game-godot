extends Node2D

var player: Entity
var bot: Entity
var arena_rect := Rect2(Vector2(40, 40), Vector2(1200, 640))

var hp_me: ProgressBar
var hp_bot: ProgressBar
var ability_label: Label
var win_label: Label

func _ready():
	# spawn player
	var player_class = get_tree().root.get_meta("player_class", "melee")
	var bot_class    = get_tree().root.get_meta("bot_class",    "melee")

	match player_class:
		"ranged": player = RangedPlayerController.new()
		_:        player = PlayerController.new()
	add_child(player)
	player.global_position = Vector2(340, 360)
	player.arena_rect = arena_rect
	player.projectile_spawned.connect(func(p): add_child(p))

	# spawn bot
	match bot_class:
		"ranged": bot = RangedBotController.new()
		_:        bot = BotController.new()
	add_child(bot)
	bot.global_position = Vector2(900, 360)
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
	hp_bot.position = Vector2(1040, 20)
	hp_bot.size = Vector2(220, 22)
	hp_bot.show_percentage = false
	canvas.add_child(hp_bot)

	ability_label = Label.new()
	ability_label.position = Vector2(20, 670)
	ability_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(ability_label)

	win_label = Label.new()
	win_label.position = Vector2(540, 310)
	win_label.add_theme_font_size_override("font_size", 36)
	win_label.visible = false
	canvas.add_child(win_label)

	var hint = Label.new()
	hint.text = "WASD move | Shift/Space dash | Mouse aim | LMB auto | RMB/G parry | E ability | Q ability | F ult | R reset"
	hint.position = Vector2(20, 698)
	hint.add_theme_font_size_override("font_size", 13)
	canvas.add_child(hint)

	# class name labels above HP bars
	var p_label = Label.new()
	p_label.text = "DUELIST" if not (player is RangedEntity) else "MAGE"
	p_label.position = Vector2(20, 46)
	p_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(p_label)

	var b_label = Label.new()
	b_label.text = "BOT  " + ("DUELIST" if not (bot is RangedEntity) else "MAGE")
	b_label.position = Vector2(1040, 46)
	b_label.add_theme_font_size_override("font_size", 13)
	canvas.add_child(b_label)

func _process(_delta):
	if is_instance_valid(player):
		hp_me.value = player.hp
	if is_instance_valid(bot):
		hp_bot.value = bot.hp
	if is_instance_valid(player):
		if player is RangedEntity:
			ability_label.text = "Shot %.1fs | Bolt %.1fs | Blink %.1fs | Ult %d%%" % [
				player.cd_auto, player.cd_a1, player.cd_a2,
				int(player.ult_charge / Entity.ULT_CHARGE_MAX * 100)
			]
		else:
			ability_label.text = "Auto %.1fs | Slash %.1fs | Lunge %.1fs | Ult %d%% | Combo x%d" % [
				player.cd_auto, player.cd_a1, player.cd_a2,
				int(player.ult_charge / Entity.ULT_CHARGE_MAX * 100), player.combo_stacks
			]

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
