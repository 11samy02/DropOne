extends Node
class_name QueueManager

## UI parent for the local human player's hand.
@export var player_container: Control
## UI parents for opponent seats (order follows relative turn order).
@export var other_player_containers: Array[Control]
@export var card_manager: CardManager

## Total human + bot participants for this match.
@export var player_count := 1
## Cards dealt to each player at match start.
@export var start_card_count := 7
## Bot AI profiles used when creating offline bots.
@export var bot_profiles: Array[BotProfile] = []

const BOT_DIFFICULTY_NAMES := ["Rookie", "Casual", "Smart", "Hard", "Master", "Omega"]
const BOT_PERSONALITY_NAMES := ["Balanced", "Aggressor", "Collector", "Chaos", "Punisher", "Color Monarch"]

## Holders who emptied their hand and won the round.
var winners: Array[HandCardHolder] = []
## Holders eliminated by the max-card-lose deck rule.
var max_card_losers: Array[HandCardHolder] = []

var players: Array[HandCardHolder] = []
var bots: Array[HandCardHolder] = []
## Active turn order (humans + bots); index is current_turn_index.
var turn_order: Array[HandCardHolder] = []

var current_turn_index := 0
## True after the current player played a card this turn.
var has_played_this_turn := false
## True after the current player drew a card this turn.
var has_drawn_this_turn := false
## If false, drawing ends the turn even when a playable card exists.
var allow_play_after_draw := true

## Play direction: 1 = forward, -1 = reverse.
var direction := 1
## Accumulated +draw penalty waiting for the next player.
var draw_stack_amount := 0
## Minimum +value required to stack on the current draw pile.
var draw_stack_min_value := 0
## True when the stack was started or extended by a wild +draw.
var draw_stack_is_wild := false
## Color constraint for stacking colored +draw cards.
var draw_stack_color: CardResource.CardColor = CardResource.CardColor.BLACK
## Seat that played the current +draw stack; that player must never resolve it.
var draw_stack_source_slot: int = -1
## Holder who must pick wild color after playing a wild card.
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
var roulette_target_slot: int = -1
var roulette_chosen_color: CardResource.CardColor = CardResource.CardColor.BLACK
var roulette_step_running := false
var pending_swap_owner: HandCardHolder = null
var swap_color_pending := false
var _swap_resolve_running := false
var _swap_resolve_started_ms := 0

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
var _match_deal_in_progress := false
var _match_deal_complete := false
var _client_has_hand := false
var _client_has_state := false
var _client_match_started := false
var _game_over_handled := false
var _winner_overlay: CanvasLayer = null
var _lobby_return_requested := false
var _placement_toast: CanvasLayer = null
var _loser_overlay: CanvasLayer = null
var _local_loser_overlay_shown := false
var _server_last_players_change_ms := 0
var _server_start_delay_active := false
const SERVER_START_DELAY_MS := 300
const DEAL_CARD_DURATION := 0.11
const DEAL_CARD_GAP := 0.04
var _client_play_animating := false
var _client_play_uids_in_flight: Dictionary = {}
var _client_place_all_animating := false
var _client_place_all_slot := -1
var _client_suppress_draw_sound_once := false
var _client_deal_animating := false
var _client_deal_batch_queue: Array = []
var _client_deal_batch_running := false
var _client_deal_finish_scheduled := false
var _opponent_left_overlay_shown := false
## True once the initial _on_players_received ran in _ready(); prevents
## any later client_set_players broadcast from destroying holders mid-match.
var _client_holders_initialized := false
var _client_swap_animating := false
var _client_draw_animating := false
var _client_draw_queue: Array = []
var _client_hand_watchdog_armed := false
var _last_hand_resync_ms := 0
var _pending_counts_apply := false
var _stuck_reconcile_running := false
var _stuck_watchdog: Timer = null
## Uids whose special-card effects were already applied (prevents double skip etc.).
var _resolved_effect_uids: Dictionary = {}
## Top-card uids whose swap-hands effect already applied (prevents double swap).
var _completed_swap_uids: Dictionary = {}

## Init networking + buffered snapshots
func _ready() -> void:
	get_tree().paused = false
	_client_has_hand = false
	_client_has_state = false
	_client_match_started = false
	_match_deal_in_progress = false
	_match_deal_complete = false
	_game_over_handled = false
	connect_signals()

	NetworkManager.players_received.connect(_on_players_received)
	NetworkManager.hand_received.connect(_on_hand_received)
	NetworkManager.match_state_received.connect(_on_match_state_received)
	NetworkManager.counts_received.connect(_on_counts_received)
	NetworkManager.play_event_received.connect(_on_play_event_received)
	NetworkManager.place_all_event_received.connect(_on_place_all_event_received)
	NetworkManager.swap_hands_event_received.connect(_on_client_swap_hands_visual)
	NetworkManager.draw_event_received.connect(_on_draw_event_received)
	NetworkManager.deal_begin_received.connect(_on_deal_begin_received)
	NetworkManager.deal_batch_received.connect(_on_deal_batch_received)
	NetworkManager.dealing_finished_received.connect(_on_dealing_finished_received)
	NetworkManager.game_won.connect(_on_game_won)
	NetworkManager.player_eliminated.connect(_on_player_eliminated)
	NetworkManager.return_to_lobby.connect(_on_return_to_lobby)
	NetworkManager.lobby_disconnected.connect(_on_host_disconnected_during_match)

	var buffered_players := NetworkManager.get_last_players()
	if buffered_players.size() > 0:
		_on_players_received(buffered_players)
		NetworkManager.clear_last_players()
		if !multiplayer.is_server():
			_client_holders_initialized = true
	elif multiplayer.is_server():
		call_deferred("_server_request_player_rebroadcast")

	var buffered_hand := NetworkManager.get_last_hand()
	if buffered_hand.size() > 0:
		_on_hand_received(buffered_hand)

	var buffered_state := NetworkManager.get_last_match_state()
	if buffered_state.size() > 0:
		_on_match_state_received(buffered_state)

	# Server starts match when players are received via _on_players_received().

	_stuck_watchdog = Timer.new()
	_stuck_watchdog.wait_time = 1.5
	_stuck_watchdog.one_shot = false
	_stuck_watchdog.timeout.connect(_on_stuck_watchdog_timeout)
	add_child(_stuck_watchdog)
	_stuck_watchdog.start()

## Connect gameplay signals
func connect_signals() -> void:
	Signals.DECK_draw_pressed.connect(on_draw_pressed)
	Signals.TARGET_target_selected.connect(resolve_target_draw)
	Signals.COLOR_color_selected.connect(_on_roulette_color_selected)


## Plays draw-card SFX locally, syncs fly-in animation to clients, and optionally updates counts.
func notify_card_drawn(from_slot: int, count: int = 1, sync_counts: bool = true, card: CardResource = null) -> void:
	SoundManager.play_draw_card(count)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var card_c := int(card.color) if card != null else -1
		var card_t := int(card.type) if card != null else -1
		var card_v := int(card.value) if card != null else 0
		var card_id := int(card.uid) if card != null else 0
		for _i in range(maxi(int(count), 1)):
			NetworkManager.rpc(
				"client_draw_event",
				int(from_slot),
				card_c,
				card_t,
				card_v,
				card_id,
				NetworkManager.match_epoch
			)
	if sync_counts:
		_sync_deck_counts()

## Pushes authoritative deck + hand counts to every peer.
func _sync_deck_counts() -> void:
	if _is_authoritative():
		_server_broadcast_counts()

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


func get_holder_for_slot(slot: int) -> HandCardHolder:
	return _slot_to_holder.get(int(slot), null)


func get_holder_visual_center(holder: HandCardHolder) -> Vector2:
	if holder == null:
		return Vector2.ZERO
	var container := get_container_for_holder(holder)
	if container != null and is_instance_valid(container):
		return container.get_global_rect().get_center()
	return holder.get_global_rect().get_center()


## Builds a fly CardView for remote plays (pulls a card back or spawns a temp card).
func _acquire_client_fly_card_view(holder: HandCardHolder, res: CardResource, match_uid: bool = false, allow_fallback: bool = true) -> CardView:
	if holder == null or !is_instance_valid(holder) or res == null:
		return null

	if match_uid:
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null and int(ch.card_res.uid) == int(res.uid):
				return ch
		if !allow_fallback:
			return null

	var fly_start := get_holder_visual_center(holder)
	var cv: CardView = null
	var back_cards: Array[CardView] = []
	for ch in holder.get_children():
		if ch is CardView and is_instance_valid(ch) and not ch.get_meta("anim_temp", false):
			back_cards.append(ch)
	if back_cards.size() > 0:
		cv = back_cards[back_cards.size() - 1]
		if cv.visuells != null and is_instance_valid(cv.visuells):
			fly_start = cv.visuells.global_position
		cv.set_meta("fly_start_vis_global", fly_start)
		holder.remove_child(cv)
	else:
		cv = holder.CARD_VIEW.instantiate()
		cv.in_hand_card = false
		cv.hand_card_holder = null
		cv.set_meta("fly_start_vis_global", fly_start)
		holder.add_child(cv)

	cv.card_res = res
	cv.show_front = true
	cv.set_clickable(false, true)
	if cv.is_inside_tree():
		cv.load_card()
	if cv.get_parent() == holder:
		holder.remove_child(cv)
	return cv


func register_client_play_in_flight(_uid: int) -> void:
	pass


func clear_client_play_in_flight(_uid: int) -> void:
	pass


func _get_swap_hands_feedback() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("swap_hands_feedback")

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
		if i == 0 and Globals != null and Globals.client_profile != null:
			if Globals.client_profile.player_name.strip_edges() != "":
				holder.profile.player_name = Globals.client_profile.player_name
			if Globals.client_profile.picture != null:
				holder.profile.picture = Globals.client_profile.picture
			elif int(Globals.client_profile.picture_id) >= 0:
				holder.profile.apply_picture_from_id(int(Globals.client_profile.picture_id))
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
		holder.bot_difficulty = bot_profile.difficulty
		holder.bot_personality = bot_profile.personality
		var fallback_name := bot_profile.name if bot_profile.name.strip_edges() != "" else "Bot " + str(i + 1)
		holder.profile.player_name = _bot_display_name(bot_profile.difficulty, fallback_name)
		holder.profile.holder = holder
		holder.profile.apply_bot_avatar(bot_profile.difficulty)
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

	_match_deal_in_progress = true
	await deal_starting_cards(start_card_count)
	_match_deal_in_progress = false
	_match_deal_complete = true

	await get_tree().process_frame
	update_turn_state()
	_server_broadcast_counts()
	call_deferred("_handle_start_of_turn_effects")

## Current holder getter
func _is_authoritative() -> bool:
	return !multiplayer.has_multiplayer_peer() or multiplayer.is_server()

## True while a multiplayer match is running on this machine (host or client).
func is_match_in_progress() -> bool:
	return _server_match_started or _client_match_started


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
	if is_local_spectating():
		return false
	var my_holder := _get_local_holder()
	return my_holder != null and is_players_turn(my_holder)

## True when the local human was eliminated by the max-card rule.
func is_local_eliminated() -> bool:
	var my_holder := _get_local_holder()
	return is_holder_eliminated(my_holder)

## True when the local human finished their hand and is spectating (full ranking).
func is_local_spectating() -> bool:
	if is_local_eliminated():
		return true
	if not _is_full_ranking_mode():
		return false
	var my_holder := _get_local_holder()
	return is_holder_finished(my_holder)

func _get_local_holder() -> HandCardHolder:
	var my_slot := int(NetworkManager.my_slot)
	if my_slot < 0:
		my_slot = 0
	return _slot_to_holder.get(my_slot, null)

func is_holder_eliminated(holder: HandCardHolder) -> bool:
	return holder != null and max_card_losers.has(holder)

func is_holder_finished(holder: HandCardHolder) -> bool:
	if holder == null or !is_instance_valid(holder):
		return false
	return winners.has(holder) and not turn_order.has(holder)

## Play permission check
func can_play_now(holder: HandCardHolder) -> bool:
	if is_holder_eliminated(holder) or is_holder_finished(holder):
		return false
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
	if has_played_this_turn and draw_stack_amount <= 0:
		return false
	if card_manager != null and card_manager.waiting_for_color:
		return false
	return true

## Holder that would be skipped if next_turn(true) runs now.
func _peek_skipped_holder() -> HandCardHolder:
	if turn_order.size() <= 1:
		return null
	var skipped_index := current_turn_index + direction
	skipped_index = skipped_index % turn_order.size()
	if skipped_index < 0:
		skipped_index += turn_order.size()
	return turn_order[skipped_index]

## Notifies the skipped human player on their client (server sends targeted RPC).
func _notify_player_skipped(skipped_holder: HandCardHolder) -> void:
	if skipped_holder == null or skipped_holder.is_bot:
		return

	var slot := int(skipped_holder.player_index)

	if !multiplayer.has_multiplayer_peer():
		if _is_local_human_owner(skipped_holder):
			_show_feedback("Skipped", Signals.FeedbackKind.SKIPPED)
		return

	if !multiplayer.is_server():
		return

	NetworkManager.server_notify_player_skipped(slot)


## Returns false when this card's effects were already resolved or the card is not the current top.
func _can_resolve_card_effect(played_card: CardResource) -> bool:
	if played_card == null:
		return false
	var uid := int(played_card.uid)
	if uid <= 0:
		return false
	if _resolved_effect_uids.has(uid):
		return false
	if card_manager != null and card_manager.top_card != null:
		if uid != int(card_manager.top_card.uid):
			return false
	return true


## Recovers when an effect uid was marked resolved but the turn never advanced.
func _try_recover_stuck_card_play(played_card: CardResource, player: HandCardHolder = null) -> void:
	if played_card == null or card_manager == null or card_manager.top_card == null:
		return
	var uid := int(played_card.uid)
	if uid <= 0 or int(card_manager.top_card.uid) != uid:
		return
	if !_resolved_effect_uids.has(uid):
		return
	var actor := player if player != null else get_current_holder()
	if actor == null or !is_players_turn(actor):
		return
	if played_card.type in [
		CardResource.CardType.DRAW,
		CardResource.CardType.WILD_DRAW,
		CardResource.CardType.WILD_DRAW_REVERSE,
	]:
		if _holder_is_draw_stack_source(actor):
			_try_recover_draw_stack_source_turn(actor)
		return
	if has_played_this_turn:
		if played_card.type == CardResource.CardType.SWAP_HANDS and is_players_turn(actor):
			call_deferred("_try_recover_stuck_swap", actor)
		elif _holder_has_active_sub_effect(actor):
			pass
		elif is_players_turn(actor):
			call_deferred("_try_recover_stuck_turn", actor)
		return
	# Effect already resolved — replay skip-style advances for bots only.
	if actor.is_bot:
		match played_card.type:
			CardResource.CardType.SKIP:
				next_turn(true)
			CardResource.CardType.REVERSE:
				if turn_order.size() == 2:
					next_turn(true)


## Register played card and advance rules
func register_card_play(played_card: CardResource, player: HandCardHolder = null) -> void:
	if played_card == null:
		end_turn()
		return

	if !_is_authoritative():
		return

	if place_all_active:
		return

	if not _can_resolve_card_effect(played_card):
		_try_recover_stuck_card_play(played_card, player)
		return

	_resolved_effect_uids[int(played_card.uid)] = true

	var actor := player if player != null else get_current_holder()
	has_played_this_turn = true

	if _check_and_finish_current_holder():
		_after_holder_finished()
		if _is_authoritative():
			_server_sync_match_state()
			_server_broadcast_counts()
		return

	match played_card.type:
		CardResource.CardType.SKIP:
			var skipped_holder := _peek_skipped_holder()
			next_turn(true)
			_notify_player_skipped(skipped_holder)
			return
		CardResource.CardType.REVERSE:
			if turn_order.size() == 2:
				next_turn(true)
			else:
				apply_reverse()
				end_turn()
			return
		CardResource.CardType.DRAW:
			start_or_stack_draw(_draw_stack_value_for_play(played_card), false, played_card.value, actor)
			_advance_turn_after_draw_penalty()
			return
		CardResource.CardType.WILD_DRAW:
			start_or_stack_draw(played_card.value, true, played_card.value, actor)
			_advance_turn_after_draw_penalty()
			return
		CardResource.CardType.WILD_DRAW_REVERSE:
			if turn_order.size() > 2:
				apply_reverse()
			start_or_stack_draw(played_card.value, true, played_card.value, actor)
			_advance_turn_after_draw_penalty()
			return
		CardResource.CardType.SWAP_HANDS:
			if swap_color_pending:
				if wild_color_owner != null and is_instance_valid(wild_color_owner):
					_restore_turn_to_holder(wild_color_owner)
					if wild_color_owner.is_bot:
						call_deferred("_finish_bot_swap_color", wild_color_owner)
					else:
						call_deferred("_ensure_wild_color_resolved", wild_color_owner)
				return
			start_swap_hands(actor)
			return
		CardResource.CardType.TARGET_DRAW:
			start_target_draw(actor, played_card.value, false, played_card.color)
			return
		CardResource.CardType.MULTI_TARGET_DRAW:
			start_target_draw(actor, played_card.value, true, played_card.color)
			return
		CardResource.CardType.WILD_COLOR_ROULET:
			start_color_roulette(actor)
			return

	end_turn()

## After someone finishes hand
func _after_holder_finished() -> void:
	has_played_this_turn = false
	has_drawn_this_turn = false
	if winners.size() > 0:
		var finished: HandCardHolder = winners[-1]
		_finalize_finished_holder_ui(finished)
		if _is_authoritative():
			if _is_full_ranking_mode():
				_server_on_new_winner()
				if turn_order.size() <= 1:
					_server_try_finish_ranking_match()
				else:
					update_turn_state()
					_server_sync_match_state()
					_server_broadcast_counts()
					call_deferred("_handle_start_of_turn_effects")
			else:
				_server_handle_game_over()
		return
	if current_turn_index >= turn_order.size():
		current_turn_index = 0
	update_turn_state()
	call_deferred("_handle_start_of_turn_effects")

## Restart match
## Restarts the current scene after a short delay (offline rematch).
func _restart_match() -> void:
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()

## Server: announce winner RPC, wait, then return all peers to lobby.
func _is_full_ranking_mode() -> bool:
	return int(NetworkManager.lobby_end_mode) == NetworkManager.LobbyEndMode.FULL_RANKING


func _holder_display_name(holder: HandCardHolder) -> String:
	if holder == null or !is_instance_valid(holder):
		return "Player"
	if holder.profile != null:
		return str(holder.profile.player_name)
	return "Player"


func _build_ranking_results() -> Array:
	var results: Array = []
	for i in range(winners.size()):
		var h: HandCardHolder = winners[i]
		if h == null or !is_instance_valid(h):
			continue
		results.append({
			"name": _holder_display_name(h),
			"slot": int(h.player_index),
			"place": i + 1,
		})

	var total := maxi(player_count, winners.size() + max_card_losers.size())
	var last_place := total
	for h in max_card_losers:
		if h == null or !is_instance_valid(h):
			continue
		results.append({
			"name": _holder_display_name(h),
			"slot": int(h.player_index),
			"place": last_place,
		})
		last_place -= 1

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("place", 999)) < int(b.get("place", 999))
	)
	return results


func _server_on_new_winner() -> void:
	if not _is_authoritative() or _game_over_handled:
		return
	if winners.is_empty():
		return

	var winner: HandCardHolder = winners[-1]
	var winner_name := _holder_display_name(winner)
	var winner_slot := int(winner.player_index)
	var place := winners.size()
	var results := _build_ranking_results()
	NetworkManager.server_announce_winner(winner_name, winner_slot, place, false, results)


func _server_try_finish_ranking_match() -> void:
	if not _is_authoritative() or _game_over_handled:
		return
	if turn_order.size() == 1:
		var last_holder: HandCardHolder = turn_order[0]
		if last_holder != null and is_instance_valid(last_holder) and not winners.has(last_holder):
			winners.append(last_holder)
		turn_order.clear()
	if not turn_order.is_empty():
		return
	_server_handle_game_over()


func _server_handle_game_over() -> void:
	if not _is_authoritative():
		return
	if _game_over_handled:
		return
	_game_over_handled = true

	var results := _build_ranking_results()
	var winner_name := "Player"
	var winner_slot := -1
	var place := 1
	if results.size() > 0:
		var first: Dictionary = results[0]
		winner_name = str(first.get("name", "Player"))
		winner_slot = int(first.get("slot", -1))
		place = int(first.get("place", 1))
	elif winners.size() > 0 and winners[0] != null and is_instance_valid(winners[0]):
		winner_slot = int(winners[0].player_index)
		winner_name = _holder_display_name(winners[0])

	NetworkManager.server_announce_winner(winner_name, winner_slot, place, true, results)


## Shows winner overlay on all peers and pauses the scene tree (final only).
func _on_game_won(
	winner_name: String,
	winner_slot: int = -1,
	place: int = 1,
	is_final: bool = true,
	all_results: Array = []
) -> void:
	await get_tree().create_timer(0.45).timeout
	_force_clear_winner_hand(winner_slot)
	if is_final:
		var results := all_results if all_results.size() > 0 else [{
			"name": winner_name,
			"slot": winner_slot,
			"place": place,
		}]
		_show_results_overlay(results)
		get_tree().paused = true
	else:
		_show_placement_toast(winner_name, place)

## Remove every card view from the winner's seat so they visibly have no cards.
## Clears winner hand visuals on every peer after the last card animation.
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

## Host-only: remote peer left during an active match — pause and offer lobby return.
func on_remote_peer_left_during_match() -> void:
	if !multiplayer.is_server() or _opponent_left_overlay_shown:
		return
	_opponent_left_overlay_shown = true
	_show_feedback("Gegner hat Verbindung verloren", Signals.FeedbackKind.BLOCKED)
	_show_opponent_left_overlay()


func _show_opponent_left_overlay() -> void:
	if _winner_overlay != null and is_instance_valid(_winner_overlay):
		return

	var layer := CanvasLayer.new()
	layer.layer = 127
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var label := Label.new()
	label.text = "Ein Spieler hat die Verbindung verloren."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	vbox.add_child(label)

	var btn := Button.new()
	btn.text = "Zurück zur Lobby"
	btn.custom_minimum_size = Vector2(360, 64)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_size_override("font_size", 28)
	btn.pressed.connect(_on_opponent_left_lobby_pressed)
	vbox.add_child(btn)

	get_tree().root.add_child(layer)
	_winner_overlay = layer


func _on_opponent_left_lobby_pressed() -> void:
	if _lobby_return_requested:
		return
	_lobby_return_requested = true
	NetworkManager.server_return_to_lobby()


## Zurück in die Lobby (Verbindung bleibt bestehen)
## Unpauses and navigates back to steam_lobby_room while keeping connection.
func _on_return_to_lobby() -> void:
	print("QueueManager: _on_return_to_lobby fired is_server=%s match_started=%s deal_progress=%s deal_complete=%s" % [
		str(multiplayer.is_server()), str(_client_match_started),
		str(_match_deal_in_progress), str(_match_deal_complete)])
	get_tree().paused = false
	_lobby_return_requested = false
	_opponent_left_overlay_shown = false
	_hide_winner_overlay()
	_hide_placement_toast()
	_hide_loser_overlay()
	_local_loser_overlay_shown = false
	NetworkManager.mark_rejoin_from_match()
	Globals.change_scene_file("res://Scenes/UI/steam_lobby_room.tscn")

## Called when the ENet/Steam connection drops while in the match scene.
## Returns the client to the lobby hub since the game is unplayable without the host.
func _on_host_disconnected_during_match() -> void:
	if multiplayer.is_server():
		return
	print("QueueManager: host disconnected during match — returning to lobby")
	_on_return_to_lobby()

## Creates full-screen final results overlay with all placements.
func _show_results_overlay(results: Array) -> void:
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
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "🏆 MATCH RESULTS 🏆"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	for entry in results:
		if not (entry is Dictionary):
			continue
		var place_num := int(entry.get("place", 0))
		var suffix := _place_suffix(place_num)
		var row := Label.new()
		row.text = "%d%s – %s" % [place_num, suffix, str(entry.get("name", "Player"))]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 36 if place_num == 1 else 28)
		if place_num == 1:
			row.modulate = Color(1.0, 0.9, 0.4)
		vbox.add_child(row)

	var btn := Button.new()
	btn.text = "Zurück zur Lobby"
	btn.custom_minimum_size = Vector2(380, 70)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_size_override("font_size", 32)
	var btn_normal := load("res://Themes/ui_button.tres") as StyleBox
	var btn_hover := load("res://Themes/ui_button_hover.tres") as StyleBox
	var btn_pressed := load("res://Themes/ui_button_pressed.tres") as StyleBox
	if btn_normal:
		btn.add_theme_stylebox_override("normal", btn_normal)
	if btn_hover:
		btn.add_theme_stylebox_override("hover", btn_hover)
	if btn_pressed:
		btn.add_theme_stylebox_override("pressed", btn_pressed)
	btn.pressed.connect(_on_results_lobby_button_pressed)
	vbox.add_child(btn)

	get_tree().root.add_child(layer)
	_winner_overlay = layer


func _on_results_lobby_button_pressed() -> void:
	if _lobby_return_requested:
		return
	_lobby_return_requested = true

	if not multiplayer.has_multiplayer_peer():
		_on_return_to_lobby()
		return
	if multiplayer.is_server():
		NetworkManager.server_return_to_lobby()
	else:
		NetworkManager.request_return_to_lobby()


func _place_suffix(place: int) -> String:
	match place:
		1: return "st"
		2: return "nd"
		3: return "rd"
		_: return "th"


## Brief non-blocking toast when a player secures a place in full-ranking mode.
func _show_placement_toast(player_name: String, place: int) -> void:
	_hide_placement_toast()

	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 80.0
	panel.custom_minimum_size = Vector2(520, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var label := Label.new()
	label.text = "%s – %d%s place!" % [player_name, place, _place_suffix(place)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	margin.add_child(label)

	get_tree().root.add_child(layer)
	layer.add_child(panel)
	_placement_toast = layer

	var timer := get_tree().create_timer(2.0, true)
	timer.timeout.connect(_hide_placement_toast)


func _hide_placement_toast() -> void:
	if _placement_toast != null and is_instance_valid(_placement_toast):
		_placement_toast.queue_free()
	_placement_toast = null


## Creates full-screen winner overlay with name and lobby-return hint.
func _show_winner_overlay(winner_name: String) -> void:
	_show_results_overlay([{"name": winner_name, "slot": -1, "place": 1}])

## Removes winner overlay if present.
func _hide_winner_overlay() -> void:
	if _winner_overlay != null and is_instance_valid(_winner_overlay):
		_winner_overlay.queue_free()
	_winner_overlay = null


## True while match results block normal pause-menu input.
func is_results_screen_visible() -> bool:
	return _winner_overlay != null and is_instance_valid(_winner_overlay)

## Shows local elimination overlay when max-card rule triggers on this peer.
func _show_loser_overlay() -> void:
	if _local_loser_overlay_shown:
		return
	_local_loser_overlay_shown = true
	_hide_loser_overlay()
	_ensure_active_deck_on_card_manager()

	var max_count := get_max_card_lose_count()
	var layer := CanvasLayer.new()
	layer.layer = 127
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "YOU LOSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.35, 0.35)
	vbox.add_child(title)

	var reason := Label.new()
	reason.text = "You reached %d cards and were eliminated." % max_count
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.add_theme_font_size_override("font_size", 28)
	vbox.add_child(reason)

	var hint := Label.new()
	hint.text = "You can watch the rest of the match."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(hint)

	var spectate_btn := Button.new()
	spectate_btn.text = "Spectate"
	spectate_btn.custom_minimum_size = Vector2(320, 64)
	spectate_btn.pressed.connect(_dismiss_loser_overlay_for_spectate)
	vbox.add_child(spectate_btn)

	get_tree().root.add_child(layer)
	_loser_overlay = layer

## Dismisses loser overlay so the eliminated player can spectate.
func _dismiss_loser_overlay_for_spectate() -> void:
	_hide_loser_overlay()

## Removes loser overlay if present.
func _hide_loser_overlay() -> void:
	if _loser_overlay != null and is_instance_valid(_loser_overlay):
		_loser_overlay.queue_free()
	_loser_overlay = null

## Reverse direction
func apply_reverse() -> void:
	direction *= -1
	Signals.MATCH_direction_changed.emit(direction)
	_show_direction_reversed_feedback()
	# Synchronize direction change
	if multiplayer.is_server():
		_server_sync_match_state()


## Popup when play direction reverses (Reverse card).
func _show_direction_reversed_feedback() -> void:
	var text := "Direction reversed"
	if turn_order.size() == 2:
		text = "Reverse!"
	_show_feedback(text, Signals.FeedbackKind.REVERSE)


## Shows a gameplay feedback popup locally or via server RPC in multiplayer.
func _show_feedback(text: String, kind: int, target_slot: int = -1) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		NetworkManager.server_show_feedback(text, kind, target_slot)
	else:
		Signals.FEEDBACK_show.emit(text, kind)

## Resets all draw-stack tracking fields.
func _clear_draw_stack() -> void:
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	draw_stack_source_slot = -1
	_draw_stack_resolving = false


## Draw stack add/stack
func start_or_stack_draw(value: int, is_wild: bool, min_card_value: int = -1, stacker: HandCardHolder = null) -> void:
	draw_stack_amount += value
	var card_min := min_card_value if min_card_value >= 0 else value
	draw_stack_min_value = max(draw_stack_min_value, card_min)
	var who := stacker if stacker != null else get_current_holder()
	if who != null:
		draw_stack_source_slot = int(who.player_index)
	if is_wild:
		draw_stack_is_wild = true
		if card_manager != null:
			draw_stack_color = card_manager.current_color
	elif card_manager != null and card_manager.top_card != null:
		draw_stack_color = card_manager.top_card.color


## Ends the turn after a +draw card; sync happens in next_turn().
func _advance_turn_after_draw_penalty() -> void:
	end_turn()


## True when this holder played the last +draw stack card.
func _holder_is_draw_stack_source(holder: HandCardHolder) -> bool:
	if holder == null or draw_stack_source_slot < 0:
		return false
	return int(holder.player_index) == draw_stack_source_slot

## The stack source must never resolve their own penalty (even if end_turn failed).
func _holder_blocked_from_resolving_draw_stack(holder: HandCardHolder) -> bool:
	return _holder_is_draw_stack_source(holder)

## If the stack source still holds the turn, advance it (end_turn was skipped).
func _try_recover_draw_stack_source_turn(holder: HandCardHolder) -> bool:
	if draw_stack_amount <= 0:
		return false
	if !_holder_is_draw_stack_source(holder):
		return false
	end_turn()
	return true

var _draw_stack_resolving := false

## Accepts an active +draw stack penalty for the current holder (single-flight).
func _accept_draw_stack_penalty(holder: HandCardHolder) -> void:
	if _draw_stack_resolving:
		return
	if holder == null or !is_instance_valid(holder):
		return
	if draw_stack_amount <= 0:
		return
	if !is_players_turn(holder):
		return
	if has_drawn_this_turn or has_played_this_turn:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return
	if roulette_active or place_all_resolving:
		return
	if _holder_blocked_from_resolving_draw_stack(holder):
		return

	_draw_stack_resolving = true
	if draw_stack_is_wild:
		await force_wild_draw_continue(holder)
	else:
		await force_draw_stack_continue(holder)
	_draw_stack_resolving = false
	if _is_authoritative():
		_server_sync_holder_hand(holder, false)

## Resolves an active draw stack for the current holder when they cannot counter-stack.
func _resolve_draw_stack_for_holder(holder: HandCardHolder) -> void:
	if _draw_stack_resolving:
		return
	if holder == null or !is_instance_valid(holder):
		return
	if draw_stack_amount <= 0:
		return
	if !is_players_turn(holder):
		return
	if has_drawn_this_turn or has_played_this_turn:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return
	if roulette_active or place_all_resolving:
		return
	if _holder_blocked_from_resolving_draw_stack(holder):
		return
	if holder_has_playable_card(holder):
		holder.refresh_playable_cards()
		return

	await _accept_draw_stack_penalty(holder)


## Returns how many cards the current +draw play adds to the active stack.
func _draw_stack_value_for_play(played_card: CardResource) -> int:
	if played_card == null:
		return 0
	return played_card.value

## Max-card-lose rule helpers (configured on DeckResource).
func _resolve_active_deck() -> DeckResource:
	var path := str(NetworkManager.lobby_deck_path)
	if path != "":
		if NetworkManager.lobby_deck_override_path == path and NetworkManager.lobby_deck_override != null:
			return NetworkManager.lobby_deck_override.duplicate(true)
		var chosen := Globals.load_deck(path)
		if chosen != null:
			return chosen.duplicate(true)
	if card_manager != null and card_manager.loaded_deck != null:
		return card_manager.loaded_deck
	return null

func _ensure_active_deck_on_card_manager() -> void:
	if card_manager == null:
		return
	var deck := _resolve_active_deck()
	if deck != null:
		card_manager.loaded_deck = deck

func is_max_card_lose_enabled() -> bool:
	var deck := _resolve_active_deck()
	if deck == null:
		return false
	return deck.max_card_lose_enabled

func get_max_card_lose_count() -> int:
	var deck := _resolve_active_deck()
	if deck == null:
		return 0
	return maxi(1, deck.max_card_lose_count)

func on_holder_hand_changed(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder):
		return
	if !_is_authoritative():
		return
	if _match_deal_in_progress:
		return
	_check_max_card_lose(holder)

func _check_max_card_lose(holder: HandCardHolder) -> bool:
	if holder == null or !is_max_card_lose_enabled():
		return false
	if is_holder_eliminated(holder):
		return false
	if _count_cards_in_holder(holder) < get_max_card_lose_count():
		return false
	_eliminate_holder_for_max_cards(holder)
	return true

## Runs max-card elimination before end_turn so deferred hand callbacks cannot double-advance.
func _try_eliminate_holder_for_max_cards(holder: HandCardHolder) -> bool:
	if !_is_authoritative():
		return is_holder_eliminated(holder)
	return _check_max_card_lose(holder)

func _finish_draw_turn_if_needed(holder: HandCardHolder) -> void:
	if is_holder_eliminated(holder):
		return
	if _try_eliminate_holder_for_max_cards(holder):
		return
	end_turn()

func _eliminate_holder_for_max_cards(holder: HandCardHolder) -> void:
	if !_is_authoritative():
		return
	if holder == null or is_holder_eliminated(holder):
		return
	var slot := int(holder.player_index)
	if multiplayer.has_multiplayer_peer():
		NetworkManager.rpc("client_on_player_eliminated", slot)
	else:
		_on_player_eliminated(slot)

func _on_player_eliminated(slot: int) -> void:
	_apply_player_eliminated_slot(int(slot), true)

## Computes the active turn index after one player leaves turn_order.
func _turn_index_after_player_removed(
	removed_index: int, old_size: int, old_turn_index: int
) -> int:
	var new_size := old_size - 1
	if new_size <= 0:
		return 0
	if removed_index == old_turn_index:
		var next_old := (removed_index + direction) % old_size
		if next_old < 0:
			next_old += old_size
		var new_index := next_old
		if next_old > removed_index:
			new_index = next_old - 1
		return clampi(new_index, 0, new_size - 1)
	var new_index := old_turn_index
	if removed_index < old_turn_index:
		new_index -= 1
	return clampi(new_index, 0, new_size - 1)

## Applies max-card elimination: remove from turn order and update UI.
func _apply_player_eliminated_slot(slot: int, show_local_lose_ui: bool) -> void:
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or !is_instance_valid(holder):
		return
	if is_holder_eliminated(holder):
		_finalize_eliminated_holder_ui(holder, show_local_lose_ui)
		return

	max_card_losers.append(holder)
	_recycle_eliminated_holder_cards(holder)
	_clear_blocking_state_for_holder(holder)

	var was_current_turn := false
	var removed_index := turn_order.find(holder)
	if removed_index >= 0:
		var old_size := turn_order.size()
		var old_turn_index := current_turn_index
		was_current_turn = removed_index == old_turn_index
		turn_order.remove_at(removed_index)
		if turn_order.is_empty():
			if _is_authoritative():
				_check_max_card_lose_winner()
			_finalize_eliminated_holder_ui(holder, show_local_lose_ui)
			return
		current_turn_index = _turn_index_after_player_removed(
			removed_index, old_size, old_turn_index
		)
		if was_current_turn:
			has_played_this_turn = false
			has_drawn_this_turn = false

	_finalize_eliminated_holder_ui(holder, show_local_lose_ui)

	if _is_authoritative():
		_check_max_card_lose_winner()
		_server_broadcast_counts()
		_server_sync_match_state()

	if !turn_order.is_empty():
		update_turn_state()
		if card_manager != null:
			card_manager.update_draw_button_state()
		if _is_authoritative() and was_current_turn:
			call_deferred("_handle_start_of_turn_effects")

## Returns eliminated hand cards to the discard pile while keeping ghost visuals in the seat.
func _recycle_eliminated_holder_cards(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder):
		return
	if holder.get_meta("cards_recycled", false):
		return
	holder.set_meta("cards_recycled", true)

	var to_discard: Array[CardResource] = []
	for c in holder.get_children():
		if c is CardView and not c.get_meta("anim_temp", false):
			var res: CardResource = c.card_res
			if res == null or c.get_meta("eliminated_ghost", false):
				continue
			if _is_authoritative() and card_manager != null:
				to_discard.append(res)
			_set_card_view_eliminated_ghost(c as CardView, res)

	if _is_authoritative() and card_manager != null and !to_discard.is_empty():
		for res in to_discard:
			card_manager.discard_pile.append(res)
		_sync_deck_counts()


func _set_card_view_eliminated_ghost(cv: CardView, res: CardResource) -> void:
	if cv == null or res == null:
		return
	var ghost := CardResource.new()
	ghost.color = res.color
	ghost.type = res.type
	ghost.value = res.value
	ghost.uid = -maxi(1, int(res.uid))
	cv.card_res = ghost
	cv.set_meta("eliminated_ghost", true)
	cv.load_card()


## Clears in-progress special states owned by an eliminated holder.
func _clear_blocking_state_for_holder(holder: HandCardHolder) -> void:
	if holder == null:
		return
	holder._busy = false
	holder._queued = null
	holder._waiting_color_turn_end = false

	if wild_color_owner == holder:
		clear_wild_owner()
		if card_manager != null:
			card_manager.waiting_for_color = false

	if place_all_owner == holder:
		place_all_active = false
		place_all_resolving = false
		place_all_owner = null
		place_all_card = null
		_place_all_sequence_running = false

	if pending_swap_owner == holder:
		pending_swap_owner = null
		swap_color_pending = false

	if pending_target_draw_owner == holder:
		target_draw_active = false
		pending_target_draw_owner = null

	if roulette_owner == holder or roulette_target == holder:
		if _is_authoritative():
			_abort_roulette()
		else:
			roulette_active = false
			roulette_waiting_for_color = false
			roulette_owner = null
			roulette_target = null
			roulette_target_slot = -1
			roulette_step_running = false

	Signals.COLOR_color_select_dismissed.emit()

## Dims eliminated seat UI and shows lose overlay for local human.
func _finalize_eliminated_holder_ui(holder: HandCardHolder, show_local_lose_ui: bool) -> void:
	holder.set_turn_active(false)
	_dim_eliminated_holder(holder)
	var ui_container := get_container_for_holder(holder)
	if ui_container != null:
		_smooth_modulate(ui_container, Color(0.2, 0.2, 0.2, 1.0), 0.25)
	holder.refresh_playable_cards()

	if show_local_lose_ui and int(NetworkManager.my_slot) == int(holder.player_index) and !holder.is_bot:
		_dim_all_cards_for_local_loser()
		_show_loser_overlay()

func _dim_eliminated_holder(holder: HandCardHolder) -> void:
	if holder == null:
		return
	for c in holder.get_children():
		if c is CardView:
			c.set_clickable(false, true)
			_smooth_modulate(c, Color(0.15, 0.15, 0.15, 1.0), 0.25)

func _dim_all_cards_for_local_loser() -> void:
	var my_slot := int(NetworkManager.my_slot)
	var my_holder: HandCardHolder = _slot_to_holder.get(my_slot, null)
	if my_holder != null and is_instance_valid(my_holder):
		_dim_eliminated_holder(my_holder)
	if card_manager != null and card_manager.draw_button != null:
		_smooth_modulate(card_manager.draw_button, Color(0.15, 0.15, 0.15, 1.0), 0.25)

func _get_eliminated_slots() -> Array:
	var slots: Array = []
	for h in max_card_losers:
		if h != null and is_instance_valid(h):
			slots.append(int(h.player_index))
	return slots

func _sync_eliminated_slots_from_state(state: Dictionary) -> void:
	var slots: Array = state.get("eliminated_slots", [])
	for slot_val in slots:
		var show_ui := int(slot_val) == int(NetworkManager.my_slot)
		_apply_player_eliminated_slot(int(slot_val), show_ui)


## Rebuilds client turn order when winners/eliminations shrink the active player list.
func _apply_active_turn_order_from_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	if !state.has("active_turn_slots"):
		return
	var slots: Array = state.get("active_turn_slots", [])
	if slots.is_empty():
		return
	var rebuilt: Array[HandCardHolder] = []
	for slot_val in slots:
		var h: HandCardHolder = _slot_to_holder.get(int(slot_val), null)
		if h != null and is_instance_valid(h) and !is_holder_eliminated(h) and !is_holder_finished(h):
			rebuilt.append(h)
	if rebuilt.is_empty():
		return
	turn_order = rebuilt
	_apply_turn_index_from_state(state)

func _apply_turn_index_from_state(state: Dictionary) -> void:
	if turn_order.is_empty():
		return
	var server_turn_index := int(state.get("turn_index", current_turn_index))
	var wild_slot := int(state.get("wild_owner_slot", -1))
	var needs_color := bool(state.get("waiting_for_color", false)) \
		or bool(state.get("swap_color_pending", false))
	if !multiplayer.is_server() and wild_slot >= 0 and needs_color:
		var owner: HandCardHolder = _slot_to_holder.get(wild_slot, null)
		if owner != null and turn_order.has(owner):
			current_turn_index = turn_order.find(owner)
			return
	if !multiplayer.is_server():
		var my_holder := _get_local_holder()
		if my_holder != null and my_holder._busy and !_is_server_turn_index_for_local(server_turn_index):
			return
	current_turn_index = clampi(server_turn_index, 0, turn_order.size() - 1)

func _is_server_turn_index_for_local(turn_idx: int) -> bool:
	var my_slot := int(NetworkManager.my_slot)
	if my_slot < 0 or turn_idx < 0 or turn_idx >= turn_order.size():
		return false
	return int(turn_order[turn_idx].player_index) == my_slot

func _check_max_card_lose_winner() -> void:
	if !is_max_card_lose_enabled():
		return
	if turn_order.size() != 1:
		return
	var winner := turn_order[0]
	if winner == null or !is_instance_valid(winner):
		return
	if winners.has(winner):
		return
	winners.append(winner)
	if _is_authoritative():
		if _is_full_ranking_mode():
			_server_on_new_winner()
			_server_try_finish_ranking_match()
		else:
			_server_handle_game_over()

## Human draw action
func on_draw_pressed() -> void:
	var holder := get_current_holder()
	if holder == null:
		return
	if is_holder_eliminated(holder) or is_holder_finished(holder):
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
		if _try_recover_draw_stack_source_turn(holder):
			return
		if _holder_blocked_from_resolving_draw_stack(holder):
			return
		await _accept_draw_stack_penalty(holder)
		if _is_authoritative():
			_server_sync_match_state()
		return

	# Server-side or offline draw
	var card := card_manager.draw_card()
	if card == null:
		_try_pass_if_stuck(holder)
		return

	notify_card_drawn(int(holder.player_index), 1, true, card)
	holder.add_card(card, true)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	if !allow_play_after_draw:
		_finish_draw_turn_if_needed(holder)
		return

	await get_tree().create_timer(0.25).timeout
	if is_holder_eliminated(holder):
		return
	if _try_eliminate_holder_for_max_cards(holder):
		return
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
		return _try_pass_if_stuck(holder)

	notify_card_drawn(int(holder.player_index), 1, true, card)
	holder.add_card(card, true)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	return true

## End turn
func end_turn() -> void:
	# Place-all runs as an async server sequence; block premature end_turn calls
	# (e.g. legacy bot finisher logic) so the turn is not advanced twice.
	if place_all_resolving or _place_all_sequence_running:
		return
	if _blocks_turn_advance():
		var pending := _get_pending_turn_holder()
		if pending != null:
			_restore_turn_to_holder(pending)
		return
	next_turn()

## Next turn logic
func next_turn(skip_next: bool = false) -> void:
	if !skip_next and _blocks_turn_advance():
		var pending := _get_pending_turn_holder()
		if pending != null:
			_restore_turn_to_holder(pending)
		return
	if turn_order.size() == 0:
		return
	if turn_order.size() == 1:
		current_turn_index = 0
		has_played_this_turn = false
		has_drawn_this_turn = false
		update_turn_state()
		if multiplayer.is_server():
			_server_sync_match_state()
		if _is_authoritative():
			call_deferred("_handle_start_of_turn_effects")
		return

	var steps := 1
	if skip_next:
		steps = 2

	current_turn_index = (current_turn_index + direction * steps) % turn_order.size()
	if current_turn_index < 0:
		current_turn_index += turn_order.size()

	has_played_this_turn = false
	has_drawn_this_turn = false
	if card_manager != null and wild_color_owner == null and !swap_color_pending:
		card_manager.waiting_for_color = false
	update_turn_state()
	
	# Synchronize turn change to all clients
	if multiplayer.is_server():
		_server_sync_match_state()
	
	call_deferred("_handle_start_of_turn_effects")

## Turn UI update
func update_turn_state() -> void:
	for holder in max_card_losers:
		if holder == null or !is_instance_valid(holder):
			continue
		holder.set_turn_active(false)
		_dim_eliminated_holder(holder)
		var eliminated_ui := get_container_for_holder(holder)
		if eliminated_ui != null:
			_smooth_modulate(eliminated_ui, Color(0.2, 0.2, 0.2, 1.0), 0.25)

	for holder in winners:
		if holder == null or !is_instance_valid(holder):
			continue
		if turn_order.has(holder):
			continue
		_finalize_finished_holder_ui(holder)

	for holder in turn_order:
		var active := is_players_turn(holder)
		holder.set_turn_active(active)

		var ui_container := get_container_for_holder(holder)
		if ui_container != null:
			var target_color := Color.WHITE if active else Color(0.35, 0.35, 0.35, 1.0)
			_smooth_modulate(ui_container, target_color, 0.25)

	Signals.TURN_changed.emit(get_current_holder())

## Round-robin deal: one card per player each round, parallel fly within a round.
func deal_starting_cards(cards_per_player: int = 7) -> void:
	if card_manager == null:
		return

	_cleanup_deal_overlay_cards()
	for holder in turn_order:
		_clear_holder_hand(holder)

	_last_hand_counts.clear()
	_sync_deck_counts()

	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_server_broadcast_deal_begin()

	for round_i in range(cards_per_player):
		var batch: Array = []
		for holder in turn_order:
			if holder == null or !is_instance_valid(holder):
				continue
			var card := card_manager.draw_card()
			if card == null:
				break
			batch.append([holder, card])
		if batch.is_empty():
			break
		if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
			_server_broadcast_deal_batch(batch)
		await _animate_deal_batch(batch)
		_sync_deck_counts()
		if round_i < cards_per_player - 1:
			await get_tree().create_timer(DEAL_CARD_GAP).timeout

	for holder in turn_order:
		if holder == null or !is_instance_valid(holder):
			continue
		holder.sort_cards_full()
		holder.refresh_playable_cards()

	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_server_broadcast_dealing_finished()

func _server_broadcast_deal_begin() -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	for peer_id in multiplayer.get_peers():
		NetworkManager.rpc_id(int(peer_id), "client_begin_dealing", NetworkManager.match_epoch)

func _server_broadcast_deal_batch(batch: Array) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	for peer_id in multiplayer.get_peers():
		var pid := int(peer_id)
		var peer_slot := int(_peer_to_slot.get(pid, -1))
		var payload: Array = []
		for entry in batch:
			if entry.size() < 2:
				continue
			var holder: HandCardHolder = entry[0]
			var card: CardResource = entry[1]
			if holder == null or card == null:
				continue
			var slot := int(holder.player_index)
			var item: Dictionary = {"slot": slot}
			if !holder.is_bot and slot == peer_slot:
				item["card"] = _serialize_card(card)
			payload.append(item)
		if payload.size() > 0:
			NetworkManager.rpc_id(pid, "client_deal_batch", payload, NetworkManager.match_epoch)

func _server_broadcast_dealing_finished() -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	for peer_id in multiplayer.get_peers():
		NetworkManager.rpc_id(int(peer_id), "client_dealing_finished", NetworkManager.match_epoch)

func _on_deal_begin_received() -> void:
	if multiplayer.is_server():
		return
	if turn_order.is_empty():
		# turn_order not ready yet — defer and wait. Don't touch the batch queue;
		# batches may already be queued and must not be discarded on retry.
		if _match_deal_in_progress or _match_deal_complete:
			return  # deal already running or finished via a parallel path — stop looping
		call_deferred("_on_deal_begin_received")
		return
	# Guard against double-init (signal fired twice or deferred retry after deal already started).
	if _match_deal_in_progress or _match_deal_complete:
		return
	_match_deal_in_progress = true
	_match_deal_complete = false
	_client_deal_animating = true
	# Preserve any batches already queued (arrived before turn_order was ready).
	_client_deal_batch_running = false
	_pending_hand.clear()
	_cleanup_deal_overlay_cards()
	for holder in turn_order:
		_clear_holder_hand(holder)
	# Kick off processing of any batches that arrived before this setup ran.
	call_deferred("_try_run_client_deal_batch_queue")

func _on_deal_batch_received(batch: Array) -> void:
	if multiplayer.is_server():
		return
	_client_deal_batch_queue.append(batch)
	# Only trigger immediately if deal has already begun; otherwise the
	# deferred retry in _on_deal_begin_received will kick the queue.
	if _match_deal_in_progress:
		call_deferred("_try_run_client_deal_batch_queue")

func _try_run_client_deal_batch_queue() -> void:
	if _client_deal_batch_running or _client_deal_batch_queue.is_empty():
		return
	call_deferred("_run_client_deal_batch_queue")

func _run_client_deal_batch_queue() -> void:
	if _client_deal_batch_running:
		return
	_client_deal_batch_running = true
	_client_deal_animating = true
	while _client_deal_batch_queue.size() > 0:
		if !is_instance_valid(self) or !is_inside_tree():
			break
		var batch: Array = _client_deal_batch_queue.pop_front()
		await _client_animate_deal_batch(batch)
		if !is_instance_valid(self) or !is_inside_tree():
			break
		if _client_deal_batch_queue.size() > 0:
			await get_tree().create_timer(DEAL_CARD_GAP).timeout
	_client_deal_batch_running = false
	if !_match_deal_in_progress:
		_schedule_client_deal_finish()

func _schedule_client_deal_finish() -> void:
	if _client_deal_finish_scheduled:
		return
	_client_deal_finish_scheduled = true
	call_deferred("_finish_client_deal_when_ready")

func _finish_client_deal_when_ready() -> void:
	_client_deal_finish_scheduled = false
	if multiplayer.is_server():
		return
	if _match_deal_in_progress:
		return
	if _client_deal_batch_running or !_client_deal_batch_queue.is_empty():
		_schedule_client_deal_finish()
		return
	_client_deal_animating = false
	_client_deal_batch_queue.clear()
	_try_apply_pending_hand()
	_try_apply_pending_match_state()
	_apply_counts_to_ui()
	_apply_local_visibility()
	call_deferred("_client_request_hand_resync_if_desynced")

func _on_dealing_finished_received() -> void:
	if multiplayer.is_server():
		return
	_match_deal_in_progress = false
	_match_deal_complete = true
	_schedule_client_deal_finish()

func _client_animate_deal_batch(batch: Array) -> void:
	if card_manager == null or batch.is_empty():
		return
	var deck_anchor := card_manager.get_draw_deck_anchor_global()
	var slides: Array[CardView] = []
	var touched: Array[HandCardHolder] = []
	var my_slot := int(NetworkManager.my_slot)

	for item in batch:
		if not (item is Dictionary):
			continue
		var slot := int(item.get("slot", -1))
		var holder: HandCardHolder = _slot_to_holder.get(slot, null)
		if holder == null or !is_instance_valid(holder):
			continue
		var card_data = item.get("card", null)
		var res: CardResource
		var show_front := false
		if card_data is Dictionary and CardResource.sync_dict_has_identity(card_data):
			res = CardResource.from_sync_dict(card_data)
			show_front = slot == my_slot
		else:
			res = _make_dummy_deal_card()
		var cv := holder.add_card_for_deal(res, show_front)
		if cv != null:
			slides.append(cv)
			if !touched.has(holder):
				touched.append(holder)

	if slides.is_empty():
		return

	for _i in range(4):
		if !is_instance_valid(self) or !is_inside_tree():
			return
		await get_tree().process_frame

	if !is_instance_valid(self) or !is_inside_tree():
		return

	SoundManager.play_draw_card(slides.size())
	for cv in slides:
		if cv != null and is_instance_valid(cv) and cv.has_method("deal_slide_in"):
			cv.deal_slide_in(deck_anchor, DEAL_CARD_DURATION)

	if !is_instance_valid(self) or !is_inside_tree():
		return
	await get_tree().create_timer(DEAL_CARD_DURATION + 0.02).timeout

	if !is_instance_valid(self) or !is_inside_tree():
		return
	for holder in touched:
		if holder != null and is_instance_valid(holder):
			holder.sort_cards_full()
			holder.refresh_playable_cards()

func _clear_holder_hand(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder):
		return
	for c in holder.get_children():
		if c is CardView:
			if c.get_parent() == holder:
				holder.remove_child(c)
			c.queue_free()

func _should_show_dealt_card_front(holder: HandCardHolder) -> bool:
	if holder.is_bot:
		return false
	if !multiplayer.has_multiplayer_peer():
		return true
	return int(holder.player_index) == int(NetworkManager.my_slot)

func _make_dummy_deal_card() -> CardResource:
	var dummy := CardResource.new()
	dummy.color = CardResource.CardColor.BLACK
	dummy.type = CardResource.CardType.NUMBER
	dummy.value = 0
	dummy.uid = 0
	return dummy

func _animate_deal_batch(batch: Array) -> void:
	var deck_anchor := card_manager.get_draw_deck_anchor_global()
	var slides: Array[CardView] = []
	for entry in batch:
		var holder: HandCardHolder = entry[0]
		var card: CardResource = entry[1]
		if holder == null or card == null:
			continue
		var show_front := _should_show_dealt_card_front(holder)
		var cv := holder.add_card_for_deal(card, show_front)
		if cv != null:
			slides.append(cv)
	if slides.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	SoundManager.play_draw_card(slides.size())
	for cv in slides:
		if cv != null and is_instance_valid(cv) and cv.has_method("deal_slide_in"):
			cv.deal_slide_in(deck_anchor, DEAL_CARD_DURATION)
	await get_tree().create_timer(DEAL_CARD_DURATION + 0.02).timeout
	for entry in batch:
		var holder: HandCardHolder = entry[0]
		if holder != null and is_instance_valid(holder):
			holder.refresh_playable_cards()

func _animate_deal_card_to_holder(holder: HandCardHolder, card: CardResource, play_sound: bool = true) -> void:
	if holder == null or !is_instance_valid(holder) or card_manager == null:
		return
	var show_front := _should_show_dealt_card_front(holder)
	var cv := holder.add_card_for_deal(card, show_front)
	await get_tree().process_frame
	await get_tree().process_frame
	if cv == null or !is_instance_valid(cv):
		return
	if play_sound:
		SoundManager.play_draw_card(1)
	var deck_anchor := card_manager.get_draw_deck_anchor_global()
	if cv.has_method("deal_slide_in"):
		await cv.deal_slide_in(deck_anchor, DEAL_CARD_DURATION)
	if is_instance_valid(holder):
		holder.refresh_playable_cards()

func _reveal_hand_animated(holder: HandCardHolder, hand: Array) -> void:
	if holder == null or card_manager == null:
		return
	_client_deal_animating = true
	_cleanup_deal_overlay_cards()
	SoundManager.play_draw_card(hand.size())
	for i in range(hand.size()):
		var entry: Variant = hand[i]
		if not (entry is Dictionary):
			continue
		var res := CardResource.from_sync_dict(entry)
		await _animate_deal_card_to_holder(holder, res, false)
		if i < hand.size() - 1:
			await get_tree().create_timer(DEAL_CARD_GAP).timeout
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	_client_deal_animating = false

func _cleanup_deal_overlay_cards() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var layer := scene.get_node_or_null("CanvasLayer")
	if layer == null:
		return
	for child in layer.get_children():
		if child is CardView and child.in_hand_card and child.hand_card_holder != null:
			var holder: HandCardHolder = child.hand_card_holder
			if holder != null and is_instance_valid(holder):
				layer.remove_child(child)
				child.top_level = false
				holder.add_child(child)
				if child.has_method("_snap_rest_pose"):
					child._snap_rest_pose()

## Playable check
func holder_has_playable_card(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	for c in holder.get_children():
		if c is CardView and holder.can_play_card(c.card_res):
			return true
	return false

## True when at least one card can still be drawn (deck or refillable discard).
func can_draw_from_pile() -> bool:
	if card_manager == null:
		return false
	if card_manager.deck.size() > 0:
		return true
	return card_manager.get_discard_size() > 1

## Pass the turn when the player cannot play and the draw pile is exhausted.
func _try_pass_if_stuck(holder: HandCardHolder) -> bool:
	if holder == null:
		return false
	# Humans must never be auto-passed — only bots use recovery pass logic.
	if !holder.is_bot:
		return false
	if has_played_this_turn:
		if _holder_has_active_sub_effect(holder):
			return false
		if draw_stack_amount > 0:
			return false
		if card_manager != null and card_manager.waiting_for_color:
			return false
		if roulette_active or place_all_resolving or _place_all_sequence_running:
			return false
		end_turn()
		return true
	if draw_stack_amount > 0:
		return false
	if card_manager != null and card_manager.waiting_for_color:
		return false
	if roulette_active or place_all_resolving:
		return false
	if holder_has_playable_card(holder):
		return false
	if can_draw_from_pile():
		return false
	has_drawn_this_turn = true
	end_turn()
	return true

## True while an async draw-stack resolve should still advance this holder's turn.
func _is_holder_still_resolving_draw_stack(holder: HandCardHolder) -> bool:
	if holder == null or !is_instance_valid(holder):
		return false
	if is_holder_eliminated(holder) or is_holder_finished(holder):
		return false
	return get_current_holder() == holder

## Ensures the active bot resolves draw stacks even after eliminations reshuffle turn order.
func _kick_bot_turn_if_needed(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder) or !holder.is_bot:
		return
	if !_is_authoritative():
		return
	if get_current_holder() != holder:
		return
	if draw_stack_amount <= 0:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return
	if place_all_resolving or _place_all_sequence_running or roulette_active:
		return
	var ki := _get_ki_for_holder(holder)
	if ki != null and !ki.is_play_turn_running():
		ki.play_turn()

## True while a holder is inside swap, wild-color, target-draw, or place-all resolution.
func _holder_has_active_sub_effect(holder: HandCardHolder) -> bool:
	if holder == null or !is_instance_valid(holder):
		return false
	if pending_swap_owner == holder or _swap_resolve_running:
		return true
	if swap_color_pending and wild_color_owner == holder:
		return true
	if card_manager != null and card_manager.waiting_for_color and wild_color_owner == holder:
		return true
	if target_draw_active and pending_target_draw_owner == holder:
		return true
	if place_all_active and place_all_owner == holder:
		return true
	if place_all_resolving or _place_all_sequence_running:
		return true
	if roulette_active:
		return true
	return false


## Recover when has_played is set but no sub-effect is running anymore.
func _try_recover_stuck_turn(holder: HandCardHolder) -> void:
	if !_is_authoritative() or holder == null or !is_instance_valid(holder):
		return
	if !holder.is_bot:
		return
	if !is_players_turn(holder) or !has_played_this_turn:
		return
	if _holder_has_active_sub_effect(holder):
		return
	if draw_stack_amount > 0:
		return
	if _draw_stack_resolving:
		return
	if card_manager != null and card_manager.waiting_for_color:
		return
	if card_manager != null and card_manager.top_card != null:
		if card_manager.top_card.type == CardResource.CardType.SWAP_HANDS:
			call_deferred("_try_recover_stuck_swap", holder)
			return
		var uid := int(card_manager.top_card.uid)
		if uid > 0 and !_resolved_effect_uids.has(uid) and _can_resolve_card_effect(card_manager.top_card):
			register_card_play(card_manager.top_card, holder)
			return
	holder._busy = false
	end_turn()


## Start-of-turn effects
func _handle_start_of_turn_effects() -> void:
	if !_is_authoritative():
		return
	if multiplayer.is_server() and !_match_deal_complete:
		return
	if place_all_resolving:
		return
	if _place_all_sequence_running:
		return

	if roulette_active:
		_handle_roulette_start()
		return

	var pending_holder := _get_pending_turn_holder()
	if pending_holder != null:
		_restore_turn_to_holder(pending_holder)
		call_deferred("_resume_pending_effect_for_holder", pending_holder)
		return

	var holder := get_current_holder()
	if holder == null:
		return

	if _try_finish_empty_hand(holder):
		return

	if draw_stack_amount > 0:
		if _try_recover_draw_stack_source_turn(holder):
			return
		if holder.is_bot:
			call_deferred("_kick_bot_turn_if_needed", holder)
		else:
			holder.refresh_playable_cards()
			if card_manager != null:
				card_manager.update_draw_button_state()
		return

	if holder.is_bot and _try_pass_if_stuck(holder):
		return

	if holder.is_bot:
		if swap_color_pending and wild_color_owner == holder:
			call_deferred("_finish_bot_swap_color", holder)
			return
		if card_manager != null and card_manager.waiting_for_color and wild_color_owner == holder:
			call_deferred("_ensure_wild_color_resolved", holder)
			return
		if has_played_this_turn and _is_unresolved_swap_for_holder(holder):
			call_deferred("_try_recover_stuck_swap", holder)
			return
		if has_played_this_turn:
			call_deferred("_try_recover_stuck_turn", holder)
			return
		if has_drawn_this_turn and !has_played_this_turn:
			var ki_after_draw := _get_ki_for_holder(holder)
			if ki_after_draw != null and !ki_after_draw.is_play_turn_running():
				ki_after_draw.play_turn()
			return
		if !has_drawn_this_turn:
			var ki := _get_ki_for_holder(holder)
			if ki != null and !ki.is_play_turn_running():
				ki.play_turn()

## Force wild draw resolve
func force_wild_draw_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		notify_card_drawn(int(holder.player_index), 1, false, card)
		holder.add_card(card, true)

	_clear_draw_stack()

	_sync_deck_counts()
	# Synchronize draw stack reset
	if multiplayer.is_server():
		_server_sync_match_state()

	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	await get_tree().create_timer(0.25).timeout
	if !_is_holder_still_resolving_draw_stack(holder):
		return
	if is_holder_eliminated(holder):
		return
	if _try_eliminate_holder_for_max_cards(holder):
		return
	if !holder_has_playable_card(holder):
		end_turn()
	if multiplayer.is_server():
		_server_sync_holder_hand(holder, false)

## Force draw stack resolve
func force_draw_stack_continue(holder: HandCardHolder) -> void:
	for i in range(draw_stack_amount):
		var card := card_manager.draw_card()
		if card == null:
			break
		notify_card_drawn(int(holder.player_index), 1, false, card)
		holder.add_card(card, true)

	_clear_draw_stack()

	_sync_deck_counts()
	# Synchronize draw stack reset
	if multiplayer.is_server():
		_server_sync_match_state()

	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true

	await get_tree().create_timer(0.25).timeout
	if !_is_holder_still_resolving_draw_stack(holder):
		return
	if is_holder_eliminated(holder):
		return
	if _try_eliminate_holder_for_max_cards(holder):
		return
	if !holder_has_playable_card(holder):
		end_turn()
	if multiplayer.is_server():
		_server_sync_holder_hand(holder, false)

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
	if _count_cards_in_holder(holder) > 0:
		return false

	winners.append(holder)

	var removed_index := current_turn_index
	var old_size := turn_order.size()
	var old_turn_index := current_turn_index
	turn_order.remove_at(removed_index)

	if turn_order.size() == 0:
		return true

	current_turn_index = _turn_index_after_player_removed(
		removed_index, old_size, old_turn_index
	)

	return true

## Detect and resolve a player who still sits in turn order but has no cards left.
func _try_finish_empty_hand(holder: HandCardHolder) -> bool:
	if multiplayer.is_server() and !_match_deal_complete:
		return false
	if holder == null or !is_instance_valid(holder):
		return false
	if not turn_order.has(holder):
		return false
	if _count_cards_in_holder(holder) > 0:
		return false
	if get_current_holder() != holder:
		return false
	if _check_and_finish_current_holder():
		_after_holder_finished()
		if _is_authoritative():
			_server_sync_match_state()
			_server_broadcast_counts()
		return true
	return false

## Dims a seat that finished their hand and clears blocking interaction state.
func _finalize_finished_holder_ui(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder):
		return
	_clear_blocking_state_for_holder(holder)
	holder.set_turn_active(false)
	_dim_eliminated_holder(holder)
	var ui_container := get_container_for_holder(holder)
	if ui_container != null:
		_smooth_modulate(ui_container, Color(0.45, 0.45, 0.45, 1.0), 0.25)
	var local := _get_local_holder()
	if local == holder and !holder.is_bot and card_manager != null:
		card_manager.update_draw_button_state()

## Wild owner helpers
func clear_wild_owner() -> void:
	wild_color_owner = null

func set_wild_color_owner(holder: HandCardHolder) -> void:
	wild_color_owner = holder

## Holder that must finish swap/color/target selection before the turn advances.
func _get_pending_turn_holder() -> HandCardHolder:
	if wild_color_owner != null and is_instance_valid(wild_color_owner):
		if swap_color_pending or (card_manager != null and card_manager.waiting_for_color):
			return wild_color_owner
	if pending_swap_owner != null and is_instance_valid(pending_swap_owner):
		return pending_swap_owner
	if target_draw_active and pending_target_draw_owner != null and is_instance_valid(pending_target_draw_owner):
		return pending_target_draw_owner
	return null

func _restore_turn_to_holder(holder: HandCardHolder) -> bool:
	if holder == null or !is_instance_valid(holder) or !turn_order.has(holder):
		return false
	var idx := turn_order.find(holder)
	if idx < 0:
		return false
	if current_turn_index != idx:
		current_turn_index = idx
		update_turn_state()
		if multiplayer.is_server():
			_server_sync_match_state()
		return true
	return false

func _blocks_turn_advance() -> bool:
	if place_all_resolving or _place_all_sequence_running:
		return true
	if _swap_resolve_running:
		return true
	if roulette_active:
		return true
	return _get_pending_turn_holder() != null

func _resume_pending_effect_for_holder(holder: HandCardHolder) -> void:
	if holder == null or !is_instance_valid(holder):
		return
	if swap_color_pending and wild_color_owner == holder:
		if holder.is_bot:
			call_deferred("_finish_bot_swap_color", holder)
		else:
			call_deferred("_ensure_wild_color_resolved", holder)
		return
	if card_manager != null and card_manager.waiting_for_color and wild_color_owner == holder:
		call_deferred("_ensure_wild_color_resolved", holder)
		return
	if pending_swap_owner == holder:
		call_deferred("_kick_pending_swap_resolution")
		return
	if target_draw_active and pending_target_draw_owner == holder:
		if holder.is_bot:
			return
		call_deferred("_request_target_select_for_owner", holder, false)

## Picks and applies wild color for a bot (also used as watchdog fallback).
func _finish_bot_wild_color(holder: HandCardHolder) -> void:
	if !_is_authoritative() or card_manager == null or holder == null or !is_instance_valid(holder):
		return
	if !card_manager.waiting_for_color:
		return
	if wild_color_owner != holder:
		return
	server_apply_local_wild_color(int(_bot_choose_wild_color(holder)))

## Ensures a pending wild-color pick completes (bot auto-pick or human UI prompt).
func _ensure_wild_color_resolved(owner: HandCardHolder) -> void:
	if card_manager == null or owner == null or !is_instance_valid(owner):
		return
	if !card_manager.waiting_for_color:
		owner._busy = false
		return
	if wild_color_owner != owner:
		return
	if owner.is_bot:
		_finish_bot_wild_color(owner)
	elif _is_local_human_owner(owner):
		Signals.COLOR_request_color_select.emit()
	elif multiplayer.is_server():
		var peer_id := _slot_to_peer_id(int(owner.player_index))
		if peer_id > 0 and peer_id != multiplayer.get_unique_id():
			NetworkManager.rpc_id(peer_id, "client_request_color", int(owner.player_index))

func _on_stuck_watchdog_timeout() -> void:
	if !_is_authoritative() or !is_match_in_progress():
		return
	if _stuck_reconcile_running:
		return
	call_deferred("_reconcile_stuck_state")

## Authoritative safety net for orphaned wild-color waits, draw stacks, and idle bot turns.
func _reconcile_stuck_state() -> void:
	if _stuck_reconcile_running or !_is_authoritative() or !is_match_in_progress():
		return
	if place_all_resolving or _place_all_sequence_running or roulette_active:
		return
	_stuck_reconcile_running = true

	if card_manager != null and card_manager.waiting_for_color:
		if wild_color_owner != null and is_instance_valid(wild_color_owner):
			_restore_turn_to_holder(wild_color_owner)
			_ensure_wild_color_resolved(wild_color_owner)
		_stuck_reconcile_running = false
		return

	if swap_color_pending and wild_color_owner != null and is_instance_valid(wild_color_owner):
		_restore_turn_to_holder(wild_color_owner)
		if wild_color_owner.is_bot:
			call_deferred("_finish_bot_swap_color", wild_color_owner)
		else:
			call_deferred("_ensure_wild_color_resolved", wild_color_owner)
		_stuck_reconcile_running = false
		return

	if pending_swap_owner != null and is_instance_valid(pending_swap_owner):
		call_deferred("_kick_pending_swap_resolution")
		_stuck_reconcile_running = false
		return

	if _swap_resolve_running and Time.get_ticks_msec() - _swap_resolve_started_ms > 6000:
		push_warning("QueueManager: swap resolve watchdog reset stuck _swap_resolve_running")
		_swap_resolve_running = false

	var swap_holder := get_current_holder()
	if swap_holder != null and _is_unresolved_swap_for_holder(swap_holder):
		call_deferred("_try_recover_stuck_swap", swap_holder)
		_stuck_reconcile_running = false
		return

	if wild_color_owner != null and is_instance_valid(wild_color_owner) and card_manager != null:
		var orphan := wild_color_owner
		if orphan._waiting_color_turn_end and card_manager.top_card != null and !card_manager.waiting_for_color:
			if orphan.is_bot:
				var top_uid := int(card_manager.top_card.uid)
				orphan._waiting_color_turn_end = false
				orphan._pending_effect_card_uid = -1
				orphan._busy = false
				if top_uid > 0 and !_resolved_effect_uids.has(top_uid) and _can_resolve_card_effect(card_manager.top_card):
					register_card_play(card_manager.top_card, orphan)
				clear_wild_owner()
			else:
				call_deferred("_ensure_wild_color_resolved", orphan)

	var holder := get_current_holder()
	if holder == null:
		_stuck_reconcile_running = false
		return

	if draw_stack_amount > 0:
		if _try_recover_draw_stack_source_turn(holder):
			_stuck_reconcile_running = false
			return
		if holder.is_bot:
			_kick_bot_turn_if_needed(holder)
			if not holder_has_playable_card(holder) and !_draw_stack_resolving:
				if !_holder_blocked_from_resolving_draw_stack(holder):
					call_deferred("_resolve_draw_stack_for_holder", holder)
		_stuck_reconcile_running = false
		return

	if holder.is_bot and card_manager != null and !card_manager.waiting_for_color:
		if has_played_this_turn and _is_unresolved_swap_for_holder(holder):
			call_deferred("_try_recover_stuck_swap", holder)
		elif has_played_this_turn:
			call_deferred("_try_recover_stuck_turn", holder)
		elif has_drawn_this_turn and !has_played_this_turn:
			var ki_drawn := _get_ki_for_holder(holder)
			if ki_drawn != null and !ki_drawn.is_play_turn_running():
				ki_drawn.play_turn()
		elif !has_drawn_this_turn:
			var ki := _get_ki_for_holder(holder)
			if ki != null and !ki.is_play_turn_running():
				if holder_has_playable_card(holder) or draw_stack_amount > 0:
					ki.play_turn()
				elif can_draw_from_pile():
					if bot_draw_current():
						call_deferred("_kick_bot_after_draw", holder)
					elif _try_pass_if_stuck(holder):
						pass
				elif _try_pass_if_stuck(holder):
					pass

	_stuck_reconcile_running = false


## Continue bot turn after a watchdog-triggered draw.
func _kick_bot_after_draw(holder: HandCardHolder) -> void:
	if !_is_authoritative() or holder == null or !is_instance_valid(holder):
		return
	if get_current_holder() != holder or !holder.is_bot:
		return
	var ki := _get_ki_for_holder(holder)
	if ki != null and !ki.is_play_turn_running():
		ki.play_turn()

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

	if multiplayer.is_server():
		_server_sync_match_state()

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var play_order := _collect_place_all_play_order(holder, place_all_view, played_card)
		var serialized: Array = []
		for res in play_order:
			if res is CardResource:
				serialized.append(_serialize_card(res))
		NetworkManager.rpc("client_place_all_event", int(holder.player_index), int(color), serialized)

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
		if multiplayer.is_server():
			_server_push_hand(holder)
			_server_broadcast_counts()
			_server_sync_match_state()
		return

	# Push the authoritative hand before advancing the turn so clients can apply
	# it right after the place-all fly animation (without a stale full-hand resync).
	if multiplayer.is_server():
		_server_push_hand(holder)

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

		SoundManager.play_card_played()
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

	SoundManager.play_card_played()
	place_all_view.set_clickable(false, true)
	place_all_view.smooth_move_button_to_top_card_juicy(duration)

	await get_tree().create_timer(duration).timeout

	if place_all_view != null and is_instance_valid(place_all_view):
		if place_all_view.get_parent() == owner:
			owner.remove_child(place_all_view)
		place_all_view.queue_free()

	card_manager.set_top_card_no_effect(place_all_res)

## Collects same-color cards + finisher in the order they are played during place-all.
func _collect_place_all_play_order(owner: HandCardHolder, place_all_view: CardView, place_all_res: CardResource) -> Array:
	var ordered: Array = []
	if owner == null or place_all_res == null:
		return ordered

	var match_color := place_all_res.color
	for c in owner.get_children():
		if c is CardView and is_instance_valid(c) and c.card_res != null:
			if c == place_all_view:
				continue
			if c.card_res.color == match_color:
				ordered.append(c.card_res)

	ordered.append(place_all_res)
	return ordered

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

## Valid targets for target draw / swap (active players only, card owner excluded).
func get_valid_target_holders(exclude: HandCardHolder) -> Array[HandCardHolder]:
	var res: Array[HandCardHolder] = []
	var exclude_slot := -1
	if exclude != null and is_instance_valid(exclude):
		exclude_slot = int(exclude.player_index)
	for h in turn_order:
		if h == null or !is_instance_valid(h):
			continue
		if exclude_slot >= 0 and int(h.player_index) == exclude_slot:
			continue
		if is_holder_eliminated(h) or is_holder_finished(h):
			continue
		res.append(h)
	return res

## Count CardView nodes in a holder (ignores transient animation cards).
func _count_cards_in_holder(holder: HandCardHolder) -> int:
	if holder == null:
		return 0
	var n := 0
	for c in holder.get_children():
		if c is CardView and not c.get_meta("anim_temp", false):
			n += 1
	return n

## Find the KIController attached to a bot holder.
func _get_ki_for_holder(holder: HandCardHolder) -> KIController:
	if holder == null:
		return null
	for child in get_children():
		if child is KIController and child.hand_card_holder == holder:
			return child
	return null

## Pick a target with the fewest cards; random among ties.
func get_least_hand_target(exclude: HandCardHolder) -> HandCardHolder:
	var candidates: Array[HandCardHolder] = []
	var best_count := 999999
	for h in get_valid_target_holders(exclude):
		var c := _count_cards_in_holder(h)
		if c < best_count:
			best_count = c
			candidates.clear()
			candidates.append(h)
		elif c == best_count:
			candidates.append(h)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

## Threat target = player closest to winning (fewest cards).
func get_most_threatening_target(exclude: HandCardHolder) -> HandCardHolder:
	return get_least_hand_target(exclude)

## Show target selection UI on the card owner's machine (host/solo included).
func _request_target_select_for_owner(owner: HandCardHolder, allow_self: bool) -> void:
	if _is_local_human_owner(owner):
		Signals.TARGET_request_target_select.emit(owner, allow_self)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var peer_id := _slot_to_peer_id(owner.player_index)
		if peer_id != 0:
			NetworkManager.rpc_id(peer_id, "client_request_target_select", int(owner.player_index), allow_self)

## True when this machine should show UI for a human card owner.
func _is_local_human_owner(owner: HandCardHolder) -> bool:
	if owner == null or owner.is_bot:
		return false
	if !multiplayer.has_multiplayer_peer():
		return true
	return int(owner.player_index) == int(NetworkManager.my_slot)

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

	if multiplayer.is_server():
		_server_sync_match_state()

	if multi:
		if _is_authoritative():
			resolve_target_draw(null)
		return

	if owner.is_bot:
		var target: HandCardHolder
		var ki := _get_ki_for_holder(owner)
		if ki != null and ki.difficulty == KIController.AIDifficulty.OMEGA:
			target = ki.omega_choose_target_draw_target()
		else:
			target = get_most_threatening_target(owner)
		resolve_target_draw(target)
		return

	_request_target_select_for_owner(owner, false)

## True when a swap-hands play still needs target selection or color follow-up.
func _is_unresolved_swap_for_holder(holder: HandCardHolder) -> bool:
	if holder == null or !is_instance_valid(holder) or card_manager == null:
		return false
	if card_manager.top_card == null or card_manager.top_card.type != CardResource.CardType.SWAP_HANDS:
		return false
	if !is_players_turn(holder):
		return false
	var uid := int(card_manager.top_card.uid)
	if uid > 0 and !_resolved_effect_uids.has(uid):
		return true
	if !has_played_this_turn:
		return false
	if _swap_resolve_running:
		return false
	if swap_color_pending:
		return wild_color_owner == holder
	if pending_swap_owner != null:
		return true
	return wild_color_owner == null


func _pick_swap_target_for_owner(owner: HandCardHolder) -> HandCardHolder:
	if owner == null:
		return null
	var target: HandCardHolder = null
	var ki := _get_ki_for_holder(owner)
	if ki != null and ki.has_method("choose_swap_target"):
		target = ki.choose_swap_target()
	if target == null:
		target = get_least_hand_target(owner)
	return target


## Resume a stalled swap target pick (bot auto-pick or human UI).
func _kick_pending_swap_resolution() -> void:
	if !_is_authoritative() or pending_swap_owner == null or !is_instance_valid(pending_swap_owner):
		pending_swap_owner = null
		return
	if _swap_resolve_running:
		return
	var owner := pending_swap_owner
	if owner.is_bot:
		var target := _pick_swap_target_for_owner(owner)
		if target == null:
			pending_swap_owner = null
			end_turn()
			return
		_resolve_swap_with_target(owner, target)
		return
	_request_target_select_for_owner(owner, false)


## Recover when swap-hands was played but target/color resolution never finished.
func _try_recover_stuck_swap(holder: HandCardHolder) -> void:
	if !_is_authoritative() or holder == null or !is_instance_valid(holder):
		return
	if _swap_resolve_running:
		return
	if card_manager == null or card_manager.top_card == null:
		return
	if card_manager.top_card.type != CardResource.CardType.SWAP_HANDS:
		return
	if !is_players_turn(holder):
		return
	var top := card_manager.top_card
	var uid := int(top.uid)
	if uid > 0 and !_resolved_effect_uids.has(uid) and _can_resolve_card_effect(top):
		register_card_play(top, holder)
		return
	if !has_played_this_turn:
		return
	if swap_color_pending:
		if wild_color_owner == holder:
			if holder.is_bot:
				call_deferred("_finish_bot_swap_color", holder)
			else:
				call_deferred("_ensure_wild_color_resolved", holder)
		return
	if pending_swap_owner != null:
		_kick_pending_swap_resolution()
		return
	if uid > 0 and _completed_swap_uids.has(uid):
		return
	holder._busy = false
	start_swap_hands(holder)


## Swap hands start
func start_swap_hands(owner: HandCardHolder) -> void:
	if owner == null or !_is_authoritative():
		return
	if pending_swap_owner != null:
		if pending_swap_owner == owner and !_swap_resolve_running:
			pending_swap_owner = null
		elif _swap_resolve_running:
			return
		else:
			pending_swap_owner = null
	pending_swap_owner = owner
	if multiplayer.is_server():
		_server_sync_match_state()
	if owner.is_bot:
		var target := _pick_swap_target_for_owner(owner)
		if target == null:
			pending_swap_owner = null
			end_turn()
			return
		_resolve_swap_with_target(owner, target)
		return
	_request_target_select_for_owner(owner, false)

## Target draw resolve
func resolve_target_draw(target_holder: HandCardHolder) -> void:
	if !target_draw_active:
		if pending_swap_owner != null:
			if _swap_resolve_running or _is_swap_already_completed_for_top():
				pending_swap_owner = null
				return
			var owner := pending_swap_owner
			pending_swap_owner = null
			_resolve_swap_with_target(owner, target_holder)
		return

	var owner := pending_target_draw_owner

	if _is_authoritative():
		if target_draw_is_multi:
			# Multi target draw: every active player except the card owner draws card.value times.
			var recipients := get_valid_target_holders(owner)
			for h in recipients:
				for i in range(target_draw_value):
					var card := card_manager.draw_card()
					if card == null:
						break
					notify_card_drawn(int(h.player_index), 1, false, card)
					h.add_card(card, true)
				h.sort_cards_full()
				h.refresh_playable_cards()
				_try_eliminate_holder_for_max_cards(h)
				_server_push_hand(h)
		else:
			if target_holder == null:
				target_holder = get_most_threatening_target(owner)
			if target_holder != null:
				for i in range(target_draw_value):
					var card := card_manager.draw_card()
					if card == null:
						break
					notify_card_drawn(int(target_holder.player_index), 1, false, card)
					target_holder.add_card(card, true)
				target_holder.sort_cards_full()
				target_holder.refresh_playable_cards()
				_try_eliminate_holder_for_max_cards(target_holder)
				_server_push_hand(target_holder)

	target_draw_active = false
	target_draw_value = 0
	target_draw_is_multi = false
	target_draw_color = CardResource.CardColor.BLACK
	pending_target_draw_owner = null

	if !_is_authoritative():
		return

	_sync_deck_counts()

	end_turn()

## Swap hands resolve
func resolve_swap_hands(owner: HandCardHolder) -> void:
	if owner == null:
		return
	var target := get_next_holder(owner)
	_resolve_swap_with_target(owner, target)

## Execute swap between two holders, then request color selection
func _resolve_swap_with_target(owner: HandCardHolder, target: HandCardHolder) -> void:
	if owner == null or target == null:
		return
	if _swap_resolve_running:
		return
	if _is_swap_already_completed_for_top():
		return
	# Bots resolve immediately so deferred calls cannot leave pending_swap_owner stuck.
	if owner.is_bot:
		_resolve_swap_with_target_async(owner, target)
	else:
		call_deferred("_resolve_swap_with_target_async", owner, target)


func _is_swap_already_completed_for_top() -> bool:
	if card_manager == null or card_manager.top_card == null:
		return false
	var uid := int(card_manager.top_card.uid)
	return uid > 0 and _completed_swap_uids.has(uid)


func _resolve_swap_with_target_async(owner: HandCardHolder, target: HandCardHolder) -> void:
	while _swap_resolve_running:
		await get_tree().process_frame
	_swap_resolve_running = true
	_swap_resolve_started_ms = Time.get_ticks_msec()

	pending_swap_owner = null
	if owner == null:
		swap_color_pending = false
		_swap_resolve_running = false
		end_turn()
		return
	if target == null:
		swap_color_pending = false
		_swap_resolve_running = false
		end_turn()
		return

	var top_uid := -1
	if card_manager != null and card_manager.top_card != null:
		top_uid = int(card_manager.top_card.uid)
	if top_uid > 0 and _completed_swap_uids.has(top_uid):
		_swap_resolve_running = false
		return

	var my_cards := owner.get_all_card_resources()
	var opp_cards := target.get_all_card_resources()
	var owner_count := my_cards.size()
	var target_count := opp_cards.size()

	if _is_authoritative():
		var anim_seed := randi()
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			var feedback := _get_swap_hands_feedback()
			var finished := false
			var on_finished := func() -> void:
				finished = true
			if feedback != null and feedback.has_signal("visual_finished"):
				feedback.visual_finished.connect(on_finished, CONNECT_ONE_SHOT)
			NetworkManager.rpc(
				"client_swap_hands_event",
				int(owner.player_index),
				int(target.player_index),
				owner_count,
				target_count,
				int(anim_seed),
				int(NetworkManager.match_epoch)
			)
			if feedback != null:
				var deadline := Time.get_ticks_msec() + 8000
				while not finished and is_instance_valid(feedback) and Time.get_ticks_msec() < deadline:
					await get_tree().process_frame
			else:
				await get_tree().create_timer(1.0).timeout
		else:
			var feedback := _get_swap_hands_feedback()
			if feedback != null and feedback.has_method("run_swap_visual"):
				await feedback.run_swap_visual(owner, target, owner_count, target_count, anim_seed)
			else:
				await get_tree().create_timer(0.9).timeout
		_apply_swap_hands_state(owner, target, my_cards, opp_cards)
		if top_uid > 0:
			_completed_swap_uids[top_uid] = true

	_swap_resolve_running = false


func _apply_swap_hands_state(
	owner: HandCardHolder,
	target: HandCardHolder,
	my_cards: Array,
	opp_cards: Array
) -> void:
	if !_is_authoritative():
		return
	if owner == null or target == null:
		return

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
	owner._busy = false
	target._busy = false

	_server_push_hand(owner)
	_server_push_hand(target)

	if card_manager != null:
		card_manager.current_color = CardResource.CardColor.BLACK
		card_manager.waiting_for_color = true
	swap_color_pending = true
	owner._waiting_color_turn_end = true
	if card_manager != null and card_manager.top_card != null:
		owner._pending_effect_card_uid = int(card_manager.top_card.uid)
	set_wild_color_owner(owner)
	if owner.is_bot:
		call_deferred("_finish_bot_swap_color", owner)
	else:
		Signals.COLOR_request_color_select.emit()
		if multiplayer.is_server():
			var peer_id := _slot_to_peer_id(owner.player_index)
			if peer_id != 0:
				NetworkManager.rpc_id(peer_id, "client_request_color", int(owner.player_index))
	if multiplayer.is_server():
		_server_broadcast_counts()
		_server_sync_match_state()

## Bot swap follow-up: pick a wild color and end the turn.
func _finish_bot_swap_color(owner: HandCardHolder) -> void:
	if card_manager == null or owner == null or !is_instance_valid(owner):
		return
	if wild_color_owner != owner and !swap_color_pending:
		return
	if !card_manager.waiting_for_color and !swap_color_pending:
		return
	await get_tree().create_timer(0.15).timeout
	if card_manager == null or !is_instance_valid(owner):
		return
	if wild_color_owner != owner and !swap_color_pending:
		return
	if !card_manager.waiting_for_color and !swap_color_pending:
		if _is_authoritative() and is_players_turn(owner) and has_played_this_turn:
			owner._busy = false
			swap_color_pending = false
			clear_wild_owner()
			end_turn()
		return
	if card_manager.waiting_for_color:
		if wild_color_owner != owner:
			set_wild_color_owner(owner)
	var color := _bot_choose_wild_color(owner)
	server_apply_local_wild_color(int(color))

func _bot_choose_wild_color(holder: HandCardHolder) -> CardResource.CardColor:
	var ki := _get_ki_for_holder(holder)
	if ki != null:
		return ki.choose_best_wild_color()
	return choose_color_for_roulette(holder)

## Color roulette start – next player picks a color, then draws until that color is drawn.
func start_color_roulette(owner: HandCardHolder) -> void:
	if not _is_authoritative():
		return
	if owner == null:
		end_turn()
		return

	var target := get_next_holder(owner)
	if target == null:
		end_turn()
		return

	roulette_active = true
	roulette_waiting_for_color = true
	roulette_owner = owner
	roulette_target = target
	roulette_target_slot = int(target.player_index)
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false

	has_played_this_turn = true
	has_drawn_this_turn = false

	next_turn(false)
	await get_tree().process_frame

	if roulette_target == null or not is_instance_valid(roulette_target):
		_abort_roulette()
		return

	if not _ensure_roulette_target_turn():
		_abort_roulette()
		return

	if multiplayer.is_server():
		_server_sync_match_state()

	if roulette_target.is_bot:
		var chosen := choose_color_for_roulette(roulette_target)
		_resolve_roulette_color(chosen)
	else:
		_prompt_roulette_color_for(roulette_target)


func _prompt_roulette_color_for(target: HandCardHolder) -> void:
	if target == null or not is_instance_valid(target):
		_abort_roulette()
		return
	if card_manager != null:
		card_manager.waiting_for_color = true
	set_wild_color_owner(target)
	Signals.COLOR_request_color_select.emit()
	if multiplayer.is_server():
		var peer_id := _slot_to_peer_id(target.player_index)
		if peer_id != 0:
			NetworkManager.rpc_id(peer_id, "client_request_color", int(target.player_index))


func _ensure_roulette_target_turn() -> bool:
	if roulette_target == null or not is_instance_valid(roulette_target):
		return false
	if get_current_holder() == roulette_target:
		return true
	var idx := turn_order.find(roulette_target)
	if idx < 0:
		return false
	current_turn_index = idx
	update_turn_state()
	return get_current_holder() == roulette_target


func is_local_roulette_color_picker() -> bool:
	if not roulette_active or not roulette_waiting_for_color:
		return false
	if roulette_target == null or roulette_target.is_bot:
		return false
	if not multiplayer.has_multiplayer_peer():
		return is_players_turn(roulette_target)
	return int(NetworkManager.my_slot) == int(roulette_target.player_index)


## Roulette color selected (server/offline only).
func _on_roulette_color_selected(color: CardResource.CardColor) -> void:
	if not _is_authoritative():
		return
	_resolve_roulette_color(color)


func _resolve_roulette_color(color: CardResource.CardColor) -> void:
	if not roulette_active or not roulette_waiting_for_color:
		return
	if roulette_target == null or not _ensure_roulette_target_turn():
		_abort_roulette()
		return

	roulette_waiting_for_color = false
	roulette_chosen_color = color

	if card_manager != null and card_manager.waiting_for_color:
		card_manager.select_color(color)
	else:
		_apply_roulette_color_to_top_card(color)

	clear_wild_owner()
	Signals.COLOR_color_select_dismissed.emit()
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		NetworkManager.rpc("client_dismiss_color_select")
	_handle_roulette_start()


func _abort_roulette() -> void:
	_end_roulette(false)


## Roulette step loop
func _handle_roulette_start() -> void:
	if not _is_authoritative():
		return
	if !roulette_active:
		return
	if roulette_target == null:
		_abort_roulette()
		return

	var holder := get_current_holder()
	if holder != roulette_target:
		if not _ensure_roulette_target_turn():
			_abort_roulette()
			return
		holder = roulette_target

	if roulette_waiting_for_color:
		return
	if roulette_step_running:
		return

	roulette_step_running = true
	call_deferred("_do_roulette_draw_step", holder)


## Roulette draw step – always draw from deck until the chosen color appears.
func _do_roulette_draw_step(holder: HandCardHolder) -> void:
	if not _is_authoritative():
		return
	if holder == null or not is_instance_valid(holder):
		_abort_roulette()
		return

	var card: CardResource
	var ki := _get_ki_for_holder(holder)
	if ki != null and ki.difficulty == KIController.AIDifficulty.OMEGA and ki.omega_roulette_peek_range > 0:
		card = ki.omega_roulette_draw_card(roulette_chosen_color)
	else:
		card = card_manager.draw_card()
	if card == null:
		_abort_roulette()
		return

	notify_card_drawn(int(holder.player_index), 1, true, card)
	holder.add_card(card, true)
	holder.sort_cards_full()
	holder.refresh_playable_cards()

	if multiplayer.is_server():
		_server_push_hand(holder)

	await get_tree().create_timer(0.22).timeout

	if not roulette_active:
		return

	if card.color == roulette_chosen_color:
		_finish_roulette_draw()
		return

	roulette_step_running = false
	_handle_roulette_start()


func _finish_roulette_draw() -> void:
	_end_roulette(true)


## Roulette end
func _end_roulette(success: bool) -> void:
	if not _is_authoritative():
		return

	roulette_active = false
	roulette_waiting_for_color = false
	roulette_owner = null
	roulette_target = null
	roulette_target_slot = -1
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false

	if card_manager != null:
		card_manager.waiting_for_color = false
	clear_wild_owner()

	if success:
		has_drawn_this_turn = true
		has_played_this_turn = false

		var holder := get_current_holder()
		if holder != null:
			holder.refresh_playable_cards()

		update_turn_state()
		if card_manager != null:
			card_manager.update_draw_button_state()

		if multiplayer.is_server():
			_server_sync_match_state()
			_server_broadcast_counts()

		if holder != null and holder.is_bot:
			var ki := _get_ki_for_holder(holder)
			if ki != null:
				ki.call_deferred("play_turn")
		return

	end_turn()
	if multiplayer.is_server():
		_server_sync_match_state()

## Roulette color choice for bots
func choose_color_for_roulette(target: HandCardHolder) -> CardResource.CardColor:
	if target == null:
		return CardResource.CardColor.RED

	if target.is_bot:
		var ki := _get_ki_for_holder(target)
		if ki != null and ki.difficulty == KIController.AIDifficulty.OMEGA:
			return ki.omega_choose_roulette_color()

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
	card_manager.sync_top_card_color_visual()

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
	_schedule_client_hand_watchdog()
	_try_apply_pending_hand()

## Apply buffered hand when ready
func _try_apply_pending_hand() -> void:
	if _pending_hand.size() == 0:
		return
	if !multiplayer.is_server() and _client_place_all_animating:
		return
	if !multiplayer.is_server() and _client_deal_animating:
		return
	if !multiplayer.is_server() and _client_swap_animating:
		return
	if !multiplayer.is_server() and _client_play_animating:
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
	if my_holder._busy and _client_play_animating:
		return
	var prev_count := _count_cards_in_holder(my_holder)
	if my_holder.get_child_count() == 0:
		if !multiplayer.is_server() and _pending_hand.size() > 1 and !_match_deal_complete:
			await _reveal_hand_animated(my_holder, _pending_hand)
		else:
			for entry: Dictionary in _pending_hand:
				if int(entry.get("id", 0)) <= 0:
					continue
				my_holder.add_card(CardResource.from_sync_dict(entry), false)
			my_holder.sort_cards_full()
			my_holder.refresh_playable_cards()
	else:
		_reconcile_hand(my_holder, _pending_hand)

	if !multiplayer.is_server():
		var new_count := _count_cards_in_holder(my_holder)
		if new_count > prev_count and !_client_suppress_draw_sound_once:
			SoundManager.play_draw_card(new_count - prev_count)
	_client_suppress_draw_sound_once = false

	_last_applied_hand = _pending_hand.duplicate(true)
	_pending_hand = []
	_client_hand_watchdog_armed = false
	NetworkManager.clear_last_hand()
	_client_has_hand = true
	if !multiplayer.is_server() and _client_has_state:
		_client_match_started = true
	if multiplayer.is_server():
		_apply_counts_to_ui()
		_apply_local_visibility()
	else:
		_apply_local_visibility()
		_apply_counts_to_ui()
		_try_finalize_client_sync()
	_refresh_seat_names()

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
	_match_deal_complete = true
	_client_match_started = true
	_ensure_active_deck_on_card_manager()
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
	print("QueueManager: _on_players_received count=%d is_server=%s holders_init=%s deal_progress=%s deal_complete=%s match_started=%s" % [
		players_in.size(), str(multiplayer.is_server()), str(_client_holders_initialized),
		str(_match_deal_in_progress), str(_match_deal_complete), str(_client_match_started)])
	_players_meta = players_in.duplicate(true)
	if !multiplayer.is_server():
		_resolve_client_slot(_players_meta)
	# Once the client has built its holders in _ready(), never rebuild them again.
	# Any subsequent broadcast (e.g. profile re-register, peer reconnect) only needs
	# the peer-slot map updated, not a full holder teardown that destroys deal state.
	if !multiplayer.is_server() and _client_holders_initialized:
		_update_peer_slots_from_players(_players_meta)
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
func _build_holders_from_players(players_meta: Array) -> void:
	print("QueueManager: _build_holders_from_players count=%d is_server=%s deal_progress=%s match_started=%s" % [
		players_meta.size(), str(multiplayer.is_server()),
		str(_match_deal_in_progress), str(_client_match_started)])
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
			if is_bot_row:
				var diff := int(row.get("difficulty", KIController.AIDifficulty.SMART))
				var pers := int(row.get("personality", KIController.AIPersonality.BALANCED))
				holder.bot_difficulty = diff
				holder.bot_personality = pers
				nm = _bot_display_name(diff, nm)

		holder.profile.player_index = i
		holder.profile.is_bot = is_bot_row
		holder.profile.player_name = nm
		holder.profile.holder = holder
		if is_bot_row:
			holder.profile.apply_bot_avatar(holder.bot_difficulty)
		elif pic_id >= 0:
			holder.profile.apply_picture_from_id(pic_id)
		holder.profile.ensure_picture()

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
		if !h.is_bot and !h.compact_view:
			h.ensure_description_label()
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
func _get_display_card_count(slot: int) -> int:
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	var live := 0
	if holder != null and is_instance_valid(holder):
		live = _count_cards_in_holder(holder)

	if _is_authoritative():
		return live

	var my_slot := int(NetworkManager.my_slot)
	if slot == my_slot:
		return live

	# Opponents on clients: show the visible card-back stack, not the server count
	# (counts can arrive before stagger animations finish).
	return live

func _refresh_seat_names() -> void:
	var used: Dictionary = {}
	for h in turn_order:
		if h == null or !is_instance_valid(h):
			continue
		var container := get_container_for_holder(h)
		if container == null:
			continue
		_set_seat_name(container, h)
		used[container] = true

	for c in other_player_containers:
		if c != null and not used.has(c):
			_remove_seat_name(c)

func _set_seat_name(container: Control, holder: HandCardHolder) -> void:
	if container == null or holder == null:
		return

	if !holder.is_bot and int(holder.player_index) == int(NetworkManager.my_slot):
		_remove_seat_name(container)
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

	var name := holder.profile.player_name if holder.profile != null else ""
	var count := _get_display_card_count(int(holder.player_index))
	if name.strip_edges() != "":
		label.text = "%s (%d)" % [name, count]
	else:
		label.text = "(%d)" % count

	var info := container.get_node_or_null("SeatBotInfo") as Label
	var info_text := _format_bot_seat_info(holder)
	var has_info := info_text.strip_edges() != ""

	# Holder is bottom-anchored; cards extend upward (~240px). Keep all text above the stack.
	const CARD_STACK_CLEARANCE := 250
	const GAP_ABOVE_CARDS := 14
	const INFO_LINE_HEIGHT := 22
	const NAME_LINE_HEIGHT := 40
	const LABEL_GAP := 4

	var text_bottom_y := -CARD_STACK_CLEARANCE - GAP_ABOVE_CARDS
	if has_info:
		if info == null:
			info = Label.new()
			info.name = "SeatBotInfo"
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.z_index = 100
			info.size = Vector2(300, INFO_LINE_HEIGHT)
			info.add_theme_font_size_override("font_size", 16)
			info.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.95))
			info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
			info.add_theme_constant_override("shadow_offset_x", 2)
			info.add_theme_constant_override("shadow_offset_y", 2)
			container.add_child(info)
		info.text = info_text
		info.position = Vector2(-150, text_bottom_y - INFO_LINE_HEIGHT)
		label.position = Vector2(-150, info.position.y - LABEL_GAP - NAME_LINE_HEIGHT)
	else:
		if info != null:
			info.queue_free()
		label.position = Vector2(-150, text_bottom_y - NAME_LINE_HEIGHT)


func _bot_display_name(difficulty: int, fallback: String) -> String:
	if difficulty == KIController.AIDifficulty.OMEGA:
		return "Omega"
	return fallback


func _format_bot_seat_info(holder: HandCardHolder) -> String:
	if holder == null or not holder.is_bot or holder.bot_difficulty < 0:
		return ""
	if holder.bot_difficulty == KIController.AIDifficulty.OMEGA:
		return ""
	var diff_name = BOT_DIFFICULTY_NAMES[holder.bot_difficulty] if holder.bot_difficulty < BOT_DIFFICULTY_NAMES.size() else "?"
	var pers_name = BOT_PERSONALITY_NAMES[holder.bot_personality] if holder.bot_personality >= 0 and holder.bot_personality < BOT_PERSONALITY_NAMES.size() else "?"
	return "%s / %s" % [diff_name, pers_name]


func _remove_seat_name(container: Control) -> void:
	if container == null:
		return
	var lbl := container.get_node_or_null("SeatName")
	if lbl != null:
		lbl.queue_free()
	var info_lbl := container.get_node_or_null("SeatBotInfo")
	if info_lbl != null:
		info_lbl.queue_free()

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
	_match_deal_in_progress = false
	_match_deal_complete = false
	_client_match_started = false
	_client_deal_animating = false
	_client_deal_batch_queue.clear()
	_client_deal_batch_running = false
	_client_deal_finish_scheduled = false
	_opponent_left_overlay_shown = false
	_client_play_animating = false
	_client_play_uids_in_flight.clear()
	_client_place_all_animating = false
	_client_place_all_slot = -1
	_client_swap_animating = false
	_client_draw_animating = false
	current_turn_index = 0
	has_played_this_turn = false
	has_drawn_this_turn = false
	winners.clear()
	max_card_losers.clear()
	_lobby_return_requested = false
	_local_loser_overlay_shown = false
	_hide_loser_overlay()
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	draw_stack_source_slot = -1
	_draw_stack_resolving = false
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
	roulette_target_slot = -1
	roulette_chosen_color = CardResource.CardColor.BLACK
	roulette_step_running = false
	pending_swap_owner = null
	swap_color_pending = false
	_swap_resolve_running = false
	_swap_resolve_started_ms = 0
	_resolved_effect_uids.clear()
	_completed_swap_uids.clear()
	if card_manager != null:
		card_manager.waiting_for_color = false
		card_manager.pending_wild_card = null
		card_manager.current_color = CardResource.CardColor.BLACK

## Build serializable match state snapshot (server authoritative).
func _build_match_state() -> Dictionary:
	var top_card_dict := {}
	if card_manager != null and card_manager.top_card != null:
		top_card_dict = _serialize_card(card_manager.top_card)

	var pending_swap_slot := -1
	if pending_swap_owner != null and is_instance_valid(pending_swap_owner):
		pending_swap_slot = int(pending_swap_owner.player_index)

	var wild_owner_slot := -1
	if wild_color_owner != null and is_instance_valid(wild_color_owner):
		wild_owner_slot = int(wild_color_owner.player_index)

	var active_turn_slots: Array = []
	for h in turn_order:
		if h != null and is_instance_valid(h):
			active_turn_slots.append(int(h.player_index))

	return {
		"top_card": top_card_dict,
		"turn_index": int(current_turn_index),
		"active_turn_slots": active_turn_slots,
		"direction": int(direction),
		"draw_stack": int(draw_stack_amount),
		"draw_stack_min": int(draw_stack_min_value),
		"draw_stack_is_wild": bool(draw_stack_is_wild),
		"draw_stack_color": int(draw_stack_color),
		"draw_stack_source_slot": int(draw_stack_source_slot),
		"current_color": int(card_manager.current_color) if card_manager != null else 0,
		"waiting_for_color": bool(card_manager.waiting_for_color) if card_manager != null else false,
		"has_played": bool(has_played_this_turn),
		"has_drawn": bool(has_drawn_this_turn),
		"roulette_active": bool(roulette_active),
		"roulette_waiting": bool(roulette_waiting_for_color),
		"roulette_target_slot": int(roulette_target_slot),
		"place_all_active": bool(place_all_active),
		"place_all_resolving": bool(place_all_resolving),
		"swap_color_pending": bool(swap_color_pending),
		"target_draw_active": bool(target_draw_active),
		"pending_swap_slot": pending_swap_slot,
		"wild_owner_slot": wild_owner_slot,
		"eliminated_slots": _get_eliminated_slots(),
	}

## Apply special-mode flags from a match-state snapshot.
func _apply_match_state_flags(state: Dictionary) -> void:
	has_played_this_turn = bool(state.get("has_played", has_played_this_turn))
	has_drawn_this_turn = bool(state.get("has_drawn", has_drawn_this_turn))
	roulette_active = bool(state.get("roulette_active", false))
	roulette_waiting_for_color = bool(state.get("roulette_waiting", false))
	roulette_target_slot = int(state.get("roulette_target_slot", -1))
	if roulette_target_slot >= 0:
		roulette_target = _slot_to_holder.get(roulette_target_slot, null)
	else:
		roulette_target = null
	place_all_active = bool(state.get("place_all_active", false))
	place_all_resolving = bool(state.get("place_all_resolving", false))
	if !multiplayer.is_server():
		swap_color_pending = bool(state.get("swap_color_pending", false))
	target_draw_active = bool(state.get("target_draw_active", false))
	var swap_slot := int(state.get("pending_swap_slot", -1))
	if swap_slot >= 0:
		pending_swap_owner = _slot_to_holder.get(swap_slot, null)
	else:
		pending_swap_owner = null

## Buffer incoming match state
func _on_match_state_received(state: Dictionary) -> void:
	_pending_state = state
	if !multiplayer.is_server():
		_client_has_state = false
		# Apply immediately when possible so draw-stack/turn flags never lag
		# behind card fly animations (prevents stale "+N" soft-locks).
		if _client_play_animating or _client_place_all_animating or _client_deal_animating or _client_swap_animating or _client_draw_animating:
			_apply_match_state_snapshot(state, true)
		else:
			_try_apply_pending_match_state()
	else:
		_try_apply_pending_match_state()

## Apply match state when possible
func _try_apply_pending_match_state() -> void:
	if _pending_state.size() == 0:
		return
	if card_manager == null:
		return

	# While a card fly animation runs, still mirror turn/draw-stack/flags so
	# clients do not stay soft-locked with a stale "+N" overlay. Only defer the
	# top-card swap — the in-flight animation will finish it via suppression.
	var skip_top_card := !multiplayer.is_server() and (_client_play_animating or _client_swap_animating)
	_apply_match_state_snapshot(_pending_state, skip_top_card)

	_pending_state = {}
	NetworkManager.clear_last_match_state()
	_client_has_state = true
	if !multiplayer.is_server():
		if _client_has_hand:
			_client_match_started = true
		_try_finalize_client_sync()

## Apply a server match-state snapshot on clients (optionally defer top card).
func _apply_match_state_snapshot(state: Dictionary, skip_top_card: bool = false) -> void:
	if card_manager == null or state.size() == 0:
		return

	var top = state.get("top_card", null)
	if !skip_top_card and top is Dictionary and CardResource.sync_dict_has_identity(top):
		var r := CardResource.from_sync_dict(top)
		var same_top := card_manager.top_card != null and int(card_manager.top_card.uid) == int(r.uid)
		if !same_top:
			card_manager.set_top_card_runtime(r, false)

	var new_direction := int(state.get("direction", 1))
	if direction != new_direction:
		direction = new_direction
		Signals.MATCH_direction_changed.emit(direction)
		if !multiplayer.is_server():
			_show_direction_reversed_feedback()
	else:
		direction = new_direction
	if !multiplayer.is_server():
		draw_stack_amount = int(state.get("draw_stack", 0))
		draw_stack_min_value = int(state.get("draw_stack_min", draw_stack_min_value))
		draw_stack_is_wild = bool(state.get("draw_stack_is_wild", draw_stack_is_wild))
		draw_stack_color = int(state.get("draw_stack_color", draw_stack_color))
		draw_stack_source_slot = int(state.get("draw_stack_source_slot", draw_stack_source_slot))

	if state.has("waiting_for_color") and card_manager != null and !multiplayer.is_server():
		var waiting := bool(state.get("waiting_for_color", card_manager.waiting_for_color))
		if waiting and !card_manager.waiting_for_color:
			card_manager.waiting_for_color = true
			card_manager.pending_wild_card = card_manager.top_card
		if !waiting and card_manager.waiting_for_color:
			card_manager.waiting_for_color = false
			card_manager.pending_wild_card = null

	if state.has("current_color") and card_manager != null and !multiplayer.is_server():
		# Never tint a pending wild with the previous pile color while the owner
		# is still choosing (RED == 0 was leaking through as a false "chosen" color).
		if card_manager.waiting_for_color:
			card_manager.current_color = CardResource.CardColor.BLACK
		else:
			card_manager.current_color = int(state.get("current_color", card_manager.current_color))
	# Clients mirror server snapshots; the server must not reconcile
	# waiting_for_color from its own broadcasts or a pending wild play can be
	# auto-resolved without register_card_play (stacked +4 stays at +4).
	_sync_wild_owner_from_state(state)
	if card_manager != null:
		card_manager.sync_top_card_color_visual()

	_apply_match_state_flags(state)
	_sync_eliminated_slots_from_state(state)
	_apply_active_turn_order_from_state(state)
	if !state.has("active_turn_slots") or (state.get("active_turn_slots", []) as Array).is_empty():
		_apply_turn_index_from_state(state)

	update_turn_state()

	if card_manager != null:
		card_manager.update_draw_button_state()

	if not multiplayer.is_server() and roulette_active and roulette_waiting_for_color:
		_try_prompt_local_roulette_color()
	elif not multiplayer.is_server() and not roulette_waiting_for_color:
		var needs_color_pick := bool(state.get("waiting_for_color", false)) \
			or bool(state.get("swap_color_pending", false))
		if !needs_color_pick:
			Signals.COLOR_color_select_dismissed.emit()
	_try_prompt_wild_color_from_state(state)

func _sync_wild_owner_from_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	var wild_slot := int(state.get("wild_owner_slot", -1))
	if wild_slot >= 0:
		var owner: HandCardHolder = _slot_to_holder.get(wild_slot, null)
		if owner != null and is_instance_valid(owner):
			set_wild_color_owner(owner)
			return
	if card_manager == null or !card_manager.waiting_for_color:
		clear_wild_owner()

func _try_prompt_wild_color_from_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	if card_manager == null:
		return
	var waiting := bool(state.get("waiting_for_color", card_manager.waiting_for_color))
	var swap_pending := bool(state.get("swap_color_pending", swap_color_pending))
	if !waiting and !swap_pending:
		return
	if wild_color_owner == null or !is_instance_valid(wild_color_owner):
		return
	if !_is_local_human_owner(wild_color_owner):
		return
	_prompt_local_wild_color_picker()


func _prompt_local_wild_color_picker() -> void:
	if multiplayer.is_server():
		return
	if card_manager == null or wild_color_owner == null or !is_instance_valid(wild_color_owner):
		return
	if !_is_local_human_owner(wild_color_owner):
		return
	if !card_manager.waiting_for_color and !swap_color_pending:
		return
	card_manager.waiting_for_color = true
	card_manager.pending_wild_card = card_manager.top_card
	card_manager.current_color = CardResource.CardColor.BLACK
	card_manager.sync_top_card_color_visual()
	Signals.COLOR_request_color_select.emit()

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
	_match_deal_in_progress = false
	_match_deal_complete = false
	_game_over_handled = false
	_lobby_return_requested = false

	start_card_count = NetworkManager.normalize_start_card_count(NetworkManager.lobby_start_card_count)

	randomize()
	current_turn_index = randi() % turn_order.size()
	direction = 1
	draw_stack_amount = 0
	draw_stack_min_value = 0
	draw_stack_is_wild = false
	draw_stack_color = CardResource.CardColor.BLACK
	draw_stack_source_slot = -1
	has_played_this_turn = false
	has_drawn_this_turn = false
	winners.clear()
	max_card_losers.clear()
	_local_loser_overlay_shown = false
	_hide_loser_overlay()
	_resolved_effect_uids.clear()
	_completed_swap_uids.clear()

	# Apply the deck chosen in the lobby (host-authoritative). Falls back to the
	# card manager's default deck if none was selected / it fails to load.
	_ensure_active_deck_on_card_manager()
	if card_manager.loaded_deck != null:
		print("QueueManager: Using deck '%s'" % str(card_manager.loaded_deck.deck_name))

	card_manager.reset_for_new_match()
	card_manager.deck = card_manager.create_default_cards()
	if card_manager.deck.is_empty():
		push_error("QueueManager: Cannot start match – deck is empty.")
		_reset_server_match_state()
		return
	card_manager.deck.shuffle()
	card_manager.set_top_card()

	# Deal starting hands before any match-state sync so empty-hand win checks
	# never run against undistributed cards.
	_match_deal_in_progress = true
	await deal_starting_cards(start_card_count)
	_match_deal_in_progress = false
	_match_deal_complete = true

	for holder in turn_order:
		if holder == null:
			continue
		var hand: Array = []
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null and not ch.get_meta("anim_temp", false):
				hand.append(_serialize_card(ch.card_res))
		var peer_id := _slot_to_peer_id(holder.player_index)
		if peer_id != 0 and int(peer_id) != 1:
			NetworkManager.rpc_id(peer_id, "client_set_hand", hand, NetworkManager.match_epoch)

	await get_tree().process_frame

	var state := _build_match_state()
	state["epoch"] = NetworkManager.match_epoch
	NetworkManager.rpc("client_set_match_state", state, NetworkManager.match_epoch)
	_on_match_state_received(state)

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
			if c.get_parent() == holder:
				holder.remove_child(c)
			c.queue_free()

	for entry: Dictionary in hand:
		holder.add_card(CardResource.from_sync_dict(entry), false)

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
				if cv.get_parent() == holder:
					holder.remove_child(cv)
				cv.queue_free()

	for uid in desired.keys():
		if !current.has(uid):
			var entry: Dictionary = desired[uid]
			var play_appear := false
			if multiplayer.is_server() or _is_authoritative():
				play_appear = true
			holder.add_card(CardResource.from_sync_dict(entry), play_appear)

	holder.sort_cards_full()
	holder.refresh_playable_cards()

## Counts received
func _on_counts_received(hand_counts: Array, deck_count: int) -> void:
	_last_hand_counts = hand_counts.duplicate(true)
	_last_deck_count = int(deck_count)
	if _match_deal_in_progress:
		_refresh_seat_names()
		return
	_try_apply_counts_to_ui()

func _client_counts_blocked() -> bool:
	if multiplayer.is_server():
		return false
	return _client_place_all_animating or _client_deal_animating or _client_swap_animating or _client_play_animating or _client_draw_animating

func _try_apply_counts_to_ui() -> void:
	if _last_hand_counts.is_empty():
		return
	if _match_deal_in_progress:
		return
	if _client_counts_blocked():
		_pending_counts_apply = true
		return
	_pending_counts_apply = false
	_apply_counts_to_ui()

## Build opponent dummy backs from counts
func _apply_counts_to_ui() -> void:
	if _last_hand_counts.is_empty():
		return
	if _match_deal_in_progress:
		return
	if _client_counts_blocked():
		_pending_counts_apply = true
		return
	_pending_counts_apply = false

	var my_slot := int(NetworkManager.my_slot)
	if my_slot < 0:
		my_slot = 0

	var stagger_jobs: Array = []

	for i in range(_last_hand_counts.size()):
		if i == my_slot:
			continue

		var holder: HandCardHolder = _slot_to_holder.get(i, null)
		if holder == null or !is_instance_valid(holder):
			continue
		if is_holder_eliminated(holder):
			continue

		var current_count := _count_cards_in_holder(holder)

		var n := int(_last_hand_counts[i])
		if current_count == n:
			continue

		if current_count > n:
			var to_remove := current_count - n
			var cards: Array[CardView] = []
			for c in holder.get_children():
				if c is CardView and not c.get_meta("anim_temp", false):
					cards.append(c)
			for j in range(to_remove):
				var idx := cards.size() - 1 - j
				if idx < 0:
					break
				var cv: CardView = cards[idx]
				if cv != null and is_instance_valid(cv):
					holder.remove_child(cv)
					cv.queue_free()
		else:
			var to_add := n - current_count
			if to_add > 1 and !multiplayer.is_server():
				stagger_jobs.append([holder, to_add])
			else:
				for k in range(to_add):
					var dummy := CardResource.new()
					dummy.color = CardResource.CardColor.BLACK
					dummy.type = CardResource.CardType.NUMBER
					dummy.value = 0
					dummy.uid = 0
					holder.add_card(dummy, to_add == 1)

		holder.sort_cards_full()

	if stagger_jobs.size() > 0:
		call_deferred("_run_opponent_stagger_jobs", stagger_jobs)

	_apply_local_visibility()
	_refresh_seat_names()

	if !multiplayer.is_server() and my_slot >= 0 and my_slot < _last_hand_counts.size():
		var my_holder: HandCardHolder = _slot_to_holder.get(my_slot, null)
		if my_holder != null and is_instance_valid(my_holder):
			if _client_place_all_animating and _client_place_all_slot == my_slot:
				pass
			elif _client_play_animating:
				pass
			elif _count_cards_in_holder(my_holder) != int(_last_hand_counts[my_slot]):
				call_deferred("_client_request_hand_resync_if_desynced")

func _run_opponent_stagger_jobs(jobs: Array) -> void:
	_client_deal_animating = true
	for job in jobs:
		if job.size() < 2:
			continue
		var holder: HandCardHolder = job[0]
		var count: int = int(job[1])
		if holder == null or !is_instance_valid(holder) or count <= 0:
			continue
		SoundManager.play_draw_card(count)
		for i in range(count):
			await _animate_deal_card_to_holder(holder, _make_dummy_deal_card(), false)
			if i < count - 1:
				await get_tree().create_timer(DEAL_CARD_GAP).timeout
		holder.sort_cards_full()
	_apply_local_visibility()
	_client_deal_animating = false
	_try_apply_pending_hand()
	_apply_counts_to_ui()
	_try_apply_pending_match_state()

## Deck count getter
func get_synced_deck_count() -> int:
	return _last_deck_count

## Group registration
## Registers this node in the queue_manager group on enter tree.
func _enter_tree() -> void:
	add_to_group("queue_manager")

## Server apply play request
## Server: validates and applies a client's play request by card uid.
func server_apply_play(peer_id: int, card_id: int) -> void:
	if not multiplayer.is_server():
		return

	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return

	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or not is_instance_valid(holder):
		return
	if is_holder_eliminated(holder):
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
	var was_place_all := cv.card_res.type == CardResource.CardType.PLACE_ALL
	await holder.set_card(cv)

	# start_place_all awaits to completion and already syncs + advances the turn.
	if was_place_all:
		return

	if card_manager != null and card_manager.waiting_for_color and wild_color_owner == holder:
		var owner_peer := _slot_to_peer_id(holder.player_index)
		if owner_peer > 1:
			NetworkManager.rpc_id(owner_peer, "client_request_color", int(holder.player_index))
		elif owner_peer == 1:
			call_deferred("_ensure_wild_color_resolved", holder)

	# Synchronize match state after card play
	_server_sync_match_state()
	_server_broadcast_counts()

## Server apply draw request
## Server: validates and applies a client's draw request.
func server_apply_draw(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return

	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or not is_instance_valid(holder):
		return
	if is_holder_eliminated(holder):
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
		if _draw_stack_resolving:
			return
		if _try_recover_draw_stack_source_turn(holder):
			_server_sync_match_state()
			return
		if _holder_blocked_from_resolving_draw_stack(holder):
			_server_sync_match_state()
			return
		await _accept_draw_stack_penalty(holder)
		_server_sync_match_state()
		return

	# Normal draw
	var card := card_manager.draw_card()
	if card == null:
		if _try_pass_if_stuck(holder):
			_server_sync_match_state()
		return

	notify_card_drawn(int(slot), 1, true, card)
	holder.add_card(card, true)
	holder.sort_cards_full()
	holder.refresh_playable_cards()
	has_drawn_this_turn = true
	_server_sync_holder_hand(holder)

	if !allow_play_after_draw:
		_finish_draw_turn_if_needed(holder)
		return

	if is_holder_eliminated(holder):
		return
	if _try_eliminate_holder_for_max_cards(holder):
		return
	if !holder_has_playable_card(holder):
		end_turn()
		return

## Server apply target selection from client
## Server: applies target selection for target-draw or swap-hands.
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

	if _swap_resolve_running or _is_swap_already_completed_for_top():
		return
	if swap_color_pending and wild_color_owner == owner_holder:
		return

	if pending_swap_owner == owner_holder:
		pending_swap_owner = null
		_resolve_swap_with_target(owner_holder, target_holder)

## Server apply wild color from client
## Server: applies wild or roulette color from a client RPC.
func server_apply_wild_color(peer_id: int, color: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or !is_instance_valid(holder):
		return

	# Color roulette: next player picks, then draws until that color is drawn.
	if roulette_active and roulette_waiting_for_color:
		if roulette_target != null and int(slot) == int(roulette_target.player_index):
			_resolve_roulette_color(color)
			if multiplayer.is_server():
				NetworkManager.rpc("client_set_wild_color", int(color), int(slot))
				_server_sync_match_state()
		return

	if card_manager == null:
		return
	var needs_color := card_manager.waiting_for_color
	if !needs_color and wild_color_owner == holder and is_instance_valid(holder):
		if holder._waiting_color_turn_end or swap_color_pending:
			needs_color = true
	if !needs_color:
		return
	if wild_color_owner != holder:
		return
	_apply_wild_color(color, slot)

## Host/local authoritative wild color (same path as client RPC).
func server_apply_local_wild_color(color: int) -> void:
	if not _is_authoritative():
		return
	if wild_color_owner == null or !is_instance_valid(wild_color_owner):
		return
	_apply_wild_color(color, int(wild_color_owner.player_index))

## Apply wild color locally and broadcast to clients
func _apply_wild_color(color: int, owner_slot: int) -> void:
	if card_manager == null:
		return
	if card_manager.waiting_for_color:
		card_manager.select_color(color)
	else:
		card_manager.current_color = color
		card_manager.sync_top_card_color_visual()
	Signals.COLOR_color_selected.emit(color)
	if _is_authoritative():
		if roulette_active:
			pass
		elif wild_color_owner != null and is_instance_valid(wild_color_owner):
			var owner := wild_color_owner
			owner._waiting_color_turn_end = false
			owner._pending_effect_card_uid = -1
			owner._busy = false
			if swap_color_pending:
				swap_color_pending = false
				clear_wild_owner()
				end_turn()
			elif card_manager.top_card != null and _can_resolve_card_effect(card_manager.top_card):
				register_card_play(card_manager.top_card, owner)
				clear_wild_owner()
			else:
				clear_wild_owner()
		if multiplayer.has_multiplayer_peer():
			NetworkManager.rpc("client_set_wild_color", int(color), int(owner_slot))
			_server_sync_match_state()

## Client receive wild color
## Client: mirrors wild color from server without re-triggering play logic.
func client_apply_wild_color(color: int, owner_slot: int) -> void:
	if card_manager == null:
		return
	var chosen := int(color) as CardResource.CardColor
	card_manager.waiting_for_color = false
	card_manager.pending_wild_card = null
	card_manager.current_color = chosen
	card_manager.sync_top_card_color_visual()
	card_manager.update_draw_button_state()
	if not roulette_active:
		Signals.COLOR_color_selected.emit(chosen)
	var owner: HandCardHolder = _slot_to_holder.get(int(owner_slot), null)
	if owner != null and is_instance_valid(owner):
		owner._waiting_color_turn_end = false
		owner._pending_effect_card_uid = -1
		owner._busy = false
	clear_wild_owner()
	Signals.COLOR_color_select_dismissed.emit()


func _try_prompt_local_roulette_color() -> void:
	if not is_local_roulette_color_picker():
		return
	var holder: HandCardHolder = _slot_to_holder.get(roulette_target_slot, null)
	if holder == null or not is_instance_valid(holder):
		return
	if card_manager != null and !card_manager.waiting_for_color:
		card_manager.waiting_for_color = true
	set_wild_color_owner(holder)
	Signals.COLOR_request_color_select.emit()


## Client request to show color selector for a specific owner slot
func client_request_color(owner_slot: int) -> void:
	if multiplayer.is_server():
		return
	var holder: HandCardHolder = _slot_to_holder.get(int(owner_slot), null)
	if holder == null or !is_instance_valid(holder):
		return
	set_wild_color_owner(holder)
	_prompt_local_wild_color_picker()

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

	var state := _build_match_state()
	NetworkManager.rpc("client_set_match_state", state, NetworkManager.match_epoch)
	# Do not apply the snapshot on the server — it is authoritative and
	# re-applying (especially mid wild-color pick) can clobber draw_stack.

## Broadcast hand + deck counts to every peer (offline applies locally too).
func _server_broadcast_counts() -> void:
	if not _is_authoritative():
		return

	var counts: Array = []
	var total := maxi(player_count, _slot_to_holder.size())
	for i in range(total):
		var h: HandCardHolder = _slot_to_holder.get(i, null)
		if h == null or not is_instance_valid(h):
			counts.append(0)
		else:
			counts.append(_count_cards_in_holder(h))

	var deck_count := 0
	if card_manager != null and card_manager.deck != null:
		deck_count = int(card_manager.deck.size())

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		NetworkManager.rpc("client_set_counts", counts, deck_count)
	if !multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		NetworkManager.counts_received.emit(counts, deck_count)

## Push a holder's authoritative hand to its owning client. Many special-card
## effects (target/multi draw, swap, roulette, place-all) change a hand purely
## on the server; without this the client keeps showing the old cards, which
## causes desyncs and soft-locks (cards that look playable but no longer exist).
func _server_sync_holder_hand(holder: HandCardHolder, sync_state: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if holder == null or not is_instance_valid(holder):
		return
	if not holder.is_bot:
		var peer_id := _slot_to_peer_id(int(holder.player_index))
		if peer_id != 0 and peer_id != 1:
			var hand: Array = []
			for ch in holder.get_children():
				if ch is CardView and ch.card_res != null and not ch.get_meta("anim_temp", false):
					hand.append(_serialize_card(ch.card_res))
			NetworkManager.rpc_id(peer_id, "client_set_hand", hand, NetworkManager.match_epoch)
	_server_broadcast_counts()
	if sync_state:
		_server_sync_match_state()


## Server: re-push hand for a peer that reports desync.
func server_resync_hand_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := int(_peer_to_slot.get(int(peer_id), -1))
	if slot < 0:
		return
	if _place_all_sequence_running and place_all_owner != null and is_instance_valid(place_all_owner):
		if int(place_all_owner.player_index) == slot:
			return
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or not is_instance_valid(holder) or holder.is_bot:
		return
	_server_sync_holder_hand(holder, true)


func _server_push_hand(holder: HandCardHolder) -> void:
	if not multiplayer.is_server():
		return
	if holder == null or not is_instance_valid(holder) or holder.is_bot:
		return
	_server_sync_holder_hand(holder, false)

## Client play event for opponents
func _on_play_event_received(from_slot: int, card: Dictionary) -> void:
	if multiplayer.is_server():
		return

	SoundManager.play_card_played()
	_client_play_animating = true
	var anim_watchdog := get_tree().create_timer(5.0)
	anim_watchdog.timeout.connect(func() -> void:
		if _client_play_animating:
			push_warning("QueueManager: play animation watchdog fired; releasing client sync lock")
			_client_play_animating = false
			_try_apply_pending_hand()
			_apply_counts_to_ui()
			_try_apply_pending_match_state()
	, CONNECT_ONE_SHOT)
	var my_slot := int(NetworkManager.my_slot)
	
	# Handle own card play - remove card from hand
	if int(from_slot) == my_slot:
		var holder: HandCardHolder = _slot_to_holder.get(int(from_slot), null)
		if holder == null or !is_instance_valid(holder):
			_finish_client_play_animation()
			return

		var card_uid := int(card.get("id", 0))
		var cv: CardView = null
		for ch in holder.get_children():
			if ch is CardView and ch.card_res != null and int(ch.card_res.uid) == card_uid:
				cv = ch
				break

		var r := CardResource.from_sync_dict(card)

		if card_manager != null:
			card_manager.begin_top_card_suppression()

		if cv != null and is_instance_valid(cv):
			cv.set_clickable(false, true)
			if is_instance_valid(cv):
				await cv.fly_to_discard_pile(0.3)
			if is_instance_valid(cv):
				if cv.get_parent() != null:
					cv.get_parent().remove_child(cv)
				cv.queue_free()

		clear_client_play_in_flight(card_uid)

		var is_wild_play := r.type in [
			CardResource.CardType.WILD,
			CardResource.CardType.WILD_DRAW,
			CardResource.CardType.WILD_DRAW_REVERSE,
		]
		if is_wild_play:
			set_wild_color_owner(holder)
			holder._waiting_color_turn_end = true
			holder._pending_effect_card_uid = int(r.uid)

		if card_manager != null:
			card_manager.end_top_card_suppression(r, false)

		update_turn_state()

		if is_wild_play:
			if card_manager != null:
				card_manager.waiting_for_color = true
				card_manager.current_color = CardResource.CardColor.BLACK
				card_manager.pending_wild_card = card_manager.top_card
				card_manager.sync_top_card_color_visual()
			call_deferred("_ensure_wild_color_resolved", holder)

		holder.sort_cards_full()
		holder.refresh_playable_cards()
		holder.notify_remote_play_finished()
		_finish_client_play_animation()
		return

	var holder: HandCardHolder = _slot_to_holder.get(int(from_slot), null)
	if holder == null or not is_instance_valid(holder):
		_finish_client_play_animation()
		return

	var r := CardResource.from_sync_dict(card)

	if card_manager != null:
		card_manager.begin_top_card_suppression()

	var cv := _acquire_client_fly_card_view(holder, r, false)
	if cv == null:
		if card_manager != null:
			card_manager.end_top_card_suppression(r, false)
		_finish_client_play_animation()
		return

	await get_tree().process_frame
	await get_tree().process_frame

	await cv.fly_to_discard_pile(0.3)

	if cv != null and is_instance_valid(cv):
		if cv.get_parent() != null:
			cv.get_parent().remove_child(cv)
		cv.queue_free()

	var is_wild_play := r.type in [
		CardResource.CardType.WILD,
		CardResource.CardType.WILD_DRAW,
		CardResource.CardType.WILD_DRAW_REVERSE,
	]

	if card_manager != null:
		card_manager.end_top_card_suppression(r, false)

	if is_wild_play:
		set_wild_color_owner(holder)
		if card_manager != null:
			card_manager.waiting_for_color = true
			card_manager.current_color = CardResource.CardColor.BLACK
			card_manager.pending_wild_card = card_manager.top_card
			card_manager.sync_top_card_color_visual()

	update_turn_state()
	_refresh_seat_names()
	_try_apply_counts_to_ui()
	_finish_client_play_animation()

func _on_client_swap_hands_visual(
	owner_slot: int,
	target_slot: int,
	owner_count: int,
	target_count: int,
	anim_seed: int
) -> void:
	if _is_dedicated_server_peer():
		return
	if !multiplayer.is_server():
		_client_swap_animating = true
		var swap_watchdog := get_tree().create_timer(8.0)
		swap_watchdog.timeout.connect(func() -> void:
			if _client_swap_animating:
				push_warning("QueueManager: swap animation watchdog fired; releasing client sync lock")
				_finish_client_swap_animation()
		, CONNECT_ONE_SHOT)
	var owner := get_holder_for_slot(int(owner_slot))
	var target := get_holder_for_slot(int(target_slot))
	var feedback := _get_swap_hands_feedback()
	if feedback == null or owner == null or target == null or !is_instance_valid(owner) or !is_instance_valid(target):
		if !multiplayer.is_server():
			call_deferred("_finish_client_swap_animation")
		else:
			call_deferred("_emit_swap_visual_finished", feedback)
		return
	if feedback.has_signal("visual_finished") and !multiplayer.is_server():
		feedback.visual_finished.connect(_finish_client_swap_animation, CONNECT_ONE_SHOT)
	if feedback.has_method("begin_swap_visual"):
		feedback.begin_swap_visual(owner, target, int(owner_count), int(target_count), int(anim_seed))
	elif !multiplayer.is_server():
		call_deferred("_finish_client_swap_animation")


func _is_dedicated_server_peer() -> bool:
	return multiplayer.is_server() and (OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless")


func _emit_swap_visual_finished(feedback: Node) -> void:
	if feedback != null and is_instance_valid(feedback) and feedback.has_signal("visual_finished"):
		feedback.visual_finished.emit()

func _finish_client_swap_animation() -> void:
	_client_swap_animating = false
	_try_apply_pending_hand()
	_apply_counts_to_ui()
	_try_apply_pending_match_state()
	if swap_color_pending and wild_color_owner != null:
		_prompt_local_wild_color_picker()

func _finish_client_play_animation() -> void:
	_client_play_animating = false
	_try_apply_pending_hand()
	_apply_counts_to_ui()
	_try_apply_pending_match_state()

func _finish_client_draw_animation() -> void:
	_client_draw_animating = false
	_apply_counts_to_ui()
	_try_apply_pending_hand()
	_try_apply_pending_match_state()

func _schedule_client_hand_watchdog() -> void:
	if multiplayer.is_server() or _client_hand_watchdog_armed:
		return
	_client_hand_watchdog_armed = true
	var watchdog := get_tree().create_timer(5.0)
	watchdog.timeout.connect(func() -> void:
		_client_hand_watchdog_armed = false
		if _client_place_all_animating:
			return
		if _pending_hand.is_empty():
			_client_request_hand_resync_if_desynced()
			return
		push_warning("QueueManager: hand sync watchdog fired; applying buffered hand")
		_release_client_hand_sync_locks()
		_try_apply_pending_hand()
		_apply_counts_to_ui()
		_try_apply_pending_match_state()
		if !_pending_hand.is_empty():
			_client_request_hand_resync_if_desynced()
	, CONNECT_ONE_SHOT)

func _client_request_hand_resync_if_desynced() -> void:
	if multiplayer.is_server():
		return
	if _client_play_animating or _client_place_all_animating:
		return
	var slot := int(NetworkManager.my_slot)
	if slot < 0 or slot >= _last_hand_counts.size():
		return
	var holder: HandCardHolder = _slot_to_holder.get(slot, null)
	if holder == null or !is_instance_valid(holder):
		return
	var live := _count_cards_in_holder(holder)
	var server_count := int(_last_hand_counts[slot])
	if live == server_count:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hand_resync_ms < 3000:
		return
	_last_hand_resync_ms = now
	push_warning(
		"QueueManager: hand desync (%d local vs %d server); requesting resync" % [live, server_count]
	)
	NetworkManager.request_hand_sync()

func _release_client_hand_sync_locks() -> void:
	_client_draw_animating = false
	_client_draw_queue.clear()
	_client_swap_animating = false

## Client: fly a drawn card from the deck pile into a player's hand.
func _on_draw_event_received(from_slot: int, card_c: int, card_t: int, card_v: int, card_id: int) -> void:
	if multiplayer.is_server():
		return
	# Own draws are authoritative via client_set_hand; animating them blocks hand sync.
	if int(from_slot) == int(NetworkManager.my_slot):
		return
	_client_draw_queue.append([int(from_slot), int(card_c), int(card_t), int(card_v), int(card_id)])
	call_deferred("_try_run_client_draw_queue")

func _try_run_client_draw_queue() -> void:
	if _client_draw_animating or _client_draw_queue.is_empty():
		return
	call_deferred("_run_client_draw_queue")

func _run_client_draw_queue() -> void:
	if _client_draw_animating:
		return
	_client_draw_animating = true
	var draw_watchdog := get_tree().create_timer(8.0)
	draw_watchdog.timeout.connect(func() -> void:
		if _client_draw_animating:
			push_warning("QueueManager: draw animation watchdog fired; releasing client sync lock")
			_client_draw_queue.clear()
			_finish_client_draw_animation()
	, CONNECT_ONE_SHOT)
	while _client_draw_queue.size() > 0:
		var job: Array = _client_draw_queue.pop_front()
		if job.size() < 5:
			continue
		var slot: int = int(job[0])
		var card_c: int = int(job[1])
		var card_t: int = int(job[2])
		var card_v: int = int(job[3])
		var card_id: int = int(job[4])
		var holder: HandCardHolder = _slot_to_holder.get(slot, null)
		if holder == null or !is_instance_valid(holder):
			continue
		var res: CardResource = _make_dummy_deal_card()
		await _animate_deal_card_to_holder(holder, res, true)
		_refresh_seat_names()
	_finish_client_draw_animation()

func _finish_client_place_all_animation() -> void:
	_client_place_all_animating = false
	_client_place_all_slot = -1
	_client_suppress_draw_sound_once = true
	_try_apply_pending_hand()
	_apply_counts_to_ui()
	_try_apply_pending_match_state()

## Client: animate a remote (or own) place-all sequence from server broadcast.
func _on_place_all_event_received(from_slot: int, color: int, cards: Array) -> void:
	if multiplayer.is_server():
		return
	_client_place_all_animating = true
	_client_place_all_slot = int(from_slot)
	var pa_watchdog := get_tree().create_timer(10.0)
	pa_watchdog.timeout.connect(func() -> void:
		if _client_place_all_animating:
			push_warning("QueueManager: place-all animation watchdog fired; releasing client sync lock")
			_finish_client_place_all_animation()
	, CONNECT_ONE_SHOT)
	call_deferred("_client_animate_place_all", int(from_slot), int(color), cards)

func _client_animate_place_all(from_slot: int, color: int, cards: Array) -> void:
	if !_client_place_all_animating:
		_client_place_all_animating = true
		_client_place_all_slot = from_slot

	var holder: HandCardHolder = _slot_to_holder.get(from_slot, null)
	if holder == null or !is_instance_valid(holder) or cards.is_empty():
		_finish_client_place_all_animation()
		return

	place_all_active = true
	place_all_owner = holder
	place_all_color = int(color) as CardResource.CardColor

	var my_slot := int(NetworkManager.my_slot)
	var is_own_hand := int(from_slot) == my_slot

	if card_manager != null:
		card_manager.begin_top_card_suppression()

	var duration := 0.20
	var delay_between := 0.01

	for i in range(cards.size()):
		var entry = cards[i]
		if not (entry is Dictionary):
			continue

		var res := CardResource.from_sync_dict(entry)
		# Always allow fallback so a uid mismatch (minor desync) never silently
		# drops the fly animation — the correct face is set from res either way.
		var cv := _acquire_client_fly_card_view(holder, res, is_own_hand, true)
		if cv == null:
			if card_manager != null:
				card_manager.set_top_card_no_effect(res)
			if i < cards.size() - 1:
				await get_tree().create_timer(delay_between).timeout
			continue

		var anim_duration := 0.26 if i == cards.size() - 1 else duration

		SoundManager.play_card_played()
		await get_tree().process_frame
		await get_tree().process_frame
		await cv.fly_to_discard_pile(anim_duration)
		if is_instance_valid(cv):
			if cv.get_parent() == holder:
				holder.remove_child(cv)
			cv.queue_free()

		if card_manager != null:
			card_manager.set_top_card_no_effect(res)

		if i < cards.size() - 1:
			await get_tree().create_timer(delay_between).timeout

	if card_manager != null and cards.size() > 0 and cards[-1] is Dictionary:
		card_manager.end_top_card_suppression(CardResource.from_sync_dict(cards[-1]), false)
	elif card_manager != null:
		card_manager.end_top_card_suppression(null, false)

	place_all_active = false
	place_all_owner = null
	place_all_color = CardResource.CardColor.RED

	if is_instance_valid(holder):
		holder.sort_cards_full()
		holder.refresh_playable_cards()
		if is_own_hand:
			holder._busy = false
			holder.notify_remote_play_finished()

	update_turn_state()
	_finish_client_place_all_animation()

func _server_sync_late_joiners(players_in: Array) -> void:
	if not _server_match_started:
		return
	if card_manager == null:
		return

	var state := _build_match_state()

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

		NetworkManager.rpc_id(peer_id, "client_set_match_state", state, NetworkManager.match_epoch)
		NetworkManager.rpc_id(peer_id, "client_set_hand", hand, NetworkManager.match_epoch)

	_server_broadcast_counts()
