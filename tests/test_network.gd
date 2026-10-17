extends SceneTree
const Network = preload("res://scripts/network_client.gd")
var first: TuxNetwork
var second: TuxNetwork
var messages: Array = [{},{}]
var failures := 0
var checks := 0
var expected_fingerprint := ""

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func until(condition: Callable, description: String, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var success: bool = condition.call()
	check(success,description)
	return success

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	expected_fingerprint = OS.get_environment("ATOMICTUX_TEST_FINGERPRINT")
	var port := OS.get_environment("ATOMICTUX_TEST_PORT").to_int()
	if port <= 0:
		push_error("Run through python3 -m tests.test_network_integration")
		quit(1)
		return
	first = Network.new()
	second = Network.new()
	root.add_child(first)
	root.add_child(second)
	for index in 2:
		var client: TuxNetwork = [first,second][index]
		client.message_received.connect(func(msg): messages[index][str(msg.type)] = msg)
		client.trust_requested.connect(func(fingerprint):
			check(fingerprint == expected_fingerprint,"Certificate fingerprint matches server")
			if fingerprint == expected_fingerprint: client.trust_certificate())
		client.status_changed.connect(func(message): print("NET ",index,": ",message))
	first.connect_server("127.0.0.1",port,"Alice")
	second.connect_server("127.0.0.1",port,"Bob")
	if not await until(func(): return first.identity != "" and second.identity != "", "Two named Godot clients connect over verified TLS"):
		quit(1)
		return
	check(first.identity != second.identity,"Server assigns separate identities")
	first.send_message({"type":"create","name":"Penguin party","difficulty":0})
	if not await until(func(): return messages[0].has("room"),"Owner creates waiting room"): quit(1); return
	var room_id: String = messages[0].room.room.id
	await until(func(): return messages[1].has("rooms") and messages[1].rooms.rooms.size() == 1,"Other client sees waiting game")
	second.send_message({"type":"join","room":room_id})
	await until(func(): return messages[0].room.room.players.size() == 2,"Lobby updates player count")
	first.send_message({"type":"powerup_amount","powerup":"bomb","change":1})
	await until(func(): return int(messages[0].room.room.powerup_amounts.bomb) == 7 and int(messages[1].room.room.powerup_amounts.bomb) == 7, "Host amounts broadcast to both clients")
	second.send_message({"type":"powerup_amount","powerup":"bomb","change":1})
	await until(func(): return messages[1].has("error") and str(messages[1].error.message).contains("owner"), "Guest cannot change power-ups")
	second.send_message({"type":"start"})
	await until(func(): return messages[1].has("error"),"Non-owner cannot start")
	first.send_message({"type":"start"})
	if not await until(func(): return messages[0].has("started") and messages[1].has("started"),"Owner starts both clients"): quit(1); return
	check(int(messages[1].started.state.powerup_amounts.bomb) == 7, "Server starts match with host amounts")
	check(int(messages[1].started.slot) == 1,"Second client receives its own actor slot")
	check(messages[0].started.state.humans.size() == 2 and messages[0].started.state.actors.size() == 4,"Empty slots filled with AI")
	# Exercise the real main scene's online slot mapping and presentation state machine.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._network_message(messages[1].started)
	check(game.online and game.local_actor_id == 1 and game._actor_name(1) == "Bob","Game displays local name and actor correctly")
	var motion: Dictionary = messages[1].started.duplicate(true)
	motion.type = "snapshot"
	motion.state.actors[1].position = [10.7, 9.0]
	game._network_message(motion)
	check(game.arena.actors[1].position.is_equal_approx(Vector2(10.7,9)), "Client preserves fractional authoritative positions")
	game._process_online(.025)
	check(game.arena.actors[1].display_position.is_equal_approx(Vector2(10.85,9)), "Online rendering interpolates between snapshots")
	game._process_online(.025)
	check(game.arena.actors[1].display_position.is_equal_approx(Vector2(10.7,9)), "Interpolation reaches the snapshot without tile snapping")
	var pulses: Array = []
	game.haptics.pulse_requested.connect(func(duration, strength): pulses.append([duration,strength]))
	var explosion: Dictionary = motion.duplicate(true)
	explosion.events = [{"type":"explosion", "cells":[[11,9]]}]
	game._network_message(explosion)
	check(pulses.size() == 1, "Nearby online explosion triggers haptic feedback")
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < deadline:
		first.send_message({"type":"input","direction":[0.5,0.8660254],"bomb":false})
		second.send_message({"type":"input","direction":[-1,0],"bomb":false})
		if messages[0].has("snapshot") and bool(messages[0].snapshot.state.finished): break
		await create_timer(.05).timeout
	check(messages[0].has("snapshot") and bool(messages[0].snapshot.state.finished),"Server round completes")
	check(float(messages[0].snapshot.state.elapsed) > 0,"Authoritative match ticks")
	check(messages[0].snapshot.state.actors[0].cell != [1,1],"Server applies held movement")
	check(float(messages[0].snapshot.state.actors[0].position[1]) > 1.1, "Server applies the vertical component of analog input")
	var final_state: Dictionary = messages[1].snapshot
	game._network_message(final_state)
	if game.mode == "dying": game._process_online(2.1)
	check(game.mode == "result","Online round reaches results")
	# Death of local slot 1 keeps spectating instead of ending everyone's match.
	game._network_message(messages[1].started)
	var death: Dictionary = messages[1].started.duplicate(true)
	death.type = "snapshot"
	death.events = []
	death.state.actors[1].alive = false
	death.state.flames = [{"cell":death.state.actors[1].cell,"time":0.65}]
	game._network_message(death)
	check(game.mode == "dying","Online death preserves death animation")
	game._process_online(2.1)
	check(game.mode == "spectating","Eliminated player spectates unfinished round")
	game._network_message(final_state)
	check(game.mode == "result","Spectator receives end-of-round choices")
	game.queue_free()
	first.send_message({"type":"ready"})
	second.send_message({"type":"ready"})
	await until(func():
		var room: Dictionary = messages[0].room.room
		return room.state == "waiting" and room.players.all(func(p): return p.ready),"Both players opt into same-room rematch")
	messages[0].erase("started")
	first.send_message({"type":"start"})
	await until(func(): return messages[0].has("started") and int(messages[0].started.round) == 2,"Owner starts second round in same room")
	second.send_message({"type":"leave"})
	await until(func(): return messages[1].has("left"),"Player can exit to game selection")
	await until(func(): return messages[0].room.room.players.size() == 1,"Departure updates owner lobby state")
	first.disconnect_server()
	second.disconnect_server()
	var cached := Network.new()
	root.add_child(cached)
	cached.trust_requested.connect(func(_fp): check(false,"Saved trust should not prompt again"))
	cached.connect_server("127.0.0.1",port,"Returning Tux")
	await until(func(): return cached.identity != "", "Saved certificate reconnects without another trust prompt")
	cached.disconnect_server()
	var wrong_pem := FileAccess.get_file_as_string(OS.get_environment("ATOMICTUX_TEST_WRONG_CERT"))
	cached.pins.set_value("certificates",cached.endpoint(),wrong_pem)
	cached.connect_server("127.0.0.1",port,"Rejected Tux")
	await until(func(): return not cached.connecting, "Changed certificate fails instead of downgrading")
	check(not cached.connected and cached.identity.is_empty(),"Untrusted server receives no player identity")
	cached.disconnect_server()
	cached.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("AtomicTux network: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
