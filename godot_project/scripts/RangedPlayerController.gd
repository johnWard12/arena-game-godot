extends "res://scripts/RangedEntity.gd"
class_name RangedPlayerController

var dash_key_was_down := false

func _ready():
	super._ready()
	is_player = true

func get_movement_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D): v.x += 1
	if Input.is_physical_key_pressed(KEY_W): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S): v.y += 1
	return v

func get_aim_dir(_opp: Entity) -> Vector2:
	var dir = get_global_mouse_position() - global_position
	if dir.length() < 0.01:
		return facing
	return dir.normalized()

func _physics_process(delta):
	super._physics_process(delta)
	poll_dash()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		try_auto(opponent)

func poll_dash():
	var held = Input.is_physical_key_pressed(KEY_SPACE)
	if held and not dash_key_was_down:
		var input_vec = get_movement_input()
		var dir = input_vec if input_vec.length() > 0.01 else facing
		try_dash(dir)
	dash_key_was_down = held

func _unhandled_input(event):
	if not alive:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: try_a1(opponent)
			KEY_Q: try_a2(opponent)
			KEY_F: try_a3(opponent)
			KEY_SHIFT: try_shift(opponent)
			KEY_R: try_ult(opponent)
			KEY_G: try_parry()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			try_parry()
