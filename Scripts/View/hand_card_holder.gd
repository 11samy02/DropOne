extends HBoxContainer
class_name HandCardHolder

const HAND_CARD_HOLDER = preload("uid://bpglgdslmw461")

@export var CARD_VIEW: PackedScene
@export var smooth_speed: float = 12.0
@export var card_manager: CardManager
@export var queue_manager: QueueManager
@export var is_bot := false
@export var compact_view := false
@export var profile: PlayerProfile


var player_index := -1
var bot_index := -1
var turn_active := false
var _current_sep: float = 0.0

var _busy := false
var _queued: CardView = null
var _waiting_color_turn_end := false

## Creates and returns an instance of this holder scene
static func create() -> HandCardHolder:
	return HAND_CARD_HOLDER.instantiate()

## Connects required signals for wild color selection follow-up
func _ready() -> void:
	Signals.COLOR_color_selected.connect(_on_color_selected)

## Updates card alignment smoothly every frame
func _process(delta: float) -> void:
	align_cards(delta)

## Activates or deactivates this holder's turn state and refreshes playable cards
func set_turn_active(value: bool) -> void:
	turn_active = value
	refresh_playable_cards()

## Smoothly aligns cards based on dynamic separation for the current hand size
func align_cards(delta: float) -> void:
	var count := get_child_count()
	var target_sep := _get_target_separation(count)
	_current_sep = lerp(_current_sep, float(target_sep), 1.0 - exp(-smooth_speed * delta))
	add_theme_constant_override("separation", int(round(_current_sep)))

## Returns the appropriate card separation based on how many cards are in the hand
func _get_target_separation(count: int) -> int:
	if is_bot or compact_view: return -162
	if count <= 7: return 0
	if count <= 10: return -25
	if count <= 15: return -50
	if count <= 21: return -75
	if count <= 28: return -100
	if count <= 36: return -125
	if count <= 45: return -130
	if count <= 52: return -135
	if count <= 61: return -140
	if count <= 75: return -145
	if count <= 90: return -150
	return -153

## Defines ordering rules for sorting cards by color, type, and value
func _compare_cards(a: CardResource, b: CardResource) -> bool:
	var color_order := {
		CardResource.CardColor.RED: 0,
		CardResource.CardColor.GREEN: 1,
		CardResource.CardColor.BLUE: 2,
		CardResource.CardColor.YELLOW: 3,
		CardResource.CardColor.BLACK: 4
	}

	var type_order := {
		CardResource.CardType.NUMBER: 0,
		CardResource.CardType.DRAW: 1,
		CardResource.CardType.TARGET_DRAW: 2,
		CardResource.CardType.MULTI_TARGET_DRAW: 3,
		CardResource.CardType.SKIP: 4,
		CardResource.CardType.REVERSE: 5,
		CardResource.CardType.PLACE_ALL: 6,
		CardResource.CardType.WILD: 7,
		CardResource.CardType.WILD_DRAW: 8,
		CardResource.CardType.WILD_DRAW_REVERSE: 9,
		CardResource.CardType.SWAP_HANDS: 10,
		CardResource.CardType.WILD_COLOR_ROULET: 11
	}

	var ca = color_order[a.color]
	var cb = color_order[b.color]
	if ca != cb:
		return ca < cb

	var ta = type_order.get(a.type, 999)
	var tb = type_order.get(b.type, 999)
	if ta != tb:
		return ta < tb

	return a.value < b.value

## Returns the correct insertion index for a new card based on sorting rules
func _get_insert_index(card_res: CardResource) -> int:
	var children := get_children()
	for i in range(children.size()):
		var c := children[i]
		if c is CardView and c.card_res != null:
			if _compare_cards(card_res, c.card_res):
				return i
	return children.size()

## Adds a card to this holder and places it directly into the correct sorted position
func add_card(card_res: CardResource, play_appear: bool = false) -> void:
	var card_view: CardView = CARD_VIEW.instantiate()
	card_view.in_hand_card = true
	card_view.hand_card_holder = self
	card_view.visible = false
	card_view.set_meta("play_appear", play_appear)

	add_child(card_view)

	card_view.card_res = card_res
	card_view.show_front = !is_bot
	
	if card_view.has_method("load_card"):
		card_view.load_card()
	
	var idx := _get_insert_index(card_res)
	move_child(card_view, idx)

	call_deferred("_finalize_spawned_card", card_view)


## Finalizes a newly added card after layout settles and plays an appear animation if available
func _finalize_spawned_card(card_view: CardView) -> void:
	if card_view == null or !is_instance_valid(card_view):
		return

	if !is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return

	await tree.process_frame
	await tree.process_frame

	if card_view == null or !is_instance_valid(card_view):
		return
	if !is_inside_tree():
		return

	card_view.visible = true

	if card_view.get_meta("play_appear", false):
		if card_view.has_node("AnimationPlayer"):
			var ap := card_view.get_node("AnimationPlayer") as AnimationPlayer
			if ap != null and ap.has_animation("appear"):
				ap.play("appear")

	refresh_playable_cards()

## Plays a card, handles special rules, and supports place-all finisher selection flow
func set_card(card_view: CardView) -> void:
	if card_view == null or !is_instance_valid(card_view) or card_view.card_res == null:
		return
	if _busy:
		_queued = card_view
		return
	if queue_manager == null:
		return
	if !queue_manager.can_play_now(self):
		return
	if !can_play_card(card_view.card_res):
		return
	
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		_busy = true
		_queued = null
		NetworkManager.request_play(int(card_view.card_res.uid))
		await get_tree().create_timer(0.15).timeout
		_busy = false
		return
	
	_busy = true
	_queued = null
	
	var played_card_res := card_view.card_res
	
	if played_card_res.type == CardResource.CardType.PLACE_ALL:
		card_view.set_clickable(false, true)
		_busy = true
		_queued = null
		queue_manager.start_place_all(self, played_card_res.color, played_card_res, card_view)
		return
	
	# Multiplayer: broadcast the play so every client flies this card to the
	# discard pile. This runs on the server for BOTH the host's own plays and
	# client plays (which reach here via server_apply_play), so the placement
	# animation now shows on non-host peers too (previously only client plays
	# were broadcast, so the host's cards just snapped into place for others).
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var ev := {
			"c": int(played_card_res.color),
			"t": int(played_card_res.type),
			"v": int(played_card_res.value),
			"id": int(played_card_res.uid),
		}
		NetworkManager.rpc("client_play_event", int(player_index), ev)
	
	card_view.set_clickable(false, true)
	var animation_duration := 0.3
	card_view.smooth_move_button_to_top_card_juicy(animation_duration)
	await get_tree().create_timer(animation_duration).timeout
	
	if is_instance_valid(card_view):
		remove_child(card_view)
		card_view.queue_free()
	
	if queue_manager != null:
		match played_card_res.type:
			CardResource.CardType.WILD, \
			CardResource.CardType.WILD_DRAW, \
			CardResource.CardType.WILD_DRAW_REVERSE:
				queue_manager.set_wild_color_owner(self)
	
	card_manager.set_top_card_runtime(played_card_res)
	
	_busy = false
	refresh_playable_cards()
	
	if card_manager.waiting_for_color:
		_waiting_color_turn_end = true
	else:
		queue_manager.register_card_play(played_card_res)
	
	if _queued != null and is_instance_valid(_queued):
		var next := _queued
		_queued = null
		call_deferred("set_card", next)

## Returns whether a card may be played under the current top card and game rules
func can_play_card(card_res: CardResource) -> bool:
	if card_res == null:
		return false

	if queue_manager != null and queue_manager.place_all_active:
		if queue_manager.place_all_owner != self:
			return false
		if card_res.color != queue_manager.place_all_color:
			return false
		return true

	# Target Draw and Multi Target Draw are NOT stackable: once played they
	# resolve immediately, the targeted player(s) just draw. No counter-play.

	if queue_manager != null and queue_manager.draw_stack_amount > 0:
		if queue_manager.draw_stack_is_wild:
			if card_res.type != CardResource.CardType.WILD_DRAW and card_res.type != CardResource.CardType.WILD_DRAW_REVERSE:
				return false
			if card_res.value < queue_manager.draw_stack_min_value:
				return false
			return true
		if card_res.type != CardResource.CardType.DRAW:
			return false

		if card_res.value == queue_manager.draw_stack_min_value:
			return true

		if card_res.value > queue_manager.draw_stack_min_value:
			return card_res.color == queue_manager.draw_stack_color

		return false

	var top := card_manager.top_card
	if top == null:
		return false

	var current_color := card_manager.current_color

	match card_res.type:
		CardResource.CardType.WILD, CardResource.CardType.WILD_DRAW, CardResource.CardType.WILD_DRAW_REVERSE, CardResource.CardType.SWAP_HANDS, CardResource.CardType.WILD_COLOR_ROULET:
			return true

	if card_res.color == current_color and card_res.color != CardResource.CardColor.BLACK:
		return true

	if card_res.type == top.type and card_res.type != CardResource.CardType.NUMBER:
		if card_res.type == CardResource.CardType.DRAW:
			if top.type == CardResource.CardType.DRAW:
				if card_res.value == top.value:
					return true
				if card_res.color == top.color and card_res.value > top.value:
					return true
				return false
			return card_res.color == current_color
		return true

	if card_res.type == CardResource.CardType.NUMBER and top.type == CardResource.CardType.NUMBER and card_res.value == top.value:
		return true

	return false

## Sorts the full hand instantly into correct order using the compare rules
func sort_cards_full() -> void:
	var card_views: Array[CardView] = []
	for c in get_children():
		if c is CardView:
			card_views.append(c)

	if card_views.size() <= 1:
		return

	card_views.sort_custom(func(a, b):
		return _compare_cards(a.card_res, b.card_res)
	)

	for i in range(card_views.size()):
		move_child(card_views[i], i)

## Refreshes clickable state and visuals for all cards in this hand
func refresh_playable_cards() -> void:
	if !is_bot:
		for c in get_children():
			if c is CardView:
				if !c.show_front:
					c.set_clickable(false, true)
					smooth_modulate(c, Color.WHITE, 0.3)
					continue

				var playable := can_play_card(c.card_res)
				var allowed = turn_active and !is_bot and c.show_front and playable
				c.set_clickable(allowed)

				var target_color := Color.WHITE if allowed else Color.DIM_GRAY
				smooth_modulate(c, target_color, 0.3)

## Smoothly transitions node modulate color for playable feedback
func smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.15) -> void:
	if node.has_meta("modulate_tween"):
		var old_tween = node.get_meta("modulate_tween")
		if old_tween and old_tween.is_running():
			old_tween.kill()

	var tween := create_tween()
	tween.tween_property(node, "modulate", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	node.set_meta("modulate_tween", tween)

## Queues post-wild processing after a color has been selected
func _on_color_selected(_color: CardResource.CardColor) -> void:
	call_deferred("_after_color_selected")

## Finalizes wild play and turn flow after color selection
func _after_color_selected() -> void:
	refresh_playable_cards()
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		_waiting_color_turn_end = false
		if queue_manager != null:
			queue_manager.clear_wild_owner()
		return
	if _waiting_color_turn_end:
		_waiting_color_turn_end = false
		queue_manager.register_card_play(card_manager.top_card)
		queue_manager.clear_wild_owner()

	# Keep target turn UI in sync after wild color selection
	if queue_manager != null and multiplayer.is_server():
		queue_manager.update_turn_state()

## Returns all card resources currently inside this hand
func get_all_card_resources() -> Array[CardResource]:
	var arr: Array[CardResource] = []
	for c in get_children():
		if c is CardView and c.card_res != null:
			arr.append(c.card_res)
	return arr

func setup_profile(index: int, bot: bool, name: String = "") -> void:
	player_index = index
	is_bot = bot

	if profile == null:
		profile = PlayerProfile.new()

	profile.player_index = index
	profile.is_bot = bot
	profile.holder = self

	if name.strip_edges() != "":
		profile.player_name = name
	elif profile.player_name.strip_edges() == "":
		profile.player_name = "Player " + str(index + 1)

	profile.ensure_picture()
