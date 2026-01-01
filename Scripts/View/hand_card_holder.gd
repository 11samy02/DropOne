extends HBoxContainer
class_name HandCardHolder

const HAND_CARD_HOLDER = preload("uid://bpglgdslmw461")

@export var CARD_VIEW: PackedScene
@export var smooth_speed: float = 12.0
@export var card_manager: CardManager
@export var queue_manager: QueueManager
@export var is_bot := false

var player_index := -1
var bot_index := -1

var turn_active := false
var _current_sep: float = 0.0

var _busy := false
var _queued: CardView = null
var _waiting_color_turn_end := false




static func create() -> HandCardHolder:
	return HAND_CARD_HOLDER.instantiate()

func _ready() -> void:
	Signals.COLOR_color_selected.connect(_on_color_selected)

func _process(delta: float) -> void:
	align_cards(delta)
	


## Sets active state for turn control
func set_turn_active(value: bool) -> void:
	turn_active = value
	refresh_playable_cards()


## Aligns cards smoothly based on count
func align_cards(delta: float) -> void:
	var count := get_child_count()
	var target_sep := _get_target_separation(count)
	_current_sep = lerp(_current_sep, float(target_sep), 1.0 - exp(-smooth_speed * delta))
	add_theme_constant_override("separation", int(round(_current_sep)))


## Returns separation value for current hand size
func _get_target_separation(count: int) -> int:
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


## Adds a card view to this holder
func add_card(card_res: CardResource) -> void:
	var card_view: CardView = CARD_VIEW.instantiate()
	card_view.hand_card_holder = self
	add_child(card_view)
	card_view.card_res = card_res
	card_view.show_front = !is_bot
	refresh_playable_cards()



## Plays a card and handles wild color selection correctly
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
	
	_busy = true
	_queued = null
	
	card_view.set_clickable(false, true)
	var animation_duration := 0.3
	card_view.smooth_move_button_to_top_card(animation_duration)
	await get_tree().create_timer(animation_duration).timeout
	
	var played_card_res := card_view.card_res
	
	if is_instance_valid(card_view):
		remove_child(card_view)
		card_view.queue_free()
	
	card_manager.set_top_card_runtime(played_card_res)
	
	_busy = false
	refresh_playable_cards()
	
	if card_manager.waiting_for_color:
		_waiting_color_turn_end = true
	else:
		queue_manager.register_card_play()
	
	if _queued != null and is_instance_valid(_queued):
		var next := _queued
		_queued = null
		call_deferred("set_card", next)



## Checks if card matches current top card rules
func can_play_card(card_res: CardResource) -> bool:
	if card_res == null:
		return false

	if card_manager.waiting_for_color:
		return false

	var top := card_manager.top_card
	if top == null:
		return false

	var current_color := card_manager.current_color

	if card_res.type == CardResource.CardType.WILD or card_res.type == CardResource.CardType.WILD_DRAW:
		return true

	if card_res.color == current_color and card_res.color != CardResource.CardColor.BLACK:
		return true

	if card_res.type == top.type and card_res.type != CardResource.CardType.NUMBER:
		return true

	if card_res.type == CardResource.CardType.NUMBER and top.type == CardResource.CardType.NUMBER and card_res.value == top.value:
		return true

	return false


## Sorts hand by color, type and value
func sort_cards_full() -> void:
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
		CardResource.CardType.SKIP: 2,
		CardResource.CardType.REVERSE: 3,
		CardResource.CardType.WILD: 4,
		CardResource.CardType.WILD_DRAW: 5
	}

	var card_views: Array = get_children()
	card_views.sort_custom(func(a, b):
		var ar = a.card_res
		var br = b.card_res

		var ca = color_order[ar.color]
		var cb = color_order[br.color]
		if ca != cb:
			return ca < cb

		var ta = type_order[ar.type]
		var tb = type_order[br.type]
		if ta != tb:
			return ta < tb

		return ar.value < br.value
	)

	for i in range(card_views.size()):
		move_child(card_views[i], i)


## Refreshes clickable state for all cards
func refresh_clickable_cards() -> void:
	for c in get_children():
		if c is CardView:
			c.can_be_clicked()


## Updates clickability for all hand cards based on rules and turn state
func refresh_playable_cards() -> void:
	for c in get_children():
		if c is CardView:
			var playable := can_play_card(c.card_res)
			var allowed = turn_active and !is_bot and c.show_front and playable
			c.set_clickable(allowed)
			
			var target_color := Color.WHITE if allowed else Color.DIM_GRAY
			smooth_modulate(c, target_color, 0.3)

func smooth_modulate(node: CanvasItem, target: Color, duration: float = 0.15) -> void:
	if node.has_meta("modulate_tween"):
		var old_tween = node.get_meta("modulate_tween")
		if old_tween and old_tween.is_running():
			old_tween.kill()
		
	var tween := create_tween()
	tween.tween_property(node, "modulate", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	node.set_meta("modulate_tween", tween)


## Refreshes playable cards after wild color was applied and handles solo turn end
func _on_color_selected(_color: CardResource.CardColor) -> void:
	call_deferred("_after_color_selected")

## Executes after CardManager updated waiting_for_color
func _after_color_selected() -> void:
	refresh_playable_cards()
	
	if _waiting_color_turn_end:
		_waiting_color_turn_end = false
		queue_manager.register_card_play()
