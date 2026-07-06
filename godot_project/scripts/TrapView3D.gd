extends Node3D
class_name TrapView3D
# 3D presentation for a Trap — a flat ground ring + small core, dim while
# arming and pulsing once live. Mirrors ProjectileView3D's shape: pure
# observer of the already-simulated Trap, zero gameplay logic here.

const CoordUtil = preload("res://scripts/CoordUtil.gd")
const Trap = preload("res://scripts/Trap.gd")

var trap: Trap = null

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D

func setup(t: Trap):
	trap = t
	var col: Color = t.trap_color
	var r: float = t.radius / 90.0  # sim-units -> meters, matches ProjectileView3D's scale

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.85
	torus.outer_radius = r
	_ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = col
	_ring_mat.emission_energy_multiplier = 1.2
	_ring.material_override = _ring_mat
	add_child(_ring)

	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r * 0.18
	sphere.height = r * 0.36
	_core.mesh = sphere
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = col
	_core_mat.emission_enabled = true
	_core_mat.emission = col
	_core_mat.emission_energy_multiplier = 2.0
	_core.material_override = _core_mat
	add_child(_core)

func _process(_delta):
	if trap == null or not is_instance_valid(trap):
		queue_free()
		return
	position = CoordUtil.to_world(trap.global_position, 0.05)

	if trap.armed:
		var pulse = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
		_ring_mat.albedo_color.a = 0.7 * pulse
		_ring_mat.emission_energy_multiplier = 1.0 + pulse
		_core_mat.emission_energy_multiplier = 1.5 + pulse
	else:
		_ring_mat.albedo_color.a = 0.25
		_ring_mat.emission_energy_multiplier = 0.4
		_core_mat.emission_energy_multiplier = 0.6
