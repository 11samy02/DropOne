extends Resource
class_name DeckResource

## Display name shown in lobby and deck pickers.
@export var deck_name: String = "DropOne Default"
## Rules for generating numbered cards (0–9 copies per color).
@export var number_rules: DeckNumberRuleResource
## Special/action card entries appended after number cards.
@export var entries: Array[DeckEntryResource] = []

## When enabled, a player who reaches max_card_lose_count cards is eliminated
## and cannot take turns until the match ends.
## Enables elimination when a player reaches max_card_lose_count cards.
@export var max_card_lose_enabled: bool = false
## Hand size at which a player is eliminated (when max_card_lose_enabled).
@export var max_card_lose_count: int = 20
