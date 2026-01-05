extends Node
class_name CardManager

@export_group("Ui Elements")
@export var top_card: CardResource
@export var top_card_view: CardView
@export var queue_manager: QueueManager
@export var draw_button: TextureButton

@export_group("Deck")
@export var loaded_deck: DeckResource


var deck: Array[CardResource] = []
var discard_pile: Array[CardResource] = []
var current_color: CardResource.CardColor
var waiting_for_color := false
var pending_wild_card: CardResource = null

func _ready() -> void:
	randomize()
	connect_signals()
	Signals.TURN_changed.connect(_on_turn_changed)
	deck = create_default_cards()
	deck.shuffle()
	set_top_card()
	update_draw_button_state()

## Connect shared signals
func connect_signals() -> void:
	Signals.COLOR_color_selected.connect(select_color)


## Creates the default DropOne deck scaled for up to 8 players with extra draw variants and expanded action density
func create_default_cards() -> Array[CardResource]:
	return create_cards_from_deck(loaded_deck)


## Create a card resource instance
func create_card(color: CardResource.CardColor, type: CardResource.CardType, value: int) -> CardResource:
	var card := CardResource.new()
	card.color = color
	card.type = type
	card.value = value
	return card

## Set initial top card to first non-action number
func set_top_card() -> void:
	while deck.size() > 0:
		var card: CardResource = deck[0]
		if card.type == CardResource.CardType.NUMBER:
			deck.remove_at(0)
			set_top_card_runtime(card)
			return
		deck.remove_at(0)
		deck.append(card)

## Update top card, discard, and wild color state
func set_top_card_runtime(card: CardResource) -> void:
	if top_card != null:
		discard_pile.append(top_card)

	top_card = card
	top_card_view.card_res = top_card
	top_card_view.override_color_enabled = false

	if card.type == CardResource.CardType.WILD or card.type == CardResource.CardType.WILD_DRAW:
		current_color = CardResource.CardColor.BLACK
		waiting_for_color = true
		pending_wild_card = card
		top_card_view.load_card()
		Signals.COLOR_request_color_select.emit()
	else:
		current_color = card.color
		waiting_for_color = false
		pending_wild_card = null
		top_card_view.load_card()

## Apply selected wild color and update view
func select_color(color: CardResource.CardColor) -> void:
	if !waiting_for_color:
		return

	current_color = color
	waiting_for_color = false

	top_card_view.override_color_enabled = true
	top_card_view.override_color = color
	top_card_view.load_card()

	pending_wild_card = null
	update_draw_button_state()

## Emit draw request from UI (human only)
func _on_draw_deck_pressed() -> void:
	if waiting_for_color:
		return
	if queue_manager != null and !queue_manager.is_human_turn():
		return
	Signals.DECK_draw_pressed.emit()

## Draw one card from deck (refill if needed)
func draw_card() -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	if deck.is_empty():
		return null
	var card: CardResource = deck[0]
	deck.remove_at(0)
	return card

## Returns the next card in the deck without removing it (Omega cheat)
func peek_next_card(offset: int = 0) -> CardResource:
	if deck.is_empty():
		return null
	if offset < 0:
		offset = 0
	if offset >= deck.size():
		return null
	return deck[offset]


## Returns the next N cards (Omega cheat)
func peek_next_cards(amount: int = 3) -> Array[CardResource]:
	var res: Array[CardResource] = []
	if deck.is_empty():
		return res
	for i in range(min(amount, deck.size())):
		res.append(deck[i])
	return res


## Refill deck from discard pile while keeping top
func refill_deck_from_discard() -> void:
	if discard_pile.size() <= 1:
		return
	var keep_top = discard_pile.pop_back()
	deck = discard_pile
	deck.shuffle()
	discard_pile = [keep_top]

## Get current top card
func get_top_card() -> CardResource:
	return top_card

## Get current active color
func get_current_color() -> CardResource.CardColor:
	return current_color

## Enable/disable draw button based on turn and wild color selection
func update_draw_button_state() -> void:
	if draw_button == null:
		return
	var allow := true
	if waiting_for_color:
		allow = false
	elif queue_manager != null and !queue_manager.is_human_turn():
		allow = false
	draw_button.disabled = !allow

## React to turn changes for draw button state
func _on_turn_changed(_holder: HandCardHolder) -> void:
	update_draw_button_state()

func create_cards_from_deck(deck_res: DeckResource) -> Array[CardResource]:
	var arr: Array[CardResource] = []
	if deck_res == null:
		return arr
	
	var colors := [
		CardResource.CardColor.RED,
		CardResource.CardColor.GREEN,
		CardResource.CardColor.BLUE,
		CardResource.CardColor.YELLOW
	]
	
	if deck_res.number_rules != null:
		add_number_cards(arr, colors, deck_res.number_rules)
	
	for entry in deck_res.entries:
		if entry == null:
			continue
		add_entry_cards(arr, entry)
	
	return arr


func add_number_cards(arr: Array[CardResource], colors: Array, rule: DeckNumberRuleResource) -> void:
	var min_n := rule.min_number
	var max_n := rule.max_number
	var default_copies := rule.default_copies
	var overrides := rule.overrides
	
	for c in colors:
		for n in range(min_n, max_n + 1):
			var key := str(n)
			var copies := default_copies
			if overrides.has(key):
				copies = int(overrides[key])
			
			for i in range(copies):
				arr.append(create_card(c, CardResource.CardType.NUMBER, n))


func add_entry_cards(arr: Array[CardResource], entry: DeckEntryResource) -> void:
	if entry.duplicate_for_all_colors:
		for c in entry.colors:
			for i in range(entry.count):
				arr.append(create_card(c, entry.type, entry.value))
	else:
		for i in range(entry.count):
			arr.append(create_card(entry.color, entry.type, entry.value))

func draw_specific_card_from_top_range(range: int, prefer_fn: Callable) -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	if deck.is_empty():
		return null
	
	range = clamp(range, 1, deck.size())
	
	var best_index := 0
	var best_score := -999999
	
	for i in range(range):
		var c := deck[i]
		if c == null:
			continue
		
		var s := int(prefer_fn.call(c))
		if s > best_score:
			best_score = s
			best_index = i
	
	var picked := deck[best_index]
	deck.remove_at(best_index)
	return picked

func force_insert_card_on_top(card: CardResource) -> void:
	if card == null:
		return
	deck.insert(0, card)

func force_insert_card_at(index: int, card: CardResource) -> void:
	if card == null:
		return
	index = clamp(index, 0, deck.size())
	deck.insert(index, card)

func remove_first_matching_card(predicate: Callable) -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	if deck.is_empty():
		return null
	
	for i in range(deck.size()):
		var c := deck[i]
		if c == null:
			continue
		if bool(predicate.call(c)):
			deck.remove_at(i)
			return c
	
	return null

func get_deck_size() -> int:
	return deck.size()

func get_discard_size() -> int:
	return discard_pile.size()
