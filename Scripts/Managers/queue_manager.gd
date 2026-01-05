extends Node
class_name QueueManager

@export var player_container: Control
@export var other_player_containers: Array[Control]
@export var card_manager: CardManager

@export var player_count := 1
@export var start_card_count := 7

## Profiles for each bot in order (index 0 = first bot, etc.)
@export var bot_profiles: Array[BotProfile] = []

var winners: Array[HandCardHolder] = []

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
var draw_stack_color: CardResource.CardColor = CardResource.CardColor.BLACK
var wild_color_owner: HandCardHolder = null

var place_all_active := false
var place_all_owner: HandCardHolder = null
var place_all_color: CardResource.CardColor = CardResource.CardColor.RED
var place_all_resolving := false



func _ready() -> void:
	connect_signals()
	create_players()
	create_bots()
	build_turn_order()
	start_game()


## Connects shared gameplay signals
func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)


## Returns the correct UI container to attach a specific holder to
func get_container_for_holder(holder: HandCardHolder) -> Control:
	if holder == null:
		return player_container
	
	if !holder.is_bot and holder.player_index == 0:
		return player_container
	
	var index := get_opponent_index(holder)
	if index >= 0 and index < other_player_containers.size():
		return other_player_containers[index]
	
	return player_container


## Returns the correct "opponent index" used for placement in UI containers
func get_opponent_index(holder: HandCardHolder) -> int:
	if holder == null:
		return -1
	
	if !holder.is_bot:
		return holder.player_index - 1
	
	return max(0, player_count - 1) + holder.bot_index


## Creates all human players based on player_count
func create_players() -> void:
	players.clear()
	
	for i in range(player_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = false
		holder.player_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		
		get_container_for_holder(holder).add_child(holder)
		players.append(holder)


## Creates all bots based on bot_profiles size and applies their profile settings
func create_bots() -> void:
	bots.clear()
	
	for i in range(bot_profiles.size()):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = true
		holder.bot_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		
		get_container_for_holder(holder).add_child(holder)
		bots.append(holder)
		
		var profile := _get_bot_profile(i)
		
		var ki := KIController.new()
		ki.hand_card_holder = holder
		ki.queue_manager = self
		ki.card_manager = card_manager
		ki.difficulty = profile.difficulty
		ki.personality = profile.personality
		add_child(ki)


## Returns the bot profile for a given index or generates a fallback profile if missing
func _get_bot_profile(index: int) -> BotProfile:
	if index >= 0 and index < bot_profiles.size():
		if bot_profiles[index] != null:
			return bot_profiles[index]
	
	var fallback := BotProfile.new()
	fallback.name = "Bot " + str(index + 1)
	return fallback


## Builds the turn order list (players first, then bots)
func build_turn_order() -> void:
	turn_order.clear()
	turn_order.append_array(players)
	turn_order.append_array(bots)


## Starts the game flow and deals the starting hand
func start_game() -> void:
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()
	await get_tree().process_frame
	deal_starting_cards(start_card_count)


## Returns the holder whose turn is currently active
func get_current_holder() -> HandCardHolder:
	return turn_order[current_turn_index]


## Returns true if the passed holder is the current active holder
func is_players_turn(holder: HandCardHolder) -> bool:
	return holder == get_current_holder()

## Determines if a holder is allowed to play a card right now
func can_play_now(holder: HandCardHolder) -> bool:
	if place_all_resolving:
		return false
	
	if holder == null:
		return false
	
	if place_all_active:
		if holder != place_all_owner:
			return false
		if !is_players_turn(holder):
			return false
		if card_manager != null and card_manager.waiting_for_color:
			return false
		return true
	
	if !is_players_turn(holder):
		return false
	if has_played_this_turn:
		return false
	if card_manager != null and card_manager.waiting_for_color:
		return false
	return true




## Registers the played card and applies its effect logic to the turn system
func register_card_play(played_card: CardResource) -> void:
	if played_card == null:
		end_turn()
		return
	
	if place_all_active:
		return
	
	has_played_this_turn = true
	
	if _check_and_finish_current_holder():
		_after_holder_finished()
		return
	
	match played_card.type:
		CardResource.CardType.SKIP:
			next_turn(true)
			return
		CardResource.CardType.REVERSE:
			if turn_order.size() == 2:
				next_turn(true)
			else:
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


## Handles progression after a holder finished (winner removed)
func _after_holder_finished() -> void:
	has_played_this_turn = false
	has_drawn_this_turn = false
	
	if turn_order.size() == 1:
		call_deferred("_restart_match")
		return
	
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
	
	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")

## Restarts the scene when only one player remains
func _restart_match() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()


## Flips the direction of play
func apply_reverse() -> void:
	direction *= -1


## Adds draw stack pressure and keeps track of minimum stack value and wild status
func start_or_stack_draw(value: int, is_wild: bool) -> void:
	draw_stack_amount += value
	draw_stack_min_value = max(draw_stack_min_value, value)
	
	if is_wild:
		draw_stack_is_wild = true
		return
		
	if draw_stack_color == CardResource.CardColor.BLACK:
		draw_stack_color = card_manager.top_card.color



## Handles human draw button logic including draw stack interaction
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
			force_draw_stack_continue(holder)
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


## Allows a bot to draw one card on its turn
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
	
	if draw_stack_amount > 0:
		return false
	
	var card := card_manager.draw_card()
	if card == null:
		return false
	
	holder.add_card(card)
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	return true


## Ends the current turn normally
func end_turn() -> void:
	next_turn()


## Advances to the next turn, optionally skipping one player
func next_turn(skip_next: bool = false) -> void:
	if turn_order.size() == 0:
		return
	if turn_order.size() == 1:
		current_turn_index = 0
		update_turn_state()
		return
	
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


## Updates all holder turn states and emits the TURN_changed signal
func update_turn_state() -> void:
	for holder in turn_order:
		holder.set_turn_active(is_players_turn(holder))
	Signals.TURN_changed.emit(get_current_holder())


## Deals starting cards to all players and bots
func deal_starting_cards(cards_per_player: int = 7) -> void:
	for holder in turn_order:
		for i in range(cards_per_player):
			var card := card_manager.draw_card()
			if card == null:
				return
			holder.add_card(card)
		holder.refresh_playable_cards()


## Returns true if the current holder is the human player
func is_human_turn() -> bool:
	var holder := get_current_holder()
	return holder != null and !holder.is_bot


## Returns true if the holder has any playable card
func holder_has_playable_card(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView:
			if holder.can_play_card(c.card_res):
				return true
	return false


## Applies special stack effects at the beginning of a new turn
func _handle_start_of_turn_effects() -> void:
	var holder := get_current_holder()
	if holder == null:
		return
	
	if draw_stack_amount > 0 and draw_stack_is_wild:
		force_wild_draw_continue(holder)
		return
	
	if draw_stack_amount > 0 and !draw_stack_is_wild and !holder.is_bot:
		holder.refresh_playable_cards()
		return


## Forces wild draw stack resolution without skipping the player turn
func force_wild_draw_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)
	
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	holder.refresh_playable_cards()

## Forces normal draw stack resolution without skipping the player turn
func force_draw_stack_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)
	
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	
	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()


## Returns the current draw stack text for UI display
func get_draw_stack_text() -> String:
	if draw_stack_amount <= 0:
		return ""
	return "+" + str(draw_stack_amount)


## Returns the current turn direction
func get_direction() -> int:
	return direction


## Removes the current holder if finished and adds them to winners
func _check_and_finish_current_holder() -> bool:
	var holder := get_current_holder()
	if holder == null:
		return false
	if holder.get_child_count() > 0:
		return false
	
	winners.append(holder)
	
	var removed_index := current_turn_index
	turn_order.remove_at(removed_index)
	
	if turn_order.size() == 0:
		return true
	
	current_turn_index = clamp(removed_index, 0, turn_order.size() - 1)
	return true


## Clears the wild owner reference
func clear_wild_owner() -> void:
	wild_color_owner = null


## Sets the holder who is allowed to choose wild card color
func set_wild_color_owner(holder: HandCardHolder) -> void:
	wild_color_owner = holder

## Starts place-all mode if the owner has at least one additional card of that color, otherwise resolves immediately as a normal play
func start_place_all(holder: HandCardHolder, color: CardResource.CardColor, played_card: CardResource) -> void:
	if holder == null or played_card == null:
		return
	
	if !_holder_has_place_all_finisher(holder, color):
		register_card_play(played_card)
		return
	
	place_all_active = true
	place_all_owner = holder
	place_all_color = color
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()

## Returns true if the holder has a valid finisher card for the current place-all color
func _holder_has_place_all_finisher(holder: HandCardHolder, color: CardResource.CardColor) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView and c.card_res != null:
			if c.card_res.color == color:
				return true
	return false



## Resolves place-all by auto-playing all matching cards silently and applying only the finisher effect
func resolve_place_all(finisher_view: CardView) -> void:
	if !place_all_active:
		return
	if finisher_view == null or !is_instance_valid(finisher_view):
		return
	if place_all_owner == null:
		return
	if place_all_owner != get_current_holder():
		return
	if finisher_view.hand_card_holder != place_all_owner:
		return
	if finisher_view.card_res == null:
		return
	if finisher_view.card_res.color != place_all_color:
		return

	place_all_resolving = true

	var owner := place_all_owner
	var finisher_res := finisher_view.card_res

	var to_play: Array[CardView] = []
	for c in owner.get_children():
		if c is CardView and c != finisher_view:
			if c != null and is_instance_valid(c) and c.card_res != null:
				if c.card_res.color == place_all_color:
					to_play.append(c)

	var fly_duration := 0.28
	var hold_time := 0.08

	for cv in to_play:
		if cv == null or !is_instance_valid(cv):
			continue
		if cv.card_res == null:
			continue

		var res := cv.card_res

		cv.set_clickable(false, true)
		cv.smooth_move_button_to_top_card_juicy(fly_duration)

		await get_tree().create_timer(fly_duration).timeout

		if cv == null or !is_instance_valid(cv):
			continue

		if cv.get_parent() == owner:
			owner.remove_child(cv)

		cv.queue_free()

		card_manager.set_top_card_runtime(res)

		await get_tree().create_timer(hold_time).timeout

	if finisher_view == null or !is_instance_valid(finisher_view):
		place_all_active = false
		place_all_owner = null
		place_all_resolving = false
		return

	finisher_view.set_clickable(false, true)
	finisher_view.smooth_move_button_to_top_card_juicy(fly_duration)

	await get_tree().create_timer(fly_duration).timeout

	if finisher_view == null or !is_instance_valid(finisher_view):
		place_all_active = false
		place_all_owner = null
		place_all_resolving = false
		return

	if finisher_view.get_parent() == owner:
		owner.remove_child(finisher_view)

	finisher_view.queue_free()

	card_manager.set_top_card_runtime(finisher_res)

	await get_tree().process_frame

	place_all_active = false
	place_all_owner = null
	place_all_resolving = false

	register_card_play(finisher_res)


## Cancels place-all mode safely and ends the current turn
func _cancel_place_all() -> void:
	place_all_active = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED
	end_turn()
