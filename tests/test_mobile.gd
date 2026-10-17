extends SceneTree
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func touch(game: Node, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = game.position + point * game.scale
	event.pressed = pressed
	game._input(event)

func drag(game: Node, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = game.position + point * game.scale
	game._input(event)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game._start_match()
	game.countdown = 0
	var center: Vector2 = game._move_center()
	touch(game, 4, center, true)
	check(game.held.has(4) and game._direction() == Vector2i.ZERO, "Center touch captures joystick without moving")
	drag(game, 4, center + Vector2(70,0))
	check(game._direction() == Vector2i.RIGHT, "Slide from center starts moving")
	# Hold one touch over multiple simulation steps; no repeated press events.
	game.arena.start(42813, 0)
	for x in range(1, 6): game.arena.grid[1][x] = 0
	for i in 6: game._process(0.1)
	check(game.arena.actors[0].cell.x >= 3, "Held joystick continuously advances across tiles")
	drag(game, 4, center + Vector2(5,-180))
	check(game._direction() == Vector2i.UP, "Captured finger keeps moving outside pad and changes direction")
	touch(game, 8, center + Vector2(-60,0), true)
	check(not game.held.has(8) and game._direction() == Vector2i.UP, "Second finger cannot steal movement")
	touch(game, 9, game._bomb_center(), true)
	check(game.arena.actors[0].bombs == 1 and game._direction() == Vector2i.UP, "Bomb finger works during a held move")
	drag(game, 9, center + Vector2(60,0))
	check(game._direction() == Vector2i.UP, "Dragging bomb finger cannot take over joystick")
	touch(game, 9, game._bomb_center(), false)
	check(game._direction() == Vector2i.UP, "Releasing bomb finger preserves movement")
	drag(game, 4, center)
	check(game._direction() == Vector2i.ZERO and game.held.has(4), "Returning to dead zone stops without releasing capture")
	drag(game, 4, center + Vector2(-60,0))
	check(game._direction() == Vector2i.LEFT, "Same held finger can resume in a new direction")
	touch(game, 4, center, false)
	check(game.held.is_empty() and game.stick_offset == Vector2.ZERO, "Release stops and recenters")
	touch(game, 4, center + Vector2(50,0), true)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 4
	cancel.pressed = true
	cancel.canceled = true
	game._input(cancel)
	check(game.held.is_empty(), "Canceled touch cannot leave movement stuck")
	touch(game, 4, center + Vector2(50,0), true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.held.is_empty() and game.mode == "paused", "Background clears movement")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._toggle_pause()

	root.content_scale_size = Vector2i.ZERO
	for dimensions in [Vector2i(1280,800), Vector2i(1600,720), Vector2i(1024,768)]:
		root.size = dimensions
		await process_frame
		game._resize()
		var board: Rect2 = game.board_transform * Rect2(294,134,692,588)
		check(board.position.x >= 280 and board.end.x <= game.canvas_size.x - 280, "Board stays between side panels at %s" % dimensions)
		check(board.position.y >= 108 and board.end.y <= game.canvas_size.y - 68, "Board fits vertically at %s" % dimensions)
		check((game.canvas_size * game.scale).is_equal_approx(Vector2(dimensions)), "Canvas fills display at %s" % dimensions)
		var move: Vector2 = game._move_center()
		check(move.x + game.MOVE_TOUCH_RADIUS < game.canvas_size.x and move.y + game.MOVE_TOUCH_RADIUS < game.canvas_size.y, "Joystick fits at %s" % dimensions)
		touch(game, 1, move, true)
		drag(game, 1, move + Vector2(60,0))
		check(game._direction() == Vector2i.RIGHT, "Touch coordinates follow resize at %s" % dimensions)
		touch(game, 1, move, false)
		game.queue_redraw()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://builds/mobile-%dx%d.png" % [dimensions.x,dimensions.y])
	game._apply_layout(Rect2(40,10,1520,690))
	check(game.position == Vector2(40,10), "Safe area offsets UI")
	touch(game, 1, game._move_center() + Vector2(60,0), true)
	check(game._direction() == Vector2i.RIGHT, "Touch coordinates account for safe-area inset")
	game._resize()
	check(game.held.is_empty(), "Resize cancels active touch")

	var sound = game.sound
	sound.enabled = true
	for kind in ["place","boom","pickup","shield"]:
		check(sound.samples[kind].size() == 3, "Cached variants for " + kind)
		var sample: AudioStreamWAV = sound.samples[kind][0]
		check(sample.data.decode_s16(0) == 0 and sample.data.decode_s16(sample.data.size()-2) == 0, "No hard edge clicks for " + kind)
		check(sample.data != sound.samples[kind][1].data, "Audible variation for " + kind)
		sample.save_to_wav("res://builds/sound-" + kind + ".wav")
	sound.play_effect("place")
	sound.play_effect("pickup")
	check(sound.voices.filter(func(v): return v.playing).size() >= 2, "Effects overlap instead of cutting off")
	sound.enabled = false
	check(sound.voices.all(func(v): return not v.playing), "Mute stops every active sound")
	print("AtomicTux mobile: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(1 if failures else 0)
