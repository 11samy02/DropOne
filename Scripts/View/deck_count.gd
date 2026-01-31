extends Label
class_name DeckCount

@export var queue_manager: QueueManager

var _deck_count: int = 0

func _ready() -> void:
	NetworkManager.counts_received.connect(_on_counts)
	_set_text()

func _on_counts(_hand_counts: Array, deck_count: int) -> void:
	_deck_count = int(deck_count)
	_set_text()

func _set_text() -> void:
	set_text(str(_deck_count))
