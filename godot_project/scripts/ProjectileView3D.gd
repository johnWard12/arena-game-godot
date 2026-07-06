extends Node3D
class_name ProjectileView3D
# 3D presentation for a Projectile — mirrors its already-simulated position
# the same way EntityView3D does for Entity. Built from a core+glow+trail+
# glint stack (all simple primitives) rather than a single flat sphere, so
# projectiles read as "energy bolts" instead of plain dots even without any
# custom shaders or textures.

const CoordUtil = preload("res://scripts/CoordUtil.gd")

var projectile: Projectile = null

var _core: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _glint_a: MeshInstance3D
var _glint_b: MeshInstance3D

const TRAIL_SEGMENTS := 6
var _trail_meshes: Array[MeshInstance3D] = []

func setup(p: Projectile):
	projectile = p
	var col: Color = p.proj_color
	var r: float = p.proj_radius_visual / 90.0  # rough sim-units -> meters scale

	# outer glow halo
	_glow = MeshInstance3D.new()
	var glow_sphere := SphereMesh.new()
	glow_sphere.radius = r * 2.1
	glow_sphere.height = r * 4.2
	_glow.mesh = glow_sphere
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(col.r, col.g, col.b, 0.22)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = col
	_glow_mat.emission_energy_multiplier = 0.8
	_glow.material_override = _glow_mat
	add_child(_glow)

	# core (colored body)
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	_core.mesh = sphere
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = col
	core_mat.emission_enabled = true
	core_mat.emission = col
	core_mat.emission_energy_multiplier = 2.6
	_core.material_override = core_mat
	add_child(_core)

	# bright white hot-spot so the core doesn't read as a flat color disc
	var hotspot := MeshInstance3D.new()
	var hs_sphere := SphereMesh.new()
	hs_sphere.radius = r * 0.45
	hs_sphere.height = r * 0.9
	hotspot.mesh = hs_sphere
	var hs_mat := StandardMaterial3D.new()
	hs_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hs_mat.albedo_color = Color(1, 1, 1, 0.9)
	hs_mat.emission_enabled = true
	hs_mat.emission = Color(1, 1, 1)
	hs_mat.emission_energy_multiplier = 3.0
	hotspot.material_override = hs_mat
	_core.add_child(hotspot)

	# rotating cross-glint for a "magic/energy" read, matching the old 2D art
	var glint_mat := StandardMaterial3D.new()
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.albedo_color = Color(1, 1, 1, 0.6)
	glint_mat.emission_enabled = true
	glint_mat.emission = Color(1, 1, 1)
	glint_mat.emission_energy_multiplier = 1.5
	_glint_a = MeshInstance3D.new()
	var quad_a := QuadMesh.new()
	quad_a.size = Vector2(r * 3.2, r * 0.3)
	_glint_a.mesh = quad_a
	_glint_a.material_override = glint_mat
	add_child(_glint_a)
	_glint_b = MeshInstance3D.new()
	var quad_b := QuadMesh.new()
	quad_b.size = Vector2(r * 0.3, r * 3.2)
	_glint_b.mesh = quad_b
	_glint_b.material_override = glint_mat
	add_child(_glint_b)

	# fading trail ghosts, one mesh per segment, reused every frame
	for i in TRAIL_SEGMENTS:
		var seg := MeshInstance3D.new()
		var seg_sphere := SphereMesh.new()
		var age = float(i) / float(TRAIL_SEGMENTS)
		seg_sphere.radius = lerp(r * 0.85, r * 0.15, age)
		seg_sphere.height = seg_sphere.radius * 2.0
		seg.mesh = seg_sphere
		var seg_mat := StandardMaterial3D.new()
		seg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		seg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		seg_mat.albedo_color = Color(col.r, col.g, col.b, (1.0 - age) * 0.4)
		seg_mat.emission_enabled = true
		seg_mat.emission = col
		seg_mat.emission_energy_multiplier = 1.0
		seg.material_override = seg_mat
		seg.visible = false
		add_child(seg)
		_trail_meshes.append(seg)

func _process(_delta):
	if projectile == null or not is_instance_valid(projectile):
		queue_free()
		return
	position = CoordUtil.to_world(projectile.global_position, 0.9)

	var t = Time.get_ticks_msec() * 0.012
	_glint_a.rotation.y = t
	_glint_b.rotation.y = t + PI * 0.5
	var pulse = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02)
	_glow.scale = Vector3.ONE * pulse

	var trail = projectile.trail
	var n = trail.size()
	for i in _trail_meshes.size():
		var seg = _trail_meshes[i]
		if i >= n:
			seg.visible = false
			continue
		var src_idx = n - 1 - i
		if src_idx < 0:
			seg.visible = false
			continue
		seg.visible = true
		seg.global_position = CoordUtil.to_world(trail[src_idx], 0.9)
