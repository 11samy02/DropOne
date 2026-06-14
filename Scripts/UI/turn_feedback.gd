extends Control

const POPUP_DURATION := 0.5
const FADE_IN := 0.12
const FADE_OUT := 0.18
const HOLD := POPUP_DURATION - FADE_IN - FADE_OUT
const ICON_SIZE := 56.0

const _KIND_ICON := {
	Signals.FeedbackKind.BLOCKED: CardResource.SKIP_ICON,
	Signals.FeedbackKind.SKIPPED: CardResource.SKIP_ICON,
	Signals.FeedbackKind.INVALID: CardResource.TARGET_ICON,
	Signals.FeedbackKind.ELIMINATED: CardResource.MULTI_TARGET,
	Signals.FeedbackKind.COLOR: CardResource.WILD_ICON,
	Signals.FeedbackKind.WAIT: CardResource.REVERSE_ICON,
	Signals.FeedbackKind.ALREADY_PLAYED: CardResource.REVERSE_ICON,
}

const _KIND_BORDER := {
	Signals.FeedbackKind.BLOCKED: Color(1.0, 0.35, 0.35, 0.95),
	Signals.FeedbackKind.SKIPPED: Color(1.0, 0.55, 0.1, 0.95),
	Signals.FeedbackKind.INVALID: Color(0.95, 0.25, 0.25, 0.95),
	Signals.FeedbackKind.ELIMINATED: Color(0.55, 0.2, 0.85, 0.95),
	Signals.FeedbackKind.COLOR: Color(0.35, 0.75, 1.0, 0.95),
	Signals.FeedbackKind.WAIT: Color(0.75, 0.75, 0.85, 0.95),
	Signals.FeedbackKind.ALREADY_PLAYED: Color(1.0, 0.82, 0.15, 0.95),
}

const _KIND_ICON_TINT := {
	Signals.FeedbackKind.BLOCKED: Color(1.0, 0.55, 0.55, 1.0),
	Signals.FeedbackKind.SKIPPED: Color(1.0, 0.72, 0.3, 1.0),
	Signals.FeedbackKind.INVALID: Color(1.0, 0.45, 0.45, 1.0),
	Signals.FeedbackKind.ELIMINATED: Color(0.85, 0.55, 1.0, 1.0),
	Signals.FeedbackKind.COLOR: Color(0.55, 0.9, 1.0, 1.0),
	Signals.FeedbackKind.WAIT: Color(0.85, 0.85, 0.95, 1.0),
	Signals.FeedbackKind.ALREADY_PLAYED: Color(1.0, 0.9, 0.4, 1.0),
}

var _popup: Control = null
var _panel: PanelContainer = null
var _panel_style: StyleBoxFlat = null
var _icon_frame: PanelContainer = null
var _popup_label: Label = null
var _popup_icon: TextureRect = null
var _popup_tween: Tween = null
var _busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 400
	Signals.FEEDBACK_show.connect(_on_feedback_show)
	_build_popup()


func _build_popup() -> void:
	_popup = Control.new()
	_popup.visible = false
	_popup.modulate = Color(1, 1, 1, 0)
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.z_index = 10
	add_child(_popup)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.05, 0.05, 0.12, 0.92)
	_panel_style.border_color = _KIND_BORDER[Signals.FeedbackKind.BLOCKED]
	_panel_style.set_border_width_all(3)
	_panel_style.set_corner_radius_all(20)
	_panel_style.content_margin_left = 20
	_panel_style.content_margin_right = 22
	_panel_style.content_margin_top = 16
	_panel_style.content_margin_bottom = 16
	_panel_style.shadow_color = Color(0, 0, 0, 0.5)
	_panel_style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_popup.add_child(_panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)

	_icon_frame = PanelContainer.new()
	_icon_frame.custom_minimum_size = Vector2(ICON_SIZE + 8, ICON_SIZE + 8)
	_icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(1, 1, 1, 0.08)
	frame_style.set_corner_radius_all(int((ICON_SIZE + 8) * 0.5))
	frame_style.set_border_width_all(2)
	frame_style.border_color = Color(1, 1, 1, 0.18)
	frame_style.content_margin_left = 4
	frame_style.content_margin_right = 4
	frame_style.content_margin_top = 4
	frame_style.content_margin_bottom = 4
	_icon_frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(_icon_frame)

	_popup_icon = TextureRect.new()
	_popup_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_popup_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_popup_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_popup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_popup_icon.texture = CardResource.SKIP_ICON
	_popup_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_frame.add_child(_popup_icon)

	_popup_label = Label.new()
	_popup_label.text = "Invalid"
	_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_popup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_popup_label.add_theme_font_size_override("font_size", 32)
	_popup_label.add_theme_color_override("font_color", Color(1, 0.96, 0.96, 1))
	_popup_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_popup_label.add_theme_constant_override("outline_size", 5)
	_popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_popup_label)


func _on_feedback_show(text: String, kind: int = Signals.FeedbackKind.BLOCKED) -> void:
	if _popup == null:
		return
	if _busy:
		if _popup_tween != null and _popup_tween.is_valid():
			_popup_tween.kill()
		_busy = false

	var safe_kind := kind if _KIND_ICON.has(kind) else Signals.FeedbackKind.BLOCKED

	if _popup_label != null:
		_popup_label.text = text
	if _popup_icon != null:
		_popup_icon.texture = _KIND_ICON[safe_kind]
		_popup_icon.modulate = _KIND_ICON_TINT.get(safe_kind, Color.WHITE)
	if _panel_style != null:
		_panel_style.border_color = _KIND_BORDER.get(safe_kind, _KIND_BORDER[Signals.FeedbackKind.BLOCKED])
		_panel.queue_redraw()

	_popup.scale = Vector2(0.82, 0.82)
	_popup.modulate = Color(1, 1, 1, 0)
	_popup.visible = true
	if _popup_icon != null:
		_popup_icon.scale = Vector2(0.6, 0.6)
	call_deferred("_center_popup")
	_busy = true

	if _popup_tween != null and _popup_tween.is_valid():
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.set_parallel(true)
	_popup_tween.tween_property(_popup, "modulate:a", 1.0, FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _popup_icon != null:
		_popup_tween.tween_property(_popup_icon, "scale", Vector2.ONE, FADE_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tween.set_parallel(false)
	_popup_tween.tween_interval(HOLD)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_popup_tween.tween_callback(func():
		if _popup != null:
			_popup.visible = false
		if _popup_icon != null:
			_popup_icon.scale = Vector2.ONE
		_busy = false
	)


func _center_popup() -> void:
	if _popup == null or _panel == null:
		return
	await get_tree().process_frame
	var size := _panel.get_combined_minimum_size()
	if size.x <= 1.0 or size.y <= 1.0:
		size = _panel.size
	var vp := get_viewport().get_visible_rect().size
	_popup.position = (vp - size) * 0.5 + Vector2(0, -40)
