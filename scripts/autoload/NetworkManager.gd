extends Node

signal connected
signal disconnected
signal message_received(data: Dictionary)

var _socket: WebSocketPeer = WebSocketPeer.new()
var _connected: bool = false
var _url: String = "ws://172.30.1.98:8080"

# Auto-reconnect
var _auto_reconnect: bool = true
var _reconnect_timer: float = 0.0
var _reconnect_delay: float = 3.0
var _should_reconnect: bool = false

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_should_reconnect = false
				print("[Network] Connected to server")
				connected.emit()
			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				var text := packet.get_string_from_utf8()
				var json := JSON.new()
				var err := json.parse(text)
				if err == OK:
					var data: Dictionary = json.data
					message_received.emit(data)
				else:
					push_warning("[Network] Failed to parse JSON: " + text)

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				var code := _socket.get_close_code()
				var reason := _socket.get_close_reason()
				print("[Network] Disconnected: %d %s" % [code, reason])
				disconnected.emit()
				if _auto_reconnect:
					_should_reconnect = true
					_reconnect_timer = _reconnect_delay

			if _should_reconnect:
				_reconnect_timer -= delta
				if _reconnect_timer <= 0:
					print("[Network] Attempting reconnect...")
					connect_to_server(_url)

func connect_to_server(url: String = "") -> void:
	if url != "":
		_url = url
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_url)
	if err != OK:
		push_error("[Network] Failed to connect: " + str(err))
		_should_reconnect = true
		_reconnect_timer = _reconnect_delay

func send_message(data: Dictionary) -> void:
	if _connected:
		var json_str := JSON.stringify(data)
		_socket.send_text(json_str)
	else:
		push_warning("[Network] Cannot send: not connected")

func disconnect_from_server() -> void:
	_auto_reconnect = false
	_should_reconnect = false
	_socket.close()
	_connected = false

func is_connected_to_server() -> bool:
	return _connected
