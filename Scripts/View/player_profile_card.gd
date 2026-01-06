extends VBoxContainer
class_name ProfileCardDisplay

signal pressed(holder: HandCardHolder)

@onready var profile: TextureRect = %profile
@onready var player_name: Label = %player_name
@onready var card_count: Label = %card_count
@onready var panel: Panel = $Panel

var _holder: HandCardHolder = null
var _disabled := false
var _tween: Tween = null

var normal_scale := Vector2.ONE
var hover_scale := Vector2(1.07, 1.07)
var press_scale := Vector2(0.92, 0.92)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

	for c in get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE

	scale = normal_scale

func setup(p: PlayerProfile, count: int, holder: HandCardHolder, disabled: bool = false) -> void:
	_holder = holder
	_disabled = disabled

	if p != null:
		player_name.text = p.player_name
		profile.texture = p.picture

	card_count.text = str(count) + "x"

	if _disabled:
		modulate = Color(0.6, 0.6, 0.6, 0.85)
	else:
		modulate = Color(1, 1, 1, 1)

func _on_hover_enter() -> void:
	if _disabled:
		return
	_animate_scale(hover_scale, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT)

func _on_hover_exit() -> void:
	if _disabled:
		return
	_animate_scale(normal_scale, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT)

func _on_gui_input(event: InputEvent) -> void:
	if _disabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_animate_scale(press_scale, 0.08, Tween.TRANS_QUAD, Tween.EASE_OUT)
		else:
			_animate_scale(hover_scale if get_global_rect().has_point(get_global_mouse_position()) else normal_scale, 0.14, Tween.TRANS_BACK, Tween.EASE_OUT)
			emit_signal("pressed", _holder)

func _animate_scale(target: Vector2, duration: float, trans := Tween.TRANS_BACK, ease := Tween.EASE_OUT) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", target, duration).set_trans(trans).set_ease(ease)
