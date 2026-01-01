@tool
extends Control
class_name CardView

static var current_top_card: CardView

var hand_card_holder: HandCardHolder

@export var is_top_card := false
@export_enum("Small", "Medium", "Large") var card_size := "Medium"

var _show_front := true
@export var show_front := true:
	get:
		return _show_front
	set(value):
		_show_front = value
		if is_inside_tree():
			load_card()

var _card_res: CardResource = null
@export var card_res: CardResource:
	get:
		return _card_res
	set(value):
		_card_res = value
		if is_inside_tree():
			load_card()

var _override_color_enabled := false
@export var override_color_enabled := false:
	get:
		return _override_color_enabled
	set(value):
		_override_color_enabled = value
		if is_inside_tree():
			load_card()

var _override_color: CardResource.CardColor = CardResource.CardColor.RED
@export var override_color: CardResource.CardColor = CardResource.CardColor.RED:
	get:
		return _override_color
	set(value):
		_override_color = value
		if is_inside_tree():
			load_card()

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

const COLOR_BLUE := Color("#0027da")
const COLOR_YELLOW := Color("#c39f00")
const COLOR_RED := Color("#ad0000")
const COLOR_GREEN := Color("#0ca500")
const COLOR_BLACK_TEXT := Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	load_card()
	rezise_card()
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

		if _card_res.type != CardResource.CardType.WILD and _card_res.type != CardResource.CardType.WILD_DRAW:
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

func _mouse_exit() -> void:
	if _show_front and !is_top_card:
		animation_player.play_backwards("zoom")

## Enable/disable click behavior for this card
func set_clickable(active: bool, stop_hover: bool = false) -> void:
	button.disabled = !active
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if stop_hover:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_button_pressed() -> void:
	if hand_card_holder != null:
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

## Animate moving this card button to the top card
func smooth_move_button_to_top_card_juicy(duration: float = 0.35, overshoot: float = 14.0) -> void:
	if current_top_card == null:
		return
	if current_top_card == self:
		return
	if button == null or !is_instance_valid(button):
		return

	show_front = true

	var parent_control := button.get_parent() as Control
	if parent_control == null:
		return

	var target_global_pos: Vector2 = current_top_card.button.global_position
	var target_local_pos: Vector2 = parent_control.get_global_transform().affine_inverse() * target_global_pos

	var dir := (target_local_pos - button.position)
	if dir.length() < 0.001:
		return

	var overshoot_pos := target_local_pos + dir.normalized() * overshoot

	var tween := create_tween()
	tween.tween_property(button, "position", overshoot_pos, duration * 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position", target_local_pos, duration * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
