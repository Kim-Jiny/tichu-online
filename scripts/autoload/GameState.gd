extends Node

# Player info
var player_name: String = ""
var player_id: String = ""

# Room info
var current_room_id: String = ""
var current_room_name: String = ""
var room_players: Array = []
var is_host: bool = false

# Game data
var game_data: Dictionary = {}
var my_cards: Array = []
var current_phase: String = ""
var is_my_turn: bool = false
var current_trick: Array = []
var total_scores: Dictionary = {"teamA": 0, "teamB": 0}
var players_info: Array = []

# Signals for UI updates
signal room_joined(room_id: String, room_name: String)
signal room_left()
signal room_state_updated(state: Dictionary)
signal room_list_updated(rooms: Array)
signal game_state_updated(state: Dictionary)
signal game_event(event: Dictionary)
signal login_success()
signal error_received(message: String)

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.disconnected.connect(_on_disconnected)

func _on_disconnected() -> void:
	current_room_id = ""
	current_room_name = ""
	room_players = []
	is_host = false
	game_data = {}
	my_cards = []

func _on_message_received(data: Dictionary) -> void:
	var msg_type: String = data.get("type", "")

	match msg_type:
		"login_success":
			player_id = data.get("playerId", "")
			player_name = data.get("nickname", "")
			login_success.emit()

		"room_list":
			room_list_updated.emit(data.get("rooms", []))

		"room_joined":
			current_room_id = data.get("roomId", "")
			current_room_name = data.get("roomName", "")
			room_joined.emit(current_room_id, current_room_name)

		"room_left":
			current_room_id = ""
			current_room_name = ""
			room_players = []
			room_left.emit()

		"room_state":
			var room: Dictionary = data.get("room", {})
			room_players = room.get("players", [])
			is_host = false
			for p in room_players:
				if p.get("id", "") == player_id and p.get("isHost", false):
					is_host = true
					break
			room_state_updated.emit(room)

		"game_state":
			var state: Dictionary = data.get("state", {})
			game_data = state
			my_cards = state.get("myCards", [])
			current_phase = state.get("phase", "")
			is_my_turn = state.get("isMyTurn", false)
			current_trick = state.get("currentTrick", [])
			total_scores = state.get("totalScores", {"teamA": 0, "teamB": 0})
			players_info = state.get("players", [])
			print("[GameState] Received game_state: phase=%s, cards=%d" % [current_phase, my_cards.size()])
			game_state_updated.emit(state)

		"cards_played", "bomb_played", "player_passed", "dog_played", \
		"trick_won", "round_end", "large_tichu_declared", "large_tichu_passed", \
		"small_tichu_declared", "call_rank", "dragon_given":
			game_event.emit(data)

		"error":
			var message: String = data.get("message", "Unknown error")
			push_warning("[GameState] Error: " + message)
			error_received.emit(message)

func login(nickname: String) -> void:
	player_name = nickname
	NetworkManager.send_message({"type": "login", "nickname": nickname})

func request_room_list() -> void:
	NetworkManager.send_message({"type": "room_list"})

func create_room(room_name: String) -> void:
	NetworkManager.send_message({"type": "create_room", "roomName": room_name})

func join_room(room_id: String) -> void:
	NetworkManager.send_message({"type": "join_room", "roomId": room_id})

func leave_room() -> void:
	NetworkManager.send_message({"type": "leave_room"})

func start_game() -> void:
	NetworkManager.send_message({"type": "start_game"})

func play_cards(cards: Array) -> void:
	NetworkManager.send_message({"type": "play_cards", "cards": cards})

func pass_turn() -> void:
	NetworkManager.send_message({"type": "pass"})

func declare_small_tichu() -> void:
	NetworkManager.send_message({"type": "declare_small_tichu"})

func declare_large_tichu() -> void:
	NetworkManager.send_message({"type": "declare_large_tichu"})

func pass_large_tichu() -> void:
	NetworkManager.send_message({"type": "pass_large_tichu"})

func next_round() -> void:
	NetworkManager.send_message({"type": "next_round"})

func exchange_cards(left_card: String, partner_card: String, right_card: String) -> void:
	NetworkManager.send_message({
		"type": "exchange_cards",
		"cards": {"left": left_card, "partner": partner_card, "right": right_card}
	})

func dragon_give(target: String) -> void:
	NetworkManager.send_message({"type": "dragon_give", "target": target})

func call_rank(rank: String) -> void:
	NetworkManager.send_message({"type": "call_rank", "rank": rank})
