extends Control

signal visual_finished

const AVATAR_SIZE := 88.0
const SWAP_ICON_SIZE := 56.0
const CARD_FLY_SIZE := Vector2(54, 78)
const MAX_FLYING_CARDS := 10
const FLY_DURATION := 0.55
const POPUP_HOLD := 0.65
const FADE_IN := 0.14
const FADE_OUT := 0.15

@export var queue_manager: QueueManager

var _fly_layer: Control = null
var _overlay: Control = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _message_label: Label = null
var _owner_avatar: TextureRect = null
var _target_avatar: TextureRect = null
var _owner_name: Label = null
var _target_name: Label = null
var _visual_running := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 450
	add_to_group("swap_hands_feedback")
	_build_ui()
	if queue_manager == null:
		queue_manager = get_tree().get_first_node_in_group("queue_manager") as QueueManager


func get_fly_duration() -> float:
	return FLY_DURATION + 0.35


func get_visual_duration() -> float:
	return get_fly_duration() + POPUP_HOLD + FADE_OUT


## Awaitable swap visual used by solo/offline authoritative resolution.
func run_swap_visual(
	owner: HandCardHolder,
	target: HandCardHolder,
	owner_count: int,
	target_count: int,
	anim_seed: int = 0
) -> void:
	if owner == null or target == null:
		return
	await _run_swap_visual(owner, target, owner_count, target_count, anim_seed)


func _build_ui() -> void:
	_fly_layer = Control.new()
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fly_layer)

	_overlay = Control.new()
	_overlay.visible = false
	_overlay.modulate = Color(1, 1, 1, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.14, 0.94)
	style.border_color = Color(0.55, 0.82, 1.0, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(root)

	_title_label = Label.new()
	_title_label.text = "Hands swapped!"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 1))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_title_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	root.add_child(row)

	var owner_col := _make_avatar_column()
	_owner_avatar = owner_col.avatar
	_owner_name = owner_col.name_label
	row.add_child(owner_col.root)

	row.add_child(_make_swap_icon_column())

	var target_col := _make_avatar_column()
	_target_avatar = target_col.avatar
	_target_name = target_col.name_label
	row.add_child(target_col.root)

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(520, 0)
	_message_label.add_theme_font_size_override("font_size", 24)
	_message_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 1))
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_message_label.add_theme_constant_override("outline_size", 4)
	root.add_child(_message_label)


func _make_avatar_column() -> Dictionary:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(AVATAR_SIZE + 10, AVATAR_SIZE + 10)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(1, 1, 1, 0.08)
	frame_style.border_color = Color(0.78, 0.75, 1.0, 0.85)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(int((AVATAR_SIZE + 10) * 0.5))
	frame_style.content_margin_left = 5
	frame_style.content_margin_right = 5
	frame_style.content_margin_top = 5
	frame_style.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", frame_style)
	col.add_child(frame)

	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(avatar)

	var name := Label.new()
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(140, 0)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", 22)
	name.add_theme_color_override("font_color", Color(1, 0.94, 0.55, 1))
	name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name.add_theme_constant_override("outline_size", 4)
	col.add_child(name)

	return {"root": col, "avatar": avatar, "name_label": name}


func _make_swap_icon_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(SWAP_ICON_SIZE, SWAP_ICON_SIZE)
	icon.texture = CardResource.SWAP_HANDS_ICON
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(icon)

	var arrows := Label.new()
	arrows.text = "<—  —>"
	arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrows.add_theme_font_size_override("font_size", 28)
	arrows.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1))
	col.add_child(arrows)
	return col


## Starts fly animation + popup on every peer (host included via call_local RPC).
func begin_swap_visual(
	owner: HandCardHolder,
	target: HandCardHolder,
	owner_count: int,
	target_count: int,
	anim_seed: int = 0
) -> void:
	if owner == null or target == null:
		return
	_run_swap_visual(owner, target, owner_count, target_count, anim_seed)


func _run_swap_visual(
	owner: HandCardHolder,
	target: HandCardHolder,
	owner_count: int,
	target_count: int,
	anim_seed: int = 0
) -> void:
	if _visual_running:
		await visual_finished
	_visual_running = true
	_apply_popup_content(owner, target)

	var from_a := _holder_center(owner)
	var from_b := _holder_center(target)

	_show_popup()
	_center_panel()
	_animate_card_exchange(from_a, from_b, owner_count, target_count, anim_seed)

	await get_tree().create_timer(get_fly_duration()).timeout
	await get_tree().create_timer(POPUP_HOLD).timeout
	await _hide_popup()
	if _fly_layer != null:
		_fly_layer.top_level = false
	_visual_running = false
	visual_finished.emit()


func _apply_popup_content(owner: HandCardHolder, target: HandCardHolder) -> void:
	var owner_name := _holder_name(owner)
	var target_name := _holder_name(target)
	var owner_tex := _holder_avatar(owner)
	var target_tex := _holder_avatar(target)

	if _owner_avatar != null:
		_owner_avatar.texture = owner_tex
	if _target_avatar != null:
		_target_avatar.texture = target_tex
	if _owner_name != null:
		_owner_name.text = owner_name
	if _target_name != null:
		_target_name.text = target_name

	var my_slot := int(NetworkManager.my_slot)
	if !multiplayer.has_multiplayer_peer():
		my_slot = 0

	if int(owner.player_index) == my_slot:
		_title_label.text = "You swapped hands!"
		_message_label.text = "You took %s's hand." % target_name
	elif int(target.player_index) == my_slot:
		_title_label.text = "Your hand was stolen!"
		_message_label.text = "%s swapped hands with you." % owner_name
	else:
		_title_label.text = "Hands swapped!"
		_message_label.text = "%s swapped hands with %s." % [owner_name, target_name]


func _holder_name(holder: HandCardHolder) -> String:
	if holder != null and holder.profile != null and holder.profile.player_name.strip_edges() != "":
		return holder.profile.player_name
	return "Player %d" % (int(holder.player_index) + 1 if holder != null else 0)


func _holder_avatar(holder: HandCardHolder) -> Texture2D:
	if holder == null:
		return null
	if holder.profile == null:
		holder.profile = PlayerProfile.new()
	if holder.is_bot:
		holder.profile.apply_bot_avatar(holder.bot_difficulty)
	holder.profile.ensure_picture()
	return holder.profile.picture


func _holder_center(holder: HandCardHolder) -> Vector2:
	if queue_manager != null and queue_manager.has_method("get_holder_visual_center"):
		return queue_manager.get_holder_visual_center(holder)
	if holder != null:
		return holder.get_global_rect().get_center()
	return get_viewport().get_visible_rect().size * 0.5


func _slot_to_holder(slot: int) -> HandCardHolder:
	if queue_manager == null:
		queue_manager = get_tree().get_first_node_in_group("queue_manager") as QueueManager
	if queue_manager == null:
		return null
	return queue_manager.get_holder_for_slot(int(slot))


func _animate_card_exchange(from_a: Vector2, from_b: Vector2, count_a: int, count_b: int, anim_seed: int = 0) -> void:
	var layer := _get_fly_layer()
	if layer == null:
		return
	layer.top_level = true
	layer.z_index = 4095

	var rng := RandomNumberGenerator.new()
	rng.seed = int(anim_seed)

	var n_a := mini(maxi(count_a, 1), MAX_FLYING_CARDS)
	var n_b := mini(maxi(count_b, 1), MAX_FLYING_CARDS)

	for i in range(n_a):
		var start := from_a + Vector2(rng.randf_range(-28, 28), rng.randf_range(-18, 18))
		var end := from_b + Vector2(rng.randf_range(-28, 28), rng.randf_range(-18, 18))
		var mid := (start + end) * 0.5 + Vector2(0, -80 - i * 6)
		_fly_card_back(layer, start, mid, end, float(i) * 0.04)

	for i in range(n_b):
		var start := from_b + Vector2(rng.randf_range(-28, 28), rng.randf_range(-18, 18))
		var end := from_a + Vector2(rng.randf_range(-28, 28), rng.randf_range(-18, 18))
		var mid := (start + end) * 0.5 + Vector2(0, -80 - i * 6)
		_fly_card_back(layer, start, mid, end, float(i) * 0.04 + 0.05)


func _fly_card_back(layer: Control, start: Vector2, mid: Vector2, end: Vector2, delay: float) -> void:
	var card := TextureRect.new()
	card.texture = CardResource.BACKGROUND
	card.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.custom_minimum_size = CARD_FLY_SIZE
	card.size = CARD_FLY_SIZE
	card.pivot_offset = CARD_FLY_SIZE * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 2000
	layer.add_child(card)
	card.global_position = start - card.pivot_offset
	card.scale = Vector2(0.65, 0.65)
	card.modulate = Color(1, 1, 1, 0)

	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(card, "modulate:a", 1.0, 0.08)
	tween.set_parallel(true)
	tween.tween_property(card, "global_position", mid - card.pivot_offset, FLY_DURATION * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE, FLY_DURATION * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(card, "global_position", end - card.pivot_offset, FLY_DURATION * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(card, "modulate:a", 0.0, FLY_DURATION * 0.35)
	tween.tween_callback(card.queue_free)


func _get_fly_layer() -> Control:
	return _fly_layer


func _show_popup() -> void:
	if _overlay == null:
		return
	_overlay.top_level = true
	_overlay.z_index = 4096
	_overlay.visible = true
	_overlay.modulate = Color(1, 1, 1, 0)
	_panel.scale = Vector2(0.86, 0.86)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_overlay, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(_panel, "scale", Vector2.ONE, FADE_IN).set_trans(Tween.TRANS_BACK)


func _hide_popup() -> void:
	if _overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	_overlay.visible = false
	_overlay.top_level = false


func _center_panel() -> void:
	if _panel == null:
		return
	await get_tree().process_frame
	var size := _panel.get_combined_minimum_size()
	if size.x <= 1.0:
		size = _panel.size
	var vp := get_viewport().get_visible_rect().size
	_panel.global_position = (vp - size) * 0.5
