extends RefCounted
class_name PlayerInputController
# Composed (not inherited) input handling shared by every PlayerController
# variant. GDScript only allows single inheritance, and each PlayerController
# already has to extend a different *Entity subclass (Bruiser/Ranged/Ranger/
# Cleric/base) to pick up that class's ability overrides — so this couldn't
# be a shared base class. Composition is the only way to de-duplicate the
# identical WASD/mouse-aim/dash/ability-key logic that used to be copied
# into all five PlayerController files nearly verbatim.
#
# Also the home of input buffering: a key press for an ability that isn't
# ready yet (mid-cast, on cooldown, stunned...) used to be silently dropped.
# Now it's remembered for a short window and retried automatically the
# moment it becomes available. try_*() calls are cheap no-ops when blocked
# (they check their own gates before doing anything), so retrying every
# frame for the buffer window is safe — including retrying an action that
# already successfully fired earlier in its own buffer window, which just
# no-ops against the fresh cooldown.

const CoordUtil = preload("res://scripts/CoordUtil.gd")

const BUFFER_WINDOW := 0.15

var _dash_key_was_down := false
var _buffer: Dictionary = {}  # action name (String) -> time_left (float)

func get_movement_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D): v.x += 1
	if Input.is_physical_key_pressed(KEY_W): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S): v.y += 1
	return v

func get_aim_dir(entity: Entity) -> Vector2:
	var cam = entity.get_tree().get_first_node_in_group("game_camera")
	if cam != null:
		var mouse_pos = entity.get_viewport().get_mouse_position()
		var ray_origin = cam.project_ray_origin(mouse_pos)
		var ray_dir = cam.project_ray_normal(mouse_pos)
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_dir)
		if hit != null:
			var dir = CoordUtil.to_sim(hit) - entity.global_position
			if dir.length() > 0.01:
				return dir.normalized()
		return entity.facing
	# Fallback if no 3D camera is present in the scene.
	var dir = entity.get_global_mouse_position() - entity.global_position
	if dir.length() < 0.01:
		return entity.facing
	return dir.normalized()

# Call once per _physics_process from the owning PlayerController.
func process(entity: Entity, delta: float):
	_poll_dash(entity)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		entity.try_auto(entity.opponent)
	_process_buffer(entity, delta)

func _poll_dash(entity: Entity):
	var held = Input.is_physical_key_pressed(KEY_SPACE)
	if held and not _dash_key_was_down:
		var input_vec = get_movement_input()
		var dir = input_vec if input_vec.length() > 0.01 else entity.facing
		entity.try_dash(dir)
	_dash_key_was_down = held

# Call from the owning PlayerController's _unhandled_input.
func handle_input(entity: Entity, event: InputEvent):
	if not entity.alive:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _press(entity, "a1")
			KEY_Q: _press(entity, "a2")
			KEY_F: _press(entity, "a3")
			KEY_SHIFT: _press(entity, "shift")
			KEY_R: _press(entity, "ult")
			KEY_G: _press(entity, "parry")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_press(entity, "parry")

func _press(entity: Entity, action: String):
	_fire(entity, action)
	_buffer[action] = BUFFER_WINDOW

func _process_buffer(entity: Entity, delta: float):
	var expired: Array = []
	for action in _buffer:
		_buffer[action] -= delta
		if _buffer[action] <= 0.0:
			expired.append(action)
		else:
			_fire(entity, action)
	for action in expired:
		_buffer.erase(action)

func _fire(entity: Entity, action: String):
	match action:
		"a1": entity.try_a1(entity.opponent)
		"a2": entity.try_a2(entity.opponent)
		"a3": entity.try_a3(entity.opponent)
		"shift": entity.try_shift(entity.opponent)
		"ult": entity.try_ult(entity.opponent)
		"parry": entity.try_parry()
