extends Node3D
class_name EntityView3D
# Phase-0 placeholder 3D presentation for an Entity. Mirrors the entity's
# already-simulated Vector2 state every frame; the entity itself has zero
# awareness this exists. Only ever instantiated by Main.gd — Simulate.gd
# never creates one, so headless balance runs are completely unaffected.
#
# Gives each class a distinct silhouette (body proportions + weapon prop)
# so they're readable at a glance even as placeholder primitives, matching
# the "is BruiserEntity / is RangedEntity" class-check pattern Main.gd
# already uses elsewhere.

const BODY_HEIGHT := 1.6
const BODY_RADIUS := 0.34
const HEAD_RADIUS := 0.17

var entity: Entity = null
var _body_height := BODY_HEIGHT

var _body: MeshInstance3D
var _head: MeshInstance3D
var _mat: StandardMaterial3D

func setup(e: Entity):
	entity = e

	var body_radius = BODY_RADIUS
	var body_height = BODY_HEIGHT
	if e is BruiserEntity:
		body_radius = BODY_RADIUS * 1.3
		body_height = BODY_HEIGHT * 1.1
	elif e is RangedEntity:
		body_radius = BODY_RADIUS * 0.85
		body_height = BODY_HEIGHT * 1.05
	_body_height = body_height

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = e.base_color
	_mat.emission_enabled = true
	_mat.emission = e.base_color
	_mat.emission_energy_multiplier = 0.15

	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = body_height
	capsule.radius = body_radius
	_body.mesh = capsule
	_body.position = Vector3(0, body_height * 0.5, 0)
	_body.material_override = _mat
	add_child(_body)

	_head = MeshInstance3D.new()
	var head_sphere := SphereMesh.new()
	head_sphere.radius = HEAD_RADIUS
	head_sphere.height = HEAD_RADIUS * 2.0
	_head.mesh = head_sphere
	_head.position = Vector3(0, body_height + HEAD_RADIUS * 0.55, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.7, 0.55)
	_head.material_override = head_mat
	add_child(_head)

	if e is BruiserEntity:
		_build_hammer(body_height)
	elif e is RangedEntity:
		_build_staff(body_height)
	else:
		_build_sword(body_height)

func _build_sword(body_height: float):
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.85)
	blade.mesh = box
	blade.position = Vector3(0.35, body_height * 0.65, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.84, 0.9)
	mat.metallic = 0.6
	blade.material_override = mat
	add_child(blade)

func _build_hammer(body_height: float):
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.045
	shaft_mesh.bottom_radius = 0.045
	shaft_mesh.height = 0.75
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees = Vector3(90, 0, 0)
	shaft.position = Vector3(0.42, body_height * 0.55, 0.3)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.4, 0.3, 0.22)
	shaft.material_override = shaft_mat
	add_child(shaft)

	var head := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.28, 0.22, 0.22)
	head.mesh = head_box
	head.position = Vector3(0.42, body_height * 0.55, 0.68)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.5, 0.5, 0.56)
	head_mat.metallic = 0.5
	head.material_override = head_mat
	add_child(head)

func _build_staff(body_height: float):
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.03
	shaft_mesh.bottom_radius = 0.03
	shaft_mesh.height = 1.05
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees = Vector3(90, 0, 0)
	shaft.position = Vector3(0.32, body_height * 0.6, 0.3)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.4, 0.28, 0.18)
	shaft.material_override = shaft_mat
	add_child(shaft)

	var orb := MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.1
	orb_mesh.height = 0.2
	orb.mesh = orb_mesh
	orb.position = Vector3(0.32, body_height * 0.6, 0.82)
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(0.85, 0.55, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.85, 0.55, 1.0)
	orb_mat.emission_energy_multiplier = 2.0
	orb.material_override = orb_mat
	add_child(orb)

func _process(_delta):
	if entity == null or not is_instance_valid(entity) or not entity.alive:
		visible = false
		return
	visible = true

	position = CoordUtil.to_world(entity.global_position)

	var look_dir = Vector3(entity.facing.x, 0.0, entity.facing.y)
	if look_dir.length() > 0.001:
		look_at(position + look_dir, Vector3.UP)

	var accent = entity.get_status_accent(entity.base_color)
	_mat.albedo_color = accent
	_mat.emission = accent
	_mat.emission_energy_multiplier = 1.6 if entity.hit_flash_left > 0 else 0.15
