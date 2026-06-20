class_name DeckPreview
extends RefCounted

const PLAY_COLORS: Array[CardResource.CardColor] = [
	CardResource.CardColor.RED,
	CardResource.CardColor.GREEN,
	CardResource.CardColor.BLUE,
	CardResource.CardColor.YELLOW,
]

const RECOMMENDED_MAX_PLAYERS := 8
const RECOMMENDED_START_CARDS := 12
const MIN_DRAW_BUFFER := 24
const MIN_DECK_CARD_COUNT := RECOMMENDED_MAX_PLAYERS * RECOMMENDED_START_CARDS + MIN_DRAW_BUFFER


static func build_cards(deck: DeckResource) -> Array[CardResource]:
	var cards: Array[CardResource] = []
	if deck == null:
		return cards
	if deck.number_rules != null:
		_add_number_cards(cards, deck.number_rules)
	for entry in deck.entries:
		if entry != null:
			_add_entry_cards(cards, entry)
	return cards


static func get_card_count(deck: DeckResource) -> int:
	return build_cards(deck).size()


static func get_minimum_card_count() -> int:
	return MIN_DECK_CARD_COUNT


static func meets_minimum_card_count(deck: DeckResource) -> bool:
	return get_card_count(deck) >= MIN_DECK_CARD_COUNT


static func build_grouped_cards(deck: DeckResource) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for card in build_cards(deck):
		var key := _card_group_key(card)
		if groups.has(key):
			groups[key]["count"] += 1
		else:
			groups[key] = {"card": card, "count": 1}
	var result: Array[Dictionary] = []
	for entry in groups.values():
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_preview_cards(a["card"], b["card"])
	)
	return result


static func _card_group_key(card: CardResource) -> String:
	return "%d|%d|%d" % [int(card.color), int(card.type), card.value]


static func _color_sort_index(color: CardResource.CardColor) -> int:
	var idx := PLAY_COLORS.find(color)
	if idx >= 0:
		return idx
	if color == CardResource.CardColor.BLACK:
		return PLAY_COLORS.size()
	return 99


static func _type_sort_key(card: CardResource) -> int:
	if card.type == CardResource.CardType.NUMBER:
		return card.value
	return 1000 + int(card.type) * 100 + card.value


static func _compare_preview_cards(a: CardResource, b: CardResource) -> bool:
	var color_cmp := _color_sort_index(a.color) - _color_sort_index(b.color)
	if color_cmp != 0:
		return color_cmp < 0
	return _type_sort_key(a) < _type_sort_key(b)


static func card_label(card: CardResource) -> String:
	if card == null:
		return "?"
	var type_name := _type_name(card.type)
	var text := card.get_display_text()
	if text != "":
		return "%s %s" % [card.get_color_name(), text]
	return "%s %s" % [card.get_color_name(), type_name]


static func card_tint(card: CardResource) -> Color:
	if card == null:
		return Color(0.35, 0.35, 0.35)
	match card.color:
		CardResource.CardColor.RED:
			return Color(0.68, 0.12, 0.12)
		CardResource.CardColor.GREEN:
			return Color(0.08, 0.52, 0.12)
		CardResource.CardColor.BLUE:
			return Color(0.08, 0.18, 0.62)
		CardResource.CardColor.YELLOW:
			return Color(0.62, 0.48, 0.04)
		CardResource.CardColor.BLACK:
			return Color(0.12, 0.12, 0.14)
	return Color(0.35, 0.35, 0.35)


static func _add_number_cards(cards: Array[CardResource], rules: DeckNumberRuleResource) -> void:
	for color in PLAY_COLORS:
		for number in range(rules.min_number, rules.max_number + 1):
			var copies := rules.default_copies
			if rules.overrides.has(str(number)):
				copies = int(rules.overrides[str(number)])
			for _i in range(copies):
				cards.append(_make_card(color, CardResource.CardType.NUMBER, number))


static func _add_entry_cards(cards: Array[CardResource], entry: DeckEntryResource) -> void:
	if CardResource.is_neutral_wild_type(entry.type):
		for _i in range(entry.count):
			cards.append(_make_card(CardResource.CardColor.BLACK, entry.type, entry.value))
		return
	if entry.duplicate_for_all_colors:
		for color in entry.colors:
			for _i in range(entry.count):
				cards.append(_make_card(color, entry.type, entry.value))
	else:
		for _i in range(entry.count):
			cards.append(_make_card(entry.color, entry.type, entry.value))


static func _make_card(color: CardResource.CardColor, type: CardResource.CardType, value: int) -> CardResource:
	var card := CardResource.new()
	card.color = CardResource.CardColor.BLACK if CardResource.is_neutral_wild_type(type) else color
	card.type = type
	card.value = value
	return card


static func _type_name(type: CardResource.CardType) -> String:
	match type:
		CardResource.CardType.NUMBER:
			return "Number"
		CardResource.CardType.SKIP:
			return "Skip"
		CardResource.CardType.REVERSE:
			return "Reverse"
		CardResource.CardType.DRAW:
			return "Draw"
		CardResource.CardType.WILD:
			return "Wild"
		CardResource.CardType.WILD_DRAW:
			return "Wild Draw"
		CardResource.CardType.PLACE_ALL:
			return "Place All"
		CardResource.CardType.WILD_DRAW_REVERSE:
			return "Wild Draw Reverse"
		CardResource.CardType.SWAP_HANDS:
			return "Swap Hands"
		CardResource.CardType.TARGET_DRAW:
			return "Target Draw"
		CardResource.CardType.MULTI_TARGET_DRAW:
			return "Multi Target Draw"
		CardResource.CardType.WILD_COLOR_ROULET:
			return "Color Roulette"
	return "Card"
