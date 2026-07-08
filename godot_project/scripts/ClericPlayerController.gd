extends "res://scripts/ClericEntity.gd"
class_name ClericPlayerController

const PlayerInputController = preload("res://scripts/PlayerInputController.gd")

var _input := PlayerInputController.new()

func _ready():
	super._ready()
	is_player = true

func get_movement_input() -> Vector2:
	return _input.get_movement_input()

func get_aim_dir(_opp: Entity) -> Vector2:
	return _input.get_aim_dir(self)

func get_aim_pos(_opp: Entity) -> Vector2:
	return _input.get_aim_world_pos(self)

func _physics_process(delta):
	super._physics_process(delta)
	_input.process(self, delta)

func _unhandled_input(event):
	_input.handle_input(self, event)
