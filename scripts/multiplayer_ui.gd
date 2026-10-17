class_name TuxMultiplayerUI
extends Control
signal back_requested
var net: TuxNetwork
var panel: VBoxContainer
var status_label: Label
var host_edit: LineEdit
var port_edit: LineEdit
var name_edit: LineEdit
var room_edit: LineEdit
var difficulty_select: OptionButton
var room: Dictionary = {}
var rooms: Array = []
var page := "connect"

func setup(client: TuxNetwork) -> void:
	net = client
	position = Vector2(220,60)
	size = Vector2(840,680)
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 22
	for type_name in ["Button","LineEdit","OptionButton"]:
		for style_name in ["normal","hover","pressed","focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("20364a") if style_name != "hover" else Color("30566a")
			style.set_corner_radius_all(9)
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 10
			style.content_margin_bottom = 10
			theme_resource.set_stylebox(style_name,type_name,style)
	theme = theme_resource
	panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation",12)
	add_child(panel)
	net.message_received.connect(_message)
	net.status_changed.connect(_status)
	net.trust_requested.connect(show_trust)
	net.disconnected.connect(func():
		room = {}
		show_connect())
	show_connect()

func clear(title: String, subtitle: String) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	label(title,36,Color("68efcd"))
	label(subtitle,18)
	status_label = null

func label(value: String, font_size: int = 22, color: Color = Color("edf6fc")) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	panel.add_child(node)
	return node

func button(value: String, action: Callable, parent: Node = null) -> Button:
	if parent == null: parent = panel
	var node := Button.new()
	node.text = value
	node.custom_minimum_size.y = 48
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func field(caption: String, value: String, maximum: int = 64) -> LineEdit:
	label(caption,17,Color("829caf"))
	var node := LineEdit.new()
	node.text = value
	node.max_length = maximum
	node.custom_minimum_size.y = 48
	panel.add_child(node)
	return node

func status() -> void:
	status_label = label("",17,Color("ffce74"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _status(message: String) -> void:
	if is_instance_valid(status_label): status_label.text = message

func show_connect() -> void:
	page = "connect"
	clear("MULTIPLAYER", "Join a server. Find your people. Bring a bomb.")
	name_edit = field("YOUR NAME",net.player_name,20)
	host_edit = field("SERVER IP",net.host,45)
	port_edit = field("PORT",str(net.port),5)
	button("CONNECT",func(): net.connect_server(host_edit.text,port_edit.text.to_int(),name_edit.text))
	button("Forget saved certificate for this address",func(): net.forget_certificate(host_edit.text.strip_edges(),port_edit.text.to_int()))
	button("BACK",func():
		net.disconnect_server()
		back_requested.emit())
	status()

func show_trust(fingerprint: String) -> void:
	page = "trust"
	clear("VERIFY THIS SERVER", "First connection to " + net.endpoint())
	label("Compare this SHA-256 fingerprint with the server terminal.",20)
	label(fingerprint.substr(0,32)+"\n"+fingerprint.substr(32),22,Color("ffce74"))
	label("Trust only if both match. This certificate will be remembered.",19)
	button("FINGERPRINT MATCHES — TRUST & CONNECT",net.trust_certificate)
	button("CANCEL",func():
		net.disconnect_server()
		show_connect())
	status()

func show_browser() -> void:
	page = "browser"
	room = {}
	clear("ONLINE GAMES",net.player_name + "  •  " + net.endpoint())
	var row := HBoxContainer.new()
	panel.add_child(row)
	room_edit = LineEdit.new()
	room_edit.placeholder_text = "New game name"
	room_edit.max_length = 24
	room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(room_edit)
	difficulty_select = OptionButton.new()
	for value in ["Relaxed AI","Normal AI","Fierce AI"]: difficulty_select.add_item(value)
	difficulty_select.selected = 1
	row.add_child(difficulty_select)
	button("CREATE",func(): net.send_message({"type":"create","name":room_edit.text if not room_edit.text.strip_edges().is_empty() else (net.player_name+"'s game").left(24),"difficulty":difficulty_select.selected}),row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 330
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "No waiting games yet. Create the first one."
		list.add_child(empty)
	for entry in rooms:
		var room_id: String = entry.id
		var join := button("%s   •   %d / 4 PLAYERS   •   JOIN" % [entry.name,entry.players.size()],func(): net.send_message({"type":"join","room":room_id}),list)
		join.disabled = entry.players.size() >= 4
	button("REFRESH",func(): net.send_message({"type":"list"}))
	button("DISCONNECT",func():
		net.disconnect_server()
		show_connect())
	status()

func show_room() -> void:
	page = "room"
	clear(str(room.name),"WAITING ROOM  •  %d / 4 PLAYERS" % room.players.size())
	for player in room.players:
		label("%s%s%s" % [player.name, "  • OWNER" if player.id == room.owner else "", "  • READY" if player.ready else "  • DECIDING NEXT ROUND"],24)
	for i in range(room.players.size(),4): label("Empty slot  •  AI will join at start",20,Color("829caf"))
	var ready := false
	var all_ready := true
	for player in room.players:
		if player.id == net.identity: ready = player.ready
		all_ready = all_ready and player.ready
	if not ready: button("ANOTHER ROUND",func(): net.send_message({"type":"ready"}))
	if net.identity == room.owner:
		var start := button("START GAME",func(): net.send_message({"type":"start"}))
		start.disabled = not all_ready
	else:
		label("Waiting for the owner to start…",20,Color("68efcd"))
	button("LEAVE GAME",func(): net.send_message({"type":"leave"}))
	status()

func _message(msg: Dictionary) -> void:
	match str(msg.get("type","")):
		"rooms":
			rooms = msg.rooms
			if visible and page in ["connect","trust","browser"]:
				# Keep an in-progress room name when the live list updates.
				var draft := room_edit.text if page == "browser" and is_instance_valid(room_edit) else ""
				var level := difficulty_select.selected if page == "browser" and is_instance_valid(difficulty_select) else 1
				show_browser()
				room_edit.text = draft
				difficulty_select.selected = level
		"room":
			room = msg.room
			if visible and room.state != "playing": show_room()
		"left":
			room = {}
			if visible: show_browser()
		"error": _status(str(msg.message))
