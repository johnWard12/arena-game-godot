extends Node3D
class_name Arena3D
# Phase-1 3D arena — real Kenney Castle Kit geometry (back wall, towers,
# obstacles all built from tiled/instanced .glb pieces) plus procedural
# stone materials for the floor/front walls, torches, and richer lighting.
# Still built entirely from the same Rect2 data Main.gd already generates
# (arena_rect/obstacle_rects/health_packs stay the source of truth for
# gameplay; this only renders them).

# Front/side walls are a low lip, NOT a tall barrier: the camera looks down
# over the near (bottom) edge, so any wall tall enough to matter there would
# occlude characters standing near it. Gameplay boundaries are the
# arena_rect clamp, not these meshes — these are purely a visual rim.
const CoordUtil = preload("res://scripts/CoordUtil.gd")

const WALL_HEIGHT := 0.4
const WALL_THICKNESS := 0.6

# The FAR wall (small sim Y / "top" of screen) sits deep in the background
# from the camera's angle and can safely be tall for coliseum grandeur
# without ever coming between the camera and a nearby character.
const BACK_WALL_HEIGHT := 3.2

# Obstacles kept low enough that a character standing behind one (on its
# far side from the camera) still shows head and shoulders.
const OBSTACLE_HEIGHT := 1.0

const FLOOR_COLOR     := Color(0.22, 0.19, 0.16)
const WALL_COLOR      := Color(0.14, 0.11, 0.09)
const KIT_STONE_COLOR := Color(0.62, 0.58, 0.52)
const HEALTH_COLOR    := Color(0.15, 1.0, 0.45)
const TORCH_COLOR     := Color(1.0, 0.55, 0.18)

const KIT_PATH := "res://assets/kenney_castle-kit/Models/GLB format/"
const WALL_MODEL_HEIGHT := 1.31  # measured aabb height of wall.glb / wall-pillar.glb
const WALL_TILE_SCALE := BACK_WALL_HEIGHT / WALL_MODEL_HEIGHT
const WALL_TILE_WIDTH := 1.0 * WALL_TILE_SCALE
const PILLAR_EVERY := 4  # every Nth tile is a pillar variant instead of plain wall
const OBSTACLE_TILE_SCALE := OBSTACLE_HEIGHT / WALL_MODEL_HEIGHT

var _wall_scene: PackedScene = load(KIT_PATH + "wall.glb")
var _pillar_scene: PackedScene = load(KIT_PATH + "wall-pillar.glb")
var _gate_scene: PackedScene = load(KIT_PATH + "gate.glb")
var _tower_base_scene: PackedScene = load(KIT_PATH + "tower-square-base.glb")
var _tower_mid_scene: PackedScene = load(KIT_PATH + "tower-square-mid.glb")
var _tower_roof_scene: PackedScene = load(KIT_PATH + "tower-square-top-roof.glb")
var _rock_large_scene: PackedScene = load(KIT_PATH + "rocks-large.glb")
var _rock_small_scene: PackedScene = load(KIT_PATH + "rocks-small.glb")

var arena_rect: Rect2
var obstacle_rects: Array[Rect2] = []
var health_packs: Array = []
var _pack_meshes: Array[MeshInstance3D] = []
var _pack_glows: Array[MeshInstance3D] = []
var _pack_pivots: Array[Node3D] = []
var _pack_base_y: Array[float] = []
var _torch_lights: Array[OmniLight3D] = []
var _time := 0.0

func setup(rect: Rect2, obstacles: Array[Rect2], packs: Array):
	arena_rect = rect
	obstacle_rects = obstacles
	health_packs = packs
	_build_floor()
	_build_walls()
	_build_back_wall()
	_build_obstacles()
	_build_health_packs()
	_build_torches()
	_build_center_emblem()
	_build_floor_rocks()
	_build_lighting()

func _make_stone_material(base_color: Color, seed_val: int, uv_scale: float, roughness: float = 0.92) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.045
	noise.fractal_octaves = 3

	var albedo_tex := NoiseTexture2D.new()
	albedo_tex.width = 256
	albedo_tex.height = 256
	albedo_tex.noise = noise
	albedo_tex.seamless = true

	# Same underlying noise, read as a normal map — previously the noise
	# only varied albedo brightness, so lighting couldn't tell the surface
	# had any bump at all. Sharing the noise source means the bumps align
	# with the color variation instead of reading as two unrelated patterns.
	var normal_tex := NoiseTexture2D.new()
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.noise = noise
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 6.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.albedo_texture = albedo_tex
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.roughness = roughness
	mat.roughness_texture = albedo_tex  # subtle micro-variation in shininess
	mat.metallic = 0.0
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 1.1
	return mat

# Kenney's kit assigns different flat colors per part (tan walls, blue
# roofs, etc from its shared palette atlas) which reads as mismatched
# against our chosen stone tone. Recursively force one consistent material
# across every mesh in an instanced kit piece so everything reads as the
# same coherent stone, while keeping the kit's actual modeled geometry
# (crenellations, arches, roof shapes).
func _style_kit_model(node: Node, mat: Material):
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_style_kit_model(child, mat)

func _build_floor():
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = arena_rect.size / CoordUtil.SIM_SCALE
	plane.subdivide_width = 24
	plane.subdivide_depth = 16
	mi.mesh = plane
	mi.position = CoordUtil.to_world(arena_rect.position + arena_rect.size * 0.5)
	mi.material_override = _make_stone_material(FLOOR_COLOR, 1, 10.0, 0.95)
	add_child(mi)

func _build_walls():
	var half = arena_rect.size * 0.5 / CoordUtil.SIM_SCALE
	var base = CoordUtil.to_world(arena_rect.position + arena_rect.size * 0.5)
	var mat := _make_stone_material(WALL_COLOR, 2, 4.0)
	var layout = [
		[Vector3(0, WALL_HEIGHT * 0.5,  half.y + WALL_THICKNESS * 0.5), Vector3(half.x * 2 + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS)],
		[Vector3(-half.x - WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, half.y * 2)],
		[Vector3( half.x + WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, half.y * 2)],
	]
	for entry in layout:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = entry[1]
		mi.mesh = box
		mi.position = base + entry[0]
		mi.material_override = mat
		add_child(mi)

func _build_back_wall():
	var half = arena_rect.size * 0.5 / CoordUtil.SIM_SCALE
	var base = CoordUtil.to_world(arena_rect.position + arena_rect.size * 0.5)
	var z = -half.y - WALL_THICKNESS * 0.7
	var total_width = half.x * 2.0
	var tile_count = int(ceil(total_width / WALL_TILE_WIDTH))
	var start_x = -float(tile_count) * WALL_TILE_WIDTH * 0.5
	var mat := _make_stone_material(KIT_STONE_COLOR, 8, 0.8, 0.85)

	for i in tile_count:
		var use_pillar = (i % PILLAR_EVERY == 0)
		var scene = _pillar_scene if use_pillar else _wall_scene
		var inst = scene.instantiate()
		add_child(inst)
		_style_kit_model(inst, mat)
		inst.scale = Vector3.ONE * WALL_TILE_SCALE
		inst.position = base + Vector3(start_x + (i + 0.5) * WALL_TILE_WIDTH, 0, z)

	# A gate centered on the back wall as a decorative flourish. gate.glb has
	# a very different aspect ratio from the cubic wall/tower pieces (thin
	# and tall), so it gets its own scale computed from ITS OWN measured
	# height rather than reusing the wall tile scale — reusing that scale
	# blew it up into a huge disproportionate spike.
	const GATE_MODEL_HEIGHT := 0.910339  # measured aabb height of gate.glb
	const GATE_TARGET_HEIGHT := 2.6
	var gate_scale = GATE_TARGET_HEIGHT / GATE_MODEL_HEIGHT
	var gate = _gate_scene.instantiate()
	add_child(gate)
	_style_kit_model(gate, mat)
	gate.scale = Vector3.ONE * gate_scale
	gate.position = base + Vector3(0, 0, z)

	# Corner towers (base/mid/roof stacked) at both back corners for grandeur.
	for side in [-1.0, 1.0]:
		_build_corner_tower(base + Vector3(side * (half.x + WALL_THICKNESS), 0, z), mat)

func _build_corner_tower(pos: Vector3, mat: Material):
	const TOWER_SCALE := 2.6
	var y = 0.0
	for scene in [_tower_base_scene, _tower_mid_scene, _tower_roof_scene]:
		var inst = scene.instantiate()
		add_child(inst)
		_style_kit_model(inst, mat)
		inst.scale = Vector3.ONE * TOWER_SCALE
		inst.position = pos + Vector3(0, y, 0)
		y += 1.0 * TOWER_SCALE

# Obstacles are gameplay-functional — their footprint must match the exact
# Rect2 collision data — so instead of a flat box they're now tiled from
# the same wall.glb piece used for the back wall, giving them real modeled
# stone-block detail while still covering their required footprint exactly
# (each tile stretched slightly to make an integer count fit the footprint
# cleanly; a minor, purely-cosmetic distortion).
func _build_obstacles():
	var mat := _make_stone_material(KIT_STONE_COLOR, 5, 0.8, 0.88)
	for rect in obstacle_rects:
		var width_m = rect.size.x / CoordUtil.SIM_SCALE
		var depth_m = rect.size.y / CoordUtil.SIM_SCALE
		var tile_m = 1.0 * OBSTACLE_TILE_SCALE
		var nx = max(1, int(round(width_m / tile_m)))
		var nz = max(1, int(round(depth_m / tile_m)))
		var scale_x = (width_m / nx) / 1.0
		var scale_z = (depth_m / nz) / 1.0
		var center = rect.position + rect.size * 0.5
		var base_pos = CoordUtil.to_world(center)
		var start_x = -float(nx) * (width_m / nx) * 0.5
		var start_z = -float(nz) * (depth_m / nz) * 0.5
		for ix in nx:
			for iz in nz:
				var inst = _wall_scene.instantiate()
				add_child(inst)
				_style_kit_model(inst, mat)
				inst.scale = Vector3(scale_x, OBSTACLE_TILE_SCALE, scale_z)
				inst.position = base_pos + Vector3(
					start_x + (ix + 0.5) * (width_m / nx), 0,
					start_z + (iz + 0.5) * (depth_m / nz))

func _build_health_packs():
	var ped_mat := _make_stone_material(Color(0.34, 0.27, 0.18), 6, 1.0, 0.85)
	for pack in health_packs:
		var base_pos = CoordUtil.to_world(pack["pos"])

		var ped := MeshInstance3D.new()
		var ped_mesh := CylinderMesh.new()
		ped_mesh.top_radius = 0.24
		ped_mesh.bottom_radius = 0.3
		ped_mesh.height = 0.4
		ped.mesh = ped_mesh
		ped.position = base_pos + Vector3(0, 0.2, 0)
		ped.material_override = ped_mat
		add_child(ped)

		# Spinning pivot holding a low-poly faceted gem (reads as a crystal,
		# not a plain ball) plus a crossed-box "+" symbol matching the old
		# 2D orb's plus icon — this is what actually animates/bobs. The
		# cross is sized to poke out past the gem's silhouette (rather than
		# sit flush with it) so it reads as a health-cross badge at a
		# glance instead of blending into the glowing sphere.
		var pivot := Node3D.new()
		pivot.position = base_pos + Vector3(0, 0.68, 0)
		add_child(pivot)
		_pack_pivots.append(pivot)
		_pack_base_y.append(pivot.position.y)

		var mi := MeshInstance3D.new()
		var gem := SphereMesh.new()
		gem.radius = 0.26
		gem.height = 0.52
		gem.radial_segments = 7
		gem.rings = 3
		mi.mesh = gem
		var mat := StandardMaterial3D.new()
		mat.albedo_color = HEALTH_COLOR
		mat.emission_enabled = true
		mat.emission = HEALTH_COLOR
		mat.emission_energy_multiplier = 2.2
		mat.metallic = 0.2
		mat.roughness = 0.15
		mi.material_override = mat
		pivot.add_child(mi)
		_pack_meshes.append(mi)

		var cross_mat := StandardMaterial3D.new()
		cross_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cross_mat.albedo_color = Color(0.95, 1.0, 0.97)
		cross_mat.emission_enabled = true
		cross_mat.emission = Color(0.95, 1.0, 0.97)
		cross_mat.emission_energy_multiplier = 3.2
		for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			var bar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.46, 0.13, 0.13) if axis.x > 0 else Vector3(0.13, 0.46, 0.13)
			bar.mesh = box
			bar.material_override = cross_mat
			pivot.add_child(bar)

		# soft additive glow halo so it reads as "hard to miss" like the old 2D orb
		var glow := MeshInstance3D.new()
		var glow_sphere := SphereMesh.new()
		glow_sphere.radius = 0.55
		glow_sphere.height = 1.1
		glow.mesh = glow_sphere
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(HEALTH_COLOR.r, HEALTH_COLOR.g, HEALTH_COLOR.b, 0.18)
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.emission_enabled = true
		glow_mat.emission = HEALTH_COLOR
		glow_mat.emission_energy_multiplier = 1.0
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.material_override = glow_mat
		pivot.add_child(glow)
		_pack_glows.append(glow)

func _build_torches():
	var margin = 90.0
	var corners_2d = [
		arena_rect.position + Vector2(margin, margin),
		arena_rect.position + Vector2(arena_rect.size.x - margin, margin),
		arena_rect.position + Vector2(margin, arena_rect.size.y - margin),
		arena_rect.position + Vector2(arena_rect.size.x - margin, arena_rect.size.y - margin),
	]
	for c in corners_2d:
		_build_torch(c)

func _build_torch(pos2d: Vector2):
	var base_pos = CoordUtil.to_world(pos2d)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 1.3
	pole.mesh = pole_mesh
	pole.position = base_pos + Vector3(0, 0.65, 0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.25, 0.18, 0.12)
	pole.material_override = pole_mat
	add_child(pole)

	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.2
	bowl_mesh.bottom_radius = 0.13
	bowl_mesh.height = 0.16
	bowl.mesh = bowl_mesh
	bowl.position = base_pos + Vector3(0, 1.3, 0)
	var bowl_mat := StandardMaterial3D.new()
	bowl_mat.albedo_color = Color(0.2, 0.15, 0.1)
	bowl.material_override = bowl_mat
	add_child(bowl)

	var light := OmniLight3D.new()
	light.position = base_pos + Vector3(0, 1.45, 0)
	light.light_color = TORCH_COLOR
	light.light_energy = 1.8
	light.omni_range = 4.5
	add_child(light)
	_torch_lights.append(light)

	var fire := GPUParticles3D.new()
	fire.position = base_pos + Vector3(0, 1.45, 0)
	fire.amount = 14
	fire.lifetime = 0.55
	fire.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.color = TORCH_COLOR
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.albedo_color = TORCH_COLOR
	fire_mat.emission_enabled = true
	fire_mat.emission = TORCH_COLOR
	fire_mat.emission_energy_multiplier = 2.0
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = fire_mat
	fire.draw_pass_1 = quad
	add_child(fire)

func _build_center_emblem():
	var center = arena_rect.position + arena_rect.size * 0.5

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.height = 0.04
	disc.mesh = cyl
	disc.position = CoordUtil.to_world(center, 0.02)
	disc.material_override = _make_stone_material(Color(0.42, 0.34, 0.22), 7, 1.0, 0.8)
	add_child(disc)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.6
	torus.outer_radius = 2.85
	ring.mesh = torus
	ring.position = CoordUtil.to_world(center, 0.03)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.62, 0.46, 0.24)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.62, 0.46, 0.24)
	ring_mat.emission_energy_multiplier = 0.35
	ring_mat.metallic = 0.3
	ring_mat.roughness = 0.6
	ring.material_override = ring_mat
	add_child(ring)

# Scattered rubble for floor variety, kept away from the play-critical
# center lane (obstacles/health packs) and spawn areas.
func _build_floor_rocks():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var mat := _make_stone_material(Color(0.5, 0.47, 0.42), 9, 0.6, 0.9)
	var placed = 0
	var attempts = 0
	var center = arena_rect.position + arena_rect.size * 0.5
	while placed < 10 and attempts < 200:
		attempts += 1
		var pos2d = arena_rect.position + Vector2(
			rng.randf_range(120, arena_rect.size.x - 120),
			rng.randf_range(120, arena_rect.size.y - 120))
		# Skip the central play lane and spawn zones so rubble doesn't
		# clutter gameplay-relevant sightlines.
		if pos2d.distance_to(center) < 260:
			continue
		if abs(pos2d.x - arena_rect.position.x - 450) < 160 or \
		   abs(pos2d.x - arena_rect.position.x - (arena_rect.size.x - 450)) < 160:
			continue
		var scene = _rock_large_scene if rng.randf() < 0.4 else _rock_small_scene
		var inst = scene.instantiate()
		add_child(inst)
		_style_kit_model(inst, mat)
		var s = rng.randf_range(0.5, 1.1)
		inst.scale = Vector3.ONE * s
		inst.rotation.y = rng.randf_range(0, TAU)
		inst.position = CoordUtil.to_world(pos2d)
		placed += 1

func _process(delta):
	_time += delta
	for i in health_packs.size():
		if i < _pack_pivots.size():
			var active = health_packs[i]["active"]
			var pivot = _pack_pivots[i]
			pivot.visible = active
			if active:
				pivot.rotation.y += delta * 1.4
				var bob = sin(_time * 2.2 + i * 1.7) * 0.08
				pivot.position.y = _pack_base_y[i] + bob
				var pulse = 0.5 + 0.5 * sin(_time * 2.2 + i * 1.7)
				var glow_mat: StandardMaterial3D = _pack_glows[i].material_override
				glow_mat.albedo_color.a = 0.14 + pulse * 0.10
				var gem_mat: StandardMaterial3D = _pack_meshes[i].material_override
				gem_mat.emission_energy_multiplier = 1.8 + pulse * 1.0
	for i in _torch_lights.size():
		var flicker = 1.6 + sin(_time * 9.0 + i * 2.1) * 0.15 + sin(_time * 23.0 + i) * 0.08
		_torch_lights[i].light_energy = flicker

func _build_lighting():
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.95, 0.85)
	# Re-enabled now that the front/side geometry is a short lip (0.4m).
	# The crenellated back wall/towers are fine-detail repeating geometry
	# that can alias into speckled shadow noise at default shadow settings,
	# so blur+bias are pushed up to soften that rather than disabling
	# shadows outright (which was the earlier fix for a different problem —
	# a single huge flat quad's stretched shadow).
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.15
	sun.shadow_normal_bias = 2.0
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.08, 0.14)
	sky_mat.sky_horizon_color = Color(0.30, 0.22, 0.16)
	sky_mat.ground_bottom_color = Color(0.06, 0.05, 0.04)
	sky_mat.ground_horizon_color = Color(0.22, 0.17, 0.12)
	sky.sky_material = sky_mat
	env.sky = sky
	# Ambient from a fixed neutral color rather than the sky — deriving it
	# from the sky's warm horizon color was tinting every material toward
	# the same brown regardless of its actual albedo, crushing the contrast
	# between floor/wall/obstacle.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = 0.5
	# Fog was the main culprit for the "everything looks the same" wash —
	# at this arena's ~37m scale, 0.02 density was strong enough to tint
	# every surface toward fog_light_color regardless of distance. Cut by
	# 5x and desaturated toward neutral so it only adds faint depth cueing.
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.48, 0.46)
	env.fog_density = 0.004
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1

	# SSAO was cut — it's one of the more GPU-expensive post-process effects
	# and, combined with 4x MSAA and a 4096 shadow map, made the game
	# noticeably laggy/jittery. The normal maps + tonemap + color grading
	# below do most of the visual work at a much lower cost; re-add SSAO
	# later if performance allows.
	env.ssao_enabled = false

	# Filmic tonemapping gives much better highlight rolloff than the
	# default Linear mode, which matters here since several elements are
	# emissive/bloom-lit (torches, health packs, the center ring) — Linear
	# tends to blow those out to flat white instead of a graded glow.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# A small color-grading pass for a less flat, more "produced" look.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	env_node.environment = env
	add_child(env_node)
