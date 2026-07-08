extends RefCounted
class_name CoordUtil
# Single conversion point between the game's 2D simulation space (Vector2,
# unchanged since Entity/Main/Simulate still do all gameplay math in it) and
# the 3D presentation world (Vector3, Y-up). Sim Y becomes world Z (depth).

const SIM_SCALE := 50.0  # simulation units per 3D meter

static func to_world(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x / SIM_SCALE, y, v.y / SIM_SCALE)

static func to_sim(v: Vector3) -> Vector2:
	return Vector2(v.x * SIM_SCALE, v.z * SIM_SCALE)
