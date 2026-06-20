extends Control

const _DeckStorage = preload("res://Scripts/DeckEditor/deck_storage.gd")
const _DeckPreview = preload("res://Scripts/DeckEditor/deck_preview.gd")

const DETAIL_SCENE := "res://Scenes/DeckEditor/deck_editor_detail.tscn"
const START_SCENE := "res://Scenes/UI/start_screen.tscn"

var _builtin_list: VBoxContainer
var _custom_list: VBoxContainer
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_refresh_lists()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 48)
	root.add_theme_constant_override("margin_right", 48)
	root.add_theme_constant_override("margin_top", 36)
	root.add_theme_constant_override("margin_bottom", 36)
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)

	header.add_child(_make_button("Back", _on_back_pressed, 140))

	var title := Label.new()
	title.text = "Deck Editor"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 0.98))
	header.add_child(title)

	header.add_child(_make_button("New Deck", _on_new_deck_pressed, 180))

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.9, 0.72))
	column.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	content.add_child(_make_section_title("Official Decks"))
	_builtin_list = VBoxContainer.new()
	_builtin_list.add_theme_constant_override("separation", 10)
	content.add_child(_builtin_list)

	content.add_child(_make_section_title("My Decks"))
	_custom_list = VBoxContainer.new()
	_custom_list.add_theme_constant_override("separation", 10)
	content.add_child(_custom_list)


func _refresh_lists() -> void:
	_clear_children(_builtin_list)
	_clear_children(_custom_list)

	for path in Globals.list_deck_paths():
		var editable := _DeckStorage.can_save_builtin_deck()
		_builtin_list.add_child(_make_deck_row(path, not editable, true))

	var custom_paths: Array[String] = _DeckStorage.list_user_deck_paths()
	if custom_paths.is_empty():
		_custom_list.add_child(_make_hint_label("No custom decks yet. Create one with \"New Deck\"."))
	else:
		for path in custom_paths:
			_custom_list.add_child(_make_deck_row(path, false, false))


func _make_deck_row(path: String, read_only: bool, is_official: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var deck := Globals.load_deck(path)
	var title := Label.new()
	title.text = Globals.deck_display_name(path)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	info.add_child(title)

	var meta := Label.new()
	var count: int = _DeckPreview.get_card_count(deck) if deck != null else 0
	meta.text = "%d cards · %s" % [count, "Official" if is_official else "Custom"]
	meta.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	info.add_child(meta)

	if read_only:
		row.add_child(_make_button("View", func(): _open_deck(path, true), 130))
	else:
		row.add_child(_make_button("Edit", func(): _open_deck(path, false), 130))
		if not is_official:
			row.add_child(_make_button("Delete", func(): _delete_deck(path), 110, Color(0.55, 0.18, 0.18)))

	return panel


func _open_deck(path: String, read_only: bool) -> void:
	Globals.deck_editor_path = path
	Globals.deck_editor_read_only = read_only
	Globals.deck_editor_working_deck = null
	Globals.change_scene_file(DETAIL_SCENE)


func _delete_deck(path: String) -> void:
	if _DeckStorage.delete_user_deck(path):
		_status_label.text = "Deck deleted."
		_refresh_lists()
	else:
		_status_label.text = "Could not delete deck."


func _on_new_deck_pressed() -> void:
	var deck := DeckResource.new()
	deck.deck_name = "New Deck"
	deck.number_rules = DeckNumberRuleResource.new()
	deck.number_rules.min_number = 0
	deck.number_rules.max_number = 9
	deck.number_rules.default_copies = 4
	deck.number_rules.overrides = {"0": 2}
	deck.max_card_lose_enabled = false
	deck.max_card_lose_count = 20
	Globals.deck_editor_path = ""
	Globals.deck_editor_read_only = false
	Globals.deck_editor_working_deck = deck
	Globals.change_scene_file(DETAIL_SCENE)


func _on_back_pressed() -> void:
	Globals.change_scene_file(START_SCENE)


func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.95))
	return label


func _make_hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	return label


func _make_button(text: String, callback: Callable, min_width: int = 120, tint: Color = Color(0.18, 0.34, 0.58)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 44)
	button.pressed.connect(callback)
	var normal := StyleBoxFlat.new()
	normal.bg_color = tint
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
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
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
