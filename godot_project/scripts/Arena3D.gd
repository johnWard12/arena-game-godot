extends Node3D
class_name Arena3D
# Phase-0 placeholder 3D arena — box/plane primitives built from the same
# Rect2 data Main.gd already generates (arena_rect/obstacle_rects/health_packs
# stay the source of truth for gameplay; this only renders them).

# Walls are a low lip, NOT a tall barrier: the camera looks down over the
# near (bottom) edge, so any wall tall enough to matter would occlude
# characters standing near that edge. Gameplay boundaries are the arena_rect
# clamp, not these meshes — these are purely a visual rim.
const WALL_HEIGHT := 0.4
const WALL_THICKNESS := 0.6

# Obstacles kept low enough that a character standing behind one (on its
# far side from the camera) still shows head and shoulders.
const OBSTACLE_HEIGHT := 1.0

const FLOOR_COLOR     := Color(0.34, 0.28, 0.18)
const WALL_COLOR      := Color(0.20, 0.16, 0.12)
const OBSTACLE_COLOR  := Color(0.58, 0.52, 0.46)
const HEALTH_COLOR    := Color(0.15, 1.0, 0.45)

var arena_rect: Rect2
var obstacle_rects: Array[Rect2] = []
var health_packs: Array = []
var _pack_meshes: Array[MeshInstance3D] = []
var _pack_glows: Array[MeshInstance3D] = []

func setup(rect: Rect2, obstacles: Array[Rect2], packs: Array):
	arena_rect = rect
	obstacle_rects = obstacles
	health_packs = packs
	_build_floor()
	_build_walls()
	_build_obstacles()
	_build_health_packs()
	_build_lighting()

func _build_floor():
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = arena_rect.size / CoordUtil.SIM_SCALE
	plane.subdivide_width = 24
	plane.subdivide_depth = 16
	mi.mesh = plane
	mi.position = CoordUtil.to_world(arena_rect.position + arena_rect.size * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FLOOR_COLOR
	mi.material_override = mat
	add_child(mi)

func _build_walls():
	var half = arena_rect.size * 0.5 / CoordUtil.SIM_SCALE
	var base = CoordUtil.to_world(arena_rect.position + arena_rect.size * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WALL_COLOR
	var layout = [
		[Vector3(0, WALL_HEIGHT * 0.5, -half.y - WALL_THICKNESS * 0.5), Vector3(half.x * 2 + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS)],
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

func _build_obstacles():
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OBSTACLE_COLOR
	for rect in obstacle_rects:
		var center = rect.position + rect.size * 0.5
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x / CoordUtil.SIM_SCALE, OBSTACLE_HEIGHT, rect.size.y / CoordUtil.SIM_SCALE)
		mi.mesh = box
		mi.position = CoordUtil.to_world(center, OBSTACLE_HEIGHT * 0.5)
		mi.material_override = mat
		add_child(mi)

func _build_health_packs():
	for pack in health_packs:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.45
		sphere.height = 0.9
		mi.mesh = sphere
		mi.position = CoordUtil.to_world(pack["pos"], 0.7)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = HEALTH_COLOR
		mat.emission_enabled = true
		mat.emission = HEALTH_COLOR
		mat.emission_energy_multiplier = 3.0
		mi.material_override = mat
		add_child(mi)
		_pack_meshes.append(mi)

		# soft additive glow halo so it reads as "hard to miss" like the old 2D orb
		var glow := MeshInstance3D.new()
		var glow_sphere := SphereMesh.new()
		glow_sphere.radius = 0.85
		glow_sphere.height = 1.7
		glow.mesh = glow_sphere
		glow.position = mi.position
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(HEALTH_COLOR.r, HEALTH_COLOR.g, HEALTH_COLOR.b, 0.18)
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.emission_enabled = true
		glow_mat.emission = HEALTH_COLOR
		glow_mat.emission_energy_multiplier = 1.0
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.material_override = glow_mat
		add_child(glow)
		_pack_glows.append(glow)

func _process(_delta):
	for i in health_packs.size():
		if i < _pack_meshes.size():
			var active = health_packs[i]["active"]
			_pack_meshes[i].visible = active
			_pack_glows[i].visible = active

func _build_lighting():
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	# Shadows disabled for now — a directional shadow map stretched over a
	# large, fully-visible orthogonal arena produced visible banding/aliasing
	# across the floor. Revisit with tuned shadow-map splits later.
	sun.shadow_enabled = false
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.85
	env_node.environment = env
	add_child(env_node)
