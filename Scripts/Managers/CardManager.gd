extends Node
class_name CardManager

@export_group("Ui Elements")
## Authoritative top card on the discard pile.
@export var top_card: CardResource
## Scene node displaying the current top card.
@export var top_card_view: CardView
## Turn and draw rules coordinator.
@export var queue_manager: QueueManager
## Button that triggers drawing from the deck.
@export var draw_button: TextureButton

@export_group("Deck")
## Deck definition used to build the runtime card array.
@export var loaded_deck: DeckResource

## Shuffled draw pile; cards are popped from the front.
var deck: Array[CardResource] = []
## Previously played cards kept under the current top card.
var discard_pile: Array[CardResource] = []
## Active play color after wild resolution or top number card.
var current_color: CardResource.CardColor
## True while waiting for a wild color pick before the play resolves.
var waiting_for_color := false
## Wild card pending color selection on the discard pile.
var pending_wild_card: CardResource = null
## True after _ready has connected signals.
var is_initialized: bool = false
## Monotonic id source for newly created cards.
var _uid_counter: int = 1

## While suppressed, runtime top-card updates are buffered instead of applied,
## so a card flying from a hand to the discard pile isn't instantly snapped by
## an incoming match-state sync mid-animation.
var _top_card_suppressed := false
var _suppressed_top_card: CardResource = null

## Looping highlight on the draw deck shown when the local player must draw.
var _draw_pulse_tween: Tween = null


func _ready() -> void:
	connect_signals()
	Signals.TURN_changed.connect(_on_turn_changed)
	is_initialized = true


func connect_signals() -> void:
	Signals.COLOR_color_selected.connect(select_color)


## Builds the runtime deck array from loaded_deck (or empty if unset).
func create_default_cards() -> Array[CardResource]:
	return create_cards_from_deck(loaded_deck)


## Creates a new CardResource with a fresh uid.
func create_card(color: CardResource.CardColor, type: CardResource.CardType, value: int) -> CardResource:
	var card := CardResource.new()
	card.type = type
	card.value = value
	if CardResource.is_neutral_wild_type(type):
		card.color = CardResource.CardColor.BLACK
	else:
		card.color = color
	card.uid = _uid_counter
	_uid_counter += 1
	return card

## Draws until a valid starting NUMBER card is found and sets it as top.
func set_top_card() -> void:
	if deck.is_empty():
		return

	var picked: CardResource = null
	var tries := deck.size()
	while tries > 0 and picked == null:
		var c := draw_card()
		if c == null:
			break
		if c.type != CardResource.CardType.NUMBER or c.color == CardResource.CardColor.BLACK:
			discard_pile.append(c)
		else:
			picked = c
		tries -= 1

	if picked == null:
		picked = draw_card()
	if picked != null:
		set_top_card_runtime(picked)


## Begin/end buffering of runtime top-card changes (used around remote card
## fly animations so the top card only swaps once the card lands).
func begin_top_card_suppression() -> void:
	_top_card_suppressed = true

func is_top_card_suppressed() -> bool:
	return _top_card_suppressed

func end_top_card_suppression(fallback: CardResource = null, prompt_color: bool = true) -> void:
	_top_card_suppressed = false
	var buffered := _suppressed_top_card
	_suppressed_top_card = null
	if buffered != null:
		set_top_card_runtime(buffered, prompt_color)
	elif fallback != null:
		set_top_card_runtime(fallback, prompt_color)


## Applies a new top card, handles wild color prompt, and updates UI.
func set_top_card_runtime(card: CardResource, prompt_color: bool = true) -> void:
	if card == null:
		return

	if _top_card_suppressed:
		_suppressed_top_card = card
		return

	if top_card != null:
		top_card.ensure_neutral_wild_color()
		discard_pile.append(top_card)

	top_card = card

	if _card_requires_color_selection(card):
		current_color = CardResource.CardColor.BLACK
		if prompt_color:
			waiting_for_color = true
			pending_wild_card = card
			Signals.COLOR_request_color_select.emit()
		else:
			waiting_for_color = false
			pending_wild_card = null
	else:
		current_color = card.color
		waiting_for_color = false
		pending_wild_card = null

	if top_card_view == null or !is_instance_valid(top_card_view):
		update_draw_button_state()
		return

	top_card_view.card_res = top_card
	sync_top_card_color_visual()
	update_draw_button_state()

## Sets top card without triggering wild/color side effects (place-all steps).
func set_top_card_no_effect(card: CardResource) -> void:
	if card == null:
		return

	if top_card != null:
		top_card.ensure_neutral_wild_color()
		discard_pile.append(top_card)

	top_card = card
	current_color = card.color
	waiting_for_color = false
	pending_wild_card = null

	if top_card_view == null or !is_instance_valid(top_card_view):
		update_draw_button_state()
		return

	top_card_view.card_res = top_card
	sync_top_card_color_visual()
	update_draw_button_state()


## True if this card type requires a color pick when played to the top.
func _card_requires_color_selection(card: CardResource) -> bool:
	if card == null:
		return false
	return card.type in [
		CardResource.CardType.WILD,
		CardResource.CardType.WILD_DRAW,
		CardResource.CardType.WILD_DRAW_REVERSE,
	]


## Resolves wild color selection and updates top card visuals.
func select_color(color: CardResource.CardColor) -> void:
	if !waiting_for_color:
		return

	current_color = color
	waiting_for_color = false
	sync_top_card_color_visual()

	pending_wild_card = null
	update_draw_button_state()


## Applies chosen current_color to the top discard visual without mutating wild card data.
func sync_top_card_color_visual() -> void:
	if top_card_view == null or !is_instance_valid(top_card_view) or top_card == null:
		return

	if CardResource.is_neutral_wild_type(top_card.type):
		if waiting_for_color or current_color == CardResource.CardColor.BLACK:
			top_card_view.override_color_enabled = false
		else:
			top_card_view.override_color_enabled = true
			top_card_view.override_color = current_color
	else:
		top_card_view.override_color_enabled = false

	top_card_view.load_card()


## Draw button handler: validates turn then emits DECK_draw_pressed.
func _on_draw_deck_pressed() -> void:
	if waiting_for_color:
		return
	if queue_manager != null:
		if queue_manager.is_local_spectating():
			return
		var allowed := false
		if multiplayer.has_multiplayer_peer():
			allowed = queue_manager.is_local_turn()
		else:
			allowed = queue_manager.is_human_turn()
		if !allowed:
			return
	Signals.DECK_draw_pressed.emit()


## Removes and returns the next card from the deck; refills from discard if empty.
func draw_card() -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	if deck.is_empty():
		return null
	var card := deck.pop_front()
	if card != null:
		card.ensure_neutral_wild_color()
	return card


## Returns a card at offset from the top of the deck without drawing it.
func peek_next_card(offset: int = 0) -> CardResource:
	if deck.is_empty():
		return null
	offset = max(offset, 0)
	if offset >= deck.size():
		return null
	return deck[offset]


## Returns up to `amount` cards from the top of the deck without drawing.
func peek_next_cards(amount: int = 3) -> Array[CardResource]:
	var res: Array[CardResource] = []
	for i in range(min(amount, deck.size())):
		res.append(deck[i])
	return res


## Shuffles discard back into deck, keeping the current top on the discard pile.
func refill_deck_from_discard() -> void:
	if discard_pile.size() <= 1:
		return
	var keep_top = discard_pile.pop_back()
	deck = discard_pile
	for card in deck:
		if card != null:
			card.ensure_neutral_wild_color()
	deck.shuffle()
	discard_pile = [keep_top]


func get_top_card() -> CardResource:
	return top_card


func get_current_color() -> CardResource.CardColor:
	return current_color


## Enables or disables the draw button based on turn and color-wait state.
func update_draw_button_state() -> void:
	if draw_button == null:
		return

	var allow := true
	if waiting_for_color:
		allow = false
	elif queue_manager != null and queue_manager.is_local_spectating():
		allow = false

	draw_button.disabled = !allow


func _on_turn_changed(_holder: HandCardHolder) -> void:
	update_draw_button_state()
	_update_draw_hint()


## Visually communicate the local player's draw situation:
## - not your turn  -> dimmed deck
## - your turn, can play -> bright deck
## - your turn, no playable card (must draw) -> pulsing highlight
func _update_draw_hint() -> void:
	if draw_button == null:
		return

	var my_turn := false
	if queue_manager != null:
		if multiplayer.has_multiplayer_peer():
			my_turn = queue_manager.is_local_turn()
		else:
			my_turn = queue_manager.is_human_turn()

	if !my_turn or waiting_for_color or (queue_manager != null and queue_manager.is_local_spectating()):
		_stop_draw_pulse()
		_smooth_modulate(draw_button, Color(0.35, 0.35, 0.35, 1.0), 0.25)
		return

	var must_draw := false
	if queue_manager != null:
		var ch := queue_manager.get_current_holder()
		must_draw = ch != null and !queue_manager.holder_has_playable_card(ch)

	if must_draw:
		_start_draw_pulse()
	else:
		_stop_draw_pulse()
		_smooth_modulate(draw_button, Color.WHITE, 0.25)


func _start_draw_pulse() -> void:
	if draw_button == null:
		return
	if _draw_pulse_tween != null and _draw_pulse_tween.is_valid():
		return
	_draw_pulse_tween = create_tween().set_loops()
	_draw_pulse_tween.tween_property(draw_button, "modulate", Color(1.0, 0.82, 0.2, 1.0), 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_draw_pulse_tween.tween_property(draw_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_draw_pulse() -> void:
	if _draw_pulse_tween != null and _draw_pulse_tween.is_valid():
		_draw_pulse_tween.kill()
	_draw_pulse_tween = null


## Builds card array from a DeckResource (numbers + entry cards).
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
		if entry != null:
			add_entry_cards(arr, entry)

	return arr


## Appends numbered cards for each color using number_rules copy counts.
func add_number_cards(arr: Array[CardResource], colors: Array, rule: DeckNumberRuleResource) -> void:
	for c in colors:
		for n in range(rule.min_number, rule.max_number + 1):
			var copies := rule.default_copies
			if rule.overrides.has(str(n)):
				copies = int(rule.overrides[str(n)])
			for i in range(copies):
				arr.append(create_card(c, CardResource.CardType.NUMBER, n))


## Appends special cards from a single DeckEntryResource.
func add_entry_cards(arr: Array[CardResource], entry: DeckEntryResource) -> void:
	if CardResource.is_neutral_wild_type(entry.type):
		for i in range(entry.count):
			arr.append(create_card(CardResource.CardColor.BLACK, entry.type, entry.value))
		return
	if entry.duplicate_for_all_colors:
		for c in entry.colors:
			for i in range(entry.count):
				arr.append(create_card(c, entry.type, entry.value))
	else:
		for i in range(entry.count):
			arr.append(create_card(entry.color, entry.type, entry.value))


## Omega AI: draws the best-scoring card within the top `range` indices.
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
		var s := int(prefer_fn.call(c))
		if s > best_score:
			best_score = s
			best_index = i

	var picked := deck[best_index]
	deck.remove_at(best_index)
	return picked


## Inserts a card at the top of the draw pile (index 0).
func force_insert_card_on_top(card: CardResource) -> void:
	if card != null:
		deck.insert(0, card)


## Inserts a card at a specific index in the draw pile.
func force_insert_card_at(index: int, card: CardResource) -> void:
	if card != null:
		deck.insert(clamp(index, 0, deck.size()), card)


## Removes and returns the first deck card matching predicate.
func remove_first_matching_card(predicate: Callable) -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	for i in range(deck.size()):
		if predicate.call(deck[i]):
			return deck.pop_at(i)
	return null


func get_deck_size() -> int:
	return deck.size()


func get_discard_size() -> int:
	return discard_pile.size()


## Tween helper for draw-deck and card dimming feedback.
func _smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.2) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.tween_property(node, "modulate", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
