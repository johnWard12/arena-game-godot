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

func setup(e: Entity):
	entity = e
	var key = "bruiser" if e is BruiserEntity else ("mage" if e is RangedEntity else "duelist")
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

	_update_animation()

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
	visible = true
	position = CoordUtil.to_world(entity.global_position)
	_death_timer += delta
	if _death_timer >= 2.0:
		visible = false
