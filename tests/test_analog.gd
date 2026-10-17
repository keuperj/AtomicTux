extends SceneTree
const Arena = preload("res://scripts/arena.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fresh() -> TuxArena:
	var arena := Arena.new()
	arena.start(42)
	for y in range(1,10):
		for x in range(1,12): arena.grid[y][x] = 0
	arena.actors[0].position = Vector2(6,5)
	arena.actors[0].cell = Vector2i(6,5)
	return arena

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._start_match()
	game.countdown = 0
	var center: Vector2 = game._move_center()
	for hour in 12:
		var angle := hour * TAU / 12.0
		var expected := Vector2(sin(angle),-cos(angle))
		var direction: Vector2 = game._pad_direction(center + expected * 80)
		check(direction.is_equal_approx(expected), "Proportional joystick angle at %d o'clock" % hour)
		var arena := fresh()
		arena.move_actor(0,direction,.17)
		var moved: Vector2 = arena.actors[0].position - Vector2(6,5)
		check(moved.distance_to(expected) < .0001, "Both axes receive their share at %d o'clock" % hour)
		check(absf(moved.length()-1) < .0001, "Diagonal speed stays within one movement budget")
	check(game._pad_direction(center+Vector2(5,5)) == Vector2.ZERO, "Joystick center remains a dead zone")
	var a := fresh()
	a.move_actor(0,Vector2(1,1),.17)
	check(absf(a.actors[0].position.distance_to(Vector2(6,5))-1) < .0001, "Unnormalized inputs cannot increase speed")
	a = fresh()
	for y in range(1,10): a.grid[y][7] = Arena.WALL
	a.move_actor(0,Vector2(.6,.8),.34)
	check(absf(a.actors[0].position.x-6.22) < .001 and absf(a.actors[0].position.y-6.6) < .001, "Wall sliding retains the unblocked component's budget")
	a = fresh()
	a.grid[5][7] = Arena.WALL
	a.grid[6][6] = Arena.WALL
	a.move_actor(0,Vector2(1,1),1.)
	check(a.actors[0].position.x < 6.221 and a.actors[0].position.y < 5.221, "Diagonal input cannot cut through a solid corner")
	a = fresh()
	a.actors[0].position = Vector2(7,5)
	a.actors[0].cell = Vector2i(7,5)
	a.place_bomb(0)
	a.actors[0].position = Vector2(6,5)
	a.actors[0].cell = Vector2i(6,5)
	a.actors[0].kick = true
	a.move_actor(0,Vector2(.8660254,.5),.17)
	check(a.bombs[0].direction == Vector2i.RIGHT and a.bombs[0].cell == Vector2i(8,5), "Diagonal steering kicks bombs along the contacted axis")

	var pulses: Array = []
	game.haptics.pulse_requested.connect(func(duration, strength): pulses.append([duration,strength]))
	check(not game.haptics.explosion(Vector2(1,1),[Vector2i(9,9)]), "Distant blast produces no vibration")
	check(not game.haptics.explosion(Vector2(1,1),[]), "Empty blast produces no vibration")
	check(game.haptics.explosion(Vector2(1,1),[Vector2i(3,1)]), "Nearby blast requests a pulse")
	var weaker: Array = pulses.back()
	check(not game.haptics.explosion(Vector2(1,1),[Vector2i(1,1)]), "Chain reaction pulses are rate limited")
	game.haptics.last_pulse_ms = -1000
	game.haptics.explosion(Vector2(1,1),[Vector2i(1,1)])
	check(pulses.back()[0] > weaker[0] and pulses.back()[1] > weaker[1], "Closer blast gives a longer stronger pulse")
	pulses.clear()
	game.haptics.last_pulse_ms = -1000
	game.foreground = false
	game._on_exploded([game.arena.actors[0].cell])
	check(pulses.is_empty(), "No vibration while backgrounded")
	game.foreground = true
	game.mode = "spectating"
	game._on_exploded([game.arena.actors[0].cell])
	check(pulses.is_empty(), "No vibration for an eliminated spectator")
	game.mode = "playing"
	game.arena.place_bomb(0)
	game.arena.bombs[0].fuse = 0
	game.arena.tick(.01)
	check(pulses.size() == 1, "Real local detonation triggers haptics")
	print("AtomicTux analog/haptics: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(1 if failures else 0)
