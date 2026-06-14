@tool
extends Control
class_name CardView

## Reference to the top card used as fly-to target for play animations.
static var current_top_card: CardView

var hand_card_holder: HandCardHolder

## True when this view represents a card in a player's hand.
var in_hand_card := true

@export var is_top_card := false
@export_enum("Small", "Medium", "Large") var card_size := "Medium"

var _show_front := true
@export var show_front := true:
	get:
		return _show_front
	set(value):
		_show_front = value
		if is_inside_tree():
			_queue_load_card()

var _card_res: CardResource = null
@export var card_res: CardResource:
	get:
		return _card_res
	set(value):
		_card_res = value
		if is_inside_tree():
			_queue_load_card()

var _override_color_enabled := false
@export var override_color_enabled := false:
	get:
		return _override_color_enabled
	set(value):
		_override_color_enabled = value
		if is_inside_tree():
			_queue_load_card()

var _override_color: CardResource.CardColor = CardResource.CardColor.RED
@export var override_color: CardResource.CardColor = CardResource.CardColor.RED:
	get:
		return _override_color
	set(value):
		_override_color = value
		if is_inside_tree():
			_queue_load_card()

@onready var background: TextureRect = %background
@onready var center_num: Label = %center_num
@onready var corner_num: Label = %corner_num
@onready var symbol: TextureRect = %symbol
@onready var shadow_symbol: TextureRect = %shadow_symbol
@onready var corner_symbol: TextureRect = %corner_symbol2
@onready var left_shadow_symbol: TextureRect = %left_shadow_symbol
@onready var corner_color_blind_symbol: TextureRect = %corner_color_blind_symbol
@onready var right_shadow_symbol: TextureRect = %right_shadow_symbol
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var button: Button = %button
@onready var visuells: Control = %visuells
var _is_ready := false

const COLOR_BLUE := Color("#0027da")
const COLOR_YELLOW := Color("#c39f00")
const COLOR_RED := Color("#ad0000")
const COLOR_GREEN := Color("#0ca500")
const COLOR_BLACK_TEXT := Color.WHITE

## Scene setup: load visuals, play appear animation, track top card ref.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_ready = true

	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	visible = true
	show()

	load_card()
	rezise_card()

	if animation_player != null and animation_player.has_animation("appear"):
		if in_hand_card:
			animation_player.play("appear")
		else:
			animation_player.play("appear")
			animation_player.seek(animation_player.current_animation_length, true)
			animation_player.stop()
	else:
		if animation_player != null:
			animation_player.stop()

	if is_top_card:
		current_top_card = self


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		load_card()
	rezise_card()

## Load and apply all visuals based on current card state
func load_card() -> void:
	if _card_res == null:
		return
	if !_ui_ready():
		return

	if !_show_front:
		background.texture = _card_res.get_background_texture(true)
		_hide_front()
		update_playable_visuals()
		return

	var display_color := _card_res.color
	if _override_color_enabled:
		display_color = _override_color

	background.texture = _card_res.get_background_texture_for_color(display_color)

	var sym := _card_res.get_symbol_texture()
	var text := _card_res.get_display_text()
	var c := get_card_color(display_color)

	center_num.modulate = Color.WHITE
	corner_num.modulate = Color.WHITE

	_apply_colorblind_symbol(display_color, c)

	if sym != null:
		symbol.show()
		corner_symbol.show()

		symbol.texture = sym
		corner_symbol.texture = sym
		shadow_symbol.texture = sym
		left_shadow_symbol.texture = sym
		right_shadow_symbol.texture = sym
		
		

		center_num.hide()

		if text != "":
			corner_num.show()
			corner_num.text = text
			corner_symbol.hide()
			shadow_symbol.hide()
		else:
			corner_num.hide()
			shadow_symbol.show()

		var is_wild_style := (
			_card_res.type == CardResource.CardType.WILD
			or _card_res.type == CardResource.CardType.WILD_DRAW
			or _card_res.type == CardResource.CardType.WILD_DRAW_REVERSE
			or _card_res.type == CardResource.CardType.SWAP_HANDS
			or _card_res.type == CardResource.CardType.WILD_COLOR_ROULET
		)

		if !is_wild_style:
			symbol.modulate = c
			shadow_symbol.show()
		else:
			symbol.modulate = Color.WHITE
			shadow_symbol.hide()
	else:
		symbol.hide()
		corner_symbol.hide()
		shadow_symbol.hide()
		left_shadow_symbol.hide()
		right_shadow_symbol.hide()

		center_num.show()
		corner_num.show()

		center_num.text = text
		corner_num.text = text
		center_num.modulate = c

	update_playable_visuals()

func _ui_ready() -> bool:
	return background != null \
		and center_num != null \
		and corner_num != null \
		and symbol != null \
		and shadow_symbol != null \
		and corner_symbol != null \
		and left_shadow_symbol != null \
		and corner_color_blind_symbol != null \
		and right_shadow_symbol != null

func _queue_load_card() -> void:
	if _is_ready:
		load_card()
	else:
		call_deferred("_deferred_load_card")

func _deferred_load_card() -> void:
	if _is_ready:
		load_card()

func can_be_clicked() -> void:
	update_playable_visuals()

## Hide front UI elements for back-side display
func _hide_front() -> void:
	center_num.hide()
	corner_num.hide()
	symbol.hide()
	corner_symbol.hide()
	shadow_symbol.hide()
	left_shadow_symbol.hide()
	right_shadow_symbol.hide()
	corner_color_blind_symbol.hide()

## Apply colorblind symbol based on current color
func _apply_colorblind_symbol(display_color: CardResource.CardColor, _c: Color) -> void:
	if display_color == CardResource.CardColor.BLACK:
		corner_color_blind_symbol.hide()
		return
	corner_color_blind_symbol.show()
	corner_color_blind_symbol.texture = _card_res.get_color_blind_symbol_texture_for_color(display_color)
	corner_color_blind_symbol.modulate = Color.WHITE

## Convert card color enum to display color
func get_card_color(card_color: CardResource.CardColor) -> Color:
	match card_color:
		CardResource.CardColor.RED:
			return COLOR_RED
		CardResource.CardColor.GREEN:
			return COLOR_GREEN
		CardResource.CardColor.BLUE:
			return COLOR_BLUE
		CardResource.CardColor.YELLOW:
			return COLOR_YELLOW
		CardResource.CardColor.BLACK:
			return COLOR_BLACK_TEXT
	return COLOR_BLACK_TEXT

func _mouse_enter() -> void:
	if _show_front and !is_top_card:
		animation_player.play("zoom")
	if in_hand_card and hand_card_holder != null and _show_front and _card_res != null:
		hand_card_holder.show_card_description(_card_res)

func _mouse_exit() -> void:
	if _show_front and !is_top_card:
		animation_player.play_backwards("zoom")
	if in_hand_card and hand_card_holder != null and _card_res != null:
		hand_card_holder.hide_card_description(_card_res)

## Enable/disable click behavior for this card
func set_clickable(active: bool, stop_hover: bool = false) -> void:
	if button == null:
		return
	button.disabled = !active
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if stop_hover:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_button_pressed() -> void:
	if hand_card_holder == null:
		return
	if get_meta("play_blocked", false):
		hand_card_holder.notify_play_blocked(self)
		return
	hand_card_holder.set_card(self)

## Update clickable state based on holder rules
func update_playable_visuals() -> void:
	if hand_card_holder == null:
		set_clickable(false)
		return
	if is_top_card or !_show_front:
		set_clickable(false)
		return
	if !hand_card_holder.turn_active:
		set_clickable(false)
		return
	var playable := hand_card_holder.can_play_card(_card_res)
	set_clickable(playable)

## Resize card by scale based on card_size
func rezise_card() -> void:
	if card_size == "Small":
		scale = Vector2(0.5, 0.5)
	elif card_size == "Medium":
		scale = Vector2(0.75, 0.75)
	else:
		scale = Vector2(1, 1)

## Returns the scene overlay layer used for fly animations and tooltips.
func _get_overlay_layer() -> CanvasLayer:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("CanvasLayer") as CanvasLayer

## Reset hover/zoom offsets before a fly animation.
func _reset_visuells_for_fly() -> void:
	if visuells == null:
		return
	visuells.position = Vector2.ZERO
	visuells.scale = Vector2.ONE
	visuells.z_index = 0
	if animation_player != null and animation_player.has_animation("zoom"):
		animation_player.play("zoom")
		animation_player.seek(0.0, true)
		animation_player.stop()

## Global offset from card origin to visuells anchor in screen space.
func _visuells_origin_offset() -> Vector2:
	if visuells == null:
		return Vector2.ZERO
	return visuells.global_position - global_position

## Flies this card to the discard pile, centered on the top card (all peers).
func fly_to_discard_pile(duration: float = 0.35, overshoot: float = 14.0) -> void:
	var top := current_top_card
	if top == null or top == self:
		return
	if visuells == null or !is_instance_valid(visuells):
		return
	if top.visuells == null or !is_instance_valid(top.visuells):
		return

	show_front = true
	_reset_visuells_for_fly()

	var start_vis_global := visuells.global_position
	var end_vis_global := top.visuells.global_position

	var layer := _get_overlay_layer()
	if layer == null:
		return

	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	layer.add_child(self)
	top_level = true
	z_as_relative = false
	z_index = 4096

	card_size = top.card_size
	rezise_card()

	await get_tree().process_frame

	var vis_offset := _visuells_origin_offset()
	global_position = start_vis_global - vis_offset

	var target_pos := end_vis_global - vis_offset
	var dir := target_pos - global_position
	var overshoot_pos := target_pos
	if dir.length() > 0.001:
		overshoot_pos = target_pos + dir.normalized() * overshoot

	var tween := create_tween()
	tween.tween_property(self, "global_position", overshoot_pos, duration * 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_pos, duration * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished

## Animate moving this card button to the top card
func smooth_move_button_to_top_card_juicy(duration: float = 0.35, overshoot: float = 14.0) -> void:
	await fly_to_discard_pile(duration, overshoot)
