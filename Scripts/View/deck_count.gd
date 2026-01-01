extends Label
class_name DeckCount

@export var card_manager : CardManager


func _ready() -> void:
	set_count()

func set_count() -> void:
	set_text(str(card_manager.deck.size()))

func _process(delta: float) -> void:
	set_count()
