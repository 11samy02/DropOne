extends Node
class_name QueueManager

@export var player_container: Control
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


func _ready() -> void:
	connect_signals()
	create_players()
	create_bots()
	build_turn_order()
	start_game()


func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)


## Creates all human players
func create_players() -> void:
	for i in range(player_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = false
		holder.player_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		player_container.add_child(holder)
		players.append(holder)


## Creates all bot players
func create_bots() -> void:
	for i in range(bots_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = true
		holder.bot_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		player_container.add_child(holder)
		bots.append(holder)


## Builds the full turn order list
func build_turn_order() -> void:
	turn_order.clear()
	turn_order.append_array(players)
	turn_order.append_array(bots)


## Starts the first turn
func start_game() -> void:
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()
	await get_tree().process_frame
	deal_starting_cards(7)


## Returns current active holder
func get_current_holder() -> HandCardHolder:
	return turn_order[current_turn_index]


## Checks if holder is active
func is_players_turn(holder: HandCardHolder) -> bool:
	return holder == get_current_holder()


## Validates if holder may play a card
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


## Registers a successful play and advances the turn unless in solo mode
func register_card_play() -> void:
	if turn_order.size() <= 1:
		has_played_this_turn = false
		has_drawn_this_turn = false
		update_turn_state()
		return
	
	has_played_this_turn = true
	end_turn()



## Handles draw button presses
func on_draw_pressed() -> void:
	var holder := get_current_holder()
	if holder == null:
		return
	if !is_players_turn(holder):
		return
	if has_played_this_turn:
		return
	if has_drawn_this_turn:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return
	
	var card := card_manager.draw_card()
	if card == null:
		return
	
	holder.add_card(card)
	holder.refresh_playable_cards()
	
	if turn_order.size() <= 1:
		has_drawn_this_turn = false
	else:
		has_drawn_this_turn = true
	
	if !allow_play_after_draw:
		end_turn()


## Ends current turn
func end_turn() -> void:
	next_turn()


## Advances to next turn and updates states correctly
func next_turn() -> void:
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()



## Updates active visuals and clickability
func update_turn_state() -> void:
	for holder in turn_order:
		holder.set_turn_active(is_players_turn(holder))

## deals cards to the player
func deal_starting_cards(cards_per_player: int = 7) -> void:
	for holder in turn_order:
		for i in range(cards_per_player):
			var card := card_manager.draw_card()
			if card == null:
				return
			holder.add_card(card)
		#holder.sort_cards_full()
		holder.refresh_playable_cards()
