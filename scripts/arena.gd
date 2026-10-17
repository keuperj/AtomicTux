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

func start(seed_value: int, level: int = 1) -> void:
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
	for id in 4:
		actors.append({"id": id, "cell": spawns[id], "previous": spawns[id], "alive": true,
			"cooldown": 0.0, "move_time": 0.17 if id == 0 else [0.42, 0.21, 0.17][level],
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
		if actor.alive and actor.id != actor_id and actor.cell == cell:
			return false
	return true

func move_actor(id: int, direction: Vector2i) -> bool:
	if finished or not DIRECTIONS.has(direction):
		return false
	var actor: Dictionary = actors[id]
	if not actor.alive or actor.cooldown > 0.0:
		return false
	actor.facing = direction
	var target: Vector2i = actor.cell + direction
	var obstacle := bomb_at(target)
	if obstacle >= 0 and actor.kick:
		for other in actors:
			if other.alive and other.id != id and other.cell == target:
				return false
		_kick_bomb(obstacle, direction)
	if not walkable(target, id):
		return false
	actor.previous = actor.cell
	actor.cell = target
	actor.cooldown = actor.move_time
	if flames.has(target):
		_hit_by_fire(actor)
	elif pickups.has(target):
		var kind: String = pickups[target]
		match kind:
			"bomb": actor.capacity = mini(actor.capacity + 1, 5)
			"fire": actor.power = mini(actor.power + 1, 7)
			"speed": actor.move_time = maxf(0.105, actor.move_time - 0.025)
			"kick": actor.kick = true
			"shield": actor.shield = true
		pickups.erase(target)
		collected.emit(id, kind)
	return true

func place_bomb(id: int) -> bool:
	var actor: Dictionary = actors[id]
	if finished or not actor.alive or actor.bomb_cooldown > 0.0 or actor.bombs >= actor.capacity or bomb_at(actor.cell) >= 0:
		return false
	bombs.append({"cell": actor.cell, "owner": id, "power": actor.power, "fuse": FUSE,
		"direction": Vector2i.ZERO, "motion_time": 0.0})
	actor.bombs += 1
	actor.bomb_cooldown = 4.0 if id > 0 and difficulty == 0 else 0.0
	return true

func _bomb_blocked(cell: Vector2i) -> bool:
	return not walkable(cell)

func _kick_bomb(index: int, direction: Vector2i) -> void:
	var bomb: Dictionary = bombs[index]
	var next: Vector2i = bomb.cell + direction
	if _bomb_blocked(next):
		return
	bomb.cell = next
	bomb.direction = direction
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
	for actor in actors:
		if actor.alive and flames.has(actor.cell):
			_hit_by_fire(actor)
	var survivors: Array = actors.filter(func(a): return a.alive)
	if survivors.size() <= 1 or not actors[0].alive or remaining <= 0.0:
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
			if rng.randf() < 0.38:
				pickups[cell] = POWER_UPS[rng.randi_range(0, POWER_UPS.size() - 1)]
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
	grid = state.grid.duplicate(true)
	actors = state.actors.duplicate(true)
	for actor in actors:
		actor.cell = _wire_cell(actor.cell)
		actor.previous = _wire_cell(actor.previous)
		actor.facing = _wire_cell(actor.facing)
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
