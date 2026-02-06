extends Control

# Player info labels
@onready var partner_name_label: Label = $GameBoard/TopArea/PartnerNameLabel
@onready var partner_info: Label = $GameBoard/TopArea/PartnerInfo
@onready var partner_hand: Control = $GameBoard/TopArea/PartnerHand
@onready var left_name_label: Label = $GameBoard/MiddleArea/LeftPlayer/LeftNameLabel
@onready var left_info: Label = $GameBoard/MiddleArea/LeftPlayer/LeftInfo
@onready var right_name_label: Label = $GameBoard/MiddleArea/RightPlayer/RightNameLabel
@onready var right_info: Label = $GameBoard/MiddleArea/RightPlayer/RightInfo
@onready var my_name_label: Label = $GameBoard/BottomArea/MyNameLabel

# Center area
@onready var phase_label: Label = $GameBoard/MiddleArea/CenterArea/PhaseLabel
@onready var turn_label: Label = $GameBoard/MiddleArea/CenterArea/TurnLabel
@onready var wish_label: Label = $GameBoard/MiddleArea/CenterArea/WishLabel
@onready var trick_area: VBoxContainer = $GameBoard/MiddleArea/CenterArea/TrickArea
@onready var score_label: Label = $GameBoard/MiddleArea/CenterArea/ScoreLabel

# My hand
@onready var my_hand: Control = $GameBoard/BottomArea/MyHand

# Action buttons
@onready var play_button: Button = $GameBoard/BottomArea/ActionButtons/PlayButton
@onready var pass_button: Button = $GameBoard/BottomArea/ActionButtons/PassButton
@onready var tichu_button: Button = $GameBoard/BottomArea/ActionButtons/SmallTichuButton

# Panels
@onready var large_tichu_panel: PanelContainer = $LargeTichuPanel
@onready var declare_large_button: Button = $LargeTichuPanel/VBox/HBox/DeclareLargeButton
@onready var pass_large_button: Button = $LargeTichuPanel/VBox/HBox/PassLargeButton

@onready var exchange_panel: PanelContainer = $ExchangePanel
@onready var exchange_info: Label = $ExchangePanel/VBox/ExchangeInfo
@onready var exchange_button: Button = $ExchangePanel/VBox/ExchangeButton

@onready var dragon_panel: PanelContainer = $DragonPanel
@onready var dragon_left_button: Button = $DragonPanel/VBox/HBox/DragonLeftButton
@onready var dragon_right_button: Button = $DragonPanel/VBox/HBox/DragonRightButton

@onready var call_panel: PanelContainer = $CallPanel
@onready var call_grid: GridContainer = $CallPanel/VBox/CallGrid

@onready var round_end_panel: PanelContainer = $RoundEndPanel
@onready var round_score_label: Label = $RoundEndPanel/VBox/RoundScoreLabel
@onready var total_score_label: Label = $RoundEndPanel/VBox/TotalScoreLabel
@onready var next_round_button: Button = $RoundEndPanel/VBox/NextRoundButton

const CARD_SCENE = preload("res://scenes/game/Card.tscn")

var _waiting_call_rank: bool = false
var _current_phase: String = ""

func _ready() -> void:
	# Connect buttons
	play_button.pressed.connect(_on_play_pressed)
	pass_button.pressed.connect(_on_pass_pressed)
	tichu_button.pressed.connect(_on_tichu_pressed)
	declare_large_button.pressed.connect(_on_declare_large_pressed)
	pass_large_button.pressed.connect(_on_pass_large_pressed)
	exchange_button.pressed.connect(_on_exchange_pressed)
	dragon_left_button.pressed.connect(_on_dragon_left_pressed)
	dragon_right_button.pressed.connect(_on_dragon_right_pressed)
	next_round_button.pressed.connect(_on_next_round_pressed)

	# Connect hand selection
	my_hand.cards_selected_changed.connect(_on_cards_selected_changed)

	# Connect game state updates
	GameState.game_state_updated.connect(_on_game_state_updated)
	GameState.game_event.connect(_on_game_event)
	GameState.error_received.connect(_on_error)

	# Setup call buttons
	_setup_call_buttons()

	# Initial state
	if not GameState.game_data.is_empty():
		_on_game_state_updated(GameState.game_data)

func _setup_call_buttons() -> void:
	var ranks := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
	for rank in ranks:
		var btn := Button.new()
		btn.text = rank
		btn.custom_minimum_size = Vector2(45, 40)
		btn.pressed.connect(_on_call_rank_selected.bind(rank))
		call_grid.add_child(btn)

func _on_game_state_updated(state: Dictionary) -> void:
	var phase: String = state.get("phase", "")
	_current_phase = phase
	var players: Array = state.get("players", [])
	var my_cards: Array = state.get("myCards", [])
	var current_player_raw = state.get("currentPlayer", null)
	var current_player: String = current_player_raw if current_player_raw != null else ""
	var is_my_turn: bool = state.get("isMyTurn", false)
	var trick: Array = state.get("currentTrick", [])
	var scores: Dictionary = state.get("totalScores", {})
	var call_rank = state.get("callRank", null)
	var dragon_pending: bool = state.get("dragonPending", false)
	var exchange_done: bool = state.get("exchangeDone", false)
	var large_tichu_responded: bool = state.get("largeTichuResponded", false)
	var can_declare_small_tichu: bool = state.get("canDeclareSmallTichu", false)

	# Update player info
	for p in players:
		var pos: String = p.get("position", "")
		var pname: String = p.get("name", "???")
		var card_count: int = p.get("cardCount", 0)
		var has_tichu: bool = p.get("hasSmallTichu", false)
		var has_large: bool = p.get("hasLargeTichu", false)
		var finished: bool = p.get("hasFinished", false)
		var finish_pos: int = p.get("finishPosition", 0)

		var info_text := "%d장" % card_count
		if has_large:
			info_text += " [LT]"
		elif has_tichu:
			info_text += " [ST]"
		if finished:
			info_text = "%d등!" % finish_pos

		match pos:
			"partner":
				partner_name_label.text = pname
				partner_info.text = info_text
				partner_hand.set_card_count(card_count)
			"left":
				left_name_label.text = pname
				left_info.text = info_text
			"right":
				right_name_label.text = pname
				right_info.text = info_text
			"self":
				my_name_label.text = pname

	# Update my hand
	print("[GameScreen] Setting cards: %d" % my_cards.size())
	my_hand.set_cards(my_cards, true, true)

	# Update phase display
	_update_phase_display(phase, is_my_turn, current_player, players)

	# Update trick display
	_update_trick_display(trick)

	# Update scores
	var team_a: int = scores.get("teamA", 0)
	var team_b: int = scores.get("teamB", 0)
	score_label.text = "팀A: %d | 팀B: %d" % [team_a, team_b]

	# Show/hide panels
	_update_panels(phase, large_tichu_responded, exchange_done, dragon_pending, call_rank, can_declare_small_tichu, is_my_turn, trick)

	# Wish display
	if call_rank != null and call_rank is String and call_rank != "":
		wish_label.text = "콜: %s" % str(call_rank)
		wish_label.visible = true
	else:
		wish_label.visible = false

	# Round/Game end
	if phase == "round_end" or phase == "game_end":
		_show_round_end(state)

func _update_phase_display(phase: String, is_my_turn: bool, current_player: String, players: Array) -> void:
	var phase_names := {
		"large_tichu_phase": "라지티츄 선언",
		"dealing_remaining_6": "카드 분배 중",
		"card_exchange": "카드 교환",
		"playing": "게임 진행 중",
		"round_end": "라운드 종료",
		"game_end": "게임 종료",
	}
	phase_label.text = phase_names.get(phase, phase)

	if phase == "playing":
		if is_my_turn:
			turn_label.text = "내 턴!"
			turn_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			# Find current player name
			var cp_name := ""
			for p in players:
				if p.get("id", "") == current_player:
					cp_name = p.get("name", "???")
					break
			turn_label.text = "%s의 턴" % cp_name
			turn_label.remove_theme_color_override("font_color")
	else:
		turn_label.text = ""

func _update_trick_display(trick: Array) -> void:
	# Clear existing trick cards
	for child in trick_area.get_children():
		child.queue_free()

	for play in trick:
		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", -15)

		var name_label := Label.new()
		name_label.text = play.get("playerName", "?") + ": "
		name_label.custom_minimum_size = Vector2(70, 0)
		hbox.add_child(name_label)

		var cards: Array = play.get("cards", [])
		for card_id in cards:
			var card_node: Control = CARD_SCENE.instantiate()
			card_node.custom_minimum_size = Vector2(50, 70)
			card_node.size = Vector2(50, 70)
			hbox.add_child(card_node)
			card_node.setup(card_id, true)
			card_node.is_interactive = false

		trick_area.add_child(hbox)

func _update_panels(phase: String, large_tichu_responded: bool, exchange_done: bool,
		dragon_pending: bool, call_rank, can_declare_small_tichu: bool,
		is_my_turn: bool, trick: Array) -> void:

	# Large Tichu panel
	large_tichu_panel.visible = (phase == "large_tichu_phase" and not large_tichu_responded)

	# Exchange panel
	exchange_panel.visible = (phase == "card_exchange" and not exchange_done)

	# Dragon panel
	dragon_panel.visible = dragon_pending

	# Call panel - show after playing bird
	# (handled by game event, not state directly)

	# Round end panel
	round_end_panel.visible = (phase == "round_end" or phase == "game_end")

	# Action buttons
	play_button.visible = (phase == "playing" and is_my_turn)
	pass_button.visible = (phase == "playing" and is_my_turn and trick.size() > 0)
	tichu_button.visible = can_declare_small_tichu

func _on_cards_selected_changed(selected: Array) -> void:
	if exchange_panel.visible:
		exchange_info.text = "선택: %d/3" % selected.size()
		exchange_button.disabled = (selected.size() != 3)

func _on_play_pressed() -> void:
	var selected: Array = my_hand.get_selected_cards()
	if selected.is_empty():
		return
	GameState.play_cards(selected)
	my_hand.deselect_all()

func _on_pass_pressed() -> void:
	GameState.pass_turn()

func _on_tichu_pressed() -> void:
	GameState.declare_small_tichu()

func _on_declare_large_pressed() -> void:
	GameState.declare_large_tichu()

func _on_pass_large_pressed() -> void:
	GameState.pass_large_tichu()

func _on_exchange_pressed() -> void:
	var selected: Array = my_hand.get_selected_cards()
	if selected.size() != 3:
		return
	# Order: left, partner, right
	GameState.exchange_cards(selected[0], selected[1], selected[2])
	my_hand.deselect_all()

func _on_dragon_left_pressed() -> void:
	GameState.dragon_give("left")

func _on_dragon_right_pressed() -> void:
	GameState.dragon_give("right")

func _on_call_rank_selected(rank: String) -> void:
	GameState.call_rank(rank)
	call_panel.visible = false
	_waiting_call_rank = false

func _on_next_round_pressed() -> void:
	round_end_panel.visible = false
	if _current_phase == "game_end":
		GameState.leave_room()
		var main := get_tree().root.get_node("Main")
		if main and main.has_method("go_to_lobby"):
			main.go_to_lobby()
	else:
		GameState.next_round()

func _show_round_end(state: Dictionary) -> void:
	var last_scores: Dictionary = state.get("lastRoundScores", {})
	var total: Dictionary = state.get("totalScores", {})
	var phase: String = state.get("phase", "")

	if not last_scores.is_empty():
		round_score_label.text = "이번 라운드: 팀A %d | 팀B %d" % [
			last_scores.get("teamA", 0), last_scores.get("teamB", 0)]
	total_score_label.text = "총점: 팀A %d | 팀B %d" % [
		total.get("teamA", 0), total.get("teamB", 0)]

	if phase == "game_end":
		var winner := "팀A" if total.get("teamA", 0) > total.get("teamB", 0) else "팀B"
		round_score_label.text = "%s 승리!" % winner
		next_round_button.text = "로비로 돌아가기"
	else:
		next_round_button.text = "다음 라운드"

	round_end_panel.visible = true

func _on_game_event(event: Dictionary) -> void:
	var event_type: String = event.get("type", "")
	match event_type:
		"cards_played":
			if event.get("birdPlayed", false):
				# Show call panel if it was me who played
				var player_id: String = event.get("player", "")
				if player_id == GameState.player_id:
					_waiting_call_rank = true
					call_panel.visible = true

func _on_error(message: String) -> void:
	phase_label.text = "오류: " + message
