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

var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring2: MeshInstance3D
var _ring2_mat: StandardMaterial3D
var _particles: GPUParticles3D
var _border: Array[MeshInstance3D] = []
var _border_mat: StandardMaterial3D

func setup(fx: Dictionary):
	_shape = fx["shape"]
	_size = fx["size"]
	_duration = fx["duration"]
	_color = fx["color"]
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

	_disc = MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = r
	disc_mesh.bottom_radius = r
	disc_mesh.height = 0.02
	_disc.mesh = disc_mesh
	_disc_mat = _make_mat(0.12)
	_disc_mat.emission_energy_multiplier = 0.5
	_disc.material_override = _disc_mat
	add_child(_disc)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.93
	torus.outer_radius = r
	_ring.mesh = torus
	_ring.position.y = 0.03
	_ring_mat = _make_mat(0.8)
	_ring_mat.emission_energy_multiplier = 1.6
	_ring.material_override = _ring_mat
	add_child(_ring)

	_ring2 = MeshInstance3D.new()
	var torus2 := TorusMesh.new()
	torus2.inner_radius = r * 0.5
	torus2.outer_radius = r * 0.56
	_ring2.mesh = torus2
	_ring2.position.y = 0.03
	_ring2_mat = _make_mat(0.5)
	_ring2.material_override = _ring2_mat
	add_child(_ring2)

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
