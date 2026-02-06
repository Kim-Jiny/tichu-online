extends Control

@onready var scene_container: Control = $SceneContainer

var current_scene: Node = null

const LOGIN_SCENE = preload("res://scenes/login/LoginScreen.tscn")
const LOBBY_SCENE = preload("res://scenes/lobby/LobbyScreen.tscn")
const GAME_SCENE = preload("res://scenes/game/GameScreen.tscn")

func _ready() -> void:
	GameState.room_joined.connect(_on_room_joined)
	GameState.room_left.connect(_on_room_left)
	GameState.game_state_updated.connect(_on_game_state_updated)
	_change_scene(LOGIN_SCENE)

func _change_scene(scene: PackedScene) -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	current_scene = scene.instantiate()
	scene_container.add_child(current_scene)

func go_to_lobby() -> void:
	_change_scene(LOBBY_SCENE)

func go_to_login() -> void:
	_change_scene(LOGIN_SCENE)

func go_to_game() -> void:
	_change_scene(GAME_SCENE)

func _on_room_joined(_room_id: String, _room_name: String) -> void:
	# Room screen is handled within lobby
	pass

func _on_room_left() -> void:
	pass

func _on_game_state_updated(state: Dictionary) -> void:
	var phase: String = state.get("phase", "")
	if phase != "" and phase != "waiting":
		if not current_scene is Control or current_scene.name != "GameScreen":
			go_to_game()
