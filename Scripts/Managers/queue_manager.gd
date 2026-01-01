extends Node
class_name QueueManager

@export var player_container: Control
@export var other_player_containers: Array[Control]
@export var card_manager: CardManager

@export var player_count := 1
@export var bots_count := 3

var players: Array[HandCardHolder] = []
var bots: Array[HandCardHolder] = []
var turn_order: Array[HandCardHolder] = []

var current_turn_index := 0
var has_played_this_turn := false
var has_drawn_this_turn := false
var allow_play_after_draw := true

var direction := 1
var draw_stack_amount := 0
var draw_stack_min_value := 0
var draw_stack_is_wild := false

func _ready() -> void:
	connect_signals()
	create_players()
	create_bots()
	build_turn_order()
	start_game()

## Connect input signals
func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)

## Resolve the UI container for a given holder
func get_container_for_holder(holder: HandCardHolder) -> Control:
	if !holder.is_bot and holder.player_index == 0:
		return player_container
	var index := get_opponent_index(holder)
	if index < other_player_containers.size():
		return other_player_containers[index]
	return player_container

## Map holder to opponent index for UI placement
func get_opponent_index(holder: HandCardHolder) -> int:
	if !holder.is_bot:
		return holder.player_index - 1
	return max(0, player_count - 1) + holder.bot_index

## Create human players
func create_players() -> void:
	for i in range(player_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = false
		holder.player_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		get_container_for_holder(holder).add_child(holder)
		players.append(holder)

## Create bots and attach KI controllers
func create_bots() -> void:
	for i in range(bots_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = true
		holder.bot_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		get_container_for_holder(holder).add_child(holder)
		bots.append(holder)

		var ki := KIController.new()
		ki.hand_card_holder = holder
		ki.queue_manager = self
		ki.card_manager = card_manager
		add_child(ki)

## Build initial turn order
func build_turn_order() -> void:
	turn_order.clear()
	turn_order.append_array(players)
	turn_order.append_array(bots)

## Start game and deal starting cards
func start_game() -> void:
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()
	await get_tree().process_frame
	deal_starting_cards(7)

## Get current active holder
func get_current_holder() -> HandCardHolder:
	return turn_order[current_turn_index]

## Check if a holder is currently active
func is_players_turn(holder: HandCardHolder) -> bool:
	return holder == get_current_holder()

## Determine if holder may play a card now
func can_play_now(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	if !is_players_turn(holder):
		return false
	if has_played_this_turn:
		return false
	if card_manager != null and card_manager.waiting_for_color:
		return false
	return true

## Register a played card and apply its effects
func register_card_play(played_card: CardResource) -> void:
	if played_card == null:
		end_turn()
		return

	has_played_this_turn = true

	match played_card.type:
		CardResource.CardType.SKIP:
			next_turn(true)
			return
		CardResource.CardType.REVERSE:
			apply_reverse()
			end_turn()
			return
		CardResource.CardType.DRAW:
			start_or_stack_draw(played_card.value, false)
			end_turn()
			return
		CardResource.CardType.WILD_DRAW:
			start_or_stack_draw(played_card.value, true)
			end_turn()
			return

	end_turn()

## Apply reverse by flipping direction
func apply_reverse() -> void:
	direction *= -1

## Start or stack draw penalties (+N or +4)
func start_or_stack_draw(value: int, is_wild: bool) -> void:
	draw_stack_amount += value
	draw_stack_min_value = max(draw_stack_min_value, value)
	if is_wild:
		draw_stack_is_wild = true

## Handle draw button pressed by human
func on_draw_pressed() -> void:
	var holder := get_current_holder()
	if holder == null:
		return
	if holder.is_bot:
		return
	if !is_players_turn(holder):
		return
	if has_played_this_turn:
		return
	if has_drawn_this_turn:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return

	if draw_stack_amount > 0:
		if draw_stack_is_wild:
			force_wild_draw_continue(holder)
		else:
			force_draw_stack_end_turn(holder)
		return

	var card := card_manager.draw_card()
	if card == null:
		return

	holder.add_card(card)
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	if !allow_play_after_draw:
		end_turn()
		return

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()

## Let a bot draw one card during its turn if allowed
func bot_draw_current() -> bool:
	var holder := get_current_holder()
	if holder == null:
		return false
	if !holder.is_bot:
		return false
	if has_played_this_turn:
		return false
	if has_drawn_this_turn:
		return false
	if card_manager != null and card_manager.waiting_for_color:
		return false

	if draw_stack_amount > 0 and !draw_stack_is_wild:
		force_draw_stack_end_turn(holder)
		return true

	var card := card_manager.draw_card()
	if card == null:
		return false

	holder.add_card(card)
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	return true

## End the current turn
func end_turn() -> void:
	next_turn()

## Advance to next turn with optional skip
func next_turn(skip_next: bool = false) -> void:
	var steps := 1
	if skip_next:
		steps = 2

	current_turn_index = (current_turn_index + direction * steps) % turn_order.size()
	if current_turn_index < 0:
		current_turn_index += turn_order.size()

	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")

## Update turn_active on all holders and broadcast turn change
func update_turn_state() -> void:
	for holder in turn_order:
		holder.set_turn_active(is_players_turn(holder))
	Signals.TURN_changed.emit(get_current_holder())

## Deal starting cards to all holders
func deal_starting_cards(cards_per_player: int = 7) -> void:
	for holder in turn_order:
		for i in range(cards_per_player):
			var card := card_manager.draw_card()
			if card == null:
				return
			holder.add_card(card)
		holder.refresh_playable_cards()

## Check if current turn belongs to a human
func is_human_turn() -> bool:
	var holder := get_current_holder()
	return holder != null and !holder.is_bot

## Determine if holder has any playable card currently
func holder_has_playable_card(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView:
			if holder.can_play_card(c.card_res):
				return true
	return false

## Apply pending effects at start of the new holder's turn
func _handle_start_of_turn_effects() -> void:
	var holder := get_current_holder()
	if holder == null:
		return

	if draw_stack_amount > 0 and draw_stack_is_wild:
		force_wild_draw_continue(holder)
		return

	if draw_stack_amount > 0 and !draw_stack_is_wild and holder.is_bot:
		_try_bot_stack_or_draw(holder)

## Force stack draw (+N) and end the turn
func force_draw_stack_end_turn(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)
	
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	
	holder.refresh_playable_cards()
	
	await get_tree().create_timer(0.25).timeout
	end_turn()


## Force wild draw (+4) but keep the same player active (they may draw normally)
func force_wild_draw_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)

	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false

	holder.refresh_playable_cards()


## Bot reacts to a +N stack: stack higher/equal or take stack
func _try_bot_stack_or_draw(holder: HandCardHolder) -> void:
	var candidates: Array[CardView] = []
	for c in holder.get_children():
		if c is CardView:
			var r = c.card_res
			if r.type == CardResource.CardType.DRAW and r.value >= draw_stack_min_value:
				candidates.append(c)

	if candidates.size() > 0:
		var best := candidates[0]
		for cv in candidates:
			if cv.card_res.value > best.card_res.value:
				best = cv
		holder.set_card(best)
		return

	force_draw_stack_end_turn(holder)

## Returns a UI string like "+6" for current draw stack or "" if none
func get_draw_stack_text() -> String:
	if draw_stack_amount <= 0:
		return ""
	return "+" + str(draw_stack_amount)
