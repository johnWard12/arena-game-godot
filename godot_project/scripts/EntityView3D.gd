extends Node3D
class_name EntityView3D
# 3D presentation for an Entity, using real rigged/animated Quaternius RPG
# Character models (Warrior/Wizard/Monk) instead of procedural primitives.
# Mirrors the entity's already-simulated Vector2 state every frame; the
# entity itself has zero awareness this exists. Only ever instantiated by
# Main.gd — Simulate.gd never creates one, so headless balance runs are
# completely unaffected.
#
# Animation selection is driven entirely from existing Entity fields
# (swing_time_left/total, casting, hit_flash_left, stunned_time_left,
# parrying, velocity) — no changes to gameplay code, this stays a
# read-only observer like the rest of the view layer.

const CoordUtil = preload("res://scripts/CoordUtil.gd")
const RangerEntity = preload("res://scripts/RangerEntity.gd")
const ClericEntity = preload("res://scripts/ClericEntity.gd")

const KIT_PATH := "res://assets/RPG Characters - Nov 2020/glTF/"

# Per-class model config. measured_height/ground_offset come from the
# model's actual rest-pose AABB (probed once via a debug scene) rather than
# guessed — same approach used for the Castle Kit props.
# target_height bumped 30% per user feedback (models read too small).
const SIZE_BUMP := 1.3

const MODEL_CONFIG := {
	"duelist": {
		"scene_path": KIT_PATH + "Warrior.gltf",
		"measured_height": 2.974859,
		"ground_offset": 0.087153,
		"target_height": 1.6 * SIZE_BUMP,
		"attack_anim": "Sword_Attack",
		"cast_anim": "Idle_Attacking",
	},
	"mage": {
		"scene_path": KIT_PATH + "Wizard.gltf",
		"measured_height": 3.123627,
		"ground_offset": 0.129306,
		"target_height": 1.68 * SIZE_BUMP,
		"attack_anim": "Staff_Attack",
		"cast_anim": "Spell1",
	},
	"bruiser": {
		"scene_path": KIT_PATH + "Monk.gltf",
		"measured_height": 3.2853,
		"ground_offset": 0.337144,
		"target_height": 1.76 * SIZE_BUMP,
		"attack_anim": "Attack",
		"cast_anim": "Idle_Attacking",
	},
	"ranger": {
		"scene_path": KIT_PATH + "Ranger.gltf",
		"measured_height": 2.980963,
		"ground_offset": 0.000437,
		"target_height": 1.62 * SIZE_BUMP,
		"attack_anim": "Bow_Shoot",
		"cast_anim": "Idle_Attacking",
	},
	"cleric": {
		"scene_path": KIT_PATH + "Cleric.gltf",
		"measured_height": 3.035844,
		"ground_offset": -0.003267,
		"target_height": 1.66 * SIZE_BUMP,
		"attack_anim": "Staff_Attack",
		"cast_anim": "Spell1",
	},
}

var entity: Entity = null
var _cfg: Dictionary
var _model: Node3D
var _anim: AnimationPlayer
var _current_anim := ""
var _swing_was_active := false
var _death_timer := 0.0
var _was_alive := true

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

var _freeze_pivot: Node3D
var _freeze_shards: Array[MeshInstance3D] = []

var _bloodlust_particles: GPUParticles3D

var _shift_style := ""
var _shift_dome: MeshInstance3D
var _shift_dome_mat: StandardMaterial3D
var _shift_ring: MeshInstance3D
var _shift_ring_mat: StandardMaterial3D
var _shift_ring2: MeshInstance3D
var _shift_ring2_mat: StandardMaterial3D
var _shift_was_active := false

var _slow_ring: MeshInstance3D
var _slow_ring_mat: StandardMaterial3D

var _weaken_pivot: Node3D
var _weaken_shards: Array[MeshInstance3D] = []

# Bruiser-only Warcry self-buff aura — built only for the Monk model.
var _warcry_ring: MeshInstance3D
var _warcry_ring_mat: StandardMaterial3D
var _warcry_particles: GPUParticles3D

# Guardian's Bond (Cleric ultimate) — generic on every class, since the
# linked partner can be any class. bond_time_left/bond_partner live on the
# base Entity, not ClericEntity.
var _bond_ring: MeshInstance3D
var _bond_ring_mat: StandardMaterial3D
var _bond_beam: MeshInstance3D
var _bond_beam_mat: StandardMaterial3D

func setup(e: Entity):
	entity = e
	var key = "bruiser" if e is BruiserEntity else ("mage" if e is RangedEntity else ("ranger" if e is RangerEntity else ("cleric" if e is ClericEntity else "duelist")))
	_cfg = MODEL_CONFIG[key]

	var scene: PackedScene = load(_cfg["scene_path"])
	_model = scene.instantiate()
	add_child(_model)
	var s = _cfg["target_height"] / _cfg["measured_height"]
	_model.scale = Vector3.ONE * s
	_model.position = Vector3(0, _cfg["ground_offset"] * s, 0)
	# These models are authored facing the opposite convention from what the
	# root's look_at() assumes (root's -Z faces movement direction), so
	# every character appeared to walk/turn backwards. Correct with a fixed
	# 180-degree yaw on the model itself rather than touching look_at, since
	# look_at's convention is standard and used elsewhere (ProjectileView3D
	# has no facing concept, so this correction is local to the character
	# model only).
	_model.rotation.y = PI

	_anim = _find_anim_player(_model)
	if _anim != null:
		_anim.play("Idle")
		_current_anim = "Idle"

	# A colored ground ring under the character — the natural clothing
	# colors on these textured models don't contrast enough against the
	# warm-toned floor/obstacles, so characters were hard to spot. This
	# also restores per-class/status color identity (stun/parry/bloodlust
	# etc, via get_status_accent) that the old tinted-capsule placeholder
	# had and the real textured models can't be simply recolored for
	# without destroying their painted textures.
	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.42
	ring_mesh.outer_radius = 0.56
	_ring.mesh = ring_mesh
	_ring.position = Vector3(0, 0.02, 0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.emission_enabled = true
	_ring.material_override = _ring_mat
	add_child(_ring)

	_build_freeze_shards()
	_build_bloodlust_particles()
	_build_shift_shield(key)
	_build_slow_fx()
	_build_weaken_fx()
	_build_bond_fx()
	if key == "bruiser":
		_build_warcry_fx()
		_attach_bruiser_sword()

# The Monk model is an unarmed martial-arts rig (Bruiser's kit is a hammer
# thematically, but the model itself holds nothing), which read as strange
# for a "brawler" archetype. Its skeleton does have an empty "Weapon.R"
# socket bone though — every character in this pack shares that same rig
# convention (Warrior/Rogue/Wizard/Cleric each bake their own weapon onto
# it). Rather than modeling a new prop, this reuses the Warrior's actual
# sword mesh + its authored grip transform on that shared socket, so the
# fit should already be correct without hand-tuning an offset.
func _attach_bruiser_sword():
	var skeleton := _find_skeleton(_model)
	if skeleton == null or skeleton.find_bone("Weapon.R") < 0:
		return

	var warrior_scene: PackedScene = load(KIT_PATH + "Warrior.gltf")
	var warrior := warrior_scene.instantiate()
	var sword := warrior.find_child("Warrior_Sword", true, false)
	if sword == null:
		warrior.queue_free()
		return
	var sword_copy: Node3D = sword.duplicate()
	warrior.queue_free()

	var attachment := BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = "Weapon.R"
	attachment.add_child(sword_copy)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found != null:
			return found
	return null

# Freeze (Mage's Nova) — a slowly-spinning ring of little ice shards around
# the waist, distinct from the generic yellow stun-star read so a frozen
# target is unmistakable at a glance.
func _build_freeze_shards():
	_freeze_pivot = Node3D.new()
	_freeze_pivot.position = Vector3(0, 0.9, 0)
	_freeze_pivot.visible = false
	add_child(_freeze_pivot)

	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = Color(0.65, 0.92, 1.0, 0.9)
	shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_mat.emission_enabled = true
	shard_mat.emission = Color(0.6, 0.9, 1.0)
	shard_mat.emission_energy_multiplier = 1.6
	shard_mat.metallic = 0.1
	shard_mat.roughness = 0.05

	const SHARD_COUNT := 5
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.06
		cone.height = 0.24
		shard.mesh = cone
		var a = i * TAU / SHARD_COUNT
		shard.position = Vector3(cos(a) * 0.34, sin(a * 2.0) * 0.06, sin(a) * 0.34)
		shard.rotation.x = PI
		shard.material_override = shard_mat
		_freeze_pivot.add_child(shard)
		_freeze_shards.append(shard)

# Bloodlust (Duelist, granted on a landed parry) — rising red embers, since
# a ring-color tint alone was too subtle to read as a buff mid-fight.
func _build_bloodlust_particles():
	_bloodlust_particles = GPUParticles3D.new()
	_bloodlust_particles.position = Vector3(0, 0.1, 0)
	_bloodlust_particles.amount = 10
	_bloodlust_particles.lifetime = 0.6
	_bloodlust_particles.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.65
	pm.gravity = Vector3(0, 0.35, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.9, 0.1, 0.15)
	_bloodlust_particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.95, 0.15, 0.2)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(0.95, 0.15, 0.2)
	pmat.emission_energy_multiplier = 2.5
	quad.material = pmat
	_bloodlust_particles.draw_pass_1 = quad
	add_child(_bloodlust_particles)

# Shift (Iron Resolve / Barrier / Unbreakable) — one shared "shield up"
# Each class's Shift payoff is mechanically different (a defensive buff, an
# absorb shield, a CC-cleanse), and the old 2D art already gave each one its
# own distinct look (icy guard shimmer / barrier bubble / white flash rings)
# — so rather than one shared "shield's up" effect, mirror that per-class
# identity here.
func _build_shift_shield(key: String):
	_shift_style = key
	match key:
		"duelist": _build_iron_resolve_fx()
		"mage": _build_barrier_fx()
		"bruiser": _build_unbreakable_fx()
		"ranger": _build_camouflage_fx()
		"cleric": _build_barrier_fx()

# Duelist — Iron Resolve: a slim shimmering ring at chest height, cool blue,
# matching the old 2D "icy blue guard shimmer" flavor. No dome — this is a
# guard stance, not a shield bubble.
func _build_iron_resolve_fx():
	_shift_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.46
	ring_mesh.outer_radius = 0.50
	_shift_ring.mesh = ring_mesh
	_shift_ring.position = Vector3(0, 0.95, 0)
	_shift_ring_mat = StandardMaterial3D.new()
	_shift_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_ring_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.55)
	_shift_ring_mat.emission_enabled = true
	_shift_ring_mat.emission = Color(0.55, 0.75, 1.0)
	_shift_ring_mat.emission_energy_multiplier = 1.6
	_shift_ring.material_override = _shift_ring_mat
	_shift_ring.visible = false
	add_child(_shift_ring)

# Mage — Barrier: a translucent shield bubble + bright equator ring, matching
# the old 2D absorb-shield arcs. This is the one class whose Shift is
# literally a shield, so it's the only one that gets a dome.
func _build_barrier_fx():
	_shift_dome = MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.62
	dome_mesh.height = 0.62
	dome_mesh.is_hemisphere = true
	_shift_dome.mesh = dome_mesh
	_shift_dome.position = Vector3(0, 0.05, 0)
	_shift_dome_mat = StandardMaterial3D.new()
	_shift_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_dome_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.16)
	_shift_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_dome_mat.emission_enabled = true
	_shift_dome_mat.emission = Color(0.3, 0.7, 1.0)
	_shift_dome_mat.emission_energy_multiplier = 0.8
	_shift_dome.material_override = _shift_dome_mat
	_shift_dome.visible = false
	add_child(_shift_dome)

	_shift_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.58
	ring_mesh.outer_radius = 0.66
	_shift_ring.mesh = ring_mesh
	_shift_ring.position = Vector3(0, 0.05, 0)
	_shift_ring_mat = StandardMaterial3D.new()
	_shift_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_ring_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.85)
	_shift_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_ring_mat.emission_enabled = true
	_shift_ring_mat.emission = Color(0.5, 0.85, 1.0)
	_shift_ring_mat.emission_energy_multiplier = 1.8
	_shift_ring.material_override = _shift_ring_mat
	_shift_ring.visible = false
	add_child(_shift_ring)

# Bruiser — Unbreakable: two concentric white rings around the feet that
# strobe fast, matching the old 2D "white flash rings" (CC-cleanse should
# feel like a hard, aggressive pulse, not a calm shield glow). No dome.
func _build_unbreakable_fx():
	_shift_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.56
	_shift_ring.mesh = ring_mesh
	_shift_ring.position = Vector3(0, 0.05, 0)
	_shift_ring_mat = StandardMaterial3D.new()
	_shift_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_ring_mat.albedo_color = Color(1, 1, 1, 0.85)
	_shift_ring_mat.emission_enabled = true
	_shift_ring_mat.emission = Color(1, 1, 1)
	_shift_ring_mat.emission_energy_multiplier = 2.2
	_shift_ring.material_override = _shift_ring_mat
	_shift_ring.visible = false
	add_child(_shift_ring)

	_shift_ring2 = MeshInstance3D.new()
	var ring_mesh2 := TorusMesh.new()
	ring_mesh2.inner_radius = 0.7
	ring_mesh2.outer_radius = 0.74
	_shift_ring2.mesh = ring_mesh2
	_shift_ring2.position = Vector3(0, 0.05, 0)
	_shift_ring2_mat = StandardMaterial3D.new()
	_shift_ring2_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_ring2_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_ring2_mat.albedo_color = Color(1, 1, 1, 0.45)
	_shift_ring2_mat.emission_enabled = true
	_shift_ring2_mat.emission = Color(1, 1, 1)
	_shift_ring2_mat.emission_energy_multiplier = 1.4
	_shift_ring2.material_override = _shift_ring2_mat
	_shift_ring2.visible = false
	add_child(_shift_ring2)

# Ranger — Camouflage: a soft, low-key green ground shimmer — this is a
# fade into the terrain, not a shield popping up, so no dome and a dimmer
# pulse than the other three.
func _build_camouflage_fx():
	_shift_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.46
	ring_mesh.outer_radius = 0.50
	_shift_ring.mesh = ring_mesh
	_shift_ring.position = Vector3(0, 0.05, 0)
	_shift_ring_mat = StandardMaterial3D.new()
	_shift_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shift_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shift_ring_mat.albedo_color = Color(0.4, 0.9, 0.4, 0.5)
	_shift_ring_mat.emission_enabled = true
	_shift_ring_mat.emission = Color(0.4, 0.9, 0.4)
	_shift_ring_mat.emission_energy_multiplier = 1.4
	_shift_ring.material_override = _shift_ring_mat
	_shift_ring.visible = false
	add_child(_shift_ring)

# Slow — generic debuff shared by several abilities (Duelist's A1/Sword
# Throw, Mage's Bolt, Bruiser's Tremor). A dull frost ring at the feet so a
# slowed target is never just "moving weirdly for no visible reason".
func _build_slow_fx():
	_slow_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.40
	ring_mesh.outer_radius = 0.46
	_slow_ring.mesh = ring_mesh
	_slow_ring.position = Vector3(0, 0.03, 0)
	_slow_ring_mat = StandardMaterial3D.new()
	_slow_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slow_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slow_ring_mat.albedo_color = Color(0.55, 0.65, 0.75, 0.55)
	_slow_ring_mat.emission_enabled = true
	_slow_ring_mat.emission = Color(0.5, 0.7, 0.85)
	_slow_ring_mat.emission_energy_multiplier = 0.8
	_slow_ring.material_override = _slow_ring_mat
	_slow_ring.visible = false
	add_child(_slow_ring)

# Weakened — generic outgoing-damage debuff (currently only Bruiser's
# Warcry inflicts this, on the opponent). Small dark-red spikes drooping
# around the waist, reading as "this hit will do less than normal".
func _build_weaken_fx():
	_weaken_pivot = Node3D.new()
	_weaken_pivot.position = Vector3(0, 0.85, 0)
	_weaken_pivot.visible = false
	add_child(_weaken_pivot)

	var shard_mat := StandardMaterial3D.new()
	shard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_mat.albedo_color = Color(0.55, 0.08, 0.08, 0.85)
	shard_mat.emission_enabled = true
	shard_mat.emission = Color(0.6, 0.1, 0.08)
	shard_mat.emission_energy_multiplier = 1.2

	const SHARD_COUNT := 4
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.0
		cone.height = 0.2
		shard.mesh = cone
		var a = i * TAU / SHARD_COUNT
		shard.position = Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)
		shard.material_override = shard_mat
		_weaken_pivot.add_child(shard)
		_weaken_shards.append(shard)

# Warcry (Bruiser only) — a deep-red war-drum pulse around the chest plus
# rising embers, so the self-buff window is as visible to the Bruiser as
# the enemy debuff marker is to their target.
func _build_warcry_fx():
	_warcry_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.46
	ring_mesh.outer_radius = 0.52
	_warcry_ring.mesh = ring_mesh
	_warcry_ring.position = Vector3(0, 0.95, 0)
	_warcry_ring_mat = StandardMaterial3D.new()
	_warcry_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warcry_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warcry_ring_mat.albedo_color = Color(0.9, 0.2, 0.1, 0.6)
	_warcry_ring_mat.emission_enabled = true
	_warcry_ring_mat.emission = Color(0.9, 0.25, 0.1)
	_warcry_ring_mat.emission_energy_multiplier = 1.6
	_warcry_ring.material_override = _warcry_ring_mat
	_warcry_ring.visible = false
	add_child(_warcry_ring)

	_warcry_particles = GPUParticles3D.new()
	_warcry_particles.position = Vector3(0, 0.1, 0)
	_warcry_particles.amount = 12
	_warcry_particles.lifetime = 0.55
	_warcry_particles.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.9, 0.3, 0.05)
	_warcry_particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.95, 0.35, 0.05)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.emission_enabled = true
	pmat.emission = Color(0.95, 0.35, 0.05)
	pmat.emission_energy_multiplier = 2.2
	quad.material = pmat
	_warcry_particles.draw_pass_1 = quad
	add_child(_warcry_particles)

# Guardian's Bond — a rotating gold ring on each linked entity (so it's
# visible even when there's no ally in range and the Cleric self-links),
# plus a beam tying the pair together when there is a partner. The old
# version had zero visual at all: the only tell was a stat change nobody
# could actually see mid-fight.
func _build_bond_fx():
	_bond_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.58
	_bond_ring.mesh = ring_mesh
	_bond_ring.position = Vector3(0, 0.62, 0)
	_bond_ring_mat = StandardMaterial3D.new()
	_bond_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bond_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bond_ring_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.6)
	_bond_ring_mat.emission_enabled = true
	_bond_ring_mat.emission = Color(1.0, 0.9, 0.5)
	_bond_ring_mat.emission_energy_multiplier = 1.8
	_bond_ring.material_override = _bond_ring_mat
	_bond_ring.visible = false
	add_child(_bond_ring)

	# The beam connects two potentially distant entities, so it must live
	# outside this node's own transform (which tracks — and rotates with —
	# this character specifically). It's a sibling under world_3d instead.
	_bond_beam = MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.05, 0.05, 1.0)
	_bond_beam.mesh = beam_mesh
	_bond_beam_mat = StandardMaterial3D.new()
	_bond_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bond_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bond_beam_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.5)
	_bond_beam_mat.emission_enabled = true
	_bond_beam_mat.emission = Color(1.0, 0.9, 0.5)
	_bond_beam_mat.emission_energy_multiplier = 1.6
	_bond_beam.material_override = _bond_beam_mat
	_bond_beam.visible = false
	get_parent().add_child(_bond_beam)

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found != null:
			return found
	return null

func _play(anim_name: String, blend: float = 0.15):
	if _anim == null or _current_anim == anim_name or not _anim.has_animation(anim_name):
		return
	_anim.play(anim_name, blend)
	_current_anim = anim_name

func _force_play(anim_name: String, blend: float = 0.08):
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_anim.play(anim_name, blend)
	_current_anim = anim_name

func _process(delta):
	if entity == null or not is_instance_valid(entity):
		visible = false
		return

	if not entity.alive:
		_animate_death(delta)
		return
	_was_alive = true
	_death_timer = 0.0
	visible = true
	scale = Vector3.ONE
	rotation = Vector3.ZERO

	position = CoordUtil.to_world(entity.global_position)
	var look_dir = Vector3(entity.facing.x, 0.0, entity.facing.y)
	if look_dir.length() > 0.001:
		look_at(position + look_dir, Vector3.UP)

	var accent = entity.get_status_accent(entity.base_color)
	_ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.7)
	_ring_mat.emission = accent
	_ring_mat.emission_energy_multiplier = 1.8 if entity.hit_flash_left > 0 else 0.9

	_update_status_fx(delta)
	_update_animation()

func _update_status_fx(delta: float):
	_freeze_pivot.visible = entity.freeze_time_left > 0
	if entity.freeze_time_left > 0:
		_freeze_pivot.rotation.y += delta * 0.8
		var chill = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		for shard in _freeze_shards:
			shard.scale = Vector3.ONE * (0.85 + chill * 0.25)

	_bloodlust_particles.emitting = entity.bloodlust_time_left > 0

	var shift_active = entity.get_shift_active()
	if _shift_ring != null:
		_shift_ring.visible = shift_active
	if _shift_dome != null:
		_shift_dome.visible = shift_active
	if _shift_ring2 != null:
		_shift_ring2.visible = shift_active
	if shift_active:
		match _shift_style:
			"duelist": _animate_iron_resolve_fx()
			"mage": _animate_barrier_fx(delta)
			"bruiser": _animate_unbreakable_fx()
			"ranger": _animate_camouflage_fx()
	_shift_was_active = shift_active

	_slow_ring.visible = entity.slowed_time_left > 0
	if entity.slowed_time_left > 0:
		_slow_ring.rotation.y += delta * 0.5
		var drag = 0.6 + 0.3 * sin(Time.get_ticks_msec() * 0.004)
		_slow_ring_mat.albedo_color.a = 0.35 + drag * 0.2

	_weaken_pivot.visible = entity.outgoing_dmg_debuff_time_left > 0
	if entity.outgoing_dmg_debuff_time_left > 0:
		_weaken_pivot.rotation.y -= delta * 0.6
		var sag = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.007)
		for shard in _weaken_shards:
			shard.position.y = -sag * 0.08

	if _warcry_ring != null:
		var bruiser := entity as BruiserEntity
		var warcry_active = bruiser != null and bruiser.warcry_time_left > 0
		_warcry_ring.visible = warcry_active
		_warcry_particles.emitting = warcry_active
		if warcry_active:
			var t = Time.get_ticks_msec() * 0.005
			var pulse = 0.5 + 0.4 * sin(t * 4.0)
			_warcry_ring_mat.emission_energy_multiplier = 1.2 + pulse * 1.2
			_warcry_ring_mat.albedo_color.a = 0.4 + pulse * 0.35

	_update_bond_fx(delta)

# Guardian's Bond — ring shows on both linked entities; the beam is only
# drawn once per pair (by whichever entity has the lower instance id) so
# two overlapping full-length beams don't double up their brightness.
func _update_bond_fx(delta: float):
	var bonded = entity.bond_time_left > 0
	_bond_ring.visible = bonded
	if bonded:
		_bond_ring.rotation.y += delta * 1.2
		var pulse = 0.6 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
		_bond_ring_mat.emission_energy_multiplier = 1.4 + pulse
		_bond_ring_mat.albedo_color.a = 0.45 + pulse * 0.3

	var partner = entity.bond_partner
	var show_beam = bonded and partner != null and is_instance_valid(partner) and partner.alive \
		and entity.get_instance_id() < partner.get_instance_id()
	_bond_beam.visible = show_beam
	if show_beam:
		var a = CoordUtil.to_world(entity.global_position, 0.9)
		var b = CoordUtil.to_world(partner.global_position, 0.9)
		var dist = a.distance_to(b)
		_bond_beam.global_position = (a + b) * 0.5
		if dist > 0.02:
			_bond_beam.look_at(b, Vector3.UP)
		var beam_mesh: BoxMesh = _bond_beam.mesh
		beam_mesh.size = Vector3(0.05, 0.05, dist)
		var pulse2 = 0.6 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
		_bond_beam_mat.emission_energy_multiplier = 1.2 + pulse2 * 0.8
		_bond_beam_mat.albedo_color.a = 0.35 + pulse2 * 0.25

# Iron Resolve — a gentle shimmer: alpha flicker + slow rotation, no pop.
func _animate_iron_resolve_fx():
	_shift_ring.rotation.y += 0.015
	var shimmer = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.012)
	_shift_ring_mat.emission_energy_multiplier = 1.2 + shimmer * 0.8
	_shift_ring_mat.albedo_color.a = 0.4 + shimmer * 0.25

# Barrier — the bubble breathes: soft scale/opacity pulse, like an absorb
# shield holding steady rather than reacting to anything.
func _animate_barrier_fx(delta: float):
	if not _shift_was_active:
		_shift_ring.scale = Vector3.ONE * 0.6
		_shift_dome.scale = Vector3.ONE * 0.6
	_shift_ring.scale = _shift_ring.scale.lerp(Vector3.ONE, delta * 6.0)
	_shift_dome.scale = _shift_dome.scale.lerp(Vector3.ONE, delta * 6.0)
	var pulse = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.005)
	_shift_dome_mat.albedo_color.a = 0.10 + pulse * 0.10
	_shift_ring_mat.emission_energy_multiplier = 1.4 + pulse * 1.0

# Unbreakable — a hard, fast double-ring strobe (matches the old 2D "white
# flash rings"), with the outer ring lagging the inner for a shockwave read.
func _animate_unbreakable_fx():
	var t = Time.get_ticks_msec() * 0.006
	var flash = 0.55 + 0.45 * sin(t * 5.0)
	_shift_ring_mat.emission_energy_multiplier = 1.6 + flash * 1.6
	_shift_ring_mat.albedo_color.a = 0.6 + flash * 0.35
	var flash2 = 0.5 + 0.5 * sin(t * 5.0 - 0.6)
	_shift_ring2_mat.emission_energy_multiplier = 0.8 + flash2 * 1.2
	_shift_ring2_mat.albedo_color.a = 0.25 + flash2 * 0.3

# Camouflage — slow, low-key pulse (fading into the terrain, not popping).
func _animate_camouflage_fx():
	var pulse = 0.4 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
	_shift_ring_mat.emission_energy_multiplier = 0.8 + pulse * 0.8
	_shift_ring_mat.albedo_color.a = 0.3 + pulse * 0.25

func _update_animation():
	# Priority: attack swing > just got hit > cast wind-up > parry guard >
	# stunned > movement > idle.
	var swinging = entity.swing_time_left > 0 and entity.swing_total > 0
	if swinging:
		if not _swing_was_active:
			_force_play(_cfg["attack_anim"])
		_swing_was_active = true
		return
	_swing_was_active = false

	if entity.hit_flash_left > 0.15:
		_play("RecieveHit", 0.05)
		return
	if entity.casting != null:
		_play(_cfg["cast_anim"], 0.1)
		return
	if entity.parrying:
		_play("Idle_Weapon", 0.1)
		return
	if entity.stunned_time_left > 0:
		_play("RecieveHit", 0.1)
		return

	var max_speed = entity.speed_override if entity.speed_override > 0.0 else Entity.MAX_SPEED
	var speed_pct = entity.velocity.length() / max_speed
	if speed_pct > 0.55:
		_play("Run", 0.15)
	elif speed_pct > 0.15:
		_play("Walk", 0.15)
	else:
		_play("Idle", 0.15)

func _animate_death(delta: float):
	if _was_alive:
		_was_alive = false
		_death_timer = 0.0
		_force_play("Death", 0.1)
		# _update_bond_fx() stops running once dead — the beam is a sibling
		# under world_3d, not a child, so it wouldn't otherwise disappear
		# with the rest of this view.
		_bond_ring.visible = false
		_bond_beam.visible = false
	visible = true
	position = CoordUtil.to_world(entity.global_position)
	_death_timer += delta
	if _death_timer >= 2.0:
		visible = false
