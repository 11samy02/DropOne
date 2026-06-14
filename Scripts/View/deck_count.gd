extends Label
class_name DeckCount

## QueueManager used to read synced deck size from NetworkManager counts.
@export var queue_manager: QueueManager

## Last deck count received from the server snapshot.
var _deck_count: int = 0

func _ready() -> void:
	NetworkManager.counts_received.connect(_on_counts)
	_set_text()

## Updates cached count when server broadcasts hand/deck counts.
func _on_counts(_hand_counts: Array, deck_count: int) -> void:
	_deck_count = int(deck_count)
	_set_text()

## Writes the label text from the cached deck count.
func _set_text() -> void:
	set_text(str(_deck_count))
