extends Resource
class_name DeckEntryResource

## Card color for this deck entry (ignored when duplicate_for_all_colors is true).
@export var color: CardResource.CardColor = CardResource.CardColor.RED
## Card type to add (NUMBER, SKIP, WILD, etc.).
@export var type: CardResource.CardType = CardResource.CardType.SKIP
## Numeric value for NUMBER/DRAW-style cards; 0 for action cards without values.
@export var value: int = 0
## How many copies of this entry to include in the deck.
@export var count: int = 1

## When true, one copy per color in `colors` is generated instead of a single `color`.
@export var duplicate_for_all_colors: bool = false
## Target colors used when duplicate_for_all_colors is enabled.
@export var colors: Array[CardResource.CardColor] = [
	CardResource.CardColor.RED,
	CardResource.CardColor.GREEN,
	CardResource.CardColor.BLUE,
	CardResource.CardColor.YELLOW
]
