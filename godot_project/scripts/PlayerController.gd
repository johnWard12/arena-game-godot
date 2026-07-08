extends "res://scripts/Entity.gd"
class_name PlayerController

const PlayerInputController = preload("res://scripts/PlayerInputController.gd")

var _input := PlayerInputController.new()

func _ready():
	is_player = true
	base_color = Color(0.37, 0.88, 0.75)

func get_movement_input() -> Vector2:
	return _input.get_movement_input()

func get_aim_dir(_opp: Entity) -> Vector2:
	return _input.get_aim_dir(self)

func _physics_process(delta):
	super._physics_process(delta)
	_input.process(self, delta)

func _unhandled_input(event):
	_input.handle_input(self, event)
