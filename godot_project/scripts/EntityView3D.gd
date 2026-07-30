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
# Per-instance duplicates of every material on this character's meshes —
# lets this view flash/fade ITS model without affecting other fighters
# instanced from the same GLTF (imported materials are shared resources).
var _char_mats: Array[BaseMaterial3D] = []
var _anim: AnimationPlayer
var _current_anim := ""
var _swing_was_active := false
var _death_timer := 0.0
var _was_alive := true

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

# Melee slash arc — an ImmediateMesh fan rebuilt each frame while a swing is
# active, sweeping across the swing's real arc (start angle/span/progress all
# come from the sim's swing state, so the visual matches the hit exactly).
var _slash: MeshInstance3D
var _slash_mesh: ImmediateMesh
var _slash_mat: StandardMaterial3D

# Cross-cutting character FX, each shared by several abilities:
# - motion trail: team-color streaks shed during any dash/lunge (Duelist
#   Lunge, Bruiser Seismic, Ranger Disengage recoil, the universal dash)
# - cast gather: particles converging on the chest during any wind-up
# - parry ring: a bright guard ring during the parry window
var _motion_trail: GPUParticles3D
var _cast_gather: GPUParticles3D
var _parry_ring: MeshInstance3D
var _parry_ring_mat: StandardMaterial3D

var _freeze_pivot: Node3D
var _freeze_shards: Array[MeshInstance3D] = []

var _bloodlust_particles: GPUParticles3D

var _bladestorm_particles: GPUParticles3D
var _bladestorm_light: OmniLight3D

# Gesture fallback for instant abilities (see _update_animation): commit
# tracking to detect an ability firing with no cast and no swing of its own.
var _last_commit := 0.0
var _gesture_left := 0.0

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
	_collect_char_materials(_model)
	_build_slash_arc()
	_build_motion_trail()
	_build_cast_gather()
	_build_parry_ring()

	_anim = _find_anim_player(_model)
	if _anim != null:
		# Imported clips default to LOOP_NONE, so a continuously-held state
		# like moving in a straight line would play Run/Walk/Idle once and
		# then freeze on its last frame while the character kept gliding via
		# position updates — _play()'s _current_anim guard never noticed
		# because the requested animation name hadn't changed. Movement/idle
		# poses need to actually loop; one-shot clips (attacks, hit reacts,
		# death) are left alone since holding their last frame is correct.
		for loop_anim in ["Idle", "Walk", "Run", "Idle_Weapon"]:
			if _anim.has_animation(loop_anim):
				_anim.get_animation(loop_anim).loop_mode = Animation.LOOP_LINEAR
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
		_attach_bruiser_shield()
	if key == "duelist":
		_build_bladestorm_fx()

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

# Unlike the sword, there's no pre-authored socket to reuse here — no
# character in this pack holds anything in their left hand, so "Fist.L"
# has no "Weapon.L" equivalent with a known-good grip transform sitting
# next to it. This builds a round shield from primitive meshes (same
# style as the rest of this view layer's VFX) and hand-tunes a
# best-effort local offset/rotation for a natural held pose. The exact
# fit is a guess without a reference transform to copy — if it looks off
# in-game, the position/rotation_degrees values right below are the ones
# to nudge.
func _attach_bruiser_shield():
	var skeleton := _find_skeleton(_model)
	if skeleton == null or skeleton.find_bone("Fist.L") < 0:
		return

	var attachment := BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = "Fist.L"

	var shield := Node3D.new()
	attachment.add_child(shield)
	shield.position = Vector3(0.0, 0.0, 0.1)
	shield.rotation_degrees = Vector3(0, 90, 90)

	# Sized in the model's own native (pre-scale) units so it comes out to
	# roughly a 0.38m real-world radius once the model's uniform scale
	# (target_height / measured_height, ~0.7 for the Monk) is applied.
	var r := 0.56
	var thickness := 0.12

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = r
	disc_mesh.bottom_radius = r
	disc_mesh.height = thickness
	disc.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.72, 0.73, 0.76)
	disc_mat.metallic = 0.6
	disc_mat.roughness = 0.35
	disc.material_override = disc_mat
	shield.add_child(disc)

	var boss := MeshInstance3D.new()
	var boss_mesh := CylinderMesh.new()
	boss_mesh.top_radius = r * 0.22
	boss_mesh.bottom_radius = r * 0.22
	boss_mesh.height = thickness * 1.6
	boss.mesh = boss_mesh
	boss.position.y = thickness * 0.5
	var boss_mat := StandardMaterial3D.new()
	boss_mat.albedo_color = Color(0.85, 0.85, 0.88)
	boss_mat.metallic = 0.7
	boss_mat.roughness = 0.25
	boss.material_override = boss_mat
	shield.add_child(boss)

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

# Duelist — Bladestorm (ult): previously had NO 3D visual at all (its only
# feedback was the old 2D-only "orbiting ghost swords" art, which lives in
# a code path that never runs once use_3d_view is on — the same class of
# bug Void Collapse/Rain of Arrows had before their telegraphs moved to
# real 3D effects). Small bright-gold blade shapes bursting outward
# continuously while active, so the ultimate reads as clearly "on" instead
# of only being felt through its AoE tick damage — same color language as
# the Duelist's combo-pip sword icon, shot outward rather than a diffuse
# glow so it reads as "swords flying out."
func _build_bladestorm_fx():
	_bladestorm_particles = GPUParticles3D.new()
	_bladestorm_particles.position = Vector3(0, 0.9, 0)
	_bladestorm_particles.amount = 14
	_bladestorm_particles.lifetime = 0.5
	_bladestorm_particles.emitting = false
	# local_coords: blades simulate in the character's own space, so the ring
	# stays perfectly centered on him even at full sprint. In world space,
	# his movement speed added to backward-flying blades (and subtracted from
	# forward ones) skewed the whole storm toward his front while moving.
	_bladestorm_particles.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 1, 0)
	# spread=180 (the max) covers the full sphere of possible directions
	# before flatness=1.0 collapses that down onto the horizontal plane —
	# spread=90 alone left a directional bias toward "up" that read as a
	# narrower fan instead of a complete ring around the character.
	pm.spread = 180.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 4.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	# Blood-red blades (was gold energy motes) — with align-to-velocity each
	# elongated quad flies point-first, reading as swords hurled out of the
	# spin in a full 360. Fewer, bigger blades read as swords instead of
	# shrapnel.
	pm.color = Color(1.0, 0.22, 0.22)
	pm.set_particle_flag(ParticleProcessMaterial.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	_bladestorm_particles.process_material = pm
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(1.0, 0.3, 0.3)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmat.vertex_color_use_as_albedo = true
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.12, 0.18)
	pmat.emission_energy_multiplier = 3.0
	_bladestorm_particles.draw_pass_1 = _make_blade_mesh(pmat)
	add_child(_bladestorm_particles)

# A flat sword silhouette — blade, tapered tip, crossguard, grip — built as
# one ArrayMesh for the storm's particle draw pass. +Y is the direction of
# flight, so align-to-velocity sends every sword flying point-first.
func _make_blade_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads = [
		# blade body
		[Vector2(-0.09, 0.18), Vector2(0.09, 0.18), Vector2(0.055, 0.92), Vector2(-0.055, 0.92)],
		# crossguard
		[Vector2(-0.22, 0.10), Vector2(0.22, 0.10), Vector2(0.22, 0.20), Vector2(-0.22, 0.20)],
		# grip + pommel
		[Vector2(-0.045, -0.16), Vector2(0.045, -0.16), Vector2(0.045, 0.10), Vector2(-0.045, 0.10)],
	]
	for q in quads:
		st.add_vertex(Vector3(q[0].x, q[0].y, 0))
		st.add_vertex(Vector3(q[1].x, q[1].y, 0))
		st.add_vertex(Vector3(q[2].x, q[2].y, 0))
		st.add_vertex(Vector3(q[0].x, q[0].y, 0))
		st.add_vertex(Vector3(q[2].x, q[2].y, 0))
		st.add_vertex(Vector3(q[3].x, q[3].y, 0))
	# tapered point
	st.add_vertex(Vector3(-0.055, 0.92, 0))
	st.add_vertex(Vector3(0.055, 0.92, 0))
	st.add_vertex(Vector3(0.0, 1.25, 0))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh

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

# Duplicate every character material into a per-instance copy (see
# _char_mats) and even out the imported surface response — full roughness,
# zero metallic — so the toon-textured models read as soft matte cloth/armor
# under ACES instead of slightly plasticky.
func _collect_char_materials(node: Node):
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var src: Material = node.get_active_material(i)
			if src is BaseMaterial3D:
				var dup: BaseMaterial3D = src.duplicate()
				dup.roughness = 1.0
				dup.metallic = 0.0
				node.set_surface_override_material(i, dup)
				_char_mats.append(dup)
	for child in node.get_children():
		_collect_char_materials(child)

# Team-color streaks shed in world space while dashing/lunging — sells the
# burst of speed on every gap-closer and dodge in the game.
func _build_motion_trail():
	_motion_trail = GPUParticles3D.new()
	_motion_trail.amount = 30
	_motion_trail.lifetime = 0.3
	_motion_trail.local_coords = false
	_motion_trail.emitting = false
	_motion_trail.position = Vector3(0, 0.55, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var col = entity.base_color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.8))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_motion_trail.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.vertex_color_use_as_albedo = true
	qmat.emission_enabled = true
	qmat.emission = col
	qmat.emission_energy_multiplier = 1.5
	quad.material = qmat
	_motion_trail.draw_pass_1 = quad
	add_child(_motion_trail)

# Warm motes converging on the chest during any cast wind-up — every
# wind-up ability across every class now telegraphs "charging something".
func _build_cast_gather():
	_cast_gather = GPUParticles3D.new()
	_cast_gather.amount = 16
	_cast_gather.lifetime = 0.35
	_cast_gather.emitting = false
	_cast_gather.position = Vector3(0, 1.0, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.7
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.1
	pm.radial_accel = Vector2(-16.0, -12.0)
	var gcol = Color(1.0, 0.9, 0.6)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(gcol.r, gcol.g, gcol.b, 0.0))
	ramp.set_color(1, Color(gcol.r, gcol.g, gcol.b, 0.9))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	_cast_gather.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.vertex_color_use_as_albedo = true
	qmat.emission_enabled = true
	qmat.emission = gcol
	qmat.emission_energy_multiplier = 2.0
	quad.material = qmat
	_cast_gather.draw_pass_1 = quad
	add_child(_cast_gather)

# Bright blue guard ring at chest height during the parry window — the 3D
# read of the old 2D-only parry circle.
func _build_parry_ring():
	_parry_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.56
	_parry_ring.mesh = torus
	_parry_ring.position = Vector3(0, 0.9, 0)
	_parry_ring_mat = StandardMaterial3D.new()
	_parry_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_parry_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_parry_ring_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.7)
	_parry_ring_mat.emission_enabled = true
	_parry_ring_mat.emission = Color(0.3, 0.7, 1.0)
	_parry_ring_mat.emission_energy_multiplier = 2.0
	_parry_ring.material_override = _parry_ring_mat
	_parry_ring.visible = false
	add_child(_parry_ring)

func _build_slash_arc():
	_slash_mesh = ImmediateMesh.new()
	_slash = MeshInstance3D.new()
	_slash.mesh = _slash_mesh
	# top_level: the arc's vertices are built in absolute world space from
	# sim angles, so it must NOT inherit this node's look_at rotation.
	_slash.top_level = true
	_slash_mat = StandardMaterial3D.new()
	_slash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_slash_mat.emission_enabled = true
	_slash.material_override = _slash_mat
	add_child(_slash)

func _update_slash_arc():
	var swinging = entity.swing_time_left > 0 and entity.swing_total > 0
	if not swinging:
		_slash.visible = false
		return
	_slash.visible = true
	var progress = 1.0 - (entity.swing_time_left / entity.swing_total)
	var col = entity.base_color
	var alpha = 0.5 * (1.0 - progress * 0.6)
	_slash_mat.albedo_color = Color(col.r, col.g, col.b, alpha)
	_slash_mat.emission = col
	_slash_mat.emission_energy_multiplier = 1.4

	var start_a = entity.swing_start_angle
	var swept = entity.swing_arc_span * progress
	var inner = 40.0   # sim units
	var outer = 145.0
	var steps = 12
	_slash_mesh.clear_surfaces()
	_slash_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in steps + 1:
		var a = start_a + swept * (float(s) / steps)
		var dir2 = Vector2(cos(a), sin(a))
		_slash_mesh.surface_add_vertex(CoordUtil.to_world(entity.global_position + dir2 * inner, 0.85))
		_slash_mesh.surface_add_vertex(CoordUtil.to_world(entity.global_position + dir2 * outer, 0.85))
	_slash_mesh.surface_end()

# White-hot flash on the actual model when hit — far more readable than a
# 2D overlay circle, and localized to this instance via _char_mats. Also
# owns Camouflage's ghosting: the model itself goes translucent while
# invisible_time_left runs, instead of only showing a shimmer ring.
func _update_char_flash():
	var flash = clamp(entity.hit_flash_left / 0.25, 0.0, 1.0)
	var invis = entity.invisible_time_left > 0
	for mat in _char_mats:
		if flash > 0.0:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.97, 0.92)
			mat.emission_energy_multiplier = flash * 1.6
		else:
			mat.emission_enabled = false
		if invis:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.35
		elif mat.albedo_color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = 1.0

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
	# True stealth: a cloaked ENEMY (relative to the human player's team 0)
	# disappears entirely — model, ring, trails, everything under this view.
	# Your own team's cloaked Ranger stays visible as a translucent ghost
	# (see _update_char_flash).
	visible = not (entity.invisible_time_left > 0 and entity.team_id != 0)
	scale = Vector3.ONE
	rotation = Vector3.ZERO

	position = CoordUtil.to_world(entity.global_position)
	# Knocked-up fighters actually leave the ground now — an arc that peaks
	# mid-knockup — instead of being "airborne" only in the sim's numbers.
	if entity.knockup_time_left > 0:
		var kpct = clamp(entity.knockup_time_left / Entity.KNOCKUP_DUR, 0.0, 1.0)
		position.y += sin(kpct * PI) * 0.85
	var look_dir = Vector3(entity.facing.x, 0.0, entity.facing.y)
	if look_dir.length() > 0.001:
		look_at(position + look_dir, Vector3.UP)

	var accent = entity.get_status_accent(entity.base_color)
	_ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.7)
	_ring_mat.emission = accent
	_ring_mat.emission_energy_multiplier = 1.8 if entity.hit_flash_left > 0 else 0.9

	_update_status_fx(delta)
	_update_char_flash()
	_update_slash_arc()
	_update_animation()

func _update_status_fx(delta: float):
	_freeze_pivot.visible = entity.freeze_time_left > 0
	if entity.freeze_time_left > 0:
		_freeze_pivot.rotation.y += delta * 0.8
		var chill = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		for shard in _freeze_shards:
			shard.scale = Vector3.ONE * (0.85 + chill * 0.25)

	_bloodlust_particles.emitting = entity.bloodlust_time_left > 0

	_motion_trail.emitting = entity.dashing or entity.lunging
	_cast_gather.emitting = entity.casting != null
	_parry_ring.visible = entity.parrying
	if entity.parrying:
		_parry_ring_mat.emission_energy_multiplier = 2.0 + sin(Time.get_ticks_msec() * 0.03)
		_parry_ring.rotation.y += delta * 4.0

	if _bladestorm_particles != null:
		var storming = entity.bladestorm_time_left > 0
		_bladestorm_particles.emitting = storming
		# Real light while the ult spins so the storm illuminates the arena
		# around the Duelist (lazily created the first time it's needed).
		if _bladestorm_light == null and storming:
			_bladestorm_light = OmniLight3D.new()
			_bladestorm_light.light_color = Color(1.0, 0.25, 0.25)
			_bladestorm_light.light_energy = 2.2
			_bladestorm_light.omni_range = 3.5
			_bladestorm_light.shadow_enabled = false
			_bladestorm_light.position = Vector3(0, 1.0, 0)
			add_child(_bladestorm_light)
		if _bladestorm_light != null:
			_bladestorm_light.visible = storming

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

	# One-shot gesture for instant abilities that have no cast and no swing
	# of their own (Warcry, Unbreakable, Ward, Consecrate, Barrier, Iron
	# Resolve, Camouflage...) — without this they fired with zero body
	# language. A rising ability_commit_time_left is the tell that one of
	# them just went off (swing/cast abilities never reach here mid-action
	# thanks to the earlier branches).
	_gesture_left = max(0.0, _gesture_left - get_process_delta_time())
	if entity.ability_commit_time_left > _last_commit + 0.001 and entity.casting == null:
		_gesture_left = 0.35
		_force_play(_cfg["cast_anim"], 0.06)
	_last_commit = entity.ability_commit_time_left
	if _gesture_left > 0:
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
		# _update_char_flash()/_update_slash_arc() also stop running once
		# dead — clear any residual hit-flash emission and mid-swing arc.
		for mat in _char_mats:
			mat.emission_enabled = false
		_slash.visible = false
	visible = true
	position = CoordUtil.to_world(entity.global_position)
	_death_timer += delta
	# Dissolve the body out over the final stretch instead of blinking off.
	var fade = clamp((_death_timer - 1.1) / 0.9, 0.0, 1.0)
	if fade > 0.0:
		for mat in _char_mats:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 1.0 - fade
	if _death_timer >= 2.0:
		visible = false
