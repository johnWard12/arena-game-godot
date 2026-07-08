extends Node2D
# Headless bot-vs-bot balance simulation.
# Run with:
#   Godot.app/Contents/MacOS/Godot --headless --path godot_project res://scenes/Simulate.tscn -- --matches=300

const FIXED_DT := 1.0 / 60.0
# Kiting-heavy matchups (Ranger especially) were hitting this cap as a near-
# universal draw at 90s, which made it impossible to tell "this class is
# weak" from "this class's fights just take longer than the cap." Raised to
# 150s to give those matchups room to actually resolve, then to 240s after
# all classes' HP was scaled up +35% (damage unchanged, to soften team-fight
# burst) — the bigger HP pools pushed several previously-resolving
# matchups (Mage vs Cleric, Ranger mirrors) into ~100% draws at 150s, which
# was a cap artifact, not those classes actually getting worse.
const MAX_MATCH_SECONDS := 240.0
const MAX_MATCH_TICKS := int(MAX_MATCH_SECONDS / FIXED_DT)

const CLASS_KEYS = ["melee", "ranged", "bruiser", "ranger", "cleric"]
const CLASS_LABELS = {"melee": "Duelist", "ranged": "Mage", "bruiser": "Bruiser", "ranger": "Ranger", "cleric": "Cleric"}

const HEALTH_PACK_HEAL = 25.0
const HEALTH_PACK_RADIUS = 44.0
const HEALTH_PACK_RESPAWN = 15.0

var arena_rect := Rect2(Vector2(30, 30), Vector2(1860, 1020))
var map_obstacles: Array[Rect2] = []

func _ready():
	build_map()
	var matches_per_pairing := 300
	var team_matches := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matches="):
			matches_per_pairing = int(arg.split("=")[1])
		elif arg.begins_with("--team-matches="):
			team_matches = int(arg.split("=")[1])

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

	# Opt-in (--team-matches=N): a curated set of 2v2/3v3 comps, mainly aimed
	# at answering "does fielding the Cleric actually help a team" now that
	# CharSelect can build mixed comps. Not part of the default run since the
	# 1v1 matrix above is the fast regression check most tuning passes need.
	if team_matches > 0:
		print("")
		run_team_tests(team_matches)

	get_tree().quit()

func build_map():
	map_obstacles = [
		Rect2(Vector2(857, 227), Vector2(207, 74)),
		Rect2(Vector2(857, 779), Vector2(207, 74)),
		Rect2(Vector2(428, 450), Vector2(83, 181)),
		Rect2(Vector2(1410, 450), Vector2(83, 181)),
		Rect2(Vector2(728, 503), Vector2(114, 74)),
		Rect2(Vector2(1079, 503), Vector2(114, 74)),
	]

func make_bot(key: String) -> Entity:
	var bot: Entity
	match key:
		"ranged":  bot = RangedBotController.new()
		"bruiser": bot = BruiserBotController.new()
		"ranger":  bot = RangerBotController.new()
		"cleric":  bot = ClericBotController.new()
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
	entity.heal(entity, HEALTH_PACK_HEAL)
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
		a.team_id = 0
		b.team_id = 1
		a.opponent = b
		b.opponent = a
		a.all_fighters = [a, b]
		b.all_fighters = [a, b]

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

# ---- Team (2v2/3v3) matches ----
# Generalizes run_matchup() to N-per-side teams. Targeting uses the same
# pick_ai_target() focus-fire logic Main.gd drives bots with in the real
# game (dwell + healer priority + kill-swap mixup), recomputed every tick
# exactly like Main._update_targeting() does, so this measures the same AI
# behavior a real match would show — not a simplified stand-in for it.
func run_team_matchup(team_a_keys: Array, team_b_keys: Array, n: int) -> Dictionary:
	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var total_ticks := 0

	for i in n:
		var team_a := _spawn_team(team_a_keys, 0, 510.0)
		var team_b := _spawn_team(team_b_keys, 1, 1350.0)
		var all_fighters: Array = team_a + team_b
		for f in all_fighters:
			f.all_fighters = all_fighters

		var projectiles := []
		for f in all_fighters:
			f.projectile_spawned.connect(func(p): p.obstacle_rects = map_obstacles; projectiles.append(p))

		var packs := make_health_packs()
		var ticks := 0
		while ticks < MAX_MATCH_TICKS and _team_alive(team_a) and _team_alive(team_b):
			for f in all_fighters:
				if f.alive:
					f.opponent = f.pick_ai_target(all_fighters, FIXED_DT)
			for f in all_fighters:
				f._physics_process(FIXED_DT)
			for p in projectiles:
				p._physics_process(FIXED_DT)
			projectiles = projectiles.filter(func(p): return not p.is_queued_for_deletion())
			for pack in packs:
				if not pack["active"]:
					pack["respawn_left"] = max(0.0, pack["respawn_left"] - FIXED_DT)
					if pack["respawn_left"] <= 0.0:
						pack["active"] = true
				else:
					for f in all_fighters:
						if try_pickup(pack, f):
							break
			ticks += 1

		total_ticks += ticks
		var a_alive = _team_alive(team_a)
		var b_alive = _team_alive(team_b)
		if a_alive and not b_alive:
			a_wins += 1
		elif b_alive and not a_alive:
			b_wins += 1
		else:
			draws += 1

	return {
		"a_wins": a_wins, "b_wins": b_wins, "draws": draws, "n": n,
		"avg_duration": (float(total_ticks) / n) * FIXED_DT,
	}

func _spawn_team(keys: Array, team_id: int, x: float) -> Array:
	var team := []
	var spacing := 220.0
	var start_y := 540.0 - spacing * (keys.size() - 1) * 0.5
	for i in keys.size():
		var e = make_bot(keys[i])
		e.global_position = Vector2(x, start_y + i * spacing)
		e.team_id = team_id
		e.arena_rect = arena_rect
		e.obstacle_rects = map_obstacles
		team.append(e)
	return team

func _team_alive(team: Array) -> bool:
	for f in team:
		if f.alive:
			return true
	return false

func _comp_label(keys: Array) -> String:
	var labels := []
	for k in keys:
		labels.append(CLASS_LABELS[k])
	return "+".join(labels)

func print_team_stats(comp_a: Array, comp_b: Array, s: Dictionary):
	var label_a = _comp_label(comp_a)
	var label_b = _comp_label(comp_b)
	var a_wr = float(s["a_wins"]) / s["n"] * 100.0
	var b_wr = float(s["b_wins"]) / s["n"] * 100.0
	print("%-24s vs %-24s | A: %5.1f%%  B: %5.1f%%  draws: %d  avg dur: %5.1fs" % [
		label_a, label_b, a_wr, b_wr, s["draws"], s["avg_duration"]])

# Curated rather than exhaustive (a full combinatorial sweep of 5 classes
# across 2-3 slots is a lot of matches for marginal insight) — each pair
# holds team SIZE and the non-healer classes present roughly constant while
# swapping one slot for a Cleric, isolating "does fielding the healer help"
# from "is this just a better roster."
const TEAM_COMPS_2V2 = [
	[["cleric", "bruiser"], ["melee", "bruiser"]],
	[["cleric", "ranged"], ["ranger", "ranged"]],
	[["cleric", "bruiser"], ["bruiser", "bruiser"]],
]
const TEAM_COMPS_3V3 = [
	[["cleric", "bruiser", "melee"], ["bruiser", "melee", "ranged"]],
	[["cleric", "bruiser", "ranged"], ["bruiser", "ranged", "ranger"]],
	[["cleric", "bruiser", "bruiser"], ["bruiser", "bruiser", "bruiser"]],
]

func run_team_tests(n: int):
	print("=== 2v2 comp testing (%d matches each) ===" % n)
	for pair in TEAM_COMPS_2V2:
		var stats = run_team_matchup(pair[0], pair[1], n)
		print_team_stats(pair[0], pair[1], stats)
	print("")
	print("=== 3v3 comp testing (%d matches each) ===" % n)
	for pair in TEAM_COMPS_3V3:
		var stats = run_team_matchup(pair[0], pair[1], n)
		print_team_stats(pair[0], pair[1], stats)
