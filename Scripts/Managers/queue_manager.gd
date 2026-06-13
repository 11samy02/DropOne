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
var pending_swap_owner: HandCardHolder = null
var swap_color_pending := false

var _slot_to_holder: Dictionary = {}
var _peer_to_slot: Dictionary = {}
var _players_meta: Array = []
var _last_hand_counts: Array = []
var _last_deck_count: int = 0

var _pending_hand: Array = []
var _pending_state: Dictionary = {}
var _last_applied_hand: Array = []

var _server_match_started := false
var _server_match_starting := false
var _client_has_hand := false
var _client_has_state := false
var _client_match_started := false
var _game_over_handled := false
var _winner_overlay: CanvasLayer = null
var _server_last_players_change_ms := 0
var _server_start_delay_active := false
const SERVER_START_DELAY_MS := 300

## Init networking + buffered snapshots
func _ready() -> void:
	connect_signals()

	NetworkManager.players_received.connect(_on_players_received)
	NetworkManager.hand_received.connect(_on_hand_received)
	NetworkManager.match_state_received.connect(_on_match_state_received)
	NetworkManager.counts_received.connect(_on_counts_received)
	NetworkManager.play_event_received.connect(_on_play_event_received)
	NetworkManager.game_won.connect(_on_game_won)
	NetworkManager.return_to_lobby.connect(_on_return_to_lobby)

	var buffered_players := NetworkManager.get_last_players()
	if buffered_players.size() > 0:
		_on_players_received(buffered_players)
		NetworkManager.clear_last_players()

	var buffered_hand := NetworkManager.get_last_hand()
	if buffered_hand.size() > 0:
		_on_hand_received(buffered_hand)

	var buffered_state := NetworkManager.get_last_match_state()
	if buffered_state.size() > 0:
		_on_match_state_received(buffered_state)

	# Server will start match when players are received via _on_players_received()
	if multiplayer.is_server():
		call_deferred("_server_request_player_rebroadcast")

## Connect gameplay signals
func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)
	Signals.TARGET_target_selected.connect(resolve_target_draw)
	Signals.COLOR_color_selected.connect(_on_roulette_color_selected)

## UI container resolver
func get_container_for_holder(holder: HandCardHolder) -> Control:
	if holder == null:
		return player_container

	var my_slot := int(NetworkManager.my_slot)

	if my_slot >= 0 and !holder.is_bot and holder.player_index == my_slot:
		return player_container

	var index := get_opponent_index(holder)
	if index >= 0 and index < other_player_containers.size():
		return other_player_containers[index]

	return player_container

## Compute opponent seat index for UI.
## Seats are assigned RELATIVE to the local player so turn order always runs
## around the table in a circle: the next player after the local one takes the
## first opponent seat, the one after that the second, etc.
func get_opponent_index(holder: HandCardHolder) -> int:
	if holder == null:
		return -1

	# player_count is the full participant count (set before holders are built),
	# so it is reliable even while turn_order is still being populated.
	var total: int = max(player_count, turn_order.size())
	if total <= 0:
		total = 1

	var my_slot := int(NetworkManager.my_slot)
	# Offline / kein gültiger Slot: lokalen Spieler als Slot 0 annehmen.
	if my_slot < 0:
		my_slot = 0

	if !holder.is_bot and holder.player_index == my_slot:
		return -1

	var rel: int = ((holder.player_index - my_slot) % total + total) % total
	return rel - 1

## Offline players
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

## Offline bots
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

		var bot_profile: BotProfile = _get_bot_profile(i)

		holder.profile.player_index = max(0, player_count - 1) + i
		holder.profile.is_bot = true
		holder.profile.player_name = bot_profile.name if bot_profile.name.strip_edges() != "" else "Bot " + str(i + 1)
		holder.profile.holder = holder
		holder.profile.ensure_picture()

		get_container_for_holder(holder).add_child(holder)
		bots.append(holder)

		var ki: KIController = KIController.new()
		ki.hand_card_holder = holder
		ki.queue_manager = self
		ki.card_manager = card_manager
		ki.difficulty = bot_profile.difficulty
		ki.personality = bot_profile.personality
		add_child(ki)

## Bot profile fallback
func _get_bot_profile(index: int) -> BotProfile:
	if index >= 0 and index < bot_profiles.size():
		if bot_profiles[index] != null:
			return bot_profiles[index]
	var fallback := BotProfile.new()
	fallback.name = "Bot " + str(index + 1)
	return fallback

## Build local turn order
func build_turn_order() -> void:
	turn_order.clear()
	turn_order.append_array(players)
	turn_order.append_array(bots)
	for h in turn_order:
		if h != null and h.profile != null:
			h.profile.holder = h

## Offline/server-only start
func start_game() -> void:
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		return

	randomize()
	current_turn_index = randi() % turn_order.size()
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

## Current holder getter
func get_current_holder() -> HandCardHolder:
	if turn_order.is_empty():
		return null
	current_turn_index = clamp(current_turn_index, 0, turn_order.size() - 1)
	return turn_order[current_turn_index]

## Turn check
func is_players_turn(holder: HandCardHolder) -> bool:
	return holder == get_current_holder()

## Human turn check
func is_human_turn() -> bool:
	var holder := get_current_holder()
	return holder != null and !holder.is_bot

## Local player turn check (multiplayer)
func is_local_turn() -> bool:
	var my_slot := int(NetworkManager.my_slot)
	if my_slot < 0:
		return false
	var my_holder: HandCardHolder = _slot_to_holder.get(my_slot, null)
	return my_holder != null and is_players_turn(my_holder)

## Play permission check
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

## Register played card and advance rules
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
			_apply_wild_draw_effect(played_card.value, false)
			return
		CardResource.CardType.WILD_DRAW_REVERSE:
			_apply_wild_draw_effect(played_card.value, true)
			return
		CardResource.CardType.SWAP_HANDS:
			if swap_color_pending:
				swap_color_pending = false
				clear_wild_owner()
				end_turn()
			else:
				start_swap_hands(get_current_holder())
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

## After someone finishes hand
func _after_holder_finished() -> void:
	has_played_this_turn = false
	has_drawn_this_turn = false
	if winners.size() > 0:
		if multiplayer.is_server():
			_server_handle_game_over()
		return
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")

## Restart match
func _restart_match() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()

## Server: Spielende behandeln – Gewinner ansagen, dann zurück in die Lobby
func _server_handle_game_over() -> void:
	if not multiplayer.is_server():
		return
	if _game_over_handled:
		return
	_game_over_handled = true

	var winner_name := "Player"
	var winner_slot := -1
	if winners.size() > 0 and winners[0] != null and is_instance_valid(winners[0]):
		winner_slot = int(winners[0].player_index)
		if winners[0].profile != null:
			winner_name = str(winners[0].profile.player_name)

	NetworkManager.server_announce_winner(winner_name, winner_slot)

	# Gewinner kurz anzeigen, dann alle zurück in die Lobby holen.
	await get_tree().create_timer(4.5).timeout
	NetworkManager.server_return_to_lobby()

## Gewinner-Overlay anzeigen + Spiel pausieren (Client + Server)
func _on_game_won(winner_name: String, winner_slot: int = -1) -> void:
	# Let the winning card's fly/placement animation finish first. Pausing the
	# tree immediately froze the in-flight tween and the 0.3s await that removes
	# the card, so the winner's last card visually stayed in hand and it looked
	# like they still had a card left.
	await get_tree().create_timer(0.45).timeout
	# Guarantee the winner shows an empty hand on EVERY peer, regardless of how
	# the last card's animation/counts resolved locally.
	_force_clear_winner_hand(winner_slot)
	_show_winner_overlay(winner_name)
	get_tree().paused = true

## Remove every card view from the winner's seat so they visibly have no cards.
func _force_clear_winner_hand(winner_slot: int) -> void:
	if winner_slot < 0:
		return
	var holder: HandCardHolder = _slot_to_holder.get(int(winner_slot), null)
	if holder == null or !is_instance_valid(holder):
		return
	for c in holder.get_children():
		if c is CardView:
			holder.remove_child(c)
			c.queue_free()

## Zurück in die Lobby (Verbindung bleibt bestehen)
func _on_return_to_lobby() -> void:
	get_tree().paused = false
	_hide_winner_overlay()
	Globals.change_scene_file("res://Scenes/UI/steam_lobby_room.tscn")

func _show_winner_overlay(winner_name: String) -> void:
	_hide_winner_overlay()

	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)

	var crown := Label.new()
	crown.text = "🏆 WINNER 🏆"
	crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crown.add_theme_font_size_override("font_size", 48)
	crown.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(crown)

	var name_label := Label.new()
	name_label.text = winner_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 80)
	vbox.add_child(name_label)

	var hint := Label.new()
	hint.text = "Returning to lobby..."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 28)
	hint.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(hint)

	get_tree().root.add_child(layer)
	_winner_overlay = layer

func _hide_winner_overlay() -> void:
	if _winner_overlay != null and is_instance_valid(_winner_overlay):
		_winner_overlay.queue_free()
	_winner_overlay = null

## Reverse direction
func apply_reverse() -> void:
	direction *= -1
	# Synchronize direction change
	if multiplayer.is_server():
		_server_sync_match_state()

## Draw stack add/stack
func start_or_stack_draw(value: int, is_wild: bool) -> void:
	draw_stack_amount += value
	draw_stack_min_value = max(draw_stack_min_value, value)
	if is_wild:
		draw_stack_is_wild = true
	if !is_wild and draw_stack_color == CardResource.CardColor.BLACK and card_manager != null and card_manager.top_card != null:
		draw_stack_color = card_manager.top_card.color
	
	# Synchronize draw stack changes
	if multiplayer.is_server():
		_server_sync_match_state()

## Wild draw (non-stack) apply
func _apply_wild_draw_effect(value: int, reverse: bool) -> void:
	var owner := get_current_holder()
	if owner == null:
		end_turn()
		return
	if reverse and turn_order.size() > 2:
		apply_reverse()
	var target: HandCardHolder = null
	if reverse and turn_order.size() == 2:
		target = owner
	else:
		target = get_next_holder(owner)
	if target == null:
		end_turn()
		return

	for i in range(value):
		var card := card_manager.draw_card()
		if card == null:
			break
		target.add_card(card)

	target.sort_cards_full()
	target.refresh_playable_cards()

	# Send updated hand to the drawn player in multiplayer
	if multiplayer.is_server() and target != null and !target.is_bot:
		var peer_id := _slot_to_peer_id(target.player_index)
		if peer_id != 0:
			var hand: Array = []
			for ch in target.get_children():
				if ch is CardView and ch.card_res != null:
					hand.append(_serialize_card(ch.card_res))
			NetworkManager.rpc_id(peer_id, "client_set_hand", hand)

	# Target keeps the turn after drawing
	if target != owner:
		current_turn_index = turn_order.find(target)
	has_played_this_turn = false
	has_drawn_this_turn = false
	update_turn_state()

	if multiplayer.is_server():
		_server_broadcast_counts()
		_server_sync_match_state()

	call_deferred("_handle_start_of_turn_effects")

## Human draw action
func on_draw_pressed() -> void:
	var holder := get_current_holder()
	if holder == null:
		return
	if holder.is_bot:
		return
	if multiplayer.has_multiplayer_peer():
		var my_slot := int(NetworkManager.my_slot)
		if my_slot < 0 or holder.player_index != my_slot:
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

	# Multiplayer clients must request draw from server (including draw stack)
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_draw()
		return

	if draw_stack_amount > 0:
		if draw_stack_is_wild:
			await force_wild_draw_continue(holder)
		else:
			await force_draw_stack_continue(holder)
		if multiplayer.is_server():
			_server_broadcast_counts()
			_server_sync_match_state()
		return

	# Server-side or offline draw
	var card := card_manager.draw_card()
	if card == null:
		return

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	
	# Synchronize draw action
	if multiplayer.is_server():
		_server_broadcast_counts()

	if !allow_play_after_draw:
		end_turn()
		return

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()

## Bot draw action
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

	var card := card_manager.draw_card()
	if card == null:
		return false

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	return true

## End turn
func end_turn() -> void:
	next_turn()

## Next turn logic
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
	
	# Synchronize turn change to all clients
	if multiplayer.is_server():
		_server_sync_match_state()
	
	call_deferred("_handle_start_of_turn_effects")

## Turn UI update
func update_turn_state() -> void:
	for holder in turn_order:
		var active := is_players_turn(holder)
		holder.set_turn_active(active)

		var ui_container := get_container_for_holder(holder)
		if ui_container != null:
			var target_color := Color.WHITE if active else Color(0.35, 0.35, 0.35, 1.0)
			_smooth_modulate(ui_container, target_color, 0.25)

	Signals.TURN_changed.emit(get_current_holder())

## Offline deal
func deal_starting_cards(cards_per_player: int = 7) -> void:
	if card_manager == null:
		return
	for holder in turn_order:
		for i in range(cards_per_player):
			var card := card_manager.draw_card()
			if card == null:
				break
			holder.add_card(card)
		holder.sort_cards_full()
		holder.refresh_playable_cards()

## Playable check
func holder_has_playable_card(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView and holder.can_play_card(c.card_res):
			return true
	return false

## Start-of-turn effects
func _handle_start_of_turn_effects() -> void:
	if place_all_resolving:
		return
	if _place_all_sequence_running:
		return

	if roulette_active:
		_handle_roulette_start()
		return

	var holder := get_current_holder()
	if holder == null:
		return

	if draw_stack_amount > 0 and draw_stack_is_wild:
		if !holder.is_bot:
			holder.refresh_playable_cards()
			return
		if holder_has_playable_card(holder):
			return
		force_wild_draw_continue(holder)
		return

	if draw_stack_amount > 0 and !draw_stack_is_wild:
		if !holder.is_bot:
			holder.refresh_playable_cards()
			return
		if holder_has_playable_card(holder):
			return
		force_draw_stack_continue(holder)
		return

## Force wild draw resolve
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

	# Synchronize draw stack reset
	if multiplayer.is_server():
		_server_sync_match_state()

	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()

## Force draw stack resolve
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

	# Synchronize draw stack reset
	if multiplayer.is_server():
		_server_sync_match_state()

	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	await get_tree().create_timer(0.25).timeout
	if !holder_has_playable_card(holder):
		end_turn()

## Draw stack UI text
func get_draw_stack_text() -> String:
	if draw_stack_amount <= 0:
		return ""
	return "+" + str(draw_stack_amount)

## Direction getter
func get_direction() -> int:
	return direction

## Remove empty-hand winner
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

## Wild owner helpers
func clear_wild_owner() -> void:
	wild_color_owner = null

func set_wild_color_owner(holder: HandCardHolder) -> void:
	wild_color_owner = holder

## Place-all sequence start
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

	# The whole place-all sequence runs on the server. Push the owner's new hand
	# (all color cards + the place-all card are gone) and resync top card/counts
	# so a client owner doesn't keep the already-played cards (soft-lock).
	if multiplayer.is_server():
		_server_push_hand(holder)
		_server_broadcast_counts()
		_server_sync_match_state()

	if _check_and_finish_current_holder():
		_after_holder_finished()
		return

	end_turn()

## Place-all play color cards
func _place_all_play_color_cards_sequential(owner: HandCardHolder, place_all_view: CardView) -> void:
	if owner == null:
		return

	var duration := 0.20
	var delay_between := 0.01

	while true:
		var next_card: CardView = null
		for c in owner.get_children():
			if c is CardView and is_instance_valid(c) and c.card_res != null:
				if c == place_all_view:
					continue
				if c.card_res.color == place_all_color:
					next_card = c
					break

		if next_card == null:
			break

		var res := next_card.card_res

		next_card.set_clickable(false, true)
		next_card.smooth_move_button_to_top_card_juicy(duration)

		await get_tree().create_timer(duration).timeout

		if next_card != null and is_instance_valid(next_card):
			if next_card.get_parent() == owner:
				owner.remove_child(next_card)
			next_card.queue_free()

		card_manager.set_top_card_no_effect(res)

		await get_tree().create_timer(delay_between).timeout

## Place-all final card
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

	card_manager.set_top_card_no_effect(place_all_res)

## Cancel place-all
func _cancel_place_all() -> void:
	place_all_active = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED
	place_all_resolving = false
	place_all_card = null
	_place_all_sequence_running = false
	end_turn()

## Next holder
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

## Valid targets
func get_valid_target_holders(exclude: HandCardHolder) -> Array[HandCardHolder]:
	var res: Array[HandCardHolder] = []
	for h in turn_order:
		if h == null:
			continue
		if h == exclude:
			continue
		res.append(h)
	return res

## Threat target by smallest hand
func get_most_threatening_target(exclude: HandCardHolder) -> HandCardHolder:
	var best: HandCardHolder = null
	var best_count := 999999
	for h in get_valid_target_holders(exclude):
		var c := h.get_child_count()
		if c < best_count:
			best_count = c
			best = h
	return best

## Target draw start
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
	
	if multiplayer.is_server():
		var peer_id := _slot_to_peer_id(owner.player_index)
		if peer_id != 0:
			NetworkManager.rpc_id(peer_id, "client_request_target_select", int(owner.player_index), false)
			return
	Signals.TARGET_request_target_select.emit(owner, false)

## Swap hands start
func start_swap_hands(owner: HandCardHolder) -> void:
	if owner == null:
		return
	if pending_swap_owner != null:
		return
	pending_swap_owner = owner
	if owner.is_bot:
		var target := get_most_threatening_target(owner)
		_resolve_swap_with_target(owner, target)
		return
	if multiplayer.is_server():
		var peer_id := _slot_to_peer_id(owner.player_index)
		if peer_id != 0:
			NetworkManager.rpc_id(peer_id, "client_request_target_select", int(owner.player_index), false)
			return
	Signals.TARGET_request_target_select.emit(owner, false)

## Target draw resolve
func resolve_target_draw(target_holder: HandCardHolder) -> void:
	if !target_draw_active:
		if pending_swap_owner != null:
			var owner := pending_swap_owner
			pending_swap_owner = null
			_resolve_swap_with_target(owner, target_holder)
		return

	var owner := pending_target_draw_owner

	if target_draw_is_multi:
		# Multi target draw: every player except the one who played it draws.
		for h in get_valid_target_holders(owner):
			for i in range(target_draw_value):
				var card := card_manager.draw_card()
				if card == null:
					break
				h.add_card(card)
			h.sort_cards_full()
			h.refresh_playable_cards()
			_server_push_hand(h)
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
			_server_push_hand(target_holder)

	target_draw_active = false
	target_draw_value = 0
	target_draw_is_multi = false
	target_draw_color = CardResource.CardColor.BLACK
	pending_target_draw_owner = null

	if multiplayer.is_server():
		_server_broadcast_counts()

	end_turn()

## Swap hands resolve
func resolve_swap_hands(owner: HandCardHolder) -> void:
	if owner == null:
		return
	var target := get_next_holder(owner)
	_resolve_swap_with_target(owner, target)

## Execute swap between two holders, then request color selection
func _resolve_swap_with_target(owner: HandCardHolder, target: HandCardHolder) -> void:
	if _check_and_finish_current_holder():
		_after_holder_finished()
		return
	if owner.get_child_count() == 0:
		return
	if target == null:
		return

	var my_cards := owner.get_all_card_resources()
	var opp_cards := target.get_all_card_resources()

	for c in owner.get_children():
		if c is CardView:
			owner.remove_child(c)
			c.queue_free()

	for c in target.get_children():
		if c is CardView:
			target.remove_child(c)
			c.queue_free()

	for r in opp_cards:
		owner.add_card(r)

	for r in my_cards:
		target.add_card(r)

	owner.sort_cards_full()
	target.sort_cards_full()
	owner.refresh_playable_cards()
	target.refresh_playable_cards()

	# Push both swapped hands to their owning clients, otherwise the swap is only
	# applied on the server and the affected clients keep their old cards.
	_server_push_hand(owner)
	_server_push_hand(target)

	if card_manager != null:
		card_manager.current_color = CardResource.CardColor.BLACK
		card_manager.waiting_for_color = true
	swap_color_pending = true
	set_wild_color_owner(owner)
	Signals.COLOR_request_color_select.emit()
	if multiplayer.is_server():
		var peer_id := _slot_to_peer_id(owner.player_index)
		if peer_id != 0:
			NetworkManager.rpc_id(peer_id, "client_request_color", int(owner.player_index))
	if multiplayer.is_server():
		_server_broadcast_counts()
		_server_sync_match_state()

## Color roulette start
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
		if multiplayer.is_server():
			var peer_id := _slot_to_peer_id(roulette_target.player_index)
			if peer_id != 0:
				NetworkManager.rpc_id(peer_id, "client_request_color", int(roulette_target.player_index))

## Roulette color selected
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

## Roulette step loop
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

## Roulette draw step
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

	# Keep the drawing client and everyone's counts in sync each draw step.
	if multiplayer.is_server():
		_server_push_hand(holder)
		_server_broadcast_counts()

	await get_tree().create_timer(0.22).timeout

	if card.color == roulette_chosen_color:
		_end_roulette(true)
		holder.refresh_playable_cards()
		return

	roulette_step_running = false
	_handle_roulette_start()

## Roulette end
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

## Roulette color choice for bots
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
			if c is CardView and c.card_res != null and c.card_res.color != CardResource.CardColor.BLACK:
				counts[c.card_res.color] += 1

		var best := CardResource.CardColor.RED
		var best_count := 999999
		for col in counts.keys():
			if int(counts[col]) < best_count:
				best_count = int(counts[col])
				best = col
		return best

	return CardResource.CardColor.RED

## Apply roulette color to top card
func _apply_roulette_color_to_top_card(color: CardResource.CardColor) -> void:
	if card_manager == null:
		return

	card_manager.current_color = color
	card_manager.waiting_for_color = false

	if card_manager.top_card != null:
		card_manager.top_card.color = color

	if card_manager.top_card_view != null and is_instance_valid(card_manager.top_card_view):
		card_manager.top_card_view.load_card()

## UI modulate tween helper
func _smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.2) -> void:
	if node == null:
		return

	if node.has_meta("modulate_tween"):
		var old_tween: Tween = node.get_meta("modulate_tween") as Tween
		if old_tween != null and old_tween.is_running():
			old_tween.kill()

	var tween: Tween = create_tween()
	tween.tween_property(node, "modulate", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	node.set_meta("modulate_tween", tween)

## Buffer incoming hand
func _on_hand_received(hand: Array) -> void:
	_pending_hand = hand
	if !multiplayer.is_server():
		_client_has_hand = false
	_try_apply_pending_hand()

## Apply buffered hand when ready
func _try_apply_pending_hand() -> void:
	if _pending_hand.size() == 0:
		return

	var slot := int(NetworkManager.my_slot)
	if slot < 0:
		var pid := int(multiplayer.get_unique_id())
		if pid > 0 and _peer_to_slot.has(pid):
			slot = int(_peer_to_slot[pid])
			NetworkManager.my_slot = slot
		else:
			return

	var my_holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if my_holder == null:
		return
	if player_container != null and my_holder.get_parent() != player_container:
		if my_holder.get_parent() != null:
			my_holder.get_parent().remove_child(my_holder)
		player_container.add_child(my_holder)
	my_holder.compact_view = false
	_refresh_holder_layouts()
	if my_holder.get_child_count() == 0:
		for entry: Dictionary in _pending_hand:
			var r := CardResource.new()
			r.color = int(entry.get("c", 0))
			r.type = int(entry.get("t", 0))
			r.value = int(entry.get("v", 0))
			r.uid = int(entry.get("id", 0))
			my_holder.add_card(r, false)
		my_holder.sort_cards_full()
		my_holder.refresh_playable_cards()
	else:
		_reconcile_hand(my_holder, _pending_hand)

	_last_applied_hand = _pending_hand.duplicate(true)
	_pending_hand = []
	NetworkManager.clear_last_hand()
	_client_has_hand = true
	if multiplayer.is_server():
		_apply_counts_to_ui()
		_apply_local_visibility()
	else:
		_apply_local_visibility()
		_try_finalize_client_sync()

## Show only local hand front
func _apply_local_visibility() -> void:
	var my_slot := int(NetworkManager.my_slot)

	for h in turn_order:
		if h == null:
			continue

		var is_me := (h.player_index == my_slot)

		for cv in h.get_children():
			if cv is CardView and not cv.get_meta("anim_temp", false):
				cv.show_front = is_me
				cv.load_card()

		h.refresh_playable_cards()

func _try_finalize_client_sync() -> void:
	if multiplayer.is_server():
		return
	if !_client_has_hand or !_client_has_state:
		return
	_apply_counts_to_ui()
	_apply_local_visibility()

func _server_request_player_rebroadcast() -> void:
	if !multiplayer.is_server():
		return
	if NetworkManager != null and NetworkManager.has_method("server_rebroadcast_players"):
		NetworkManager.server_rebroadcast_players()

## Server lobby bootstrap - removed, now handled via players_received signal

## Players list received
func _on_players_received(players_in: Array) -> void:
	print("QueueManager: Received %d players" % players_in.size())
	_players_meta = players_in.duplicate(true)
	if !multiplayer.is_server():
		_resolve_client_slot(_players_meta)
	if !multiplayer.is_server() and _client_match_started:
		var slot := int(NetworkManager.my_slot)
		if slot >= 0 and _slot_to_holder.has(slot) and turn_order.size() == _players_meta.size():
			return
	if multiplayer.is_server():
		_server_last_players_change_ms = Time.get_ticks_msec()
		if _server_match_started:
			if _should_reset_server_match(players_in):
				_reset_server_match_state()
			else:
				_update_peer_slots_from_players(_players_meta)
				return

	_build_holders_from_players(_players_meta)
	_ensure_holder_containers()
	_refresh_holder_layouts()

	if !multiplayer.is_server() and _client_match_started and _pending_hand.is_empty():
		if _last_applied_hand.size() > 0:
			_pending_hand = _last_applied_hand.duplicate(true)

	_try_apply_pending_match_state()
	_try_apply_pending_hand()
	if multiplayer.is_server():
		_apply_counts_to_ui()
		_apply_local_visibility()
	else:
		_try_finalize_client_sync()

	if multiplayer.is_server():
		print("QueueManager: Server mode - syncing late joiners and trying to start match")
		_server_sync_late_joiners(players_in)
		# Wait a frame to ensure all holders are built, then try to start match
		await get_tree().process_frame
		_server_try_start_match()
	else:
		print("QueueManager: Client mode - waiting for server to start match")

## Build holders + slot map
## Build holders + slot map
func _build_holders_from_players(players_meta: Array) -> void:
	for h in turn_order:
		if h != null and is_instance_valid(h):
			h.queue_free()

	# Alte Bot-KI-Controller entfernen, damit keine Duplikate entstehen.
	for child in get_children():
		if child is KIController:
			child.queue_free()

	players.clear()
	bots.clear()
	turn_order.clear()
	_slot_to_holder.clear()
	_peer_to_slot.clear()

	player_count = max(1, players_meta.size())

	var my_slot := int(NetworkManager.my_slot)
	var bot_counter := 0

	for i in range(players_meta.size()):
		var row: Variant = players_meta[i]

		var is_bot_row := false
		if row is Dictionary:
			is_bot_row = bool(row.get("is_bot", false))

		var holder: HandCardHolder = HandCardHolder.create()
		holder.is_bot = is_bot_row
		holder.compact_view = is_bot_row or (my_slot < 0) or (i != my_slot)
		holder.player_index = i
		holder.queue_manager = self
		holder.card_manager = card_manager
		if is_bot_row:
			holder.bot_index = bot_counter

		if holder.profile == null:
			holder.profile = PlayerProfile.new()

		var nm := "Player " + str(i + 1)
		var pic_id := 0
		if row is Dictionary:
			nm = str(row.get("name", nm))
			pic_id = int(row.get("picture_id", 0))

		holder.profile.player_index = i
		holder.profile.is_bot = is_bot_row
		holder.profile.player_name = nm
		holder.profile.holder = holder
		holder.profile.ensure_picture()

		## Apply profile picture id only if PlayerProfile supports it
		if holder.profile != null and holder.profile.get_property_list() != null:
			var has_pic := false
			for p in holder.profile.get_property_list():
				if p is Dictionary and str(p.get("name", "")) == "picture_id":
					has_pic = true
					break
			if has_pic:
				holder.profile.set("picture_id", pic_id)

		var container := get_container_for_holder(holder)
		if container != null:
			container.add_child(holder)
		else:
			add_child(holder)

		if is_bot_row:
			bots.append(holder)
			bot_counter += 1
			# KI nur auf dem Server (autoritativ).
			if multiplayer.is_server() and row is Dictionary:
				var ki: KIController = KIController.new()
				ki.hand_card_holder = holder
				ki.queue_manager = self
				ki.card_manager = card_manager
				ki.difficulty = int(row.get("difficulty", KIController.AIDifficulty.SMART))
				ki.personality = int(row.get("personality", KIController.AIPersonality.BALANCED))
				add_child(ki)
		else:
			players.append(holder)

		turn_order.append(holder)
		_slot_to_holder[i] = holder

		if row is Dictionary:
			var peer_id := int(row.get("peer_id", 0))
			if peer_id != 0:
				_peer_to_slot[peer_id] = i

func _update_peer_slots_from_players(players_meta: Array) -> void:
	_peer_to_slot.clear()
	for i in range(players_meta.size()):
		var row: Variant = players_meta[i]
		if row is Dictionary:
			var peer_id := int(row.get("peer_id", 0))
			if peer_id != 0:
				_peer_to_slot[peer_id] = i

func _resolve_client_slot(players_meta: Array) -> void:
	if multiplayer.is_server():
		return
	var cached_slot := int(NetworkManager.get_last_slot())
	if cached_slot >= 0:
		NetworkManager.my_slot = cached_slot
		_refresh_holder_layouts()
		return
	var my_id := int(multiplayer.get_unique_id())
	if my_id <= 0:
		return
	for i in range(players_meta.size()):
		var row: Variant = players_meta[i]
		if row is Dictionary and int(row.get("peer_id", 0)) == my_id:
			NetworkManager.my_slot = i
			_refresh_holder_layouts()
			return
	_peer_to_slot.clear()
	for i in range(players_meta.size()):
		var row: Variant = players_meta[i]
		if row is Dictionary:
			var peer_id := int(row.get("peer_id", 0))
			if peer_id != 0:
				_peer_to_slot[peer_id] = i

func _ensure_holder_containers() -> void:
	var my_slot := int(NetworkManager.my_slot)
	for h in turn_order:
		if h == null or !is_instance_valid(h):
			continue
		var target := get_container_for_holder(h)
		if target == null:
			continue
		if h.get_parent() != target:
			if h.get_parent() != null:
				h.get_parent().remove_child(h)
			target.add_child(h)

func _refresh_holder_layouts() -> void:
	var my_slot := int(NetworkManager.my_slot)
	for h in turn_order:
		if h == null or !is_instance_valid(h):
			continue
		h.compact_view = (my_slot < 0) or (h.player_index != my_slot)
		var target := get_container_for_holder(h)
		if target == null:
			continue
		if h.get_parent() != target:
			if h.get_parent() != null:
				h.get_parent().remove_child(h)
			target.add_child(h)
	_refresh_seat_names()

## ------------------------------------------------------------------
## Player name labels shown at each seat during a match.
## ------------------------------------------------------------------
func _refresh_seat_names() -> void:
	var used: Dictionary = {}
	for h in turn_order:
		if h == null or !is_instance_valid(h):
			continue
		var container := get_container_for_holder(h)
		# Only opponent seats get a name label; the local seat is a full-width
		# container at the bottom (and the local player knows their own name).
		if container == null or container == player_container:
			continue
		_set_seat_name(container, h)
		used[container] = true

	if player_container != null:
		_remove_seat_name(player_container)
	for c in other_player_containers:
		if c != null and not used.has(c):
			_remove_seat_name(c)

func _set_seat_name(container: Control, holder: HandCardHolder) -> void:
	if container == null or holder == null:
		return

	var label := container.get_node_or_null("SeatName") as Label
	if label == null:
		label = Label.new()
		label.name = "SeatName"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 100
		label.size = Vector2(300, 44)
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
		label.add_theme_constant_override("shadow_offset_x", 3)
		label.add_theme_constant_override("shadow_offset_y", 3)
		container.add_child(label)

	label.text = holder.profile.player_name if holder.profile != null else ""
	# Centered horizontally on the seat point, just above the card stack.
	label.position = Vector2(-150, -290)

func _remove_seat_name(container: Control) -> void:
	if container == null:
		return
	var lbl := container.get_node_or_null("SeatName")
	if lbl != null:
		lbl.queue_free()

func _should_reset_server_match(players_in: Array) -> bool:
	# Zähle alle Teilnehmer (Menschen + Bots). Unter 2 -> Match zurücksetzen.
	var participants := 0
	for p in players_in:
		if p is Dictionary:
			if bool(p.get("is_bot", false)) or int(p.get("peer_id", 0)) != 0:
				participants += 1
	return participants < 2

func _reset_server_match_state() -> void:
	_server_match_started = false
	_server_match_starting = false
	_client_match_started = false
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false
	winners.clear()
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	wild_color_owner = null
	target_draw_active = false
	target_draw_value = 0
	target_draw_is_multi = false
	target_draw_color = CardResource.CardColor.BLACK
	pending_target_draw_owner = null
	place_all_active = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED
	place_all_resolving = false
	place_all_card = null
	_place_all_sequence_running = false
	roulette_active = false
	roulette_waiting_for_color = false
	roulette_owner = null
	roulette_target = null
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false
	pending_swap_owner = null
	swap_color_pending = false
	if card_manager != null:
		card_manager.waiting_for_color = false
		card_manager.pending_wild_card = null
		card_manager.current_color = CardResource.CardColor.BLACK

## Buffer incoming match state
func _on_match_state_received(state: Dictionary) -> void:
	_pending_state = state
	if !multiplayer.is_server():
		_client_has_state = false
	_try_apply_pending_match_state()

## Apply match state when possible
func _try_apply_pending_match_state() -> void:
	if _pending_state.size() == 0:
		return
	if card_manager == null:
		return

	var top = _pending_state.get("top_card", null)
	if top is Dictionary:
		var r := CardResource.new()
		r.color = int(top.get("c", 0))
		r.type = int(top.get("t", 0))
		r.value = int(top.get("v", 0))
		r.uid = int(top.get("id", 0))
		card_manager.set_top_card_runtime(r)

	current_turn_index = int(_pending_state.get("turn_index", 0))
	direction = int(_pending_state.get("direction", 1))
	draw_stack_amount = int(_pending_state.get("draw_stack", 0))
	draw_stack_min_value = int(_pending_state.get("draw_stack_min", draw_stack_min_value))
	draw_stack_is_wild = bool(_pending_state.get("draw_stack_is_wild", draw_stack_is_wild))
	draw_stack_color = int(_pending_state.get("draw_stack_color", draw_stack_color))

	if _pending_state.has("current_color") and card_manager != null:
		card_manager.current_color = int(_pending_state.get("current_color", card_manager.current_color))
	if _pending_state.has("waiting_for_color") and card_manager != null:
		var waiting := bool(_pending_state.get("waiting_for_color", card_manager.waiting_for_color))
		if waiting and !card_manager.waiting_for_color:
			card_manager.waiting_for_color = true
		if !waiting and card_manager.waiting_for_color:
			card_manager.select_color(card_manager.current_color)

	has_played_this_turn = false
	has_drawn_this_turn = false

	update_turn_state()

	_pending_state = {}
	NetworkManager.clear_last_match_state()
	_client_has_state = true
	if !multiplayer.is_server():
		_client_match_started = true
	if !multiplayer.is_server():
		_try_finalize_client_sync()

## Serialize card
func _serialize_card(r: CardResource) -> Dictionary:
	return {"c": int(r.color), "t": int(r.type), "v": int(r.value), "id": int(r.uid)}

## Server start guard
func _server_try_start_match() -> void:
	if _server_match_started or _server_match_starting:
		print("QueueManager: Match already started or starting, skipping")
		return
	if turn_order.is_empty():
		print("QueueManager: Turn order is empty, cannot start match")
		return
	if turn_order.size() < 2:
		print("QueueManager: Only %d players, need at least 2" % turn_order.size())
		return

	var now := Time.get_ticks_msec()
	if now - _server_last_players_change_ms < SERVER_START_DELAY_MS:
		if !_server_start_delay_active:
			_server_start_delay_active = true
			var wait_sec := float(SERVER_START_DELAY_MS - (now - _server_last_players_change_ms)) / 1000.0
			await get_tree().create_timer(max(wait_sec, 0.1)).timeout
			_server_start_delay_active = false
			if not _server_match_started:
				call_deferred("_server_try_start_match")
		return

	print("QueueManager: Checking if all players are connected...")
	# Ensure all players have valid peer IDs (are connected)
	var all_connected := true
	var missing_peers: Array = []
	for holder in turn_order:
		if holder == null:
			all_connected = false
			missing_peers.append("null holder")
			break
		var peer_id := _slot_to_peer_id(holder.player_index)
		# If it is a real player (not bot) and has no peer_id, they are not connected yet
		if not holder.is_bot and peer_id == 0:
			all_connected = false
			missing_peers.append("player %d (slot %d)" % [holder.player_index, holder.player_index])

	if not all_connected:
		print("QueueManager: Not all players connected yet. Missing: %s" % str(missing_peers))
		# Wait a bit and try again
		await get_tree().create_timer(0.5).timeout
		if not _server_match_started:
			call_deferred("_server_try_start_match")
		return

	print("QueueManager: All players connected! Starting match...")
	_server_match_starting = true
	call_deferred("_server_start_match")
## Server match start and sync
func _server_start_match() -> void:
	if !multiplayer.is_server():
		print("QueueManager: Not server, cannot start match")
		_server_match_starting = false
		return
	if _server_match_started:
		print("QueueManager: Match already started")
		_server_match_starting = false
		return
	if card_manager == null:
		print("QueueManager: CardManager is null, cannot start match")
		_server_match_starting = false
		return
	if turn_order.is_empty():
		print("QueueManager: Turn order is empty, cannot start match")
		_server_match_starting = false
		return

	print("QueueManager: Starting match with %d players" % turn_order.size())
	_server_match_started = true
	_server_match_starting = false
	_game_over_handled = false

	randomize()
	current_turn_index = randi() % turn_order.size()
	direction = 1
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	has_played_this_turn = false
	has_drawn_this_turn = false
	winners.clear()

	# Apply the deck chosen in the lobby (host-authoritative). Falls back to the
	# card manager's default deck if none was selected / it fails to load.
	var chosen_deck_path := str(NetworkManager.lobby_deck_path)
	if chosen_deck_path != "":
		var chosen_deck := Globals.load_deck(chosen_deck_path)
		if chosen_deck != null:
			card_manager.loaded_deck = chosen_deck
			print("QueueManager: Using deck '%s'" % str(chosen_deck.deck_name))

	card_manager.deck = card_manager.create_default_cards()
	card_manager.deck.shuffle()
	card_manager.set_top_card()

	var state := {
		"top_card": _serialize_card(card_manager.top_card),
		"turn_index": int(current_turn_index),
		"direction": 1,
		"draw_stack": 0,
		"draw_stack_min": 0,
		"draw_stack_is_wild": false,
		"draw_stack_color": int(CardResource.CardColor.BLACK),
		"current_color": int(card_manager.current_color),
		"waiting_for_color": bool(card_manager.waiting_for_color)
	}

	# Broadcast match state to all clients first
	NetworkManager.rpc("client_set_match_state", state)
	_on_match_state_received(state)

	# Wait a frame to ensure state is received
	await get_tree().process_frame

	# Distribute cards to all players
	for holder in turn_order:
		if holder == null:
			continue

		var hand: Array = []
		for i in range(start_card_count):
			var c := card_manager.draw_card()
			if c == null:
				break
			hand.append(_serialize_card(c))

		_apply_hand_to_holder(holder, hand)

		var peer_id := _slot_to_peer_id(holder.player_index)
		if peer_id != 0:
			# Send hand to specific client
			NetworkManager.rpc_id(peer_id, "client_set_hand", hand)
		# For bots, hand is already applied locally via _apply_hand_to_holder

	# Wait a frame to ensure hands are received
	await get_tree().process_frame

	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")
	_server_broadcast_counts()

## Slot to peer id
func _slot_to_peer_id(slot: int) -> int:
	for pid in _peer_to_slot.keys():
		if int(_peer_to_slot[pid]) == slot:
			return int(pid)
	return 0

## Apply a hand locally
func _apply_hand_to_holder(holder: HandCardHolder, hand: Array) -> void:
	for c in holder.get_children():
		if c is CardView:
			holder.remove_child(c)
			c.queue_free()

	for entry: Dictionary in hand:
		var r := CardResource.new()
		r.color = int(entry.get("c", 0))
		r.type = int(entry.get("t", 0))
		r.value = int(entry.get("v", 0))
		r.uid = int(entry.get("id", 0))
		holder.add_card(r, false)

	holder.sort_cards_full()
	holder.refresh_playable_cards()

func _reconcile_hand(holder: HandCardHolder, hand: Array) -> void:
	if holder == null:
		return
	var current: Dictionary = {}
	for c in holder.get_children():
		if c is CardView and c.card_res != null:
			current[int(c.card_res.uid)] = c

	var desired: Dictionary = {}
	for entry: Dictionary in hand:
		var uid := int(entry.get("id", 0))
		if uid == 0:
			continue
		desired[uid] = entry

	for uid in current.keys():
		if !desired.has(uid):
			var cv: CardView = current[uid]
			if cv != null and is_instance_valid(cv):
				holder.remove_child(cv)
				cv.queue_free()

	for uid in desired.keys():
		if !current.has(uid):
			var entry: Dictionary = desired[uid]
			var r := CardResource.new()
			r.color = int(entry.get("c", 0))
			r.type = int(entry.get("t", 0))
			r.value = int(entry.get("v", 0))
			r.uid = int(entry.get("id", 0))
			holder.add_card(r, true)

	holder.sort_cards_full()
	holder.refresh_playable_cards()

## Counts received
func _on_counts_received(hand_counts: Array, deck_count: int) -> void:
	_last_hand_counts = hand_counts.duplicate(true)
	_last_deck_count = int(deck_count)
	_apply_counts_to_ui()

## Build opponent dummy backs from counts
func _apply_counts_to_ui() -> void:
	if _last_hand_counts.is_empty():
		return

	var my_slot := int(NetworkManager.my_slot)
	if my_slot < 0 or my_slot >= turn_order.size():
		return

	for i in range(min(_last_hand_counts.size(), turn_order.size())):
		if i == my_slot:
			continue

		var holder: HandCardHolder = turn_order[i]
		if holder == null or !is_instance_valid(holder):
			continue

		var current_count := 0
		for c in holder.get_children():
			if c is CardView and not c.get_meta("anim_temp", false):
				current_count += 1

		var n := int(_last_hand_counts[i])
		if current_count == n:
			continue

		for c in holder.get_children():
			# Keep transient fly-animation cards alive so the rebuild doesn't
			# cancel an in-flight play animation.
			if c is CardView and not c.get_meta("anim_temp", false):
				holder.remove_child(c)
				c.queue_free()

		for k in range(n):
			var dummy := CardResource.new()
			dummy.color = CardResource.CardColor.BLACK
			dummy.type = CardResource.CardType.NUMBER
			dummy.value = 0
			dummy.uid = 0
			holder.add_card(dummy, false)

		holder.sort_cards_full()

	_apply_local_visibility()

## Deck count getter
func get_synced_deck_count() -> int:
	return _last_deck_count

## Group registration
func _enter_tree() -> void:
	add_to_group("queue_manager")

## Server apply play request
func server_apply_play(peer_id: int, card_id: int) -> void:
	if not multiplayer.is_server():
		return

	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return

	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or not is_instance_valid(holder):
		return
	if !is_players_turn(holder):
		return

	var cv: CardView = null
	for ch in holder.get_children():
		if ch is CardView and ch.card_res != null and int(ch.card_res.uid) == int(card_id):
			cv = ch
			break
	if cv == null:
		return

	if not can_play_now(holder):
		return
	if not holder.can_play_card(cv.card_res):
		return

	# NOTE: the client_play_event broadcast now happens inside holder.set_card()
	# (server path) so it fires exactly once for both host and client plays.
	await holder.set_card(cv)

	if card_manager != null and card_manager.waiting_for_color and wild_color_owner == holder:
		var owner_peer := _slot_to_peer_id(holder.player_index)
		if owner_peer != 0:
			NetworkManager.rpc_id(owner_peer, "client_request_color", int(holder.player_index))

	# Synchronize match state after card play
	_server_sync_match_state()
	_server_broadcast_counts()

## Server apply draw request
func server_apply_draw(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return

	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or not is_instance_valid(holder):
		return

	# Only the player whose turn it is may draw (prevents drawing on someone
	# else's turn / other players affecting the game out of turn).
	if !is_players_turn(holder):
		return

	# Check if draw is allowed
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
	
	# Handle draw stack
	if draw_stack_amount > 0:
		if draw_stack_is_wild:
			await force_wild_draw_continue(holder)
		else:
			await force_draw_stack_continue(holder)
		# Send updated hand to client after stack draw
		var hand_after_stack: Array = []
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null:
				hand_after_stack.append(_serialize_card(ch.card_res))
		NetworkManager.rpc_id(peer_id, "client_set_hand", hand_after_stack)
		_server_broadcast_counts()
		_server_sync_match_state()
		return
	
	# Normal draw
	var card := card_manager.draw_card()
	if card == null:
		return

	holder.add_card(card)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	
	# Send updated hand to client
	var hand: Array = []
	for ch in holder.get_children():
		if ch is CardView and ch.card_res != null:
			hand.append(_serialize_card(ch.card_res))
	
	NetworkManager.rpc_id(peer_id, "client_set_hand", hand)
	_server_broadcast_counts()

	if !allow_play_after_draw:
		end_turn()
		return

	if !holder_has_playable_card(holder):
		end_turn()
		return

## Server apply target selection from client
func server_apply_target_select(peer_id: int, target_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var owner_slot := int(_peer_to_slot.get(int(peer_id), -1))
	if owner_slot < 0:
		return
	var owner_holder: HandCardHolder = _slot_to_holder.get(owner_slot, null)
	if owner_holder == null or !is_instance_valid(owner_holder):
		return
	var target_holder: HandCardHolder = _slot_to_holder.get(int(target_slot), null)
	if target_holder == null or !is_instance_valid(target_holder):
		return

	if target_draw_active and pending_target_draw_owner == owner_holder:
		resolve_target_draw(target_holder)
		return

	if pending_swap_owner == owner_holder:
		pending_swap_owner = null
		_resolve_swap_with_target(owner_holder, target_holder)

## Server apply wild color from client
func server_apply_wild_color(peer_id: int, color: int) -> void:
	if not multiplayer.is_server():
		return
	if card_manager == null or !card_manager.waiting_for_color:
		return
	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or !is_instance_valid(holder):
		return
	if wild_color_owner != holder:
		return
	_apply_wild_color(color, slot)

## Apply wild color locally and broadcast to clients
func _apply_wild_color(color: int, owner_slot: int) -> void:
	if card_manager == null:
		return
	if card_manager.waiting_for_color:
		card_manager.select_color(color)
	else:
		card_manager.current_color = color
		if card_manager.top_card != null:
			card_manager.top_card.color = color
		if card_manager.top_card_view != null and is_instance_valid(card_manager.top_card_view):
			card_manager.top_card_view.override_color_enabled = true
			card_manager.top_card_view.override_color = color
			card_manager.top_card_view.load_card()
	Signals.COLOR_color_selected.emit(color)
	if multiplayer.is_server():
		if wild_color_owner != null and !card_manager.waiting_for_color:
			# The COLOR_color_selected emit above already scheduled the owning
			# holder's _after_color_selected(), which would call register_card_play
			# a SECOND time. For a +4 that meant the draw effect ran twice and hit
			# another player too. Clear the holder's flag so the effect resolves
			# exactly once here.
			if is_instance_valid(wild_color_owner):
				wild_color_owner._waiting_color_turn_end = false
			register_card_play(card_manager.top_card)
			clear_wild_owner()
		NetworkManager.rpc("client_set_wild_color", int(color), int(owner_slot))
		_server_sync_match_state()

## Client receive wild color
func client_apply_wild_color(color: int, owner_slot: int) -> void:
	if card_manager == null:
		return
	if card_manager.waiting_for_color:
		card_manager.select_color(color)
	else:
		card_manager.current_color = color
		if card_manager.top_card != null:
			card_manager.top_card.color = color
		if card_manager.top_card_view != null and is_instance_valid(card_manager.top_card_view):
			card_manager.top_card_view.override_color_enabled = true
			card_manager.top_card_view.override_color = color
			card_manager.top_card_view.load_card()
	Signals.COLOR_color_selected.emit(color)
	clear_wild_owner()

## Client request to show color selector for a specific owner slot
func client_request_color(owner_slot: int) -> void:
	if multiplayer.is_server():
		return
	var holder: HandCardHolder = _slot_to_holder.get(int(owner_slot), null)
	if holder == null or !is_instance_valid(holder):
		return
	set_wild_color_owner(holder)
	Signals.COLOR_request_color_select.emit()

## Client request to show target selector for a specific owner slot
func client_request_target_select(owner_slot: int, allow_self: bool) -> void:
	if multiplayer.is_server():
		return
	var holder: HandCardHolder = _slot_to_holder.get(int(owner_slot), null)
	if holder == null or !is_instance_valid(holder):
		return
	Signals.TARGET_request_target_select.emit(holder, allow_self)

## Server sync match state to all clients
func _server_sync_match_state() -> void:
	if not multiplayer.is_server():
		return
	if card_manager == null:
		return
	
	var top_card_dict := {}
	if card_manager.top_card != null:
		top_card_dict = _serialize_card(card_manager.top_card)
	
	var state := {
		"top_card": top_card_dict,
		"turn_index": int(current_turn_index),
		"direction": int(direction),
		"draw_stack": int(draw_stack_amount),
		"draw_stack_min": int(draw_stack_min_value),
		"draw_stack_is_wild": bool(draw_stack_is_wild),
		"draw_stack_color": int(draw_stack_color),
		"current_color": int(card_manager.current_color),
		"waiting_for_color": bool(card_manager.waiting_for_color)
	}
	
	NetworkManager.rpc("client_set_match_state", state)
	# Also apply locally on server
	_on_match_state_received(state)

## Server broadcast counts
func _server_broadcast_counts() -> void:
	if not multiplayer.is_server():
		return

	var counts: Array = []
	for i in range(turn_order.size()):
		var h: HandCardHolder = _slot_to_holder.get(i, null)
		if h == null or not is_instance_valid(h):
			counts.append(0)
		else:
			counts.append(int(h.get_child_count()))

	var deck_count := 0
	if card_manager != null and card_manager.deck != null:
		deck_count = int(card_manager.deck.size())

	NetworkManager.rpc("client_set_counts", counts, deck_count)

## Push a holder's authoritative hand to its owning client. Many special-card
## effects (target/multi draw, swap, roulette, place-all) change a hand purely
## on the server; without this the client keeps showing the old cards, which
## causes desyncs and soft-locks (cards that look playable but no longer exist).
func _server_push_hand(holder: HandCardHolder) -> void:
	if not multiplayer.is_server():
		return
	if holder == null or not is_instance_valid(holder) or holder.is_bot:
		return
	var peer_id := _slot_to_peer_id(int(holder.player_index))
	# peer 0 = no peer, peer 1 = the host itself (its holder is already correct).
	if peer_id == 0 or peer_id == 1:
		return
	var hand: Array = []
	for ch in holder.get_children():
		if ch is CardView and ch.card_res != null:
			hand.append(_serialize_card(ch.card_res))
	NetworkManager.rpc_id(peer_id, "client_set_hand", hand)

## Client play event for opponents
func _on_play_event_received(from_slot: int, card: Dictionary) -> void:
	if multiplayer.is_server():
		return
	var my_slot := int(NetworkManager.my_slot)
	
	# Handle own card play - remove card from hand
	if int(from_slot) == my_slot:
		var holder: HandCardHolder = _slot_to_holder.get(int(from_slot), null)
		if holder == null or !is_instance_valid(holder):
			return

		var card_uid := int(card.get("id", 0))
		var cv: CardView = null
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null and int(ch.card_res.uid) == card_uid:
				cv = ch
				break

		var r := CardResource.new()
		r.color = int(card.get("c", 0))
		r.type = int(card.get("t", 0))
		r.value = int(card.get("v", 0))
		r.uid = int(card.get("id", 0))

		# Fly the played card to the discard pile first, then swap the top card
		# once it lands (suppress mid-flight match-state snaps).
		if card_manager != null:
			card_manager.begin_top_card_suppression()

		if cv != null and is_instance_valid(cv):
			cv.set_clickable(false, true)
			cv.smooth_move_button_to_top_card_juicy(0.3)
			await get_tree().create_timer(0.3).timeout
			if is_instance_valid(cv):
				holder.remove_child(cv)
				cv.queue_free()

		if card_manager != null:
			card_manager.end_top_card_suppression(r)

		# The top card was buffered during the fly, so any turn/playability
		# refresh that ran mid-flight evaluated against the OLD top card.
		# Re-evaluate now that the new top card is live, otherwise actually
		# playable cards stay locked and the player is forced to draw.
		update_turn_state()

		if r.type in [
			CardResource.CardType.WILD,
			CardResource.CardType.WILD_DRAW,
			CardResource.CardType.WILD_DRAW_REVERSE
		]:
			set_wild_color_owner(holder)
			if !multiplayer.is_server():
				Signals.COLOR_request_color_select.emit()

		holder.sort_cards_full()
		holder.refresh_playable_cards()
		return

		

	var holder: HandCardHolder = _slot_to_holder.get(int(from_slot), null)
	if holder == null or not is_instance_valid(holder):
		return

	# Remove one card from opponent's hand (we don't know which exact card, so remove first visible)
	var remove_one: CardView = null
	for ch in holder.get_children():
		if ch is CardView:
			remove_one = ch
			break

	if remove_one != null and is_instance_valid(remove_one):
		holder.remove_child(remove_one)
		remove_one.queue_free()

	var r := CardResource.new()
	r.color = int(card.get("c", 0))
	r.type = int(card.get("t", 0))
	r.value = int(card.get("v", 0))
	r.uid = int(card.get("id", 0))

	# Fly a face-up copy of the played card from the opponent's seat to the
	# discard pile, and only swap the top card once it lands. The suppression
	# keeps an incoming match-state sync from snapping the top card mid-flight,
	# which is why remote plays previously just "appeared" instead of flying.
	if card_manager != null:
		card_manager.begin_top_card_suppression()

	var temp: CardView = holder.CARD_VIEW.instantiate()
	temp.in_hand_card = false
	temp.hand_card_holder = null
	temp.card_res = r
	temp.show_front = true
	temp.set_clickable(false, true)
	# Mark as a transient animation card so the counts/visibility rebuilds don't
	# delete it mid-flight (that's why remote plays only animated on the host).
	temp.set_meta("anim_temp", true)
	holder.add_child(temp)

	# Let the seat container lay the card out so we read its real on-screen
	# position before flying it.
	await get_tree().process_frame
	await get_tree().process_frame

	var start_pos := temp.global_position
	var target_pos := start_pos
	if card_manager != null and card_manager.top_card_view != null and is_instance_valid(card_manager.top_card_view):
		target_pos = card_manager.top_card_view.global_position

	# Opponent seats use compact/overlapping layouts, so the old local-space fly
	# (visuells.position relative to the seat) was distorted to near-zero on
	# clients and the card just "appeared". Detach to top-level and animate in
	# global space with a high z_index so it visibly flies above all UI from the
	# seat to the centre on every peer.
	temp.top_level = true
	temp.z_index = 4096
	temp.global_position = start_pos

	var tw := create_tween()
	tw.tween_property(temp, "global_position", target_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.3).timeout

	if temp != null and is_instance_valid(temp):
		temp.queue_free()

	if card_manager != null:
		card_manager.end_top_card_suppression(r)

	# Re-evaluate playable cards now that the new top card is live (it was
	# buffered during the fly, so the mid-flight refresh used the old top card).
	update_turn_state()

func _server_sync_late_joiners(players_in: Array) -> void:
	if not _server_match_started:
		return
	if card_manager == null:
		return

	var state := {
		"top_card": _serialize_card(card_manager.top_card),
		"turn_index": int(current_turn_index),
		"direction": int(direction),
		"draw_stack": int(draw_stack_amount),
		"draw_stack_min": int(draw_stack_min_value),
		"draw_stack_is_wild": bool(draw_stack_is_wild),
		"draw_stack_color": int(draw_stack_color),
		"current_color": int(card_manager.current_color),
		"waiting_for_color": bool(card_manager.waiting_for_color)
	}

	for row in players_in:
		if not (row is Dictionary):
			continue
		var peer_id := int(row.get("peer_id", 0))
		if peer_id == 0:
			continue

		var slot := int(_peer_to_slot.get(peer_id, -1))
		if slot < 0:
			continue

		var holder: HandCardHolder = _slot_to_holder.get(slot, null)
		if holder == null or not is_instance_valid(holder):
			continue

		var hand: Array = []
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null:
				hand.append(_serialize_card(ch.card_res))

		NetworkManager.rpc_id(peer_id, "client_set_match_state", state)
		NetworkManager.rpc_id(peer_id, "client_set_hand", hand)

	_server_broadcast_counts()
