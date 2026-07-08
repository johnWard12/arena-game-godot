extends RefCounted
class_name BotSteering
# Shared, stateless bot-movement helpers. Extracted out of AI logic that was
# duplicated verbatim across bot controllers — as more classes get added,
# this is where their shared movement needs should land instead of being
# copy-pasted again.

# Pushes `ai_target` away from arena edges so a bot doesn't get pinned in a
# corner, blending the repulsion into whatever direction the AI already
# wanted to move.
static func apply_wall_repulsion(pos: Vector2, arena_rect: Rect2, ai_target: Vector2, margin: float = 120.0) -> Vector2:
	var repulse := Vector2.ZERO
	repulse.x += max(0.0, margin - (pos.x - arena_rect.position.x)) / margin
	repulse.x -= max(0.0, margin - (arena_rect.position.x + arena_rect.size.x - pos.x)) / margin
	repulse.y += max(0.0, margin - (pos.y - arena_rect.position.y)) / margin
	repulse.y -= max(0.0, margin - (arena_rect.position.y + arena_rect.size.y - pos.y)) / margin
	if repulse.length() > 0.01:
		return (ai_target + repulse * 2.0).normalized()
	return ai_target
