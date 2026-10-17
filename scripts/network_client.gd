class_name TuxNetwork
extends Node
signal message_received(message: Dictionary)
signal status_changed(message: String)
signal trust_requested(fingerprint: String)
signal disconnected
var socket: WebSocketPeer
var bootstrap: HTTPRequest
var identity := ""
var player_name := "Tux"
var host := "92.205.18.100"
var port := 8081
var pending_pem := ""
var connected := false
var connecting := false
var connect_time := 0.0
var pins := ConfigFile.new()

func _ready() -> void:
	pins.load("user://servers.cfg")
	host = str(pins.get_value("last", "host", host))
	port = int(pins.get_value("last", "port", port))
	player_name = str(pins.get_value("last", "name", player_name))
	bootstrap = HTTPRequest.new()
	bootstrap.timeout = 10.0
	bootstrap.body_size_limit = 16384
	bootstrap.max_redirects = 0
	add_child(bootstrap)
	bootstrap.request_completed.connect(_certificate_received)

func endpoint() -> String:
	return ("[" + host + "]" if ":" in host else host) + ":" + str(port)

func connect_server(address: String, server_port: int, username: String) -> void:
	disconnect_server()
	host = address.strip_edges()
	player_name = username.strip_edges()
	port = server_port
	if not host.is_valid_ip_address() or port < 1 or port > 65535 or player_name.is_empty() or player_name.length() > 20:
		status_changed.emit("Enter a valid server IP, port (1–65535), and name (1–20 characters).")
		return
	pins.set_value("last", "host", host)
	pins.set_value("last", "port", port)
	pins.set_value("last", "name", player_name)
	pins.save("user://servers.cfg")
	var pem := str(pins.get_value("certificates",endpoint(),""))
	if not pem.is_empty():
		_open_socket(pem)
	else:
		status_changed.emit("Contacting server for its certificate…")
		# Only public certificate discovery is unverified. Never send identity or game data here.
		bootstrap.set_tls_options(TLSOptions.client_unsafe())
		if bootstrap.request("https://" + endpoint() + "/certificate") != OK:
			status_changed.emit("Could not contact server.")

func _certificate_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_changed.emit("Could not reach server. Check IP, port, and firewall.")
		return
	pending_pem = body.get_string_from_utf8().replace("\r\n","\n")
	var cert := X509Certificate.new()
	if cert.load_from_string(pending_pem) != OK:
		status_changed.emit("Server returned an invalid certificate.")
		return
	var base64_der := pending_pem.replace("-----BEGIN CERTIFICATE-----", "").replace("-----END CERTIFICATE-----", "").replace("\n", "").strip_edges()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(Marshalls.base64_to_raw(base64_der))
	trust_requested.emit(hash.finish().hex_encode().to_upper())

func trust_certificate() -> void:
	if pending_pem.is_empty(): return
	pins.set_value("certificates",endpoint(),pending_pem)
	pins.save("user://servers.cfg")
	_open_socket(pending_pem)
	pending_pem = ""

func forget_certificate(address: String, server_port: int) -> void:
	var key := ("["+address+"]" if ":" in address else address)+":"+str(server_port)
	pins.erase_section_key("certificates",key)
	pins.save("user://servers.cfg")
	status_changed.emit("Saved certificate forgotten. Reconnect and verify the new fingerprint.")

func _open_socket(pem: String) -> void:
	var cert := X509Certificate.new()
	if cert.load_from_string(pem) != OK:
		status_changed.emit("Saved certificate is invalid. Forget it and reconnect.")
		return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1048576
	socket.outbound_buffer_size = 65536
	var error := socket.connect_to_url("wss://"+endpoint()+"/", TLSOptions.client(cert,"atomictux"))
	if error != OK:
		socket = null
		status_changed.emit("Connection could not be started.")
		return
	connecting = true
	connect_time = 0.0
	status_changed.emit("Connecting securely…")

func _process(delta: float) -> void:
	if socket == null: return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			connecting = false
			send_message({"type":"hello", "name":player_name,"version":1})
		while socket != null and socket.get_available_packet_count() > 0:
			var value = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if value is Dictionary:
				if value.get("type") == "welcome": identity = str(value.id)
				message_received.emit(value)
	elif state == WebSocketPeer.STATE_CLOSED:
		_fail_connection()
	elif connecting:
		connect_time += delta
		if connect_time > 12.0: _fail_connection()

func _fail_connection() -> void:
	disconnect_server()
	disconnected.emit()
	status_changed.emit("Connection lost or certificate not trusted. Check the server; changed certificates require verification.")

func send_message(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(message))

func disconnect_server() -> void:
	if bootstrap != null: bootstrap.cancel_request()
	if socket != null: socket.close()
	socket = null
	connected = false
	connecting = false
	identity = ""
	pending_pem = ""
