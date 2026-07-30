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

# Per-class visual identity ("style" key): every zone used to be the same
# ring+disc+motes in a different color, so all AoEs read identically.
# "holy"   — orbiting vertical light pillars (Cleric: the only style that
#            leaves the ground)
# "arcane" — center flash column + one-shot radial glint detonation (Mage)
# "void"   — dark hovering core + particles spiraling INWARD, matching the
#            pull (Mage ult rift)
# "quake"  — one-shot arcing rock debris, the only style whose particles
#            obey gravity (Bruiser)
var _style := ""
var _spin: Node3D    # slow forward spinner (holy pillars + sun-wheel)
var _spin2: Node3D   # fast reverse spinner (arcane rune dashes)
var _extra_mats: Array[StandardMaterial3D] = []
var _extra_alphas: Array[float] = []
var _void_core: MeshInstance3D
var _sweep: MeshInstance3D   # rect: traveling light wave
var _sweep_mat: StandardMaterial3D
var _rect_len := 0.0

func setup(fx: Dictionary):
	_shape = fx["shape"]
	_size = fx["size"]
	_duration = fx["duration"]
	_color = fx["color"]
	_anim_style = fx.get("anim", "pulse")
	_particle_style = fx.get("particles", "rise")
	_style = fx.get("style", "")
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

	match _style:
		"holy": _build_holy_extras(r)
		"arcane": _build_arcane_extras(r)
		"void": _build_void_extras(r)
		"quake": _build_quake_extras(r)

# Cleric — Purify-matched look (per user feedback): thin streaks of light
# rising across the whole zone plus a slowly-spinning ground sun-wheel.
# The earlier tall pillars + central sky-beam read as "too crazy" — this is
# gentle sanctified ground instead of a light show.
func _build_holy_extras(r: float):
	# replace the generic rising motes with Purify-style thin light streaks
	if _particles != null:
		_particles.queue_free()
	_particles = GPUParticles3D.new()
	_particles.position = Vector3(0, 0.1, 0)
	_particles.amount = 30
	_particles.lifetime = 0.6
	_particles.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = r * 0.85
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.05
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp()
	_particles.process_material = pm
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.035, 0.42)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.vertex_color_use_as_albedo = true
	qmat.emission_enabled = true
	qmat.emission = _color
	qmat.emission_energy_multiplier = 2.0
	q2.material = qmat
	_particles.draw_pass_1 = q2
	add_child(_particles)

	# spinning sun-wheel of flat spokes on the ground — keeps the circle
	# reading as a holy sigil without any tall vertical elements
	_spin = Node3D.new()
	add_child(_spin)
	for i in 8:
		var holder := Node3D.new()
		holder.rotation.y = i * TAU / 8.0
		_spin.add_child(holder)
		var spoke := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(r * 0.42, 0.09)
		spoke.mesh = q
		spoke.rotation.x = -PI / 2.0
		spoke.position = Vector3(r * 0.34, 0.05, 0)
		var smat = _make_mat(0.5)
		smat.emission_energy_multiplier = 1.8
		spoke.material_override = smat
		holder.add_child(spoke)
		_extra_mats.append(smat)
		_extra_alphas.append(0.5)

# Mage — a one-shot ring of radially-flying glints plus a counter-rotating
# rune-dash circle: reads as an arcane detonation. (Its center flash column
# was cut alongside Consecrate's sky-beam — the tall-pillar look read as
# too busy in play.)
func _build_arcane_extras(r: float):
	var burst := GPUParticles3D.new()
	burst.position.y = 0.4
	burst.amount = 26
	burst.lifetime = 0.5
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = max(0.2, r * 0.2)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	pm.radial_accel = Vector2(14.0, 18.0)
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color_ramp = _fade_ramp()
	burst.process_material = pm
	burst.draw_pass_1 = _glint_quad(0.09)
	add_child(burst)

	# fast counter-rotating ring of rune dashes — the spell-circle signature
	# that makes it read as arcane rather than a plain expanding ring
	_spin2 = Node3D.new()
	add_child(_spin2)
	for i in 10:
		var holder := Node3D.new()
		holder.rotation.y = i * TAU / 10.0
		_spin2.add_child(holder)
		var dash := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.10, r * 0.30)
		dash.mesh = q
		dash.rotation.x = -PI / 2.0
		dash.position = Vector3(r * 0.72, 0.05, 0)
		var dmat = _make_mat(0.6)
		dmat.emission_energy_multiplier = 2.0
		dash.material_override = dmat
		holder.add_child(dash)
		_extra_mats.append(dmat)
		_extra_alphas.append(0.6)

# Mage ult rift — dark hovering core wrapped in a glow shell, with particles
# spiraling INWARD from well outside the marker (negative radial accel +
# tangential swirl), matching the ability's actual pull.
func _build_void_extras(r: float):
	_void_core = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r * 0.4
	s.height = r * 0.8
	_void_core.mesh = s
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.06, 0.0, 0.12)
	_void_core.material_override = core_mat
	_void_core.position.y = 0.5
	add_child(_void_core)

	var shell := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = r * 0.52
	s2.height = r * 1.04
	shell.mesh = s2
	var shell_mat = _make_mat(0.25)
	shell_mat.emission_energy_multiplier = 1.8
	shell.material_override = shell_mat
	shell.position.y = 0.5
	add_child(shell)
	_extra_mats.append(shell_mat)
	_extra_alphas.append(0.25)

	var swirl := GPUParticles3D.new()
	swirl.position.y = 0.4
	swirl.amount = 30
	swirl.lifetime = 0.8
	swirl.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = r * 2.2
	pm.emission_ring_inner_radius = r * 1.6
	pm.emission_ring_height = 0.3
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	pm.radial_accel = Vector2(-15.0, -13.0)
	pm.tangential_accel = Vector2(4.0, 6.0)
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp()
	swirl.process_material = pm
	swirl.draw_pass_1 = _glint_quad(0.08)
	add_child(swirl)

# Bruiser — one-shot arcing rock debris: the earthy, physical signature
# (the only zone style whose particles obey gravity).
func _build_quake_extras(r: float):
	var rocks := GPUParticles3D.new()
	rocks.position.y = 0.1
	rocks.amount = 22
	rocks.lifetime = 0.7
	rocks.one_shot = true
	rocks.explosiveness = 1.0
	rocks.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = r * 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.2
	pm.gravity = Vector3(0, -11.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	rocks.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.09, 0.09)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.35, 0.25)
	rock_mat.roughness = 1.0
	box.material = rock_mat
	rocks.draw_pass_1 = box
	add_child(rocks)

	# jagged dark ground cracks radiating from the impact point
	var im := ImmediateMesh.new()
	var crack := MeshInstance3D.new()
	crack.mesh = im
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.albedo_color = Color(0.08, 0.05, 0.03, 0.7)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	crack.material_override = cmat
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var a = i * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var tip = rng.randf_range(r * 0.55, r * 0.95)
		var base_w = rng.randf_range(0.10, 0.2)
		var dir = Vector3(cos(a), 0, sin(a))
		var perp = Vector3(-dir.z, 0, dir.x)
		im.surface_add_vertex(perp * base_w + Vector3(0, 0.045, 0))
		im.surface_add_vertex(-perp * base_w + Vector3(0, 0.045, 0))
		im.surface_add_vertex(dir * tip + Vector3(0, 0.045, 0))
	im.surface_end()
	add_child(crack)
	_extra_mats.append(cmat)
	_extra_alphas.append(0.7)

func _fade_ramp() -> GradientTexture1D:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(_color.r, _color.g, _color.b, 0.9))
	ramp.set_color(1, Color(_color.r, _color.g, _color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	return tex

func _glint_quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 1.8
	quad.material = mat
	return quad

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

	# traveling light wave — a bright bar sweeping from the caster's edge to
	# the far end, so the cast reads as a directional WAVE of light passing
	# over allies rather than a static glowing box
	_rect_len = length
	_sweep = MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(width, 0.55)
	_sweep.mesh = sq
	_sweep.rotation.x = -PI / 2.0
	_sweep_mat = _make_mat(0.75)
	_sweep_mat.emission_energy_multiplier = 3.0
	_sweep.material_override = _sweep_mat
	_sweep.position = Vector3(0, 0.06, 0)
	add_child(_sweep)

	# rising light streaks across the whole area
	_particles = GPUParticles3D.new()
	_particles.position = Vector3(0, 0.1, -length * 0.5)
	_particles.amount = 26
	_particles.lifetime = 0.5
	_particles.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.02, length * 0.45)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3.ZERO
	pm.color_ramp = _fade_ramp()
	_particles.process_material = pm
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.035, 0.42)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.vertex_color_use_as_albedo = true
	qmat.emission_enabled = true
	qmat.emission = _color
	qmat.emission_energy_multiplier = 2.0
	q2.material = qmat
	_particles.draw_pass_1 = q2
	add_child(_particles)

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

	# style extras: orbit the holy pillars/sun-wheel, counter-spin the rune
	# dashes, pulse the void core, and fade every extra out with the zone
	if _spin != null:
		_spin.rotation.y += get_process_delta_time() * 0.9
	if _spin2 != null:
		_spin2.rotation.y -= get_process_delta_time() * 2.2
	for i in _extra_mats.size():
		_extra_mats[i].albedo_color.a = _extra_alphas[i] * fade
	if _void_core != null:
		_void_core.scale = Vector3.ONE * (0.9 + 0.1 * sin(t * 9.0))

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
	if _sweep != null:
		var sweep_t = clamp(_age / max(0.05, _duration * 0.7), 0.0, 1.0)
		_sweep.position.z = -_rect_len * sweep_t
		_sweep_mat.albedo_color.a = 0.75 * mult
		_sweep_mat.emission_energy_multiplier = 3.0 * mult
