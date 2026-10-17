extends SceneTree
const Arena = preload("res://scripts/arena.gd")
const Bot = preload("res://scripts/bot.gd")
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func put(a: TuxArena, id: int, cell: Vector2i) -> void:
	a.actors[id].cell = cell
	a.actors[id].position = Vector2(cell)
	a.actors[id].goal = null

func fresh() -> TuxArena:
	var arena := Arena.new()
	arena.start(42)
	for y in range(1, Arena.HEIGHT - 1):
		for x in range(1, Arena.WIDTH - 1):
			arena.grid[y][x] = Arena.EMPTY
	return arena

func _initialize() -> void:
	var a := Arena.new()
	a.start(1234)
	var b := Arena.new()
	b.start(1234)
	check(a.grid == b.grid, "Seed must reproduce arena")
	for actor in a.actors:
		check(a.tile(actor.cell) == Arena.EMPTY, "Spawn must be open")
		var exits := 0
		for direction in Arena.DIRECTIONS:
			if a.walkable(actor.cell + direction, actor.id): exits += 1
		check(exits >= 2, "Every spawn needs two exits")
	a.move_actor(0,Vector2i.LEFT,a.actors[0].move_time)
	check(a.actors[0].position.x > 0.5 and not a.move_actor(0,Vector2i.LEFT), "Border collision stops the continuous body")
	put(a, 0, Vector2i(1,1))
	check(not a.move_actor(0,Vector2(INF,0),a.actors[0].move_time), "Reject non-finite movement")
	check(a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time), "Valid move")
	check(a.move_actor(0,Vector2i.RIGHT), "Continuous movement has no tile cooldown")
	a = fresh()
	check(a.place_bomb(0), "Plant bomb")
	check(not a.place_bomb(0), "Capacity and duplicate placement")
	check(a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time), "Can leave own bomb")
	a.tick(0.2)
	a.move_actor(0,Vector2i.LEFT,a.actors[0].move_time)
	check(not a.move_actor(0,Vector2i.LEFT), "Cannot reenter bomb")
	a = fresh()
	a.grid[1][3] = Arena.CRATE
	a.grid[3][1] = Arena.WALL
	var cells := a.blast_cells(Vector2i(1,1),5)
	check(cells.has(Vector2i(3,1)), "Blast includes first crate")
	check(not cells.has(Vector2i(4,1)), "Crate stops blast")
	check(not cells.has(Vector2i(1,3)), "Wall stops blast")
	a.place_bomb(0)
	put(a, 0, Vector2i(6,5))
	a.tick(2.41)
	check(a.grid[1][3] == Arena.EMPTY, "Crate destroyed")
	check(a.actors[0].bombs == 0, "Capacity returned on explosion")
	check(a.flames.has(Vector2i(1,1)), "Explosion creates lethal flames")
	a.tick(0.7)
	check(a.flames.is_empty(), "Flames expire")
	a = fresh()
	a.actors[0].power = 4
	a.place_bomb(0)
	put(a, 0, Vector2i(8,5))
	put(a, 1, Vector2i(3,1))
	a.place_bomb(1)
	put(a, 1, Vector2i(8,7))
	a.bombs[0].fuse = 0.01
	check(a.danger_map()[Vector2i(4,1)] < 0.02, "AI sees chain timing")
	a.tick(0.02)
	check(a.bombs.is_empty(), "Chain reaction detonates both bombs")
	check(a.flames.has(Vector2i(5,1)), "Chained blast reaches beyond triggering bomb")
	a = fresh()
	a.pickups[Vector2i(2,1)] = "bomb"
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(a.actors[0].capacity == 2 and a.pickups.is_empty(), "Power-up collected")
	a = fresh()
	a.flames[Vector2i(2,1)] = 0.5
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(not a.actors[0].alive, "Walking into flame kills player")
	a.tick(0.01)
	check(a.finished, "Player elimination ends solo round")
	a = fresh()
	for id in range(1,4): a.actors[id].alive = false
	a.tick(0.01)
	check(a.finished and a.winner == 0, "Last survivor wins")
	a = fresh()
	a.remaining = 0.01
	a.tick(0.02)
	check(a.finished and a.winner == -1, "Timeout is a draw")
	a = fresh()
	put(a, 1, Vector2i(5,5))
	a.grid[5][6] = Arena.CRATE
	Bot.step(a,1)
	check(a.bombs.size() == 1, "Bot plants against crate with escape")
	for i in 160:
		a.tick(1.0/60.0)
		Bot.step(a,1)
	check(a.actors[1].alive, "Bot escapes own bomb")
	a = fresh()
	put(a, 1, Vector2i(5,5))
	for direction in Arena.DIRECTIONS:
		a.grid[5+direction.y][5+direction.x] = Arena.CRATE
	Bot.step(a,1)
	check(a.bombs.is_empty(), "Trapped bot does not suicide-bomb")
	# Exercise full matches and occupancy invariants across random layouts.
	for seed_value in 12:
		a = Arena.new()
		a.start(seed_value, seed_value % 3)
		for frame in 9000:
			a.tick(1.0/60.0)
			for id in 4: Bot.step(a,id)
			if a.finished: break
		check(a.finished, "Simulated match terminates")
		for actor in a.actors:
			check(a.tile(actor.cell) == Arena.EMPTY, "Actor remains on walkable tile")
	print("AtomicTux: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
