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
var is_initialized: bool = false
var _uid_counter: int = 1


func _ready() -> void:
	connect_signals()
	Signals.TURN_changed.connect(_on_turn_changed)
	NetworkManager.match_state_received.connect(_on_match_state_received)
	is_initialized = true


func connect_signals() -> void:
	Signals.COLOR_color_selected.connect(select_color)


func create_default_cards() -> Array[CardResource]:
	return create_cards_from_deck(loaded_deck)


func create_card(color: CardResource.CardColor, type: CardResource.CardType, value: int) -> CardResource:
	var card := CardResource.new()
	card.color = color
	card.type = type
	card.value = value
	card.uid = _uid_counter
	_uid_counter += 1
	return card

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


func set_top_card_runtime(card: CardResource) -> void:
	if card == null:
		return

	if top_card != null:
		discard_pile.append(top_card)

	top_card = card
	if top_card_view == null or !is_instance_valid(top_card_view):
		update_draw_button_state()
		return
	top_card_view.card_res = top_card
	top_card_view.override_color_enabled = false

	if _card_requires_color_selection(card):
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

	update_draw_button_state()

func set_top_card_no_effect(card: CardResource) -> void:
	if card == null:
		return

	if top_card != null:
		discard_pile.append(top_card)

	top_card = card
	current_color = card.color
	waiting_for_color = false
	pending_wild_card = null

	if top_card_view == null or !is_instance_valid(top_card_view):
		update_draw_button_state()
		return

	top_card_view.card_res = top_card
	top_card_view.override_color_enabled = false
	top_card_view.load_card()

	update_draw_button_state()


func _card_requires_color_selection(card: CardResource) -> bool:
	if card == null:
		return false
	return card.type in [
		CardResource.CardType.WILD,
		CardResource.CardType.WILD_DRAW,
		CardResource.CardType.WILD_DRAW_REVERSE,
	]


func select_color(color: CardResource.CardColor) -> void:
	if !waiting_for_color:
		return

	current_color = color
	waiting_for_color = false

	if top_card != null:
		top_card.color = color

	top_card_view.override_color_enabled = true
	top_card_view.override_color = color
	top_card_view.load_card()

	pending_wild_card = null
	update_draw_button_state()


func _on_draw_deck_pressed() -> void:
	if waiting_for_color:
		return
	if queue_manager != null:
		if multiplayer.has_multiplayer_peer():
			if !queue_manager.is_local_turn():
				return
		elif !queue_manager.is_human_turn():
			return
	Signals.DECK_draw_pressed.emit()


func draw_card() -> CardResource:
	if deck.is_empty():
		refill_deck_from_discard()
	if deck.is_empty():
		return null
	return deck.pop_front()


func peek_next_card(offset: int = 0) -> CardResource:
	if deck.is_empty():
		return null
	offset = max(offset, 0)
	if offset >= deck.size():
		return null
	return deck[offset]


func peek_next_cards(amount: int = 3) -> Array[CardResource]:
	var res: Array[CardResource] = []
	for i in range(min(amount, deck.size())):
		res.append(deck[i])
	return res


func refill_deck_from_discard() -> void:
	if discard_pile.size() <= 1:
		return
	var keep_top = discard_pile.pop_back()
	deck = discard_pile
	deck.shuffle()
	discard_pile = [keep_top]


func get_top_card() -> CardResource:
	return top_card


func get_current_color() -> CardResource.CardColor:
	return current_color


func update_draw_button_state() -> void:
	if draw_button == null:
		return

	var allow := true
	if waiting_for_color:
		allow = false
	elif queue_manager != null:
		if multiplayer.has_multiplayer_peer():
			allow = queue_manager.is_local_turn()
		else:
			allow = queue_manager.is_human_turn()

	draw_button.disabled = !allow


func _on_turn_changed(_holder: HandCardHolder) -> void:
	update_draw_button_state()

	if queue_manager != null and queue_manager.is_human_turn():
		_smooth_modulate(draw_button, Color.WHITE, 0.25)
	else:
		_smooth_modulate(draw_button, Color(0.35, 0.35, 0.35, 1.0), 0.25)


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


func add_number_cards(arr: Array[CardResource], colors: Array, rule: DeckNumberRuleResource) -> void:
	for c in colors:
		for n in range(rule.min_number, rule.max_number + 1):
			var copies := rule.default_copies
			if rule.overrides.has(str(n)):
				copies = int(rule.overrides[str(n)])
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
		var s := int(prefer_fn.call(c))
		if s > best_score:
			best_score = s
			best_index = i

	var picked := deck[best_index]
	deck.remove_at(best_index)
	return picked


func force_insert_card_on_top(card: CardResource) -> void:
	if card != null:
		deck.insert(0, card)


func force_insert_card_at(index: int, card: CardResource) -> void:
	if card != null:
		deck.insert(clamp(index, 0, deck.size()), card)


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


func _smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.2) -> void:
	if node == null:
		return
	var tween := create_tween()
	tween.tween_property(node, "modulate", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_match_state_received(state: Dictionary) -> void:
	var top = state.get("top_card", null)
	if top is Dictionary and top.has("c") and top.has("t") and top.has("v") and top.has("id"):
		var r := CardResource.new()
		r.color = int(top.get("c", 0))
		r.type = int(top.get("t", 0))
		r.value = int(top.get("v", 0))
		r.uid = int(top.get("id", 0))
		set_top_card_runtime(r)

	if state.has("current_color"):
		current_color = int(state.get("current_color", current_color))
	if state.has("waiting_for_color"):
		var waiting := bool(state.get("waiting_for_color", waiting_for_color))
		if waiting and !waiting_for_color:
			waiting_for_color = true
		elif !waiting and waiting_for_color:
			select_color(current_color)
