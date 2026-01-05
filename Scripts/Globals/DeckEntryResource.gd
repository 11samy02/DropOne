extends Resource
class_name DeckEntryResource

@export var color: CardResource.CardColor = CardResource.CardColor.RED
@export var type: CardResource.CardType = CardResource.CardType.SKIP
@export var value: int = 0
@export var count: int = 1

@export var duplicate_for_all_colors: bool = false
@export var colors: Array[CardResource.CardColor] = [
	CardResource.CardColor.RED,
	CardResource.CardColor.GREEN,
	CardResource.CardColor.BLUE,
	CardResource.CardColor.YELLOW
]
