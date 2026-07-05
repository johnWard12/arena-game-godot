extends Node3D
class_name ProjectileView3D
# Phase-0 placeholder 3D presentation for a Projectile — mirrors its
# already-simulated position the same way EntityView3D does for Entity.

var projectile: Projectile = null
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D

func setup(p: Projectile):
	projectile = p

	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	_mesh.mesh = sphere

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = p.proj_color
	_mat.emission_enabled = true
	_mat.emission = p.proj_color
	_mat.emission_energy_multiplier = 2.0
	_mesh.material_override = _mat
	add_child(_mesh)

func _process(_delta):
	if projectile == null or not is_instance_valid(projectile):
		queue_free()
		return
	position = CoordUtil.to_world(projectile.global_position, 0.9)
