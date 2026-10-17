class_name TuxArena
extends RefCounted
## Engine-independent match state. Only this class mutates the arena.
## Inputs are actor IDs + cardinal directions/bomb commands; visuals read state.
signal exploded(cells: Array)
signal collected(actor_id: int, kind: String)
signal eliminated(actor_id: int)
signal shield_absorbed(actor_id: int)

const WIDTH := 13
const HEIGHT := 11
const EMPTY := 0
const WALL := 1
const CRATE := 2
const FUSE := 2.4
const FIRE_TIME := 0.65
const SHIELD_GRACE := FIRE_TIME + 0.1
const KICK_STEP := 0.065
const ACTOR_RADIUS := 0.28
const BOMB_RADIUS := 0.30
const MOTION_STEP := 0.04
const POWER_UPS := ["bomb", "fire", "speed", "kick", "shield"]
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var grid: Array = []
var actors: Array = []
var bombs: Array = []
var flames: Dictionary = {}
var pickups: Dictionary = {}
var rng := RandomNumberGenerator.new()
var remaining := 150.0
var finished := false
var winner := -2
var elapsed := 0.0
var difficulty := 1
var ai_only := false
var enabled_powerups: Array = POWER_UPS.duplicate()

func start(seed_value: int, level: int = 1, opponents: int = 3, powerups: Array = POWER_UPS, demo: bool = false) -> void:
	ai_only = demo
	enabled_powerups = POWER_UPS.filter(func(kind): return powerups.has(kind))
	rng.seed = seed_value
	difficulty = level
	grid.clear()
	actors.clear()
	bombs.clear()
	flames.clear()
	pickups.clear()
	remaining = 150.0
	elapsed = 0.0
	finished = false
	winner = -2
	var spawns := [Vector2i(1, 1), Vector2i(11, 9), Vector2i(11, 1), Vector2i(1, 9)]
	for y in HEIGHT:
		var row: Array = []
		for x in WIDTH:
			var tile := EMPTY
			if x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1 or (x % 2 == 0 and y % 2 == 0):
				tile = WALL
			elif rng.randf() < 0.72:
				tile = CRATE
			for spawn in spawns:
				if absi(x - spawn.x) + absi(y - spawn.y) <= 2 and tile != WALL:
					tile = EMPTY
			row.append(tile)
		grid.append(row)
	for id in (4 if ai_only else clampi(opponents, 1, 3) + 1):
		actors.append({"id": id, "cell": spawns[id], "previous": spawns[id], "position": Vector2(spawns[id]), "goal": null, "alive": true,
			"cooldown": 0.0, "move_time": 0.17 if id == 0 and not ai_only else [0.42, 0.21, 0.17][level],
			"capacity": 1, "power": 2, "bombs": 0, "kick": false, "shield": false, "invulnerable": 0.0, "bomb_cooldown": 0.0, "facing": Vector2i.DOWN})

func tile(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= WIDTH or cell.y >= HEIGHT:
		return WALL
	return grid[cell.y][cell.x]

func bomb_at(cell: Vector2i) -> int:
	for i in bombs.size():
		if bombs[i].cell == cell:
			return i
	return -1

func walkable(cell: Vector2i, actor_id: int = -1) -> bool:
	if tile(cell) != EMPTY or bomb_at(cell) >= 0:
		return false
	for actor in actors:
		if actor.alive and actor.id != actor_id and _overlaps(actor.position, Vector2(cell), ACTOR_RADIUS * 2):
			return false
	return true

static func _overlaps(a: Vector2, b: Vector2, distance: float) -> bool:
	return absf(a.x - b.x) < distance - 0.00001 and absf(a.y - b.y) < distance - 0.00001

func _body_cells(point: Vector2) -> Array:
	var result: Array = []
	var low := Vector2i((point - Vector2.ONE * ACTOR_RADIUS + Vector2.ONE * 0.50001).floor())
	var high := Vector2i((point + Vector2.ONE * ACTOR_RADIUS + Vector2.ONE * 0.49999).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1): result.append(Vector2i(x, y))
	return result

func _can_occupy(id: int, point: Vector2) -> bool:
	for cell in _body_cells(point):
		if tile(cell) != EMPTY: return false
	for other in actors:
		if other.alive and other.id != id and _overlaps(point, other.position, ACTOR_RADIUS * 2): return false
	for bomb in bombs:
		if not bomb.get("passers", []).has(id) and _overlaps(point, Vector2(bomb.cell), ACTOR_RADIUS + BOMB_RADIUS): return false
	return true

func _update_bomb_passers() -> void:
	for bomb in bombs:
		var allowed: Array = []
		for id in bomb.get("passers", []):
			if actors[id].alive and _overlaps(actors[id].position, Vector2(bomb.cell), ACTOR_RADIUS + BOMB_RADIUS): allowed.append(id)
		bomb.passers = allowed

func _touch_actor(actor: Dictionary) -> void:
	for cell in _body_cells(actor.position):
		if flames.has(cell):
			_hit_by_fire(actor)
			return
	var target: Vector2i = actor.cell
	if pickups.has(target):
		var kind: String = pickups[target]
		match kind:
			"bomb": actor.capacity = mini(actor.capacity + 1, 5)
			"fire": actor.power = mini(actor.power + 1, 7)
			"speed": actor.move_time = maxf(0.105, actor.move_time - 0.025)
			"kick": actor.kick = true
			"shield": actor.shield = true
		pickups.erase(target)
		collected.emit(actor.id, kind)

func move_actor(id: int, direction: Vector2, delta: float = 1.0 / 60.0) -> bool:
	if finished or not direction.is_finite() or direction.is_zero_approx() or delta <= 0.0:
		return false
	var actor: Dictionary = actors[id]
	if not actor.alive: return false
	_update_bomb_passers()
	var input := direction.limit_length(1.0)
	var distance: float = delta / actor.move_time * input.length()
	var moved := false
	while distance > 0.000001 and actor.alive:
		var point: Vector2 = actor.position
		var axis := -1
		var sign_value := 0.0
		for candidate in 2:
			if absf(point[candidate] - roundf(point[candidate])) > 0.00001:
				axis = candidate
				break
		if axis >= 0:
			# Finish the current lane before taking a buffered perpendicular turn.
			sign_value = signf(input[axis])
			if sign_value == 0.0: sign_value = signf(actor.facing[axis])
			if sign_value == 0.0: sign_value = signf(roundf(point[axis]) - point[axis])
		else:
			point = point.round()
			actor.position = point
			var preferred := 0 if absf(input.x) > absf(input.y) else 1
			for candidate in [preferred, 1 - preferred]:
				if absf(input[candidate]) < 0.00001: continue
				var target := point
				target[candidate] += signf(input[candidate])
				if _lane_open(id, target, candidate, signf(input[candidate])):
					axis = candidate
					sign_value = signf(input[candidate])
					break
			if axis < 0: break
		var endpoint := point
		endpoint[axis] = floorf(point[axis]) + 1.0 if sign_value > 0 else ceilf(point[axis]) - 1.0
		if not _lane_open(id, endpoint, axis, sign_value): break
		var step := minf(minf(MOTION_STEP, distance), absf(endpoint[axis] - point[axis]))
		var facing := Vector2i.ZERO
		facing[axis] = int(sign_value)
		actor.facing = facing
		if not _move_axis(id, axis, step * sign_value): break
		moved = true
		distance -= step
	return moved

func _lane_open(id: int, target: Vector2, axis: int, sign_value: float) -> bool:
	if tile(Vector2i(target)) != EMPTY: return false
	for other in actors:
		if other.alive and other.id != id and _overlaps(target, other.position, ACTOR_RADIUS * 2): return false
	var index := bomb_at(Vector2i(target))
	if index >= 0 and not bombs[index].get("passers", []).has(id):
		if not actors[id].kick: return false
		var direction := Vector2i.ZERO
		direction[axis] = int(sign_value)
		_kick_bomb(index, direction)
	return _can_occupy(id, target)

func _move_axis(id: int, axis: int, amount: float) -> bool:
	if absf(amount) < 0.000001: return false
	var actor: Dictionary = actors[id]
	var point: Vector2 = actor.position
	var travel := Vector2.ZERO
	travel[axis] = signf(amount)
	var step := absf(amount)
	var target := point + travel * step
	for index in bombs.size():
		var bomb: Dictionary = bombs[index]
		if actor.kick and not bomb.get("passers", []).has(id) and _overlaps(target, Vector2(bomb.cell), ACTOR_RADIUS + BOMB_RADIUS):
			_kick_bomb(index, Vector2i(travel))
	if not _can_occupy(id, target):
		var low := 0.0
		var high := step
		for iteration in 12:
			var middle := (low + high) / 2.0
			if _can_occupy(id, point + travel * middle): low = middle
			else: high = middle
		if low < 0.000001: return false
		target = point + travel * low
	actor.previous = actor.cell
	actor.position = target
	actor.cell = Vector2i(target.round())
	_update_bomb_passers()
	_touch_actor(actor)
	return true

func place_bomb(id: int) -> bool:
	var actor: Dictionary = actors[id]
	if finished or not actor.alive or actor.bomb_cooldown > 0.0 or actor.bombs >= actor.capacity or bomb_at(actor.cell) >= 0:
		return false
	bombs.append({"cell": actor.cell, "owner": id, "power": actor.power, "fuse": FUSE,
		"direction": Vector2i.ZERO, "motion_time": 0.0,
		"passers": actors.filter(func(a): return a.alive and _overlaps(a.position, Vector2(actor.cell), ACTOR_RADIUS + BOMB_RADIUS)).map(func(a): return a.id)})
	actor.bombs += 1
	actor.bomb_cooldown = 4.0 if (id > 0 or ai_only) and difficulty == 0 else 0.0
	return true

func _bomb_blocked(cell: Vector2i) -> bool:
	if tile(cell) != EMPTY or bomb_at(cell) >= 0: return true
	for actor in actors:
		if actor.alive and _overlaps(actor.position, Vector2(cell), ACTOR_RADIUS + BOMB_RADIUS): return true
	return false

func _kick_bomb(index: int, direction: Vector2i) -> void:
	var bomb: Dictionary = bombs[index]
	var next: Vector2i = bomb.cell + direction
	if _bomb_blocked(next):
		return
	bomb.cell = next
	bomb.direction = direction
	bomb.passers = []
	bomb.motion_time = 0.0
	if flames.has(next):
		bomb.fuse = 0.0

func _move_bomb(bomb: Dictionary, delta: float) -> void:
	if bomb.direction == Vector2i.ZERO or bomb.fuse <= 0.0:
		return
	if flames.has(bomb.cell):
		bomb.fuse = 0.0
		return
	bomb.motion_time += minf(delta, bomb.fuse)
	while bomb.motion_time >= KICK_STEP:
		bomb.motion_time -= KICK_STEP
		var next: Vector2i = bomb.cell + bomb.direction
		if _bomb_blocked(next):
			bomb.direction = -bomb.direction
			next = bomb.cell + bomb.direction
		if not _bomb_blocked(next):
			bomb.cell = next
		if flames.has(bomb.cell):
			bomb.fuse = 0.0
			break

func blast_cells(cell: Vector2i, power: int) -> Array:
	var result: Array = [cell]
	for direction in DIRECTIONS:
		for distance in range(1, power + 1):
			var target: Vector2i = cell + direction * distance
			if tile(target) == WALL:
				break
			result.append(target)
			if tile(target) == CRATE or bomb_at(target) >= 0:
				break
	return result

func danger_map() -> Dictionary:
	var danger: Dictionary = {}
	for cell in flames:
		danger[cell] = 0.0
	# Propagate trigger times through bomb chains, so bots see early detonations.
	var times: Array = []
	for bomb in bombs:
		times.append(float(bomb.fuse))
	for _pass in bombs.size():
		for i in bombs.size():
			for cell in blast_cells(bombs[i].cell, bombs[i].power):
				var j := bomb_at(cell)
				if j >= 0:
					times[j] = minf(times[j], times[i])
	for i in bombs.size():
		for cell in blast_cells(bombs[i].cell, bombs[i].power):
			danger[cell] = minf(float(danger.get(cell, 99.0)), times[i])
	for bomb in bombs:
		if bomb.direction == Vector2i.ZERO:
			continue
		for sign_value in [-1, 1]:
			var cell: Vector2i = bomb.cell
			for distance in range(ceili(bomb.fuse / KICK_STEP) + 1):
				if tile(cell) != EMPTY:
					break
				for blast in blast_cells(cell, bomb.power):
					danger[blast] = minf(float(danger.get(blast, 99.0)), bomb.fuse)
				cell += bomb.direction * sign_value
	return danger

func tick(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	remaining = maxf(0.0, remaining - delta)
	for actor in actors:
		actor.cooldown = maxf(0.0, actor.cooldown - delta)
		actor.invulnerable = maxf(0.0, actor.invulnerable - delta)
		actor.bomb_cooldown = maxf(0.0, actor.bomb_cooldown - delta)
	for cell in flames.keys():
		flames[cell] -= delta
		if flames[cell] <= 0.0:
			flames.erase(cell)
	for bomb in bombs:
		_move_bomb(bomb, delta)
		bomb.fuse -= delta
	var index := 0
	while index < bombs.size():
		if bombs[index].fuse <= 0.0 or flames.has(bombs[index].cell):
			_detonate(index)
			index = 0
		else:
			index += 1
	_update_bomb_passers()
	for actor in actors:
		if actor.alive: _touch_actor(actor)
	var survivors: Array = actors.filter(func(a): return a.alive)
	if survivors.size() <= 1 or (not ai_only and not actors[0].alive) or remaining <= 0.0:
		finished = true
		winner = survivors[0].id if survivors.size() == 1 else -1

func _detonate(index: int) -> void:
	var bomb: Dictionary = bombs[index]
	var cells := blast_cells(bomb.cell, bomb.power)
	bombs.remove_at(index)
	actors[bomb.owner].bombs -= 1
	for cell in cells:
		var chain := bomb_at(cell)
		if chain >= 0:
			bombs[chain].fuse = 0.0
		flames[cell] = FIRE_TIME
		pickups.erase(cell)
		if tile(cell) == CRATE:
			grid[cell.y][cell.x] = EMPTY
			if rng.randf() < 0.38 and not enabled_powerups.is_empty():
				pickups[cell] = enabled_powerups[rng.randi_range(0, enabled_powerups.size() - 1)]
	exploded.emit(cells)

func _hit_by_fire(actor: Dictionary) -> void:
	if not actor.alive or actor.invulnerable > 0.0:
		return
	if actor.shield:
		actor.shield = false
		# One charge; the short grace window covers lingering/overlapping flames.
		actor.invulnerable = SHIELD_GRACE
		shield_absorbed.emit(actor.id)
		return
	_kill(actor)

func _kill(actor: Dictionary) -> void:
	if not actor.alive:
		return
	actor.alive = false
	eliminated.emit(actor.id)

func apply_snapshot(state: Dictionary) -> void:
	## Network snapshots are read-only presentation state; server owns online rules.
	var displayed: Dictionary = {}
	for actor in actors: displayed[actor.id] = actor.get("display_position", actor.position)
	grid = state.grid.duplicate(true)
	actors = state.actors.duplicate(true)
	for actor in actors:
		actor.cell = _wire_cell(actor.cell)
		actor.previous = _wire_cell(actor.previous)
		actor.facing = _wire_cell(actor.facing)
		var coordinates: Array = actor.get("position", [actor.cell.x, actor.cell.y])
		actor.position = Vector2(float(coordinates[0]), float(coordinates[1]))
		actor.render_from = displayed.get(actor.id, actor.position) if actor.alive else actor.position
		actor.display_position = actor.render_from
		actor.render_elapsed = 0.0
	bombs = state.bombs.duplicate(true)
	for bomb in bombs:
		bomb.cell = _wire_cell(bomb.cell)
		bomb.direction = _wire_cell(bomb.direction)
	flames.clear()
	for entry in state.flames: flames[_wire_cell(entry.cell)] = float(entry.time)
	pickups.clear()
	for entry in state.pickups: pickups[_wire_cell(entry.cell)] = str(entry.kind)
	remaining = float(state.remaining)
	elapsed = float(state.elapsed)
	finished = bool(state.finished)
	winner = int(state.winner)
	difficulty = int(state.difficulty)

static func _wire_cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]),int(value[1]))

static func interpolate_lane(from: Vector2, to: Vector2, weight: float) -> Vector2:
	if absf(from.x-to.x) < 0.00001 or absf(from.y-to.y) < 0.00001:
		return from.lerp(to, weight)
	if absf(from.x-to.x) + absf(from.y-to.y) > 1.0:
		return to
	var corner: Vector2
	if absf(from.y-roundf(from.y)) < 0.00001 and absf(to.x-roundf(to.x)) < 0.00001:
		corner = Vector2(to.x, from.y)
	elif absf(from.x-roundf(from.x)) < 0.00001 and absf(to.y-roundf(to.y)) < 0.00001:
		corner = Vector2(from.x, to.y)
	else:
		# A stale snapshot may span several turns; don't draw a shortcut through walls.
		return to
	var first := from.distance_to(corner)
	var second := corner.distance_to(to)
	var distance := (first + second) * clampf(weight, 0, 1)
	return from.move_toward(corner, distance) if distance <= first else corner.move_toward(to, distance-first)
