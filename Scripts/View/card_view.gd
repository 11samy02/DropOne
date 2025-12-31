@tool
extends Control
class_name CardView

var hand_card_holder: HandCardHolder

@export var is_top_card := false
@export var show_front := true
@export var card_res: CardResource
@export var override_color_enabled := false
@export var override_color: CardResource.CardColor = CardResource.CardColor.RED


@onready var background: TextureRect = %background
@onready var center_num: Label = %center_num
@onready var left_num: Label = %left_num
@onready var right_num: Label = %right_num
@onready var symbol: TextureRect = %symbol
@onready var left_symbol: TextureRect = %left_symbol
@onready var right_symbol: TextureRect = %right_symbol
@onready var shadow_symbol: TextureRect = %shadow_symbol
@onready var left_shadow_symbol: TextureRect = %left_shadow_symbol
@onready var right_shadow_symbol: TextureRect = %right_shadow_symbol
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var button: Button = %button

const COLOR_BLUE := Color("#0027da")
const COLOR_YELLOW := Color("#c39f00")
const COLOR_RED := Color("#ad0000")
const COLOR_GREEN := Color("#0ca500")
const COLOR_BLACK_TEXT := Color.WHITE
const CORNER_TEXT_COLOR := Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if background.material != null:
		background.material = background.material.duplicate()
	
	load_card()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		load_card()

func load_card() -> void:
	if card_res == null:
		return

	if !show_front:
		background.texture = card_res.get_background_texture(true)
		_hide_front()
		return
	
	var display_color := card_res.color
	if override_color_enabled:
		display_color = override_color
	
	background.texture = card_res.get_background_texture_for_color(display_color)
	
	var sym := card_res.get_symbol_texture()
	var text := card_res.get_display_text()
	var c := get_card_color(display_color)
	
	left_num.modulate = Color.WHITE
	right_num.modulate = Color.WHITE
	center_num.modulate = Color.WHITE
	
	if sym != null:
		symbol.show()
		left_symbol.show()
		right_symbol.show()
	
		symbol.texture = sym
		left_symbol.texture = sym
		right_symbol.texture = sym
		shadow_symbol.texture = sym
		left_shadow_symbol.texture = sym
		right_shadow_symbol.texture = sym
	
		center_num.hide()
	
		if text != "":
			left_num.show()
			right_num.show()
	
			left_symbol.hide()
			right_symbol.hide()
			shadow_symbol.hide()
	
			left_num.text = text
			right_num.text = text
	
			left_num.modulate = Color.WHITE
			right_num.modulate = Color.WHITE
		else:
			left_num.hide()
			right_num.hide()
			shadow_symbol.show()
	
		if card_res.type != CardResource.CardType.WILD and card_res.type != CardResource.CardType.WILD_DRAW:
			symbol.modulate = c
		else:
			symbol.modulate = Color.WHITE
	
	else:
		symbol.hide()
		left_symbol.hide()
		right_symbol.hide()
		shadow_symbol.hide()
		left_shadow_symbol.hide()
		right_shadow_symbol.hide()
	
		center_num.show()
		left_num.show()
		right_num.show()
	
		center_num.text = text
		left_num.text = text
		right_num.text = text
	
		center_num.modulate = c
		left_num.modulate = Color.WHITE
		right_num.modulate = Color.WHITE
	update_playable_visuals()




func _hide_front() -> void:
	center_num.hide()
	left_num.hide()
	right_num.hide()
	symbol.hide()
	left_symbol.hide()
	right_symbol.hide()
	shadow_symbol.hide()
	left_shadow_symbol.hide()
	right_shadow_symbol.hide()

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
	if show_front and !is_top_card:
		animation_player.play("zoom")

func _mouse_exit() -> void:
	if show_front and !is_top_card:
		animation_player.play_backwards("zoom")



func set_clickable(active: bool, stop_hover: bool = false) -> void:
	button.disabled = !active
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if stop_hover:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE



func can_be_clicked() -> void:
	if hand_card_holder == null:
		return
	if is_top_card or !show_front:
		set_clickable(false)
		return
	
	set_clickable(hand_card_holder.can_play_card(card_res))



func _on_button_pressed() -> void:
	if hand_card_holder != null:
		hand_card_holder.set_card(self)

func set_pulsing(value: bool = false) -> void:
	var mat := background.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("highlight_enabled", value)

func update_playable_visuals() -> void:
	if hand_card_holder == null:
		return
	if !show_front:
		set_pulsing(false)
		return
	
	var playable := hand_card_holder.can_play_card(card_res)
	set_pulsing(playable)
