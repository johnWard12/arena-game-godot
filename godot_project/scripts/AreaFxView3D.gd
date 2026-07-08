extends Node3D
class_name AreaFxView3D
# Fire-and-forget ground-effect visual for any AoE-shaped ability — a
# pulsing circular zone glow (Consecrate) or a rectangular cast flash
# (Purify). Positioned once at spawn from Entity.area_fx_spawned and never
# touched again: unlike the old 2D approach (drawing at to_local(fixed_pos)
# under the HUD's per-entity screen-space correction), this is real 3D
# world geometry, so it can never inherit the caster's own movement.
# Purely cosmetic, spawned only by Main.gd — the actual gameplay effect
# (damage/heal/cleanse) is already applied by the caster before this exists.

const CoordUtil = preload("res://scripts/CoordUtil.gd")

var _shape := "circle"
var _size := Vector2.ZERO   # circle: x = radius (sim units). rect: x = length, y = width.
var _duration := 1.0
var _color := Color.WHITE
var _age := 0.0
# "pulse" (default): static radius, brightness pulse — a lingering zone.
# "expand": radius grows from a small point to full size — a shockwave burst.
var _anim_style := "pulse"
# "rise" (default): small motes drifting up off the ground — Consecrate.
# "fall": streaks raining down from above into the zone — Rain of Arrows,
# so it visibly reads as an active damage field instead of just a glow.
var _particle_style := "rise"

var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _disc_mesh: CylinderMesh
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _torus: TorusMesh
var _ring2: MeshInstance3D
var _ring2_mat: StandardMaterial3D
var _torus2: TorusMesh
var _particles: GPUParticles3D
var _border: Array[MeshInstance3D] = []
var _border_mat: StandardMaterial3D
var _target_r := 0.0

func setup(fx: Dictionary):
	_shape = fx["shape"]
	_size = fx["size"]
	_duration = fx["duration"]
	_color = fx["color"]
	_anim_style = fx.get("anim", "pulse")
	_particle_style = fx.get("particles", "rise")
	position = CoordUtil.to_world(fx["pos"], 0.03)

	var facing: Vector2 = fx["facing"]
	if facing.length() > 0.01:
		look_at(position + Vector3(facing.x, 0.0, facing.y), Vector3.UP)

	if _shape == "circle":
		_build_circle()
	else:
		_build_rect()

func _make_mat(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_color.r, _color.g, _color.b, alpha)
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 1.4
	return mat

func _build_circle():
	var r = _size.x / CoordUtil.SIM_SCALE
	_target_r = r

	_disc = MeshInstance3D.new()
	_disc_mesh = CylinderMesh.new()
	_disc_mesh.top_radius = r
	_disc_mesh.bottom_radius = r
	_disc_mesh.height = 0.02
	_disc.mesh = _disc_mesh
	_disc_mat = _make_mat(0.12)
	_disc_mat.emission_energy_multiplier = 0.5
	_disc.material_override = _disc_mat
	add_child(_disc)

	_ring = MeshInstance3D.new()
	_torus = TorusMesh.new()
	_torus.inner_radius = r * 0.93
	_torus.outer_radius = r
	_ring.mesh = _torus
	_ring.position.y = 0.03
	_ring_mat = _make_mat(0.8)
	_ring_mat.emission_energy_multiplier = 1.6
	_ring.material_override = _ring_mat
	add_child(_ring)

	_ring2 = MeshInstance3D.new()
	_torus2 = TorusMesh.new()
	_torus2.inner_radius = r * 0.5
	_torus2.outer_radius = r * 0.56
	_ring2.mesh = _torus2
	_ring2.position.y = 0.03
	_ring2_mat = _make_mat(0.5)
	_ring2.material_override = _ring2_mat
	add_child(_ring2)

	if _particle_style == "fall":
		_build_falling_particles(r)
	else:
		_build_rising_particles(r)

func _build_rising_particles(r: float):
	_particles = GPUParticles3D.new()
	_particles.position = Vector3(0, 0.05, 0)
	_particles.amount = 20
	_particles.lifetime = 1.1
	_particles.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r * 0.85
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.18, 0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.color = _color
	_particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = _color
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = _color
	pmat.emission_energy_multiplier = 2.2
	quad.material = pmat
	_particles.draw_pass_1 = quad
	add_child(_particles)

# Rain of Arrows — thin streaks raining down from above the zone, aligned
# to their fall direction so they read as arrows/bolts rather than generic
# floating motes. Spawns across the whole zone footprint continuously for
# as long as the effect lives.
func _build_falling_particles(r: float):
	_particles = GPUParticles3D.new()
	_particles.position = Vector3(0, 2.4, 0)
	_particles.amount = 28
	_particles.lifetime = 0.55
	_particles.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r * 0.8, 0.02, r * 0.8)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	pm.color = _color
	pm.set_particle_flag(ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	_particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.32)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = _color
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = _color
	pmat.emission_energy_multiplier = 2.4
	quad.material = pmat
	_particles.draw_pass_1 = quad
	add_child(_particles)

func _build_rect():
	var length = _size.x / CoordUtil.SIM_SCALE
	var width = _size.y / CoordUtil.SIM_SCALE

	_disc = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	_disc.mesh = plane
	_disc.position = Vector3(0, 0.02, -length * 0.5)
	_disc_mat = _make_mat(0.28)
	_disc_mat.emission_energy_multiplier = 0.9
	_disc.material_override = _disc_mat
	add_child(_disc)

	# Border made of thin boxes rather than a texture outline — cheap, and
	# consistent with the rest of the view layer's primitive-mesh-only style.
	_border_mat = _make_mat(0.95)
	_border_mat.emission_energy_multiplier = 2.2
	var edge_h := 0.03
	var edges = [
		{"size": Vector3(width, edge_h, 0.05), "pos": Vector3(0, 0.03, 0.0)},
		{"size": Vector3(width, edge_h, 0.05), "pos": Vector3(0, 0.03, -length)},
		{"size": Vector3(0.05, edge_h, length), "pos": Vector3(-width * 0.5, 0.03, -length * 0.5)},
		{"size": Vector3(0.05, edge_h, length), "pos": Vector3(width * 0.5, 0.03, -length * 0.5)},
	]
	for e in edges:
		var box := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = e["size"]
		box.mesh = box_mesh
		box.position = e["pos"]
		box.material_override = _border_mat
		add_child(box)
		_border.append(box)

func _process(delta):
	_age += delta
	var remain = _duration - _age
	if remain <= 0.0:
		queue_free()
		return
	var t = Time.get_ticks_msec() * 0.001
	if _shape == "circle":
		_animate_circle(t, remain)
	else:
		_animate_rect(remain)

func _animate_circle(t: float, remain: float):
	if _anim_style == "expand":
		# Shockwave: radius grows from a near-point out to full size with an
		# ease-out settle, instead of sitting at a fixed size the whole time.
		var growth = clamp(_age / max(0.05, _duration * 0.55), 0.0, 1.0)
		growth = 1.0 - pow(1.0 - growth, 2.0)
		var cur_r = lerp(_target_r * 0.12, _target_r, growth)
		_torus.inner_radius = cur_r * 0.93
		_torus.outer_radius = cur_r
		_torus2.inner_radius = cur_r * 0.5
		_torus2.outer_radius = cur_r * 0.56
		_disc_mesh.top_radius = cur_r
		_disc_mesh.bottom_radius = cur_r
	var pulse = 0.5 + 0.4 * sin(t * 3.0)
	var fade = 1.0 if remain > 0.4 else remain / 0.4
	_ring_mat.emission_energy_multiplier = (1.2 + pulse * 1.2) * fade
	_ring_mat.albedo_color.a = (0.55 + pulse * 0.35) * fade
	_ring2_mat.albedo_color.a = (0.35 + pulse * 0.25) * fade
	_ring2.rotation.y += get_process_delta_time() * 0.35
	_disc_mat.albedo_color.a = 0.12 * fade

func _animate_rect(remain: float):
	const INTRO := 0.12
	const OUTRO := 0.22
	var mult = 1.0
	if _age < INTRO:
		mult = _age / INTRO
	elif remain < OUTRO:
		mult = remain / OUTRO
	var pop = lerp(0.82, 1.0, min(_age / INTRO, 1.0))
	scale = Vector3(pop, 1.0, pop)
	var flash = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.02)
	_disc_mat.albedo_color.a = 0.28 * mult
	_border_mat.albedo_color.a = 0.95 * mult * flash
	_border_mat.emission_energy_multiplier = 2.2 * mult * flash
