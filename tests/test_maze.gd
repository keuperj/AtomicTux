extends SceneTree
const Arena = preload("res://scripts/arena.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func crate_count(a: TuxArena) -> int:
	var count := 0
	for row in a.grid: count += row.count(Arena.CRATE)
	return count

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var layouts := {}
	for seed_value in 50:
		var a := Arena.new()
		a.start(seed_value)
		var visited := {Vector2i(1,1):true}
		var queue: Array = [Vector2i(1,1)]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			for step in Arena.DIRECTIONS:
				var next: Vector2i = cell + step
				if a.tile(next) != Arena.WALL and not visited.has(next):
					visited[next] = true
					queue.append(next)
		var walls: Array = []
		var reachable := true
		for y in Arena.HEIGHT:
			for x in Arena.WIDTH:
				var cell := Vector2i(x,y)
				if a.tile(cell) == Arena.WALL: walls.append(cell)
				else: reachable = reachable and visited.has(cell)
		check(reachable, "All floor and crate tiles share one connected maze")
		for actor in a.actors:
			check(visited.has(actor.cell) and a.tile(actor.cell) == Arena.EMPTY, "Every spawn is connected and clear")
		layouts[str(walls)] = true
		check(a.initial_crates == crate_count(a) and a.initial_crates > 0, "Starting crate count is recorded")
	check(layouts.size() == 50, "Seeds generate varied permanent wall layouts")
	var a := Arena.new()
	a.start(42)
	var sites := a.crate_sites.duplicate()
	for cell in sites: a.grid[cell.y][cell.x] = Arena.EMPTY
	var target := ceili(a.initial_crates * 0.2)
	a._regenerate_crates(1.99)
	check(crate_count(a) == 0, "Regeneration is gradual")
	a._regenerate_crates(0.02)
	check(crate_count(a) == 1, "One crate returns after two seconds")
	for i in target + 5: a._regenerate_crates(2.0)
	check(crate_count(a) == target, "Regeneration stops at rounded-up twenty percent")
	# Reserve just one original site and verify each protection separately.
	var cell: Vector2i = sites[0]
	a.crate_sites = [cell]
	a.initial_crates = 5
	for original in sites: a.grid[original.y][original.x] = Arena.EMPTY
	a.pickups[cell] = "shield"
	a._regenerate_crates(2)
	check(a.tile(cell) == Arena.EMPTY, "Never replace a pickup")
	a.pickups.clear()
	a.flames[cell] = 0.5
	a._regenerate_crates(2)
	check(a.tile(cell) == Arena.EMPTY, "Never spawn in fire")
	a.flames.clear()
	a.actors[0].position = Vector2(cell) + Vector2(0.4,0)
	a._regenerate_crates(2)
	check(a.tile(cell) == Arena.EMPTY, "Keep regeneration away from fractional player positions")
	a.actors[0].cell = cell
	a.place_bomb(0)
	a.actors[0].position = Vector2(1,1)
	a._regenerate_crates(2)
	check(a.tile(cell) == Arena.EMPTY, "Never regenerate under an active bomb")
	a = Arena.new()
	a.start(42)
	for original in a.crate_sites: a.grid[original.y][original.x] = Arena.EMPTY
	a.tick(2.01)
	check(crate_count(a) == 1, "Live simulation invokes regeneration")
	a.finished = true
	a.tick(10)
	check(crate_count(a) == 1, "Finished rounds never regenerate")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for direction in Arena.DIRECTIONS:
		var side := Vector2(-direction.y,direction.x)
		for noise in [-0.2, 0.2]:
			check(game._pad_direction(game._move_center() + (Vector2(direction)+side*noise)*80).is_equal_approx(Vector2(direction)), "Symmetric cardinal sensitivity ignores minor thumb drift")
		check(game._pad_direction(game._move_center()+Vector2(direction)*15).is_equal_approx(Vector2(direction)), "All directions respond just outside the smaller dead zone")
		for turn_sign in [-1,1]:
			a = Arena.new()
			a.start(42)
			for y in range(1,10):
				for x in range(1,12): a.grid[y][x] = Arena.EMPTY
			a.actors[0].position = Vector2(6,5)
			a.actors[0].cell = Vector2i(6,5)
			a.move_actor(0,Vector2(direction),a.actors[0].move_time*0.4)
			var turn: Vector2 = side * turn_sign
			var input: Vector2 = (turn - Vector2(direction)*0.3).normalized()
			a.move_actor(0,input,a.actors[0].move_time)
			var expected: Vector2 = Vector2(6,5) + Vector2(direction) + turn*0.4
			check(a.actors[0].position.distance_to(expected) < .001, "Noisy perpendicular turn finishes current lane instead of reversing")
	game._start_match()
	for size in [Vector2(1280,800), Vector2(1600,720), Vector2(1024,768)]:
		game._apply_layout(Rect2(Vector2(20,10),size-Vector2(40,20)))
		for direction in Arena.DIRECTIONS:
			var touch := InputEventScreenTouch.new()
			touch.index = 4
			touch.pressed = true
			touch.position = game.position + (game._move_center() + Vector2(direction)*60)*game.scale
			game._input(touch)
			check(game._direction().is_equal_approx(Vector2(direction)), "Screen-to-joystick calibration works in every direction and aspect ratio")
			touch.pressed = false
			game._input(touch)
	game.queue_free()
	await process_frame
	print("AtomicTux maze/steering: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
