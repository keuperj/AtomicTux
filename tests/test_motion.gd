extends SceneTree
const Arena = preload("res://scripts/arena.gd")
const Bot = preload("res://scripts/bot.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fresh() -> TuxArena:
	var a := Arena.new()
	a.start(42)
	for y in range(1,10):
		for x in range(1,12): a.grid[y][x] = 0
	return a

func put(a: TuxArena, id: int, point: Vector2) -> void:
	a.actors[id].position = point
	a.actors[id].cell = Vector2i(point.round())
	a.actors[id].goal = null

func _initialize() -> void:
	var a := fresh()
	a.move_actor(0, Vector2i.RIGHT)
	var point: Vector2 = a.actors[0].position
	check(point.x > 1.0 and point.x < 1.2 and a.actors[0].cell == Vector2i(1,1), "Movement advances a fraction of a tile on the first frame")
	a.tick(0.1)
	check(a.actors[0].position == point, "Releasing input stops exactly between tile centers")
	a.move_actor(0, Vector2i.LEFT)
	check(a.actors[0].position.is_equal_approx(Vector2(1,1)), "Mid-tile reversal is immediate")
	for rate in [30,60,120]:
		a = fresh()
		for frame in rate: a.move_actor(0, Vector2i.RIGHT, 1.0/rate)
		check(absf(a.actors[0].position.x - (1.0+1.0/0.23)) < 0.0001, "Same travel distance at %d Hz" % rate)
	a = fresh()
	a.move_actor(0, Vector2i.RIGHT, .04)
	point = a.actors[0].position
	a.move_actor(0, Vector2i.DOWN)
	check(a.actors[0].position.distance_to(point) <= 1.0/60.0/.23+.0001, "Changing direction does not teleport")
	for i in 20: a.move_actor(0, Vector2i.DOWN)
	check(absf(a.actors[0].position.x-2.0) < .0001 and a.actors[0].position.y > 1.5, "Buffered turn starts at the next tile center")
	for obstacle in [Arena.WALL, Arena.CRATE]:
		a = fresh()
		a.grid[1][3] = obstacle
		a.move_actor(0, Vector2i.RIGHT, 1.0)
		check(absf(a.actors[0].position.x-2.0) < .001, "Walls and crates stop Tux at the last clear tile center")
		check(not a.move_actor(0, Vector2i.RIGHT), "Blocked input does not jitter through obstacle")
	a = fresh()
	put(a, 1, Vector2(2.5,1))
	a.move_actor(0, Vector2i.RIGHT, .5)
	check(absf(a.actors[0].position.x-1.0) < .001, "Occupied lane prevents entering from the previous center")
	a = fresh()
	a.place_bomb(0)
	a.move_actor(0, Vector2i.RIGHT, .23)
	a.move_actor(0, Vector2i.LEFT, .23)
	check(absf(a.actors[0].position.x-2.0) < .001, "Bomb pass-through expires after the body leaves")
	a = fresh()
	put(a, 0, Vector2(2.2,1))
	a.place_bomb(0)
	check(a.bombs[0].cell == Vector2i(2,1), "Mid-tile bomb placement uses the nearest tile")
	a = fresh()
	a.flames[Vector2i(2,1)] = .5
	a.move_actor(0, Vector2i.RIGHT, .23)
	check(not a.actors[0].alive and a.actors[0].position.x < 1.5, "Blast hits the body before its center enters a burning tile")
	a = fresh()
	a.actors[0].shield = true
	a.flames[Vector2i(2,1)] = .5
	a.move_actor(0, Vector2i.RIGHT, .23)
	check(a.actors[0].alive and not a.actors[0].shield, "Shield protects continuous entry into fire")
	a = fresh()
	put(a, 1, Vector2(5,5))
	a.grid[5][6] = Arena.CRATE
	var before: Vector2 = a.actors[1].position
	Bot.step(a,1)
	check(a.actors[1].position.distance_to(before) > 0 and a.actors[1].position.distance_to(before) < .1, "AI also moves fractionally")
	for i in 30:
		before = a.actors[1].position
		a.tick(1.0/60.0)
		Bot.step(a,1)
		check(a.actors[1].position.distance_to(before) <= 1.0/60.0/a.actors[1].move_time + .0001, "AI never jumps at waypoint changes")
	for direction in Arena.DIRECTIONS:
		for obstacle in [Arena.WALL, Arena.CRATE]:
			a = fresh()
			put(a,0,Vector2(6,5))
			var blocked: Vector2i = Vector2i(6,5) + direction
			a.grid[blocked.y][blocked.x] = obstacle
			a.move_actor(0,Vector2(direction),1.)
			check(a.actors[0].position == Vector2(6,5), "Every wall/crate approach stops at the center")
	a = fresh()
	put(a,0,Vector2(6,5))
	for frame in 180:
		var angle := floorf(frame/15.0) * TAU/12.0
		a.move_actor(0,Vector2(sin(angle),-cos(angle)))
		point = a.actors[0].position
		check(absf(point.x-roundf(point.x)) < .00001 or absf(point.y-roundf(point.y)) < .00001, "Changing analog angles never leaves grid center lines")
	for pair in [[Vector2(1.8,1),Vector2(2,1.2)],[Vector2(1,1.8),Vector2(1.2,2)]]:
		for i in range(11):
			point = Arena.interpolate_lane(pair[0],pair[1],i/10.0)
			check(absf(point.x-roundf(point.x)) < .00001 or absf(point.y-roundf(point.y)) < .00001, "Online corner interpolation stays centered")
	print("AtomicTux continuous motion: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
