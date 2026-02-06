extends Control

signal card_selected(card_id: String)
signal card_deselected(card_id: String)

@onready var suit_label: Label = $CardPanel/MarginContainer/VBox/SuitLabel
@onready var rank_label: Label = $CardPanel/MarginContainer/VBox/RankLabel
@onready var special_label: Label = $CardPanel/MarginContainer/VBox/SpecialLabel
@onready var special_image: TextureRect = $CardPanel/MarginContainer/VBox/SpecialImage
@onready var select_highlight: PanelContainer = $SelectHighlight
@onready var back_face: PanelContainer = $BackFace
@onready var card_panel: PanelContainer = $CardPanel

var card_id: String = ""
var is_selected: bool = false
var is_face_up: bool = true
var is_interactive: bool = true
var _base_y: float = 0.0
var _pending_setup: bool = false

const SUIT_SYMBOLS := {
	"spade": "♠", "heart": "♥", "diamond": "♦", "club": "♣"
}
const SUIT_COLORS := {
	"spade": Color(0.15, 0.15, 0.2),
	"heart": Color(0.85, 0.15, 0.15),
	"diamond": Color(0.85, 0.15, 0.15),
	"club": Color(0.15, 0.15, 0.2),
}
const SPECIAL_NAMES := {
	"special_bird": "새",
	"special_dog": "犬",
	"special_phoenix": "鳳",
	"special_dragon": "龍",
}
const SPECIAL_COLORS := {
	"special_bird": Color(0.1, 0.55, 0.1),
	"special_dog": Color(0.35, 0.35, 0.4),
	"special_phoenix": Color(0.85, 0.5, 0.0),
	"special_dragon": Color(0.75, 0.1, 0.1),
}
const SPECIAL_IMAGES := {
	"special_bird": "res://assets/cards/mahjong.png",
	"special_dog": "res://assets/cards/dog.png",
	"special_phoenix": "res://assets/cards/phoenix.png",
	"special_dragon": "res://assets/cards/dragon.png",
}

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_base_y = position.y
	# Apply pending setup if setup() was called before _ready()
	if _pending_setup:
		_pending_setup = false
		_update_display()

func setup(id: String, face_up: bool = true) -> void:
	card_id = id
	is_face_up = face_up
	# If node is not ready yet, defer the display update
	if not is_node_ready():
		_pending_setup = true
	else:
		_update_display()

func _update_display() -> void:
	if not is_face_up:
		back_face.visible = true
		card_panel.visible = false
		select_highlight.visible = false
		return

	back_face.visible = false
	card_panel.visible = true

	if card_id.begins_with("special_"):
		_display_special()
	else:
		_display_normal()

func _display_normal() -> void:
	var parts := card_id.split("_")
	if parts.size() < 2:
		return
	var suit_name: String = parts[0]
	var rank: String = parts[1]

	suit_label.visible = true
	rank_label.visible = true
	special_label.visible = false

	suit_label.text = SUIT_SYMBOLS.get(suit_name, "?")
	rank_label.text = rank

	var color: Color = SUIT_COLORS.get(suit_name, Color.BLACK)
	suit_label.add_theme_color_override("font_color", color)
	rank_label.add_theme_color_override("font_color", color)

func _display_special() -> void:
	suit_label.visible = false
	rank_label.visible = false

	var image_path: String = SPECIAL_IMAGES.get(card_id, "")
	if image_path != "" and ResourceLoader.exists(image_path):
		special_label.visible = false
		special_image.visible = true
		special_image.texture = load(image_path)
	else:
		special_label.visible = true
		special_image.visible = false
		special_label.text = SPECIAL_NAMES.get(card_id, "?")
		var color: Color = SPECIAL_COLORS.get(card_id, Color.BLACK)
		special_label.add_theme_color_override("font_color", color)

func set_selected(selected: bool) -> void:
	var was_selected := is_selected
	is_selected = selected
	select_highlight.visible = selected
	if selected and not was_selected:
		position.y = _base_y - 18
	elif not selected and was_selected:
		position.y = _base_y

func toggle_selected() -> void:
	if is_selected:
		is_selected = false
		select_highlight.visible = false
		position.y = _base_y
		card_deselected.emit(card_id)
	else:
		is_selected = true
		select_highlight.visible = true
		position.y = _base_y - 18
		card_selected.emit(card_id)

func _on_gui_input(event: InputEvent) -> void:
	if not is_interactive or not is_face_up:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			toggle_selected()
			accept_event()
