extends Node
class_name QueueManager

@export var player_container: Control
@export var other_player_containers: Array[Control]
@export var card_manager: CardManager

@export var player_count := 1
@export var start_card_count := 7
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

var target_draw_active := false
var target_draw_value := 0
var target_draw_is_multi := false
var target_draw_color: CardResource.CardColor = CardResource.CardColor.BLACK
var pending_target_draw_owner: HandCardHolder = null

var place_all_active := false
var place_all_owner: HandCardHolder = null
var place_all_color: CardResource.CardColor = CardResource.CardColor.RED
var place_all_resolving := false
var place_all_card: CardResource = null
var _place_all_sequence_running := false

var roulette_active := false
var roulette_waiting_for_color := false
var roulette_owner: HandCardHolder = null
var roulette_target: HandCardHolder = null
var roulette_chosen_color: CardResource.CardColor = CardResource.CardColor.BLACK
var roulette_step_running := false


func _ready() -> void:
	connect_signals()
	create_players()
	create_bots()
	build_turn_order()
	call_deferred("start_game")


func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)
	Signals.TARGET_target_selected.connect(resolve_target_draw)
	Signals.COLOR_color_selected.connect(_on_roulette_color_selected)


func get_container_for_holder(holder: HandCardHolder) -> Control:
	if holder == null:
		return player_container
	if !holder.is_bot and holder.player_index == 0:
		return player_container
	var index := get_opponent_index(holder)
	if index >= 0 and index < other_player_containers.size():
		return other_player_containers[index]
	return player_container


func get_opponent_index(holder: HandCardHolder) -> int:
	if holder == null:
		return -1
	if !holder.is_bot:
		return holder.player_index - 1
	return max(0, player_count - 1) + holder.bot_index


func create_players() -> void:
	players.clear()
	for i in range(player_count):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = false
		holder.player_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager

		if holder.profile == null:
			holder.profile = PlayerProfile.new()

		holder.profile.player_index = i
		holder.profile.is_bot = false
		holder.profile.player_name = "Player " + str(i + 1)
		holder.profile.holder = holder
		holder.profile.ensure_picture()

		get_container_for_holder(holder).add_child(holder)
		players.append(holder)


func create_bots() -> void:
	bots.clear()
	for i in range(bot_profiles.size()):
		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = true
		holder.bot_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager

		if holder.profile == null:
			holder.profile = PlayerProfile.new()

		var bot_profile := _get_bot_profile(i)

		holder.profile.player_index = max(0, player_count - 1) + i
		holder.profile.is_bot = true
		holder.profile.player_name = bot_profile.name if bot_profile.name.strip_edges() != "" else "Bot " + str(i + 1)
		holder.profile.holder = holder
		holder.profile.ensure_picture()

		get_container_for_holder(holder).add_child(holder)
		bots.append(holder)

		var ki := KIController.new()
		ki.hand_card_holder = holder
		ki.queue_manager = self
		ki.card_manager = card_manager
		ki.difficulty = bot_profile.difficulty
		ki.personality = bot_profile.personality
		add_child(ki)


func _get_bot_profile(index: int) -> BotProfile:
	if index >= 0 and index < bot_profiles.size():
		if bot_profiles[index] != null:
			return bot_profiles[index]
	var fallback := BotProfile.new()
	fallback.name = "Bot " + str(index + 1)
	return fallback


func build_turn_order() -> void:
	turn_order.clear()
	turn_order.append_array(players)
	turn_order.append_array(bots)
	for h in turn_order:
		if h != null and h.profile != null:
			h.profile.holder = h


func start_game() -> void:
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false

	place_all_active = false
	place_all_resolving = false
	place_all_owner = null
	place_all_card = null
	_place_all_sequence_running = false

	if card_manager == null:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	deal_starting_cards(start_card_count)

	await get_tree().process_frame
	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")


func get_current_holder() -> HandCardHolder:
	if turn_order.is_empty():
		return null
	current_turn_index = clamp(current_turn_index, 0, turn_order.size() - 1)
	return turn_order[current_turn_index]


func is_players_turn(holder: HandCardHolder) -> bool:
	return holder == get_current_holder()


func is_human_turn() -> bool:
	var holder := get_current_holder()
	return holder != null and !holder.is_bot


func can_play_now(holder: HandCardHolder) -> bool:
	if place_all_resolving:
		return false
	if roulette_active:
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

		CardResource.CardType.WILD_DRAW_REVERSE:
			if turn_order.size() == 2:
				start_or_stack_draw(played_card.value, true)
				force_wild_draw_continue(get_current_holder())
				end_turn()
				return
			apply_reverse()
			start_or_stack_draw(played_card.value, true)
			end_turn()
			return

		CardResource.CardType.SWAP_HANDS:
			resolve_swap_hands(get_current_holder())
			end_turn()
			return

		CardResource.CardType.TARGET_DRAW:
			start_target_draw(get_current_holder(), played_card.value, false, played_card.color)
			return

		CardResource.CardType.MULTI_TARGET_DRAW:
			start_target_draw(get_current_holder(), played_card.value, true, played_card.color)
			return

		CardResource.CardType.WILD_COLOR_ROULET:
			start_color_roulette(get_current_holder())
			return

	end_turn()


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


func _restart_match() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()


func apply_reverse() -> void:
	direction *= -1


func start_or_stack_draw(value: int, is_wild: bool) -> void:
	draw_stack_amount += value
	draw_stack_min_value = max(draw_stack_min_value, value)
	if is_wild:
		draw_stack_is_wild = true
		return
	if draw_stack_color == CardResource.CardColor.BLACK:
		draw_stack_color = card_manager.top_card.color


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
	if roulette_active:
		return
	if place_all_resolving:
		return

	if draw_stack_amount > 0:
		if draw_stack_is_wild:
			force_wild_draw_continue(holder)
		else:
			force_draw_stack_continue(holder)
		return

	var card = card_manager.draw_card()
	if card == null:
		return

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	if !allow_play_after_draw:
		end_turn()
		return

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()


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
	if roulette_active:
		return false
	if place_all_resolving:
		return false
	if draw_stack_amount > 0:
		return false

	var card = card_manager.draw_card()
	if card == null:
		return false

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	return true


func end_turn() -> void:
	next_turn()


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


func update_turn_state() -> void:
	for holder in turn_order:
		var active := is_players_turn(holder)
		holder.set_turn_active(active)
		
		var ui_container := get_container_for_holder(holder)
		if ui_container != null:
			var target_color := Color.WHITE if active else Color(0.35, 0.35, 0.35, 1.0)
			_smooth_modulate(ui_container, target_color, 0.25)
		
	Signals.TURN_changed.emit(get_current_holder())


func deal_starting_cards(cards_per_player: int = 7) -> void:
	if card_manager == null:
		return
	for holder in turn_order:
		for i in range(cards_per_player):
			var card = card_manager.draw_card()
			if card == null:
				break
			holder.add_card(card)
		holder.sort_cards_full()
		holder.refresh_playable_cards()


func holder_has_playable_card(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView:
			if holder.can_play_card(c.card_res):
				return true
	return false


func _handle_start_of_turn_effects() -> void:
	if roulette_active:
		_handle_roulette_start()
		return

	var holder := get_current_holder()
	if holder == null:
		return

	if draw_stack_amount > 0 and draw_stack_is_wild:
		force_wild_draw_continue(holder)
		return

	if draw_stack_amount > 0 and !draw_stack_is_wild and !holder.is_bot:
		holder.refresh_playable_cards()
		return


func force_wild_draw_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card = card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)

	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	holder.sort_cards_full()
	holder.refresh_playable_cards()


func force_draw_stack_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card = card_manager.draw_card()
		if card == null:
			break
		holder.add_card(card)

	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK

	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()


func get_draw_stack_text() -> String:
	if draw_stack_amount <= 0:
		return ""
	return "+" + str(draw_stack_amount)


func get_direction() -> int:
	return direction


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

	if direction == 1:
		current_turn_index = removed_index % turn_order.size()
	else:
		current_turn_index = (removed_index - 1) % turn_order.size()
		if current_turn_index < 0:
			current_turn_index += turn_order.size()

	return true


func clear_wild_owner() -> void:
	wild_color_owner = null


func set_wild_color_owner(holder: HandCardHolder) -> void:
	wild_color_owner = holder


func start_place_all(holder: HandCardHolder, color: CardResource.CardColor, played_card: CardResource, place_all_view: CardView) -> void:
	if holder == null or played_card == null or place_all_view == null:
		return
	if _place_all_sequence_running:
		return

	_place_all_sequence_running = true

	place_all_active = true
	place_all_resolving = true
	place_all_owner = holder
	place_all_color = color
	place_all_card = played_card

	has_played_this_turn = true
	has_drawn_this_turn = false
	update_turn_state()

	place_all_view.set_clickable(false, true)

	await get_tree().process_frame
	await get_tree().process_frame

	await _place_all_play_color_cards_sequential(holder, place_all_view)
	await _place_all_play_final_place_all_card(holder, place_all_view, played_card)

	place_all_active = false
	place_all_resolving = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED
	place_all_card = null

	if holder != null and is_instance_valid(holder):
		holder._busy = false
		holder.sort_cards_full()
		holder.refresh_playable_cards()

	_place_all_sequence_running = false

	if _check_and_finish_current_holder():
		_after_holder_finished()
		return

	end_turn()


func _place_all_play_color_cards_sequential(owner: HandCardHolder, place_all_view: CardView) -> void:
	if owner == null:
		return

	var duration := 0.20
	var delay_between := 0.01

	var to_play: Array[CardView] = []
	for c in owner.get_children():
		if c is CardView and is_instance_valid(c) and c.card_res != null:
			if c == place_all_view:
				continue
			if c.card_res.color == place_all_color:
				to_play.append(c)

	if to_play.is_empty():
		return

	for cv in to_play:
		if cv == null or !is_instance_valid(cv):
			continue

		var res := cv.card_res

		cv.set_clickable(false, true)
		cv.smooth_move_button_to_top_card_juicy(duration)

		await get_tree().create_timer(duration).timeout

		if cv != null and is_instance_valid(cv):
			if cv.get_parent() == owner:
				owner.remove_child(cv)
			cv.queue_free()

		card_manager.set_top_card_runtime(res)

		await get_tree().create_timer(delay_between).timeout


func _place_all_play_final_place_all_card(owner: HandCardHolder, place_all_view: CardView, place_all_res: CardResource) -> void:
	if place_all_view == null or !is_instance_valid(place_all_view):
		return

	var duration := 0.26

	place_all_view.set_clickable(false, true)
	place_all_view.smooth_move_button_to_top_card_juicy(duration)

	await get_tree().create_timer(duration).timeout

	if place_all_view != null and is_instance_valid(place_all_view):
		if place_all_view.get_parent() == owner:
			owner.remove_child(place_all_view)
		place_all_view.queue_free()

	card_manager.set_top_card_runtime(place_all_res)


func _cancel_place_all() -> void:
	place_all_active = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED
	place_all_resolving = false
	place_all_card = null
	_place_all_sequence_running = false
	end_turn()


func get_next_holder(from_holder: HandCardHolder) -> HandCardHolder:
	if from_holder == null:
		return null
	if turn_order.size() <= 1:
		return null
	var idx := turn_order.find(from_holder)
	if idx < 0:
		return null
	var n := (idx + direction) % turn_order.size()
	if n < 0:
		n += turn_order.size()
	return turn_order[n]


func get_valid_target_holders(exclude: HandCardHolder) -> Array[HandCardHolder]:
	var res: Array[HandCardHolder] = []
	for h in turn_order:
		if h == null:
			continue
		if h == exclude:
			continue
		res.append(h)
	return res


func get_most_threatening_target(exclude: HandCardHolder) -> HandCardHolder:
	var best: HandCardHolder = null
	var best_count := 999999
	for h in get_valid_target_holders(exclude):
		var c := h.get_child_count()
		if c < best_count:
			best_count = c
			best = h
	return best


func start_target_draw(owner: HandCardHolder, value: int, multi: bool, color: CardResource.CardColor) -> void:
	target_draw_active = true
	target_draw_value = value
	target_draw_is_multi = multi
	target_draw_color = color
	pending_target_draw_owner = owner

	if owner == null:
		target_draw_active = false
		return

	if multi:
		resolve_target_draw(null)
		return

	if owner.is_bot:
		var target := get_most_threatening_target(owner)
		resolve_target_draw(target)
		return

	Signals.TARGET_request_target_select.emit(owner, false)


func resolve_target_draw(target_holder: HandCardHolder) -> void:
	if !target_draw_active:
		return

	var owner := pending_target_draw_owner

	if target_draw_is_multi:
		for h in get_valid_target_holders(owner):
			for i in range(target_draw_value):
				var card := card_manager.draw_card()
				if card == null:
					break
				h.add_card(card)
			h.sort_cards_full()
			h.refresh_playable_cards()
	else:
		if target_holder == null:
			target_holder = get_most_threatening_target(owner)
		if target_holder != null:
			for i in range(target_draw_value):
				var card := card_manager.draw_card()
				if card == null:
					break
				target_holder.add_card(card)
			target_holder.sort_cards_full()
			target_holder.refresh_playable_cards()

	target_draw_active = false
	target_draw_value = 0
	target_draw_is_multi = false
	target_draw_color = CardResource.CardColor.BLACK
	pending_target_draw_owner = null

	end_turn()


func resolve_swap_hands(owner: HandCardHolder) -> void:
	if owner == null:
		return
	if _check_and_finish_current_holder():
		_after_holder_finished()
		return
	if owner.get_child_count() == 0:
		return

	var next_holder := get_next_holder(owner)
	if next_holder == null:
		return

	var my_cards := owner.get_all_card_resources()
	var opp_cards := next_holder.get_all_card_resources()

	for c in owner.get_children():
		if c is CardView:
			owner.remove_child(c)
			c.queue_free()

	for c in next_holder.get_children():
		if c is CardView:
			next_holder.remove_child(c)
			c.queue_free()

	for r in opp_cards:
		owner.add_card(r)

	for r in my_cards:
		next_holder.add_card(r)

	owner.sort_cards_full()
	next_holder.sort_cards_full()
	owner.refresh_playable_cards()
	next_holder.refresh_playable_cards()


func start_color_roulette(owner: HandCardHolder) -> void:
	if owner == null:
		return

	var target := get_next_holder(owner)
	if target == null:
		return

	roulette_active = true
	roulette_waiting_for_color = true
	roulette_owner = owner
	roulette_target = target
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false

	has_played_this_turn = true
	has_drawn_this_turn = false

	next_turn(false)
	await get_tree().process_frame

	if roulette_target == null:
		_end_roulette(false)
		return

	if roulette_target.is_bot:
		var chosen := choose_color_for_roulette(roulette_target)
		_on_roulette_color_selected(chosen)
	else:
		if card_manager != null:
			card_manager.waiting_for_color = true
		set_wild_color_owner(roulette_target)
		Signals.COLOR_request_color_select.emit()


func _on_roulette_color_selected(color: CardResource.CardColor) -> void:
	if !roulette_active:
		return
	if roulette_target == null:
		_end_roulette(false)
		return
	if get_current_holder() != roulette_target:
		return

	roulette_waiting_for_color = false
	roulette_chosen_color = color

	_apply_roulette_color_to_top_card(color)

	clear_wild_owner()
	_handle_roulette_start()


func _handle_roulette_start() -> void:
	if !roulette_active:
		return
	if roulette_target == null:
		_end_roulette(false)
		return

	var holder := get_current_holder()
	if holder != roulette_target:
		_end_roulette(false)
		return

	if roulette_waiting_for_color:
		return
	if roulette_step_running:
		return

	roulette_step_running = true
	call_deferred("_do_roulette_draw_step", holder)


func _do_roulette_draw_step(holder: HandCardHolder) -> void:
	if holder == null:
		_end_roulette(false)
		return

	var card := card_manager.draw_card()
	if card == null:
		_end_roulette(false)
		return

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()

	await get_tree().create_timer(0.22).timeout

	if card.color == roulette_chosen_color:
		_end_roulette(true)
		holder.refresh_playable_cards()
		return

	roulette_step_running = false
	_handle_roulette_start()


func _end_roulette(success: bool) -> void:
	roulette_active = false
	roulette_waiting_for_color = false
	roulette_owner = null
	roulette_target = null
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false

	if card_manager != null:
		card_manager.waiting_for_color = false

	if success:
		has_drawn_this_turn = true
		has_played_this_turn = false

		var holder := get_current_holder()
		if holder != null:
			holder.refresh_playable_cards()

		await get_tree().process_frame

		var holder2 := get_current_holder()
		if holder2 != null and holder2.is_bot:
			for child in get_children():
				if child is KIController and child.hand_card_holder == holder2:
					child.call_deferred("play_turn")
					return
		return

	end_turn()


func choose_color_for_roulette(target: HandCardHolder) -> CardResource.CardColor:
	if target == null:
		return CardResource.CardColor.RED

	if target.is_bot:
		var counts := {
			CardResource.CardColor.RED: 0,
			CardResource.CardColor.GREEN: 0,
			CardResource.CardColor.BLUE: 0,
			CardResource.CardColor.YELLOW: 0
		}

		for c in target.get_children():
			if c is CardView and c.card_res != null:
				if c.card_res.color != CardResource.CardColor.BLACK:
					counts[c.card_res.color] += 1

		var best := CardResource.CardColor.RED
		var best_count := 999999
		for col in counts.keys():
			if counts[col] < best_count:
				best_count = counts[col]
				best = col
		return best

	return CardResource.CardColor.RED


func _apply_roulette_color_to_top_card(color: CardResource.CardColor) -> void:
	if card_manager == null:
		return

	card_manager.current_color = color
	card_manager.waiting_for_color = false

	if card_manager.top_card != null:
		card_manager.top_card.color = color

	if card_manager.top_card_view != null and is_instance_valid(card_manager.top_card_view):
		card_manager.top_card_view.load_card()

func _smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.2) -> void:
	if node == null:
		return

	if node.has_meta("modulate_tween"):
		var old_tween = node.get_meta("modulate_tween")
		if old_tween and old_tween.is_running():
			old_tween.kill()

	var tween := create_tween()
	tween.tween_property(node, "modulate", target, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	node.set_meta("modulate_tween", tween)
