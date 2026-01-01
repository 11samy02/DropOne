extends Node
class_name KIController

@export var hand_card_holder: HandCardHolder
@export var queue_manager: QueueManager
@export var card_manager: CardManager
@export var think_time := 0.45

func _ready() -> void:
	Signals.TURN_changed.connect(_on_turn_changed)
	Signals.COLOR_request_color_select.connect(_on_color_request)

## Trigger KI turn when this holder becomes active
func _on_turn_changed(holder: HandCardHolder) -> void:
	if holder == null:
		return
	if hand_card_holder == null:
		return
	if holder != hand_card_holder:
		return
	if !hand_card_holder.is_bot:
		return
	play_turn()

## Handle KI playing a full turn (play / draw / pass)
func play_turn() -> void:
	if card_manager == null or queue_manager == null or hand_card_holder == null:
		return
	if card_manager.waiting_for_color:
		return

	await get_tree().create_timer(think_time).timeout

	var playable := get_playable_cards()
	if playable.size() > 0:
		var best := choose_best_card(playable)
		if best != null:
			hand_card_holder.set_card(best)
			return

	var drew := queue_manager.bot_draw_current()
	if drew:
		await get_tree().create_timer(0.25).timeout
		playable = get_playable_cards()
		if playable.size() > 0:
			var best2 := choose_best_card(playable)
			if best2 != null:
				hand_card_holder.set_card(best2)
				return

	queue_manager.end_turn()

## Collect all playable card views from this bot hand
func get_playable_cards() -> Array[CardView]:
	var arr: Array[CardView] = []
	for c in hand_card_holder.get_children():
		if c is CardView:
			if hand_card_holder.can_play_card(c.card_res):
				arr.append(c)
	return arr

## Decide best card to play using simple but strong heuristics
func choose_best_card(playable: Array[CardView]) -> CardView:
	var opponent_low := is_any_opponent_low_cards(2)

	var wild_draw: Array[CardView] = []
	var draw: Array[CardView] = []
	var skip_reverse: Array[CardView] = []
	var normal: Array[CardView] = []
	var wild: Array[CardView] = []

	for card in playable:
		match card.card_res.type:
			CardResource.CardType.WILD_DRAW:
				wild_draw.append(card)
			CardResource.CardType.DRAW:
				draw.append(card)
			CardResource.CardType.SKIP, CardResource.CardType.REVERSE:
				skip_reverse.append(card)
			CardResource.CardType.WILD:
				wild.append(card)
			_:
				normal.append(card)

	if opponent_low:
		if wild_draw.size() > 0:
			return wild_draw.pick_random()
		if draw.size() > 0:
			return choose_biggest_draw(draw)
		if skip_reverse.size() > 0:
			return skip_reverse.pick_random()

	if queue_manager != null and queue_manager.draw_stack_amount > 0 and !queue_manager.draw_stack_is_wild:
		if draw.size() > 0:
			return choose_biggest_draw(draw)

	if normal.size() > 0:
		return choose_best_normal(normal)

	if draw.size() > 0:
		return choose_biggest_draw(draw)
	if skip_reverse.size() > 0:
		return skip_reverse.pick_random()
	if wild.size() > 0:
		return wild.pick_random()
	if wild_draw.size() > 0:
		return wild_draw.pick_random()

	return null

## Prefer biggest +N to push stack pressure
func choose_biggest_draw(draw_cards: Array[CardView]) -> CardView:
	var best := draw_cards[0]
	for c in draw_cards:
		if c.card_res.value > best.card_res.value:
			best = c
	return best

## Prefer playing from the most abundant color in hand
func choose_best_normal(cards: Array[CardView]) -> CardView:
	var color_counts := count_colors_in_hand()
	var best := cards[0]
	var best_score := -999999

	for c in cards:
		var col := c.card_res.color
		var score := 0

		score += int(color_counts.get(col, 0)) * 10

		if c.card_res.type != CardResource.CardType.NUMBER:
			score += 6

		if c.card_res.type == CardResource.CardType.NUMBER:
			score += (9 - c.card_res.value)

		if score > best_score:
			best_score = score
			best = c

	return best

## Count non-black colors in this hand
func count_colors_in_hand() -> Dictionary:
	var counts := {}
	for c in hand_card_holder.get_children():
		if c is CardView:
			var col = c.card_res.color
			if col == CardResource.CardColor.BLACK:
				continue
			counts[col] = counts.get(col, 0) + 1
	return counts

## Check if any opponent is near winning
func is_any_opponent_low_cards(max_cards: int = 2) -> bool:
	if queue_manager == null:
		return false
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		if h.get_child_count() <= max_cards:
			return true
	return false

## Auto-pick wild color for bots based on hand distribution
func _on_color_request() -> void:
	if queue_manager == null or hand_card_holder == null:
		return
	if queue_manager.get_current_holder() != hand_card_holder:
		return
	if !hand_card_holder.is_bot:
		return
	await get_tree().create_timer(0.35).timeout
	Signals.COLOR_color_selected.emit(choose_best_wild_color())

## Choose the color the bot holds the most
func choose_best_wild_color() -> CardResource.CardColor:
	var counts := count_colors_in_hand()
	var best_color := CardResource.CardColor.RED
	var best_count := -1
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var c := int(counts.get(color, 0))
		if c > best_count:
			best_count = c
			best_color = color
	return best_color
