extends Control

@onready var nickname_input: LineEdit = $CenterContainer/VBox/NicknameInput
@onready var server_input: LineEdit = $CenterContainer/VBox/ServerInput
@onready var connect_button: Button = $CenterContainer/VBox/ConnectButton
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel

var _waiting_for_connection: bool = false
var _timeout_timer: float = 0.0
const CONNECTION_TIMEOUT := 5.0

func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	nickname_input.text_submitted.connect(_on_nickname_submitted)
	NetworkManager.connected.connect(_on_connected)
	NetworkManager.disconnected.connect(_on_disconnected)
	GameState.login_success.connect(_on_login_success)
	GameState.error_received.connect(_on_error)

func _process(delta: float) -> void:
	if _waiting_for_connection:
		_timeout_timer -= delta
		if _timeout_timer <= 0:
			_waiting_for_connection = false
			connect_button.disabled = false
			status_label.text = "서버 접속 실패 - 서버가 실행 중인지 확인하세요"

func _on_connect_pressed() -> void:
	_try_connect()

func _on_nickname_submitted(_text: String) -> void:
	_try_connect()

func _try_connect() -> void:
	var nickname := nickname_input.text.strip_edges()
	if nickname.is_empty():
		status_label.text = "닉네임을 입력하세요"
		return

	connect_button.disabled = true
	status_label.text = "서버에 접속 중..."

	var url := server_input.text.strip_edges()
	if url.is_empty():
		url = "ws://172.30.1.98:8080"

	# If already connected, just login
	if NetworkManager.is_connected_to_server():
		GameState.login(nickname)
		return

	# Start connection and wait for signal
	_waiting_for_connection = true
	_timeout_timer = CONNECTION_TIMEOUT
	NetworkManager.connect_to_server(url)

func _on_connected() -> void:
	_waiting_for_connection = false
	status_label.text = "서버 접속 완료! 로그인 중..."
	# Now send login
	var nickname := nickname_input.text.strip_edges()
	if not nickname.is_empty():
		GameState.login(nickname)

func _on_disconnected() -> void:
	_waiting_for_connection = false
	connect_button.disabled = false
	status_label.text = "서버 연결 끊김"

func _on_login_success() -> void:
	status_label.text = "로그인 성공!"
	var main := get_tree().root.get_node("Main")
	if main and main.has_method("go_to_lobby"):
		main.go_to_lobby()

func _on_error(message: String) -> void:
	status_label.text = "오류: " + message
	connect_button.disabled = false
