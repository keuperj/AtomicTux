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
	game._pointer_down(0, game.buttons[0].rect.get_center())
	check(game.mode == "playing" and game.countdown == 3.0, "Play starts countdown")
	game._bomb()
	check(game.arena.bombs.is_empty(), "No bombs during countdown")
	game.countdown = 0.0
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = game.position + (game._move_center() + Vector2(60,0)) * game.scale
	touch.pressed = true
	game._input(touch)
	check(game._direction() == Vector2.RIGHT, "Touch joystick works")
	var bomb_touch := InputEventScreenTouch.new()
	bomb_touch.index = 1
	bomb_touch.position = game.position + game._bomb_center() * game.scale
	bomb_touch.pressed = true
	game._input(bomb_touch)
	check(game.arena.bombs.size() == 1 and game._direction() == Vector2.RIGHT, "Simultaneous move and bomb touches")
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
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._toggle_pause()
	# Show all pickup pictograms in the rendered integration preview.
	for i in 5:
		var cell := Vector2i(4+i,5)
		game.arena.grid[cell.y][cell.x] = 0
		game.arena.pickups[cell] = ["bomb","fire","speed","kick","shield"][i]
	game.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/arena.png")
	# Trigger a real lethal explosion, not a manually assigned death flag.
	game.arena.bombs[0].fuse = 0.0
	game._process(0.02)
	check(game.mode == "dying" and not game.arena.actors[0].alive, "Lethal explosion starts death sequence")
	check(game.arena.flames.has(game.arena.actors[0].cell), "Lethal fire remains visible")
	check(game.buttons.is_empty() and game.rounds == 0, "Results and replay are delayed")
	var frozen_time: float = game.arena.remaining
	var frozen_flames: Dictionary = game.arena.flames.duplicate()
	game._bomb()
	game._pointer_down(3,(game._move_center() + Vector2(60,0)))
	game._toggle_pause()
	game._process(0.8)
	check(game.mode == "dying" and game.held.is_empty(), "Input cannot interrupt death sequence")
	check(game.arena.remaining == frozen_time and game.arena.flames == frozen_flames, "Match freezes while death visuals play")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var death_time: float = game.death_remaining
	game._process(5.0)
	check(game.death_remaining == death_time, "Backgrounding preserves the death sequence")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._process(1.3)
	check(game.mode == "result" and game.rounds == 1, "Death sequence ends with results exactly once")
	game._start_match()
	check(game.arena.actors[0].alive and game.arena.bombs.is_empty() and game.death_remaining == 0, "Replay resets match and death animation")
	game.countdown = 0.0
	game.arena.flames[Vector2i(2,1)] = 0.5
	game.held[0] = Vector2i.RIGHT
	game._process(0.08)
	check(game.mode == "dying", "Walking into existing fire also shows death sequence")
	game._process(2.1)
	game._start_match()
	game.countdown = 0.0
	for id in range(1,4): game.arena.actors[id].alive = false
	game._process(0.02)
	check(game.mode == "result" and game.arena.winner == 0, "Victory does not play player death animation")
	game._start_match()
	game.countdown = 0.0
	game.arena.pickups[Vector2i(2,1)] = "shield"
	game.arena.move_actor(0,Vector2i.RIGHT,game.arena.actors[0].move_time)
	check(game.arena.actors[0].shield and game.flash.contains("SHIELD READY"), "Shield pickup updates player feedback")
	game.arena.place_bomb(0)
	game.arena.bombs[0].fuse = 0.0
	game._process(0.02)
	check(game.mode == "playing" and game.flash.contains("SHIELD ABSORBED"), "Shield hit gives feedback without death dialog")
	game._menu()
	check(game.mode == "menu", "Return to menu")
	print("AtomicTux UI: %d checks, %d failures" % [checks,failed])
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failed else 0)
