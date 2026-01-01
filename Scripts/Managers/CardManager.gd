extends Node
class_name CardManager

@export var top_card: CardResource
@export var top_card_view: CardView
@export var queue_manager: QueueManager
@export var draw_button: Button

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

## Create a full UNO deck (numbers, actions, wilds)
func create_default_cards() -> Array[CardResource]:
	var arr: Array[CardResource] = []
	var colors := [
		CardResource.CardColor.RED,
		CardResource.CardColor.GREEN,
		CardResource.CardColor.BLUE,
		CardResource.CardColor.YELLOW
	]

	for c in colors:
		arr.append(create_card(c, CardResource.CardType.NUMBER, 0))
		for n in range(1, 10):
			arr.append(create_card(c, CardResource.CardType.NUMBER, n))
			arr.append(create_card(c, CardResource.CardType.NUMBER, n))
		for i in range(2):
			arr.append(create_card(c, CardResource.CardType.SKIP, 0))
			arr.append(create_card(c, CardResource.CardType.REVERSE, 0))
			arr.append(create_card(c, CardResource.CardType.DRAW, 2))

	for i in range(4):
		arr.append(create_card(CardResource.CardColor.BLACK, CardResource.CardType.WILD, 0))
		arr.append(create_card(CardResource.CardColor.BLACK, CardResource.CardType.WILD_DRAW, 4))

	return arr

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
	var card: CardResource = deck[0].duplicate()
	deck.remove_at(0)
	return card

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
