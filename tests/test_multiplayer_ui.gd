extends SceneTree
var failures := 0
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._pointer_down(0,game.buttons[1].rect.get_center())
	check(game.mode == "network" and game.online_ui.visible,"Menu opens native multiplayer screen")
	check(Input.emulate_mouse_from_touch,"Touch events reach native text fields and buttons")
	var ui = game.online_ui
	check(ui.name_edit.max_length == 20 and ui.host_edit.text == game.network.host,"Name field and saved address are available")
	ui.name_edit.text = "Ada Tux"
	ui.host_edit.text = "not an IP"
	game.network.connect_server(ui.host_edit.text,8765,ui.name_edit.text)
	check(ui.status_label.text.contains("valid server IP"),"Invalid connection details get inline feedback")
	ui.host_edit.text = "192.168.1.20"
	game.network.host = ui.host_edit.text
	ui.status_label.text = ""
	await capture("res://builds/multiplayer-connect.png")
	ui.show_trust("A1B2C3D4".repeat(8))
	check(ui.page == "trust","First connection exposes certificate verification")
	await capture("res://builds/multiplayer-trust.png")
	game.network.identity = "alice"
	game.network.player_name = "Ada Tux"
	var entries := [{"id":"1","name":"Penguin party","owner":"bob","players":[{"id":"bob","name":"Bob","ready":true}],"state":"waiting"},
		{"id":"2","name":"Friday night","owner":"c","players":[{},{},{},{}],"state":"waiting"}]
	game.network.message_received.emit({"type":"rooms","rooms":entries})
	check(ui.page == "browser" and ui.rooms.size() == 2,"Live game list renders waiting rooms")
	ui.room_edit.text = "My new room"
	ui.difficulty_select.selected = 2
	game.network.message_received.emit({"type":"rooms","rooms":entries})
	check(ui.room_edit.text == "My new room" and ui.difficulty_select.selected == 2,"Live refresh preserves creation draft")
	await capture("res://builds/multiplayer-browser.png")
	var room := {"id":"1","name":"Penguin party","owner":"alice","state":"waiting","players":[
		{"id":"alice","name":"Ada Tux","ready":true},{"id":"bob","name":"Bob","ready":true}]}
	game.network.message_received.emit({"type":"room","room":room})
	check(ui.page == "room" and ui.room.players.size() == 2,"Waiting room shows player count and names")
	var start: Button
	for child in ui.panel.get_children():
		if child is Button and child.text == "START GAME": start = child
	check(start != null and not start.disabled,"Owner can start before all four slots fill")
	await capture("res://builds/multiplayer-room.png")
	room.players[1].ready = false
	game.network.message_received.emit({"type":"room","room":room})
	for child in ui.panel.get_children():
		if child is Button and child.text == "START GAME": start = child
	check(start.disabled,"Rematch waits for remaining players' decisions")
	room.owner = "bob"
	game.network.message_received.emit({"type":"room","room":room})
	check(not ui.panel.get_children().any(func(c): return c is Button and c.text == "START GAME"),"Non-owner has no start control")
	game._menu()
	check(not ui.visible and game.mode == "menu" and not Input.emulate_mouse_from_touch,"Return to solo menu restores game controls")
	game.queue_free()
	await process_frame
	print("AtomicTux multiplayer UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
