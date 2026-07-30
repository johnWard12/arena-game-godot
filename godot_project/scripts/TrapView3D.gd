extends Node3D
class_name TrapView3D
# 3D presentation for a Trap — a mechanical snare: a ring of metal jaw
# teeth around a glowing core. Teeth sit splayed flat and dim while the
# trap arms, spring near-upright with a bright "click" when it goes live,
# and SNAP inward with a flash when it fires. Mirrors ProjectileView3D's
# linger pattern: when the sim Trap frees itself, this view stays behind
# for a ~0.3s snap animation before freeing too. Pure observer of the
# already-simulated Trap, zero gameplay logic here.

const CoordUtil = preload("res://scripts/CoordUtil.gd")
const Trap = preload("res://scripts/Trap.gd")

var trap: Trap = null

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _teeth: Array[MeshInstance3D] = []
var _was_armed := false
var _snap := false
var _snap_t := 0.0

const TOOTH_SPLAYED := -0.55   # leaning outward, flat-ish (arming)
const TOOTH_READY   := 0.12    # near-upright (armed and live)
const TOOTH_SNAPPED := 1.25    # slammed inward (triggered)
const SNAP_DUR := 0.3

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

	# jaw teeth — dark metal cones ringing the snare
	var teeth_mat := StandardMaterial3D.new()
	teeth_mat.albedo_color = Color(0.35, 0.38, 0.36)
	teeth_mat.metallic = 0.6
	teeth_mat.roughness = 0.45
	for i in 8:
		var holder := Node3D.new()
		holder.rotation.y = i * TAU / 8.0
		add_child(holder)
		var tooth := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.045
		cone.height = 0.26
		tooth.mesh = cone
		tooth.material_override = teeth_mat
		tooth.position = Vector3(r * 0.85, 0.10, 0)
		tooth.rotation.z = TOOTH_SPLAYED
		holder.add_child(tooth)
		_teeth.append(tooth)

	# Tiny FX geometry — skip the shadow pass entirely.
	_no_shadows(self)

static func _no_shadows(node: Node):
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_no_shadows(c)

func _process(delta):
	if trap == null or not is_instance_valid(trap):
		_snap_anim(delta)
		return
	position = CoordUtil.to_world(trap.global_position, 0.05)

	# Enemy traps (relative to the human player's team 0) are fully hidden —
	# stepping on one is the discovery. The snap animation always shows.
	visible = trap.owner_entity == null or not is_instance_valid(trap.owner_entity) \
		or trap.owner_entity.team_id == 0

	var target_tilt = TOOTH_READY if trap.armed else TOOTH_SPLAYED
	for tooth in _teeth:
		tooth.rotation.z = lerpf(tooth.rotation.z, target_tilt, minf(1.0, delta * 10.0))

	if trap.armed:
		if not _was_armed:
			_was_armed = true
			_core_mat.emission_energy_multiplier = 5.0  # arming "click" flash
		var pulse = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
		_ring_mat.albedo_color.a = 0.7 * pulse
		_ring_mat.emission_energy_multiplier = 1.0 + pulse
		_core_mat.emission_energy_multiplier = lerpf(_core_mat.emission_energy_multiplier, 1.5 + pulse, minf(1.0, delta * 6.0))
	else:
		# dim and quiet while arming, so it reads as "not live yet"
		_ring_mat.albedo_color.a = 0.22
		_ring_mat.emission_energy_multiplier = 0.4
		_core_mat.emission_energy_multiplier = 0.6

# Jaws slam shut: teeth whip inward, the core flashes white-hot and swells,
# the ring blows outward and fades — then this view frees itself.
func _snap_anim(delta: float):
	if not _snap:
		_snap = true
		_snap_t = 0.0
		visible = true  # a hidden enemy trap reveals itself the moment it fires
	_snap_t += delta
	var t = _snap_t / SNAP_DUR
	if t >= 1.0:
		queue_free()
		return
	var close = minf(1.0, t * 2.6)
	for tooth in _teeth:
		tooth.rotation.z = lerpf(TOOTH_READY, TOOTH_SNAPPED, close)
	_core_mat.emission_energy_multiplier = 6.0 * (1.0 - t)
	_core.scale = Vector3.ONE * (1.0 + t * 1.5)
	_ring.scale = Vector3.ONE * (1.0 + t * 0.9)
	_ring_mat.albedo_color.a = 0.8 * (1.0 - t)
	_ring_mat.emission_energy_multiplier = 3.0 * (1.0 - t)
