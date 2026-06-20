extends Control

const _DeckStorage = preload("res://Scripts/DeckEditor/deck_storage.gd")
const _DeckPreview = preload("res://Scripts/DeckEditor/deck_preview.gd")

const LIST_SCENE := "res://Scenes/DeckEditor/deck_editor.tscn"
const CARD_VIEW_SCENE := preload("res://Scenes/View/card_view.tscn")
const CARD_NATURAL_SIZE := Vector2(168.75, 236.25)
const PREVIEW_CARD_SCALE := 0.5
const PREVIEW_CARD_WIDTH := CARD_NATURAL_SIZE.x * PREVIEW_CARD_SCALE
const PREVIEW_CARD_HEIGHT := CARD_NATURAL_SIZE.y * PREVIEW_CARD_SCALE
const COUNT_BADGE_SIZE := 20.0
const GRID_H_SEP := 8
const GRID_V_SEP := 8

const SPECIAL_TYPES: Array[Dictionary] = [
	{"id": CardResource.CardType.SKIP, "label": "Skip"},
	{"id": CardResource.CardType.REVERSE, "label": "Reverse"},
	{"id": CardResource.CardType.DRAW, "label": "Draw"},
	{"id": CardResource.CardType.WILD, "label": "Wild"},
	{"id": CardResource.CardType.WILD_DRAW, "label": "Wild Draw"},
	{"id": CardResource.CardType.PLACE_ALL, "label": "Place All"},
	{"id": CardResource.CardType.WILD_DRAW_REVERSE, "label": "Wild Draw Reverse"},
	{"id": CardResource.CardType.SWAP_HANDS, "label": "Swap Hands"},
	{"id": CardResource.CardType.TARGET_DRAW, "label": "Target Draw"},
	{"id": CardResource.CardType.MULTI_TARGET_DRAW, "label": "Multi Target Draw"},
	{"id": CardResource.CardType.WILD_COLOR_ROULET, "label": "Color Roulette"},
]

var _deck: DeckResource
var _read_only := false
var _save_path := ""

var _name_field: LineEdit
var _status_label: Label
var _preview_scroll: ScrollContainer
var _preview_margin: MarginContainer
var _card_flow: FlowContainer
var _count_label: Label
var _edit_panel: PanelContainer
var _min_spin: SpinBox
var _max_spin: SpinBox
var _copies_spin: SpinBox
var _type_option: OptionButton
var _value_spin: SpinBox
var _value_row: HBoxContainer
var _entry_count_spin: SpinBox
var _all_colors_check: CheckBox
var _entries_list: VBoxContainer
var _elimination_check: CheckBox
var _elimination_row: HBoxContainer
var _elimination_spin: SpinBox
var _save_button: Button
var _save_official_button: Button
var _delete_button: Button


func _ready() -> void:
	_read_only = Globals.deck_editor_read_only
	_save_path = Globals.deck_editor_path
	_deck = _load_initial_deck()
	_build_ui()
	_refresh_all()


func _load_initial_deck() -> DeckResource:
	if Globals.deck_editor_working_deck != null:
		return Globals.deck_editor_working_deck.duplicate(true)
	if _save_path != "":
		var loaded := Globals.load_deck(_save_path)
		if loaded != null:
			return loaded.duplicate(true)
	var fallback := DeckResource.new()
	fallback.deck_name = "New Deck"
	fallback.number_rules = DeckNumberRuleResource.new()
	fallback.number_rules.min_number = 0
	fallback.number_rules.max_number = 9
	fallback.number_rules.default_copies = 4
	fallback.number_rules.overrides = {"0": 2}
	fallback.max_card_lose_enabled = false
	fallback.max_card_lose_count = 20
	return fallback


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 32)
	root.add_theme_constant_override("margin_right", 32)
	root.add_theme_constant_override("margin_top", 24)
	root.add_theme_constant_override("margin_bottom", 24)
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	header.add_child(_make_button("Back", _on_back_pressed, 120))

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Deck name"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.editable = not _read_only
	_name_field.text_changed.connect(func(_t): _deck.deck_name = _name_field.text.strip_edges())
	_style_line_edit(_name_field)
	header.add_child(_name_field)

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	header.add_child(_count_label)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_stretch_ratio = 1.4
	preview_panel.add_theme_stylebox_override("panel", _panel_style())
	body.add_child(preview_panel)

	var preview_box := VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 8)
	preview_panel.add_child(preview_box)

	var preview_title := Label.new()
	preview_title.text = "Card Preview"
	preview_title.add_theme_font_size_override("font_size", 22)
	preview_box.add_child(preview_title)

	_preview_scroll = ScrollContainer.new()
	_preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preview_scroll.resized.connect(_update_preview_flow_width)
	preview_box.add_child(_preview_scroll)

	_preview_margin = MarginContainer.new()
	_preview_margin.add_theme_constant_override("margin_left", 8)
	_preview_margin.add_theme_constant_override("margin_right", 8)
	_preview_margin.add_theme_constant_override("margin_top", 12)
	_preview_margin.add_theme_constant_override("margin_bottom", 12)
	_preview_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_scroll.add_child(_preview_margin)

	_card_flow = FlowContainer.new()
	_card_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_card_flow.add_theme_constant_override("h_separation", GRID_H_SEP)
	_card_flow.add_theme_constant_override("v_separation", GRID_V_SEP)
	_card_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_margin.add_child(_card_flow)

	_edit_panel = PanelContainer.new()
	_edit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_panel.size_flags_stretch_ratio = 1.0
	_edit_panel.add_theme_stylebox_override("panel", _panel_style())
	_edit_panel.visible = not _read_only
	body.add_child(_edit_panel)

	var edit_scroll := ScrollContainer.new()
	edit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_edit_panel.add_child(edit_scroll)

	var edit_box := VBoxContainer.new()
	edit_box.add_theme_constant_override("separation", 14)
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_scroll.add_child(edit_box)

	var rules_header := HBoxContainer.new()
	rules_header.add_theme_constant_override("separation", 10)
	edit_box.add_child(rules_header)
	rules_header.add_child(_make_subtitle("Match Rules"))
	var min_hint := Label.new()
	min_hint.text = "Min. %d cards" % _DeckPreview.get_minimum_card_count()
	min_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	min_hint.add_theme_font_size_override("font_size", 14)
	min_hint.add_theme_color_override("font_color", Color(0.58, 0.62, 0.72))
	rules_header.add_child(min_hint)

	_elimination_check = CheckBox.new()
	_elimination_check.text = "Hand limit elimination"
	_elimination_check.toggled.connect(_on_elimination_toggled)
	edit_box.add_child(_elimination_check)

	_elimination_row = HBoxContainer.new()
	_elimination_row.add_theme_constant_override("separation", 10)
	edit_box.add_child(_elimination_row)
	_elimination_row.add_child(_make_label("Limit"))
	_elimination_spin = _make_spin_box(2, 50, 20)
	_elimination_spin.value_changed.connect(_on_elimination_count_changed)
	_elimination_row.add_child(_elimination_spin)
	_elimination_row.add_child(_make_label("cards"))

	edit_box.add_child(_make_subtitle("Number Cards"))
	var number_row := HBoxContainer.new()
	number_row.add_theme_constant_override("separation", 10)
	edit_box.add_child(number_row)
	_min_spin = _add_spin_row(number_row, "Min", 0, 15, 0)
	_max_spin = _add_spin_row(number_row, "Max", 0, 15, 9)
	_copies_spin = _add_spin_row(number_row, "Copies", 0, 20, 2)

	var apply_row := HBoxContainer.new()
	apply_row.add_theme_constant_override("separation", 10)
	edit_box.add_child(apply_row)
	var apply_btn := _make_button("Apply", _apply_number_rules, 0)
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_row.add_child(apply_btn)

	edit_box.add_child(_make_subtitle("Add Special Card"))
	_type_option = OptionButton.new()
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_button(_type_option)
	for item in SPECIAL_TYPES:
		_type_option.add_item(str(item["label"]), int(item["id"]))
	_type_option.item_selected.connect(_on_type_changed)
	edit_box.add_child(_type_option)

	_value_row = HBoxContainer.new()
	_value_row.add_theme_constant_override("separation", 10)
	edit_box.add_child(_value_row)
	_value_row.add_child(_make_label("Value"))
	_value_spin = _make_spin_box(0, 20, 2)
	_value_row.add_child(_value_spin)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	edit_box.add_child(count_row)
	count_row.add_child(_make_label("Count"))
	_entry_count_spin = _make_spin_box(1, 20, 1)
	count_row.add_child(_entry_count_spin)

	_all_colors_check = CheckBox.new()
	_all_colors_check.text = "All colors"
	_all_colors_check.button_pressed = true
	edit_box.add_child(_all_colors_check)

	var add_card_btn := _make_button("Add Card", _add_special_entry, 0)
	add_card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.add_child(add_card_btn)
	edit_box.add_child(_make_subtitle("Entries"))
	_entries_list = VBoxContainer.new()
	_entries_list.add_theme_constant_override("separation", 6)
	edit_box.add_child(_entries_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)

	_save_button = _make_button("Save", _save_deck, 120, Color(0.14, 0.48, 0.28))
	_save_button.visible = not _read_only
	footer.add_child(_save_button)

	if _DeckStorage.can_save_builtin_deck() and not _read_only:
		_save_official_button = _make_button("Save Official", _save_official_deck, 140, Color(0.32, 0.26, 0.52))
		footer.add_child(_save_official_button)

	_delete_button = _make_button("Delete", _delete_deck, 110, Color(0.55, 0.18, 0.18))
	_delete_button.visible = not _read_only and _DeckStorage.is_user_deck(_save_path)
	footer.add_child(_delete_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_status_label)

	_on_type_changed(0)
	call_deferred("_update_preview_flow_width")


func _refresh_all() -> void:
	if _deck.number_rules == null:
		_deck.number_rules = DeckNumberRuleResource.new()
	_name_field.text = _deck.deck_name
	_min_spin.value = _deck.number_rules.min_number
	_max_spin.value = _deck.number_rules.max_number
	_copies_spin.value = _deck.number_rules.default_copies
	_sync_elimination_controls()
	_refresh_preview()
	_refresh_entries()


func _sync_elimination_controls() -> void:
	if _elimination_check == null:
		return
	_elimination_check.button_pressed = _deck.max_card_lose_enabled
	_elimination_spin.value = _deck.max_card_lose_count
	_elimination_row.visible = _deck.max_card_lose_enabled


func _on_elimination_toggled(enabled: bool) -> void:
	_deck.max_card_lose_enabled = enabled
	_elimination_row.visible = enabled


func _on_elimination_count_changed(value: float) -> void:
	_deck.max_card_lose_count = int(value)


func _refresh_preview() -> void:
	_clear_children(_card_flow)
	var total_count := _DeckPreview.get_card_count(_deck)
	var min_count := _DeckPreview.get_minimum_card_count()
	if total_count < min_count:
		_count_label.text = "%d / %d cards" % [total_count, min_count]
		_count_label.add_theme_color_override("font_color", Color(1.0, 0.58, 0.52))
	else:
		_count_label.text = "%d cards" % total_count
		_count_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	for entry in _DeckPreview.build_grouped_cards(_deck):
		var card: CardResource = entry["card"]
		var count: int = int(entry["count"])
		_card_flow.add_child(_make_card_preview(card, count))
	call_deferred("_update_preview_flow_width")


func _update_preview_flow_width() -> void:
	if _preview_margin == null or _preview_scroll == null:
		return
	var width := _preview_scroll.size.x
	if width > 0.0:
		_preview_margin.custom_minimum_size.x = width


func _refresh_entries() -> void:
	_clear_children(_entries_list)
	for i in range(_deck.entries.size()):
		var entry: DeckEntryResource = _deck.entries[i]
		if entry == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = _entry_summary(entry)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove := _make_button("X", func(): _remove_entry(i), 40, Color(0.45, 0.16, 0.16))
		row.add_child(remove)
		_entries_list.add_child(row)


func _make_card_preview(card: CardResource, count: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(PREVIEW_CARD_WIDTH, PREVIEW_CARD_HEIGHT)
	slot.clip_contents = false
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var view: CardView = CARD_VIEW_SCENE.instantiate()
	view.in_hand_card = false
	view.is_top_card = false
	view.card_res = card
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(view)
	call_deferred("_configure_preview_card", view)

	if count > 1:
		var badge := _make_count_badge(count)
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.anchor_top = 1.0
		badge.anchor_bottom = 1.0
		badge.offset_left = -COUNT_BADGE_SIZE + 4.0
		badge.offset_right = 4.0
		badge.offset_top = -COUNT_BADGE_SIZE + 4.0
		badge.offset_bottom = 4.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		slot.add_child(badge)

	return slot


func _make_count_badge(count: int) -> Control:
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(COUNT_BADGE_SIZE, COUNT_BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 20

	var circle := PanelContainer.new()
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.96)
	style.border_color = Color(0.82, 0.86, 1.0, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(COUNT_BADGE_SIZE * 0.5))
	circle.add_theme_stylebox_override("panel", style)
	badge.add_child(circle)

	var label := Label.new()
	label.text = "%dx" % count
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	badge.add_child(label)
	return badge


func _configure_preview_card(view: CardView) -> void:
	if view == null or not is_instance_valid(view):
		return
	view.pivot_offset = Vector2.ZERO
	var visuells := view.get_node_or_null("visuells") as Control
	if visuells != null:
		visuells.pivot_offset = Vector2.ZERO
	view.card_size = "Small"
	view.position = Vector2.ZERO
	if view.has_method("rezise_card"):
		view.rezise_card()
	if view.has_method("load_card"):
		view.load_card()
	if view.button != null:
		view.button.visible = false
		view.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_clickable(false, true)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_process(false)
	if view.has_method("_snap_rest_pose"):
		view._snap_rest_pose()


func _entry_summary(entry: DeckEntryResource) -> String:
	var type_name := ""
	for item in SPECIAL_TYPES:
		if int(item["id"]) == int(entry.type):
			type_name = str(item["label"])
			break
	var value_text := ""
	if _type_has_value(entry.type):
		value_text = " +%d" % entry.value
	var color_text := "all colors" if entry.duplicate_for_all_colors else _DeckPreview.card_label(_make_temp_card(entry.color, entry.type, entry.value))
	return "%s x%d%s (%s)" % [type_name, entry.count, value_text, color_text]


func _make_temp_card(color: CardResource.CardColor, type: CardResource.CardType, value: int) -> CardResource:
	var card := CardResource.new()
	card.color = color
	card.type = type
	card.value = value
	return card


func _apply_number_rules() -> void:
	if _deck.number_rules == null:
		_deck.number_rules = DeckNumberRuleResource.new()
	_deck.number_rules.min_number = int(_min_spin.value)
	_deck.number_rules.max_number = int(_max_spin.value)
	_deck.number_rules.default_copies = int(_copies_spin.value)
	if _deck.number_rules.min_number > _deck.number_rules.max_number:
		_deck.number_rules.max_number = _deck.number_rules.min_number
	_refresh_preview()
	_status_label.text = "Number rules updated."


func _add_special_entry() -> void:
	var entry := DeckEntryResource.new()
	entry.type = _type_option.get_selected_id() as CardResource.CardType
	entry.count = int(_entry_count_spin.value)
	entry.value = int(_value_spin.value)
	entry.duplicate_for_all_colors = _all_colors_check.button_pressed and not CardResource.is_neutral_wild_type(entry.type)
	if entry.duplicate_for_all_colors:
		entry.colors = [
			CardResource.CardColor.RED,
			CardResource.CardColor.GREEN,
			CardResource.CardColor.BLUE,
			CardResource.CardColor.YELLOW,
		]
	_deck.entries.append(entry)
	_refresh_preview()
	_refresh_entries()
	_status_label.text = "Special card added."


func _remove_entry(index: int) -> void:
	if index < 0 or index >= _deck.entries.size():
		return
	_deck.entries.remove_at(index)
	_refresh_preview()
	_refresh_entries()


func _on_type_changed(_index: int) -> void:
	var selected_type := _type_option.get_selected_id() as CardResource.CardType
	var show_value := _type_has_value(selected_type)
	_value_row.visible = show_value
	_all_colors_check.visible = not CardResource.is_neutral_wild_type(selected_type)
	if CardResource.is_neutral_wild_type(selected_type):
		_all_colors_check.button_pressed = false
	elif selected_type != CardResource.CardType.WILD:
		_all_colors_check.button_pressed = true
	if selected_type == CardResource.CardType.DRAW:
		_value_spin.value = 2
	elif selected_type == CardResource.CardType.WILD_DRAW:
		_value_spin.value = 4


func _type_has_value(type: CardResource.CardType) -> bool:
	return type in [
		CardResource.CardType.DRAW,
		CardResource.CardType.WILD_DRAW,
		CardResource.CardType.WILD_DRAW_REVERSE,
		CardResource.CardType.TARGET_DRAW,
		CardResource.CardType.MULTI_TARGET_DRAW,
	]


func _save_deck() -> void:
	var name := _name_field.text.strip_edges()
	if name == "":
		_status_label.text = "Enter a deck name."
		return
	_deck.deck_name = name
	if not _DeckPreview.meets_minimum_card_count(_deck):
		_status_label.text = "Min. %d cards required." % _DeckPreview.get_minimum_card_count()
		return
	var path := ""
	if _DeckStorage.is_builtin_deck(_save_path) and _DeckStorage.can_save_builtin_deck():
		path = _DeckStorage.save_builtin_deck(_deck, name)
	else:
		path = _DeckStorage.save_user_deck(_deck, name)
	if path == "":
		_status_label.text = "Save failed."
		return
	_save_path = path
	Globals.deck_editor_path = path
	_delete_button.visible = _DeckStorage.is_user_deck(_save_path)
	_status_label.text = "Saved."


func _save_official_deck() -> void:
	if not _DeckStorage.can_save_builtin_deck():
		_status_label.text = "Official save unavailable."
		return
	var name := _name_field.text.strip_edges()
	if name == "":
		_status_label.text = "Enter a deck name."
		return
	_deck.deck_name = name
	if not _DeckPreview.meets_minimum_card_count(_deck):
		_status_label.text = "Min. %d cards required." % _DeckPreview.get_minimum_card_count()
		return
	var path := _DeckStorage.save_builtin_deck(_deck, name)
	if path == "":
		_status_label.text = "Official save failed."
		return
	_save_path = path
	Globals.deck_editor_path = path
	_delete_button.visible = false
	_status_label.text = "Saved to official decks."


func _delete_deck() -> void:
	if _save_path == "" or not _DeckStorage.is_user_deck(_save_path):
		return
	if _DeckStorage.delete_user_deck(_save_path):
		Globals.change_scene_file(LIST_SCENE)
	else:
		_status_label.text = "Delete failed."


func _on_back_pressed() -> void:
	Globals.change_scene_file(LIST_SCENE)


func _add_spin_row(parent: HBoxContainer, label_text: String, min_v: int, max_v: int, value: int) -> SpinBox:
	var label := _make_label(label_text)
	label.custom_minimum_size.x = 52
	parent.add_child(label)
	var spin := _make_spin_box(min_v, max_v, value)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _make_spin_box(min_v: int, max_v: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	spin.custom_minimum_size = Vector2(72, 34)
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_spin_box(spin)
	return spin


func _input_field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18)
	style.border_color = Color(0.35, 0.42, 0.58)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _style_spin_box(spin: SpinBox) -> void:
	var style := _input_field_style()
	spin.add_theme_stylebox_override("normal", style)
	spin.add_theme_stylebox_override("focus", style)
	spin.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	var line_edit := spin.get_line_edit()
	if line_edit != null:
		line_edit.add_theme_stylebox_override("normal", style)
		line_edit.add_theme_stylebox_override("focus", style)
		line_edit.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))


func _style_option_button(option: OptionButton) -> void:
	var style := _input_field_style()
	option.custom_minimum_size.y = 38
	option.add_theme_stylebox_override("normal", style)
	option.add_theme_stylebox_override("hover", style)
	option.add_theme_stylebox_override("pressed", style)
	option.add_theme_stylebox_override("focus", style)
	option.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))


func _make_subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	return label


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	return label


func _make_button(text: String, callback: Callable, min_width: int = 120, tint: Color = Color(0.18, 0.34, 0.58)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 40)
	button.pressed.connect(callback)
	var normal := StyleBoxFlat.new()
	normal.bg_color = tint
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate()
	hover.bg_color = tint.lightened(0.15)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.22, 0.95)
	style.border_color = Color(0.32, 0.38, 0.52)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _style_line_edit(field: LineEdit) -> void:
	var style := _input_field_style()
	field.add_theme_stylebox_override("normal", style)
	field.add_theme_stylebox_override("focus", style)
	field.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
