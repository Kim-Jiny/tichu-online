extends Control

# Lobby panel nodes
@onready var nickname_label: Label = $VBoxMain/TopBar/HBox/NicknameLabel
@onready var lobby_panel: VBoxContainer = $VBoxMain/Content/LobbyPanel
@onready var room_list_container: VBoxContainer = $VBoxMain/Content/LobbyPanel/ScrollContainer/RoomList
@onready var no_rooms_label: Label = $VBoxMain/Content/LobbyPanel/NoRoomsLabel
@onready var create_room_button: Button = $VBoxMain/Content/LobbyPanel/CreateRoomButton
@onready var refresh_button: Button = $VBoxMain/Content/LobbyPanel/RoomListHeader/RefreshButton

# Room panel nodes
@onready var room_panel: VBoxContainer = $VBoxMain/Content/RoomPanel
@onready var room_name_label: Label = $VBoxMain/Content/RoomPanel/RoomNameLabel
@onready var player_slots: Array = [
	$VBoxMain/Content/RoomPanel/PlayerSlot1/Label,
	$VBoxMain/Content/RoomPanel/PlayerSlot2/Label,
	$VBoxMain/Content/RoomPanel/PlayerSlot3/Label,
	$VBoxMain/Content/RoomPanel/PlayerSlot4/Label,
]
@onready var leave_button: Button = $VBoxMain/Content/RoomPanel/LeaveButton
@onready var start_button: Button = $VBoxMain/Content/RoomPanel/StartButton

@onready var status_label: Label = $VBoxMain/StatusLabel
@onready var create_room_dialog: AcceptDialog = $CreateRoomDialog
@onready var room_name_input: LineEdit = $CreateRoomDialog/VBox/RoomNameInput

var _in_room: bool = false

# Room button style (loaded from scene sub-resources isn't easy, so create in code)
var _room_btn_style: StyleBoxFlat
var _room_btn_hover_style: StyleBoxFlat

func _ready() -> void:
	nickname_label.text = GameState.player_name

	# Create room button styles
	_room_btn_style = StyleBoxFlat.new()
	_room_btn_style.bg_color = Color(0.16, 0.18, 0.26, 1)
	_room_btn_style.set_border_width_all(1)
	_room_btn_style.border_color = Color(0.25, 0.28, 0.38, 1)
	_room_btn_style.set_corner_radius_all(12)
	_room_btn_style.content_margin_left = 16
	_room_btn_style.content_margin_right = 16
	_room_btn_style.content_margin_top = 14
	_room_btn_style.content_margin_bottom = 14

	_room_btn_hover_style = StyleBoxFlat.new()
	_room_btn_hover_style.bg_color = Color(0.2, 0.22, 0.32, 1)
	_room_btn_hover_style.set_border_width_all(1)
	_room_btn_hover_style.border_color = Color(0.3, 0.4, 0.65, 1)
	_room_btn_hover_style.set_corner_radius_all(12)
	_room_btn_hover_style.content_margin_left = 16
	_room_btn_hover_style.content_margin_right = 16
	_room_btn_hover_style.content_margin_top = 14
	_room_btn_hover_style.content_margin_bottom = 14

	create_room_button.pressed.connect(_on_create_room_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	start_button.pressed.connect(_on_start_pressed)
	create_room_dialog.confirmed.connect(_on_create_room_confirmed)

	GameState.room_list_updated.connect(_on_room_list_updated)
	GameState.room_joined.connect(_on_room_joined)
	GameState.room_left.connect(_on_room_left)
	GameState.room_state_updated.connect(_on_room_state_updated)
	GameState.error_received.connect(_on_error)

	_show_lobby()
	GameState.request_room_list()

func _show_lobby() -> void:
	_in_room = false
	lobby_panel.visible = true
	room_panel.visible = false

func _show_room() -> void:
	_in_room = true
	lobby_panel.visible = false
	room_panel.visible = true

func _on_room_list_updated(rooms: Array) -> void:
	for child in room_list_container.get_children():
		child.queue_free()

	no_rooms_label.visible = rooms.is_empty()

	for room in rooms:
		var btn := Button.new()
		var room_id: String = room.get("id", "")
		var room_name: String = room.get("name", "???")
		var player_count: int = room.get("playerCount", 0)
		var host_name: String = room.get("hostName", "")
		btn.text = "%s  (%d/4)" % [room_name, player_count]
		btn.tooltip_text = "호스트: %s" % host_name
		btn.custom_minimum_size = Vector2(0, 56)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_stylebox_override("normal", _room_btn_style)
		btn.add_theme_stylebox_override("hover", _room_btn_hover_style)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_room_clicked.bind(room_id))
		room_list_container.add_child(btn)

func _on_create_room_pressed() -> void:
	room_name_input.text = GameState.player_name + "의 방"
	create_room_dialog.popup_centered()

func _on_create_room_confirmed() -> void:
	var room_name := room_name_input.text.strip_edges()
	if room_name.is_empty():
		room_name = GameState.player_name + "의 방"
	GameState.create_room(room_name)

func _on_refresh_pressed() -> void:
	GameState.request_room_list()

func _on_room_clicked(room_id: String) -> void:
	GameState.join_room(room_id)

func _on_room_joined(_room_id: String, room_name: String) -> void:
	room_name_label.text = room_name
	_show_room()

func _on_room_left() -> void:
	_show_lobby()
	GameState.request_room_list()

func _on_leave_pressed() -> void:
	GameState.leave_room()

func _on_start_pressed() -> void:
	GameState.start_game()

func _on_room_state_updated(state: Dictionary) -> void:
	if not _in_room:
		return

	room_name_label.text = state.get("name", "")
	var players: Array = state.get("players", [])

	# Update player slots
	# Slot layout: 0,1 = Team A, 2,3 = Team B
	var slot_map := [0, 2, 1, 3]  # players[0]→slot0, players[1]→slot2, players[2]→slot1, players[3]→slot3
	for i in range(4):
		var slot_idx: int = slot_map[i] if i < slot_map.size() else i
		if i < players.size():
			var p: Dictionary = players[i]
			var name_str: String = p.get("nickname", "???")
			var is_host: bool = p.get("isHost", false)
			player_slots[slot_idx].text = "%s%s" % [name_str, "  👑" if is_host else ""]
			player_slots[slot_idx].add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
		else:
			player_slots[slot_idx].text = "대기 중..."
			player_slots[slot_idx].add_theme_color_override("font_color", Color(0.4, 0.42, 0.5))

	start_button.visible = GameState.is_host
	start_button.disabled = players.size() < 4
	if players.size() < 4:
		start_button.text = "게임 시작 (%d/4)" % players.size()
	else:
		start_button.text = "게임 시작!"

	status_label.text = "%d/4 플레이어 대기 중" % players.size()

func _on_error(message: String) -> void:
	status_label.text = "오류: " + message
