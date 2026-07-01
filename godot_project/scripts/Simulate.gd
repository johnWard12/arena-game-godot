extends Node2D
# Headless bot-vs-bot balance simulation.
# Run with:
#   Godot.app/Contents/MacOS/Godot --headless --path godot_project res://scenes/Simulate.tscn -- --matches=300

const FIXED_DT := 1.0 / 60.0
const MAX_MATCH_SECONDS := 90.0
const MAX_MATCH_TICKS := int(MAX_MATCH_SECONDS / FIXED_DT)

const CLASS_KEYS = ["melee", "ranged", "bruiser"]
const CLASS_LABELS = {"melee": "Duelist", "ranged": "Mage", "bruiser": "Bruiser"}

const HEALTH_PACK_HEAL = 28.0
const HEALTH_PACK_RADIUS = 34.0
const HEALTH_PACK_RESPAWN = 12.0

var arena_rect := Rect2(Vector2(60, 60), Vector2(1800, 960))
var map_obstacles: Array[Rect2] = []

func _ready():
	build_map()
	var matches_per_pairing := 300
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matches="):
			matches_per_pairing = int(arg.split("=")[1])

	print("Running %d matches per pairing (%d pairings, %d total)..." % [
		matches_per_pairing, CLASS_KEYS.size() * CLASS_KEYS.size(),
		matches_per_pairing * CLASS_KEYS.size() * CLASS_KEYS.size()])
	print("")

	var all_stats := []
	for a_key in CLASS_KEYS:
		for b_key in CLASS_KEYS:
			var stats = run_matchup(a_key, b_key, matches_per_pairing)
			all_stats.append(stats)
			print_stats(a_key, b_key, stats)

	print("")
	print_summary(all_stats)
	get_tree().quit()

func build_map():
	map_obstacles = [
		Rect2(Vector2(860, 245), Vector2(200, 70)),
		Rect2(Vector2(860, 765), Vector2(200, 70)),
		Rect2(Vector2(445, 455), Vector2(80, 170)),
		Rect2(Vector2(1395, 455), Vector2(80, 170)),
		Rect2(Vector2(735, 505), Vector2(110, 70)),
		Rect2(Vector2(1075, 505), Vector2(110, 70)),
	]

func make_bot(key: String) -> Entity:
	var bot: Entity
	match key:
		"ranged":  bot = RangedBotController.new()
		"bruiser": bot = BruiserBotController.new()
		_:         bot = BotController.new()
	bot._ready()
	return bot

func make_health_packs() -> Array:
	return [
		{"pos": Vector2(960, 405), "active": true, "respawn_left": 0.0},
		{"pos": Vector2(960, 675), "active": true, "respawn_left": 0.0},
	]

func update_health_packs(packs: Array, a: Entity, b: Entity, delta: float):
	for pack in packs:
		if not pack["active"]:
			pack["respawn_left"] = max(0.0, pack["respawn_left"] - delta)
			if pack["respawn_left"] <= 0.0:
				pack["active"] = true
		else:
			if try_pickup(pack, a):
				continue
			try_pickup(pack, b)

func try_pickup(pack: Dictionary, entity: Entity) -> bool:
	if entity == null or not entity.alive or entity.hp >= entity.max_hp:
		return false
	if entity.global_position.distance_to(pack["pos"]) > HEALTH_PACK_RADIUS + Entity.RADIUS:
		return false
	entity.hp = min(entity.max_hp, entity.hp + HEALTH_PACK_HEAL)
	pack["active"] = false
	pack["respawn_left"] = HEALTH_PACK_RESPAWN
	return true

func run_matchup(a_key: String, b_key: String, n: int) -> Dictionary:
	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var total_ticks := 0
	var a_hp_pct_sum := 0.0
	var b_hp_pct_sum := 0.0

	for i in n:
		var a := make_bot(a_key)
		var b := make_bot(b_key)
		a.global_position = Vector2(510, 540)
		b.global_position = Vector2(1350, 540)
		a.arena_rect = arena_rect
		b.arena_rect = arena_rect
		a.obstacle_rects = map_obstacles
		b.obstacle_rects = map_obstacles
		a.opponent = b
		b.opponent = a

		var projectiles := []
		a.projectile_spawned.connect(func(p): p.obstacle_rects = map_obstacles; projectiles.append(p))
		b.projectile_spawned.connect(func(p): p.obstacle_rects = map_obstacles; projectiles.append(p))

		var packs := make_health_packs()
		var ticks := 0
		while ticks < MAX_MATCH_TICKS and a.alive and b.alive:
			a._physics_process(FIXED_DT)
			b._physics_process(FIXED_DT)
			for p in projectiles:
				p._physics_process(FIXED_DT)
			projectiles = projectiles.filter(func(p): return not p.is_queued_for_deletion())
			update_health_packs(packs, a, b, FIXED_DT)
			ticks += 1

		total_ticks += ticks
		if a.alive and not b.alive:
			a_wins += 1
		elif b.alive and not a.alive:
			b_wins += 1
		else:
			draws += 1
		a_hp_pct_sum += (a.hp / a.max_hp) if a.alive else 0.0
		b_hp_pct_sum += (b.hp / b.max_hp) if b.alive else 0.0

	return {
		"a_key": a_key, "b_key": b_key, "n": n,
		"a_wins": a_wins, "b_wins": b_wins, "draws": draws,
		"avg_duration": (float(total_ticks) / n) * FIXED_DT,
		"a_avg_hp_pct": a_hp_pct_sum / n,
		"b_avg_hp_pct": b_hp_pct_sum / n,
	}

func print_stats(a_key: String, b_key: String, s: Dictionary):
	var a_label = CLASS_LABELS[a_key]
	var b_label = CLASS_LABELS[b_key]
	var a_wr = float(s["a_wins"]) / s["n"] * 100.0
	var b_wr = float(s["b_wins"]) / s["n"] * 100.0
	print("%-8s vs %-8s | %s: %5.1f%%  %s: %5.1f%%  draws: %d  avg dur: %4.1fs  winner avg hp left: %s %.0f%% / %s %.0f%%" % [
		a_label, b_label, a_label, a_wr, b_label, b_wr, s["draws"], s["avg_duration"],
		a_label, s["a_avg_hp_pct"] * 100.0, b_label, s["b_avg_hp_pct"] * 100.0])

func print_summary(all_stats: Array):
	print("=== Cross-matchup win rates (excluding mirrors) ===")
	var totals := {}
	for key in CLASS_KEYS:
		totals[key] = {"wins": 0, "games": 0}
	for s in all_stats:
		if s["a_key"] == s["b_key"]:
			continue
		totals[s["a_key"]]["wins"] += s["a_wins"]
		totals[s["a_key"]]["games"] += s["n"]
		totals[s["b_key"]]["wins"] += s["b_wins"]
		totals[s["b_key"]]["games"] += s["n"]
	for key in CLASS_KEYS:
		var t = totals[key]
		var wr = float(t["wins"]) / t["games"] * 100.0 if t["games"] > 0 else 0.0
		print("%-8s overall win rate vs other classes: %5.1f%%  (%d/%d)" % [CLASS_LABELS[key], wr, t["wins"], t["games"]])
