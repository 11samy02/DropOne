extends Resource
class_name DeckNumberRuleResource

## Lowest number card included in the deck (inclusive).
@export var min_number: int = 0
## Highest number card included in the deck (inclusive).
@export var max_number: int = 9
## Default copy count per number/color pair before overrides.
@export var default_copies: int = 2
## Per-number copy overrides keyed by number string (e.g. {"0": 1}).
@export var overrides: Dictionary = {"0": 1}
