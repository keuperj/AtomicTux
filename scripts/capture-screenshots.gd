extends SceneTree
## Render actual game UI and a seeded match for the project documentation.
const Bot = preload("res://scripts/bot.gd")

func _initialize() -> void:
	run.call_deferred()

func capture(game: Node, filename: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://docs/screenshots/" + filename + ".png")
	assert(result == OK, "Screenshot could not be saved")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshot capture requires a rendering display; omit --headless.")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.opponents = 3
	game.level = 1
	game.enabled_powerups = game.Arena.POWER_UPS.duplicate()
	await capture(game, "landing")
	game._open_setup()
	await capture(game, "single-player")
	game._start_match()
	game.arena.start(7, 1)
	game.countdown = 0
	# Drive the human slot with the same bot for a reproducible live gameplay view.
	for frame in 2400:
		Bot.step(game.arena, 0)
		game._process(1.0 / 60.0)
		if game.mode != "playing": break
		if game.arena.elapsed > 8 and game.arena.flames.size() >= 6: break
	await capture(game, "arena")
	game.queue_free()
	await process_frame
	quit()
