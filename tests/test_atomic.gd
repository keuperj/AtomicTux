extends SceneTree
const Arena = preload("res://scripts/arena.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var a := Arena.new()
	a.start(42)
	for y in range(1,10):
		for x in range(1,12): a.grid[y][x] = Arena.EMPTY
	a.pickups[Vector2i(1,1)] = "atomic"
	a.tick(0)
	check(a.actors[0].atomic, "Pickup arms atomic bomb")
	a.actors[0].capacity = 0
	check(not a.place_bomb(0) and a.actors[0].atomic, "Failed placement preserves charge")
	a.actors[0].capacity = 2
	a.grid[1][3] = Arena.CRATE
	a.grid[1][4] = Arena.WALL
	a.grid[1][7] = Arena.CRATE
	a.grid[3][1] = Arena.WALL
	a.grid[7][1] = Arena.CRATE
	check(a.place_bomb(0) and not a.actors[0].atomic, "Successful placement consumes charge")
	check(a.bombs[0].power == Arena.ATOMIC_POWER, "Placed bomb retains atomic power")
	check(a.danger_map().has(Vector2i(11,1)) and a.danger_map().has(Vector2i(1,9)), "AI sees blast beyond obstacles")
	a.actors[0].cell = Vector2i(5,5)
	a.actors[0].position = Vector2(5,5)
	check(a.place_bomb(0) and a.bombs[1].power == 2, "Next bomb returns to ordinary range")
	a.actors[1].cell = Vector2i(9,1)
	a.actors[1].position = Vector2(9,1)
	a.place_bomb(1)
	a.actors[1].shield = true
	a.bombs[0].fuse = 0
	a.tick(0.01)
	check(a.flames.has(Vector2i(11,1)) and a.flames.has(Vector2i(1,9)), "Atomic reaches full row and column")
	check(not a.flames.has(Vector2i(5,5)), "Atomic does not hit off-axis tiles")
	check(a.tile(Vector2i(7,1)) == Arena.EMPTY and a.tile(Vector2i(1,7)) == Arena.EMPTY, "Crates beyond walls are destroyed")
	check(a.tile(Vector2i(4,1)) == Arena.WALL, "Permanent walls survive")
	check(a.bomb_at(Vector2i(9,1)) == -1, "Distant bomb chain-reacts")
	check(a.actors[1].alive and not a.actors[1].shield, "Shield protects against atomic blast")
	var counts := {}
	for kind in Arena.POWER_UPS: counts[kind] = 0
	for i in 10000: counts[a._roll_powerup()] += 1
	check(counts.bomb > 4000 and counts.bomb < 5000, "Extra bomb drops near 45 percent")
	check(counts.speed > 300 and counts.speed < 600, "Speed drops near 5 percent")
	a.start(42)
	check(not a.actors[0].atomic, "New round clears atomic charge")
	print("AtomicTux atomic: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
