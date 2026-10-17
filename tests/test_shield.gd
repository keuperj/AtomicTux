extends SceneTree
const Arena = preload("res://scripts/arena.gd")
var checks := 0
var failures := 0
var absorbs := 0

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
	for y in range(1,Arena.HEIGHT-1):
		for x in range(1,Arena.WIDTH-1): a.grid[y][x] = Arena.EMPTY
	a.shield_absorbed.connect(func(_id): absorbs += 1)
	return a

func _initialize() -> void:
	var a := fresh()
	check(Arena.POWER_UPS.has("shield"), "Shield is in crate drop pool")
	a.pickups[Vector2i(2,1)] = "shield"
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(a.actors[0].shield and a.pickups.is_empty(), "Pickup grants shield and disappears")
	a.tick(0.2)
	a.pickups[Vector2i(3,1)] = "shield"
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	a.place_bomb(0)
	a.bombs[0].fuse = 0.0
	a.tick(0.01)
	check(a.actors[0].alive and not a.finished, "Shield survives real bomb explosion")
	check(not a.actors[0].shield and absorbs == 1, "One shield charge consumed, duplicates do not stack")
	for frame in 42: a.tick(1.0/60.0)
	check(a.actors[0].alive and absorbs == 1, "Lingering fire cannot consume shield repeatedly or kill immediately")
	a.tick(0.1)
	check(a.actors[0].invulnerable == 0.0, "Grace period expires")
	a.place_bomb(0)
	a.bombs[0].fuse = 0.0
	a.tick(0.01)
	check(not a.actors[0].alive and a.finished, "Second explosion is lethal")
	a = fresh()
	a.actors[0].shield = true
	a.flames[Vector2i(2,1)] = 0.5
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(a.actors[0].alive and not a.actors[0].shield, "Shield also absorbs walking into existing fire")
	a.tick(0.2)
	a.pickups[Vector2i(3,1)] = "shield"
	a.move_actor(0,Vector2i.RIGHT,a.actors[0].move_time)
	check(a.actors[0].shield, "Can replenish shield after consumption")
	a.flames[Vector2i(3,1)] = 0.3
	a.tick(0.1)
	check(a.actors[0].shield, "Grace protects newly collected charge from same lingering blast")
	a.tick(0.6)
	a.flames[Vector2i(3,1)] = 0.5
	a.tick(0.01)
	check(a.actors[0].alive and not a.actors[0].shield, "Replenished shield absorbs next hit")
	a.start(43)
	check(not a.actors[0].shield and a.actors[0].invulnerable == 0.0, "New round resets protection")
	a = fresh()
	a.actors[0].shield = true
	a.place_bomb(0)
	put(a, 1, Vector2i(3,1))
	a.place_bomb(1)
	put(a, 1, Vector2i(9,9))
	a.bombs[0].fuse = 0.0
	a.tick(0.01)
	check(a.bombs.is_empty() and a.actors[0].alive, "Shield handles overlapping chain reaction")
	a = fresh()
	a.actors[1].shield = true
	a.flames[a.actors[1].cell] = 0.5
	a.tick(0.01)
	check(a.actors[1].alive and not a.actors[1].shield, "Same pickup rules apply to AI contestants")
	print("AtomicTux shield: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
