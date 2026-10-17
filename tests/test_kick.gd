extends SceneTree
const Arena = preload("res://scripts/arena.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func put(a: TuxArena, id: int, cell: Vector2i) -> void:
	a.actors[id].cell = cell
	a.actors[id].position = Vector2(cell)
	a.actors[id].goal = null

func fresh() -> TuxArena:
	var a := Arena.new()
	a.start(42)
	for y in range(1, Arena.HEIGHT - 1):
		for x in range(1, Arena.WIDTH - 1):
			a.grid[y][x] = Arena.EMPTY
	put(a, 0, Vector2i(3,5))
	a.place_bomb(0)
	put(a, 0, Vector2i(2,5))
	return a

func _initialize() -> void:
	var a := fresh()
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(not a.move_actor(0,Vector2i.RIGHT), "Bomb blocks Tux without kick")
	put(a, 0, Vector2i(2,5))
	check(a.bombs[0].direction == Vector2i.ZERO, "Uncollected ability does not move bomb")
	a.pickups[Vector2i(2,4)] = "kick"
	check(a.move_actor(0,Vector2i.UP,a.actors[0].move_time), "Can collect kick pickup")
	check(a.actors[0].kick and a.pickups.is_empty(), "Kick pickup grants persistent ability")
	put(a, 0, Vector2i(2,5))
	a.actors[0].cooldown = 0.0
	check(a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time), "Running into bomb kicks it")
	check(a.actors[0].cell == Vector2i(3,5) and a.bombs[0].cell == Vector2i(4,5), "Kicker enters vacated bomb cell")
	check(a.bombs[0].direction == Vector2i.RIGHT and a.bombs[0].fuse == Arena.FUSE, "Kick preserves fuse and sets direction")
	check(a.bombs[0].owner == 0 and a.actors[0].bombs == 1, "Kick preserves ownership and capacity accounting")
	check(a.danger_map().has(Vector2i(9,5)), "AI anticipates moving bomb corridor")
	a.tick(Arena.KICK_STEP)
	check(a.bombs[0].cell == Vector2i(5,5), "Kicked bomb moves quickly on subsequent ticks")
	check(is_equal_approx(a.bombs[0].fuse, Arena.FUSE-Arena.KICK_STEP), "Fuse continues while moving")
	for barrier in [Arena.WALL, Arena.CRATE]:
		a = fresh()
		a.actors[0].kick = true
		a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
		a.grid[5][5] = barrier
		put(a, 0, Vector2i(2,3))
		a.tick(Arena.KICK_STEP)
		check(a.bombs[0].cell == Vector2i(3,5) and a.bombs[0].direction == Vector2i.LEFT, "Bomb bounces off wall/crate")
		check(a.grid[5][5] == barrier, "Bounce does not destroy obstacle")
	a = fresh()
	a.actors[0].kick = true
	a.grid[5][4] = Arena.WALL
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(not a.move_actor(0,Vector2i.RIGHT), "Cannot kick a bomb into a solid tile")
	check(a.bombs[0].cell == Vector2i(3,5), "Blocked kick preserves bomb position")
	a = fresh()
	a.actors[0].kick = true
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	put(a, 1, Vector2i(5,5))
	put(a, 0, Vector2i(2,3))
	a.tick(Arena.KICK_STEP)
	check(a.bombs[0].cell == Vector2i(3,5), "Moving bomb bounces without overlapping an actor")
	a = fresh()
	a.actors[0].kick = true
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	put(a, 0, Vector2i(2,3))
	put(a, 1, Vector2i(5,5))
	a.place_bomb(1)
	put(a, 1, Vector2i(10,8))
	a.tick(Arena.KICK_STEP)
	check(a.bombs[0].cell == Vector2i(3,5) and a.bombs[1].cell == Vector2i(5,5), "Bombs never overlap")
	a = fresh()
	a.actors[0].kick = true
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	put(a, 0, Vector2i(2,3))
	a.flames[Vector2i(5,5)] = 0.6
	a.tick(Arena.KICK_STEP)
	check(a.bombs.is_empty() and a.flames.has(Vector2i(5,5)), "Moving bomb triggers immediately when crossing fire")
	check(a.actors[0].bombs == 0, "Moving detonation restores owner capacity")
	a = fresh()
	a.actors[0].kick = true
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	put(a, 0, Vector2i(2,3))
	a.bombs[0].fuse = 0.02
	a.tick(0.03)
	check(a.bombs.is_empty() and a.flames.has(Vector2i(4,5)), "Bomb explodes at current position when fuse expires")
	a = fresh()
	a.actors[0].kick = true
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	put(a, 0, Vector2i(2,3))
	a.grid[5][3] = Arena.WALL
	a.grid[5][5] = Arena.WALL
	for frame in 150:
		a.tick(1.0/60.0)
	check(a.bombs.is_empty(), "Bomb trapped between obstacles still explodes")
	a.start(42,0)
	check(not a.actors[0].kick, "New round clears kick ability")
	check(a.actors[1].move_time == 0.42 and a.actors[0].move_time == 0.17, "Relaxed bots move slower without slowing human")
	a.place_bomb(1)
	put(a, 1, Vector2i(1,3))
	a.tick(2.5)
	check(a.actors[1].bombs == 0 and not a.place_bomb(1), "Relaxed AI waits between bomb placements")
	a.tick(1.6)
	check(a.place_bomb(1), "Relaxed AI can bomb when cooldown expires")
	print("AtomicTux kick/difficulty: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
