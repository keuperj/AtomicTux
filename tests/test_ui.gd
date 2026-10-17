extends SceneTree
var failed := 0
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failed += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	check(game.mode == "menu", "Starts on menu")
	check(not quit_on_go_back, "Android Back is handled by game")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/menu.png")
	game._pointer_down(0, Vector2(200,480))
	check(game.mode == "playing" and game.countdown == 3.0, "Play starts countdown")
	game._bomb()
	check(game.arena.bombs.is_empty(), "No bombs during countdown")
	game.countdown = 0.0
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = game.position + Vector2(1180,580) * game.scale
	touch.pressed = true
	game._input(touch)
	check(game._direction() == Vector2i.RIGHT, "Touch D-pad works")
	var bomb_touch := InputEventScreenTouch.new()
	bomb_touch.index = 1
	bomb_touch.position = game.position + Vector2(150,580) * game.scale
	bomb_touch.pressed = true
	game._input(bomb_touch)
	check(game.arena.bombs.size() == 1 and game._direction() == Vector2i.RIGHT, "Simultaneous move and bomb touches")
	touch.pressed = false
	game._input(touch)
	check(game.held.is_empty(), "Releasing touch stops movement")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var time: float = game.arena.remaining
	game._process(1.0)
	check(game.mode == "paused" and game.arena.remaining == time, "Pause freezes simulation")
	game._toggle_pause()
	check(game.mode == "playing", "Resume restores gameplay")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.mode == "paused", "Backgrounding pauses game")
	game._toggle_pause()
	# Show all pickup pictograms in the rendered integration preview.
	for i in 4:
		var cell := Vector2i(4+i,5)
		game.arena.grid[cell.y][cell.x] = 0
		game.arena.pickups[cell] = ["bomb","fire","speed","kick"][i]
	game.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/arena.png")
	game.arena.actors[0].alive = false
	game._process(0.02)
	check(game.mode == "result", "Elimination shows results")
	game._start_match()
	check(game.arena.actors[0].alive and game.arena.bombs.is_empty(), "Replay resets match")
	game._menu()
	check(game.mode == "menu", "Return to menu")
	print("AtomicTux UI: %d checks, %d failures" % [checks,failed])
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failed else 0)
