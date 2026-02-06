extends Control

signal cards_selected_changed(selected_cards: Array)

@onready var card_container: HBoxContainer = $ScrollContainer/CardContainer

const CARD_SCENE = preload("res://scenes/game/Card.tscn")

var selected_cards: Array = []
var card_nodes: Array = []

func set_cards(card_ids: Array, face_up: bool = true, interactive: bool = true) -> void:
	clear_cards()
	for card_id in card_ids:
		var card_node: Control = CARD_SCENE.instantiate()
		card_container.add_child(card_node)
		card_node.setup(card_id, face_up)
		card_node.is_interactive = interactive
		if interactive:
			card_node.card_selected.connect(_on_card_selected)
			card_node.card_deselected.connect(_on_card_deselected)
		card_nodes.append(card_node)

func clear_cards() -> void:
	selected_cards.clear()
	card_nodes.clear()
	for child in card_container.get_children():
		child.queue_free()

func get_selected_cards() -> Array:
	return selected_cards.duplicate()

func deselect_all() -> void:
	for node in card_nodes:
		if node.is_selected:
			node.set_selected(false)
	selected_cards.clear()
	cards_selected_changed.emit(selected_cards)

func set_card_count(count: int) -> void:
	# For opponent hands - show face-down cards
	clear_cards()
	for i in range(count):
		var card_node: Control = CARD_SCENE.instantiate()
		card_container.add_child(card_node)
		card_node.setup("back", false)
		card_node.is_interactive = false
		card_nodes.append(card_node)

func _on_card_selected(card_id: String) -> void:
	if not selected_cards.has(card_id):
		selected_cards.append(card_id)
	cards_selected_changed.emit(selected_cards)

func _on_card_deselected(card_id: String) -> void:
	selected_cards.erase(card_id)
	cards_selected_changed.emit(selected_cards)
