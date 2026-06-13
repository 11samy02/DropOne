extends Resource
class_name DeckResource

@export var deck_name: String = "DropOne Default"
@export var number_rules: DeckNumberRuleResource
@export var entries: Array[DeckEntryResource] = []

## When enabled, a player who reaches max_card_lose_count cards is eliminated
## and cannot take turns until the match ends.
@export var max_card_lose_enabled: bool = false
@export var max_card_lose_count: int = 20
