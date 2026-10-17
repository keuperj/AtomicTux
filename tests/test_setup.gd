extends SceneTree
const Arena = preload("res://scripts/arena.gd")
const Bot = preload("res://scripts/bot.gd")
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func preview(game: Node, name: String) -> void:
	game.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/" + name + ".png")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.buttons.size() == 3, "Landing has exactly three mode buttons")
	await preview(game, "landing")
	game.buttons[0].action.call()
	check(game.mode == "setup", "Solo opens setup")
	await preview(game, "solo-setup")
	game.opponents = 1
	game.level = 0
	game.enabled_powerups = ["shield"]
	game._start_match()
	check(game.arena.actors.size() == 2, "One opponent creates two contestants")
	check(game.arena.actors[1].move_time == 0.57, "Relaxed opponent uses slower movement")
	check(game.arena.enabled_powerups == ["shield"], "Solo passes chosen drops to simulation")
	game.countdown = 0
	game._process(0.1)
	check(game.mode == "playing", "Reduced roster simulates without indexing missing actors")
	game._start_demo()
	check(game.demo and game.arena.ai_only and game.arena.actors.size() == 4, "Demo has four AI contestants")
	check(game.arena.enabled_powerups == Arena.POWER_UPS, "Demo enables every drop regardless of solo choices")
	check(game.arena.actors[0].move_time == game.arena.actors[1].move_time, "First bot uses AI speed")
	game.countdown = 0
	game._bomb()
	check(game.arena.bombs.is_empty(), "Demo ignores human bomb input")
	var initial: Vector2 = game.arena.actors[0].position
	for i in 60: game._process(1.0 / 60.0)
	check(game.arena.actors[0].position != initial or game.arena.actors[0].bombs > 0, "First contestant is driven by AI")
	await preview(game, "demo")
	game.arena.actors[0].alive = false
	game.arena.tick(0)
	check(not game.arena.finished, "First bot dying does not end demo")
	for id in [1, 2]: game.arena.actors[id].alive = false
	game._process(0.02)
	check(game.mode == "result" and game.arena.winner == 3, "Demo reports last surviving bot")
	check(game.rounds == 0 and game.victories == 0, "Demo does not count toward player records")
	game.buttons[0].action.call()
	check(game.demo and game.mode == "playing", "Replay preserves demo mode")
	game._menu()
	game._start_match()
	check(not game.demo and game.arena.actors.size() == 2 and game.arena.enabled_powerups == ["shield"], "Demo preserves solo setup")
	# Exercise actual crate destruction across seeds, with restricted and empty pools.
	var drops := 0
	for pool in [[], ["shield"]]:
		for seed_value in 40:
			var arena := Arena.new()
			arena.start(seed_value, 1, 1, pool)
			arena.grid[1][2] = Arena.CRATE
			arena.place_bomb(0)
			arena._detonate(0)
			for kind in arena.pickups.values():
				drops += 1
				check(pool.has(kind), "Crates only drop enabled power-ups")
			if pool.is_empty(): check(arena.pickups.is_empty(), "No power-ups means no drops")
	check(drops > 0, "Restricted pool test actually produced drops")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("AtomicTux setup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
