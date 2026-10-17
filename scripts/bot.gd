class_name TuxBot
extends RefCounted
## Breadth-first routing with arrival-time checks and a pre-placement escape test.

static func step(arena: TuxArena, id: int, delta: float = 1.0 / 60.0) -> void:
	var actor: Dictionary = arena.actors[id]
	if not actor.alive or arena.finished:
		return
	if actor.goal != null:
		_follow(arena, id, delta)
		return
	var danger := arena.danger_map()
	var origin: Vector2i = actor.cell
	if danger.has(origin):
		var escape := route(arena, id, danger, true)
		if not escape.is_empty():
			actor.goal = escape[0]
			_follow(arena, id, delta)
		return
	var useful := false
	for cell in arena.blast_cells(origin, TuxArena.ATOMIC_POWER if actor.atomic else actor.power):
		if arena.tile(cell) == TuxArena.CRATE:
			useful = true
		for other in arena.actors:
			if other.alive and other.id != id and other.cell == cell:
				useful = true
	if useful and actor.bombs < actor.capacity and actor.bomb_cooldown <= 0.0:
		var hypothetical := danger.duplicate()
		for cell in arena.blast_cells(origin, TuxArena.ATOMIC_POWER if actor.atomic else actor.power):
			hypothetical[cell] = minf(float(hypothetical.get(cell, 99.0)), TuxArena.FUSE)
		var escape := route(arena, id, hypothetical, true)
		if not escape.is_empty():
			arena.place_bomb(id)
			actor.goal = escape[0]
			_follow(arena, id, delta)
			return
	var path := route(arena, id, danger, false)
	if not path.is_empty():
		actor.goal = path[0]
		_follow(arena, id, delta)

static func _follow(arena: TuxArena, id: int, delta: float) -> void:
	var actor: Dictionary = arena.actors[id]
	var offset: Vector2 = Vector2(actor.goal) - actor.position
	if offset.length() < 0.00001:
		actor.goal = null
		step(arena, id, delta)
		return
	var direction := offset.normalized()
	var used := minf(delta, offset.length() * actor.move_time)
	if not arena.move_actor(id, direction, used):
		actor.goal = null
	elif (Vector2(actor.goal) - actor.position).length() < 0.00001:
		actor.goal = null
		if delta - used > 0.000001: step(arena, id, delta - used)

static func route(arena: TuxArena, id: int, danger: Dictionary, escape: bool) -> Array:
	var actor: Dictionary = arena.actors[id]
	var origin: Vector2i = actor.cell
	var queue: Array = [origin]
	var paths: Dictionary = {origin: []}
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		var path: Array = paths[cell]
		if cell != origin and not danger.has(cell):
			if escape or arena.pickups.has(cell) or _target(arena, cell, id):
				return path
		# Rotate order by actor ID to avoid identical movement preferences.
		for i in 4:
			var direction: Vector2i = TuxArena.DIRECTIONS[(i + id) % 4]
			var next: Vector2i = cell + direction
			if paths.has(next) or not arena.walkable(next, id):
				continue
			var arrival: float = (path.size() + 1) * actor.move_time
			if danger.has(next):
				if not escape or float(danger[next]) <= arrival + actor.move_time + 0.15:
					continue
			var next_path := path.duplicate()
			next_path.append(next)
			paths[next] = next_path
			queue.append(next)
	return []

static func _target(arena: TuxArena, cell: Vector2i, id: int) -> bool:
	for direction in TuxArena.DIRECTIONS:
		if arena.tile(cell + direction) == TuxArena.CRATE:
			return true
	for other in arena.actors:
		if other.id != id and other.alive and (other.cell - cell).length_squared() <= 4:
			return true
	return false
