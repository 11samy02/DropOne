extends HBoxContainer
class_name HandCardHolder

const HAND_CARD_HOLDER = preload("uid://bpglgdslmw461")

@export var CARD_VIEW: PackedScene
@export var smooth_speed: float = 12.0
@export var card_manager: CardManager
@export var is_bot := false

var _current_sep: float = 0.0

var _busy := false
var _queued: CardView = null

static func create() -> HandCardHolder:
	return HAND_CARD_HOLDER.instantiate()


func _process(delta: float) -> void:
	align_cards(delta)

func align_cards(delta: float) -> void:
	var count := get_child_count()
	var target_sep := _get_target_separation(count)
	_current_sep = lerp(_current_sep, float(target_sep), 1.0 - exp(-smooth_speed * delta))
	add_theme_constant_override("separation", int(round(_current_sep)))

func _get_target_separation(count: int) -> int:
	if count <= 7: return 0
	if count <= 10: return -75
	if count <= 15: return -125
	if count <= 25: return -165
	return -180

func add_card(card_res: CardResource) -> void:
	var card_view: CardView = CARD_VIEW.instantiate()
	card_view.card_res = card_res
	card_view.hand_card_holder = self
	card_view.show_front = !is_bot
	add_child(card_view)
	if !is_bot:
		card_view.set_clickable(true)

func set_card(card_view: CardView) -> void:
	if card_view == null or !is_instance_valid(card_view) or card_view.card_res == null:
		return

	if _busy:
		_queued = card_view
		return

	if !can_play_card(card_view.card_res):
		return

	_busy = true
	_queued = null

	card_view.set_clickable(false, true)
	card_view.animation_player.play("set")
	await card_view.animation_player.animation_finished

	if is_instance_valid(card_view):
		remove_child(card_view)
		card_view.queue_free()

	card_manager.set_top_card_runtime(card_view.card_res)

	_busy = false

	refresh_playable_cards()

	if _queued != null and is_instance_valid(_queued):
		var next := _queued
		_queued = null
		call_deferred("set_card", next)


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

func refresh_clickable_cards() -> void:
	for c in get_children():
		if c is CardView:
			c.can_be_clicked()

func refresh_playable_cards() -> void:
	for c in get_children():
		if c is CardView:
			var playable := can_play_card(c.card_res)
			c.set_clickable(!is_bot and c.show_front and playable)
			c.set_pulsing(playable)
