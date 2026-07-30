extends Node3D
class_name ProjectileView3D
# 3D presentation for a Projectile — mirrors its already-simulated position
# the same way EntityView3D does for Entity. Shape is picked from
# projectile.visual_kind: "orb" (the original glowing-ball look, still the
# default — e.g. Duelist's Sword Throw), "icicle" (Mage — an elongated
# tapered crystal shard), or "arrow" (Ranger — shaft + head + fletching).
# Non-orb shapes are oriented to face their travel direction each frame.

const CoordUtil = preload("res://scripts/CoordUtil.gd")

var projectile: Projectile = null
var _kind := "orb"

var _core: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _glint_a: MeshInstance3D
var _glint_b: MeshInstance3D
var _sparks: GPUParticles3D
var _light: OmniLight3D

# Impact pop: when the sim projectile frees (hit or expiry), this view
# lingers ~0.2s to play a quick expanding flash instead of vanishing on the
# same frame — sells the hit landing.
var _dying := false
var _die_t := 0.0
const IMPACT_DUR := 0.22

const TRAIL_SEGMENTS := 6
var _trail_meshes: Array[MeshInstance3D] = []

func setup(p: Projectile):
	projectile = p
	_kind = p.visual_kind
	var col: Color = p.proj_color
	var r: float = p.proj_radius_visual / 90.0  # rough sim-units -> meters scale

	# outer glow halo — shared by every shape
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

	match _kind:
		"icicle": _build_icicle(col, r)
		"arrow": _build_arrow(col, r)
		_: _build_orb(col, r)

	# comet spark trail — world-space particles shed behind the moving bolt
	_sparks = GPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.35
	_sparks.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.9))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_sparks.process_material = pm
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.07, 0.07)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.emission_enabled = true
	spark_mat.emission = col
	spark_mat.emission_energy_multiplier = 1.6
	spark_quad.material = spark_mat
	_sparks.draw_pass_1 = spark_quad
	add_child(_sparks)

	# real dynamic light so spells illuminate the floor/fighters as they fly
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.3
	_light.omni_range = 2.4
	_light.shadow_enabled = false
	add_child(_light)

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

func _unshaded_mat(col: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	return mat

# Original ball-shaped energy bolt: core + white hotspot + rotating cross-glint.
func _build_orb(col: Color, r: float):
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	_core.mesh = sphere
	_core.material_override = _unshaded_mat(col, 2.6)
	add_child(_core)

	var hotspot := MeshInstance3D.new()
	var hs_sphere := SphereMesh.new()
	hs_sphere.radius = r * 0.45
	hs_sphere.height = r * 0.9
	hotspot.mesh = hs_sphere
	hotspot.material_override = _unshaded_mat(Color(1, 1, 1), 3.0)
	_core.add_child(hotspot)

	var glint_mat := _unshaded_mat(Color(1, 1, 1), 1.5, 0.6)
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

# Elongated tapered crystal shard (bipyramid: two cones joined base-to-base),
# built along local Z so it can be oriented to face its travel direction.
func _build_icicle(col: Color, r: float):
	var length = r * 7.0
	var mid_r = r * 0.85
	var mat = _unshaded_mat(col, 2.4)

	var front := MeshInstance3D.new()
	var front_cone := CylinderMesh.new()
	front_cone.top_radius = 0.0
	front_cone.bottom_radius = mid_r
	front_cone.height = length * 0.55
	front.mesh = front_cone
	front.material_override = mat
	front.rotation.x = PI / 2.0
	front.position = Vector3(0, 0, length * 0.275)
	add_child(front)

	var back := MeshInstance3D.new()
	var back_cone := CylinderMesh.new()
	back_cone.top_radius = 0.0
	back_cone.bottom_radius = mid_r * 0.7
	back_cone.height = length * 0.45
	back.mesh = back_cone
	back.material_override = mat
	back.rotation.x = -PI / 2.0
	back.position = Vector3(0, 0, -length * 0.225)
	add_child(back)

	var hotspot := MeshInstance3D.new()
	var hs_sphere := SphereMesh.new()
	hs_sphere.radius = mid_r * 0.5
	hs_sphere.height = mid_r
	hotspot.mesh = hs_sphere
	hotspot.material_override = _unshaded_mat(Color(1, 1, 1), 3.0)
	add_child(hotspot)

# Shaft + conical head + a small cross of tail fletching, built along local
# Z (Godot's look_at faces -Z, which is what _process() orients toward).
func _build_arrow(col: Color, r: float):
	var length = r * 9.0
	var shaft_r = r * 0.28
	var head_r = r * 0.75
	var wood_mat = _unshaded_mat(Color(0.45, 0.32, 0.18), 0.4)
	var head_mat = _unshaded_mat(Color(0.75, 0.78, 0.85), 2.0)
	var fletch_mat = _unshaded_mat(col, 1.8, 0.85)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = shaft_r
	shaft_mesh.bottom_radius = shaft_r
	shaft_mesh.height = length * 0.7
	shaft.mesh = shaft_mesh
	shaft.material_override = wood_mat
	shaft.rotation.x = PI / 2.0
	shaft.position = Vector3(0, 0, length * 0.05)
	add_child(shaft)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = head_r
	head_mesh.height = length * 0.3
	head.mesh = head_mesh
	head.material_override = head_mat
	head.rotation.x = PI / 2.0
	head.position = Vector3(0, 0, length * 0.55)
	add_child(head)

	# tail fletching — two crossed thin fins near the back of the shaft
	var fin_a := MeshInstance3D.new()
	var fin_a_mesh := QuadMesh.new()
	fin_a_mesh.size = Vector2(shaft_r * 5.0, length * 0.22)
	fin_a.mesh = fin_a_mesh
	fin_a.material_override = fletch_mat
	fin_a.position = Vector3(0, 0, -length * 0.32)
	add_child(fin_a)
	var fin_b := MeshInstance3D.new()
	var fin_b_mesh := QuadMesh.new()
	fin_b_mesh.size = Vector2(shaft_r * 5.0, length * 0.22)
	fin_b.mesh = fin_b_mesh
	fin_b.material_override = fletch_mat
	fin_b.rotation.z = PI / 2.0
	fin_b.position = Vector3(0, 0, -length * 0.32)
	add_child(fin_b)

func _process(delta):
	if projectile == null or not is_instance_valid(projectile):
		_impact(delta)
		return
	position = CoordUtil.to_world(projectile.global_position, 0.9)

	if _kind != "orb":
		var dir = Vector3(projectile.velocity.x, 0, projectile.velocity.y)
		if dir.length() > 0.01:
			look_at(position + dir.normalized(), Vector3.UP)
	else:
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

# Quick expanding flash + light pop at the projectile's last position, then
# free. First frame hides the projectile body and keeps only the glow halo.
func _impact(delta: float):
	if not _dying:
		_dying = true
		_die_t = 0.0
		for c in get_children():
			if c is MeshInstance3D and c != _glow:
				c.visible = false
		if _sparks != null:
			_sparks.emitting = false
	_die_t += delta
	var t = _die_t / IMPACT_DUR
	if t >= 1.0:
		queue_free()
		return
	_glow.visible = true
	_glow.scale = Vector3.ONE * (1.0 + t * 2.6)
	_glow_mat.albedo_color.a = 0.5 * (1.0 - t)
	_glow_mat.emission_energy_multiplier = 2.0 * (1.0 - t)
	if _light != null:
		_light.light_energy = 2.2 * (1.0 - t)
