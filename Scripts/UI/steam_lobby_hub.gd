extends Control
class_name SteamLobbyHub

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"

## false = lokaler Test mit mehreren Instanzen ohne Steam (127.0.0.1:4242)
@export var use_steam: bool = true

@onready var status_label: Label = %status_label
@onready var lobby_id_input: LineEdit = %lobby_id_input
@onready var lobby_container: VBoxContainer = %lobby_container
@onready var refresh_timer: Timer = %refresh_timer
@onready var create_button: Button = %Create
@onready var mode_label: Label = %mode_label
@onready var join_button: Button = $MarginContainer/VBoxContainer/JoinRow/JoinId
@onready var list_title: Label = $MarginContainer/VBoxContainer/ListTitle
@onready var join_row: HBoxContainer = $MarginContainer/VBoxContainer/JoinRow

var _lobby_items: Dictionary = {}
var _ui_locked := false


func _ready() -> void:
	SteamManager.configure(use_steam)
	_update_mode_label()
	SteamManager.lobby_left.connect(_on_lobby_left_reset_ui)

	if not Globals.has_customized_profile():
		Globals.change_scene_file(START_SCREEN)
		return

	SteamManager.steam_init_failed.connect(_on_steam_init_failed)
	SteamManager.steam_ready_signal.connect(_on_steam_ready)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)
	SteamManager.lobby_list_loaded.connect(_on_lobby_list_loaded)

	refresh_timer.timeout.connect(_refresh_lobby_list)

	if SteamManager.steam_ready:
		_on_steam_ready()
	else:
		status_label.text = "Connecting..." if use_steam else "Local mode ready."


func _update_mode_label() -> void:
	if mode_label:
		mode_label.text = "Mode: Steam" if use_steam else "Mode: Local (127.0.0.1:4242)"

	if not use_steam:
		if create_button:
			create_button.text = "Start Host (Instance 1)"
		if join_button:
			join_button.text = "Join as Client (Instance 2+)"
		if lobby_id_input:
			lobby_id_input.placeholder_text = "ID not needed in local mode"
			lobby_id_input.editable = false
		if list_title:
			list_title.text = "Local mode: no public list"
		if join_row:
			join_row.visible = true
	else:
		if create_button:
			create_button.text = "Create Lobby"
		if join_button:
			join_button.text = "Join"
		if lobby_id_input:
			lobby_id_input.placeholder_text = "Enter Lobby ID"
			lobby_id_input.editable = true
		if list_title:
			list_title.text = "Public Lobbies"


func _on_steam_ready() -> void:
	if use_steam:
		status_label.text = "Connected to Steam as %s" % SteamManager.get_persona_name()
		_check_steam_network_async()
	else:
		status_label.text = "Step 1: Instance 1 → 'Start Host'. Step 2: Instance 2+ → 'Join as Client'."
	_refresh_lobby_list()
	if use_steam:
		refresh_timer.start()


func _check_steam_network_async() -> void:
	if not use_steam:
		return
	var ready := await SteamManager.ensure_relay_ready(12.0)
	if not is_inside_tree():
		return
	if ready:
		return
	status_label.text = SteamManager.get_relay_status_message()


func _on_steam_init_failed(reason: String) -> void:
	status_label.text = reason


func _on_lobby_join_failed(reason: String) -> void:
	status_label.text = reason
	_set_ui_locked(false)


func _on_lobby_left_reset_ui() -> void:
	_set_ui_locked(false)


func _set_ui_locked(locked: bool) -> void:
	_ui_locked = locked
	if create_button:
		create_button.disabled = locked
	if join_button:
		join_button.disabled = locked


func _refresh_lobby_list() -> void:
	if SteamManager.steam_ready and use_steam:
		SteamManager.request_lobby_list()


func _on_lobby_list_loaded(lobbies: Array) -> void:
	var compatible_version := SteamManager.get_game_version()
	var seen: Dictionary = {}
	for lobby in lobbies:
		if lobby is Dictionary:
			var id := int(lobby.get("id", 0))
			if id == 0:
				continue
			var lobby_version := str(lobby.get("version", "")).strip_edges()
			if lobby_version != "" and lobby_version != compatible_version:
				continue
			seen[id] = true
			_upsert_lobby_item(lobby)

	for id in _lobby_items.keys():
		if not seen.has(id):
			var item: Dictionary = _lobby_items[id]
			if item.has("panel") and is_instance_valid(item["panel"]):
				item["panel"].queue_free()
			_lobby_items.erase(id)


func _upsert_lobby_item(lobby: Dictionary) -> void:
	var id := int(lobby.get("id", 0))
	var name := str(lobby.get("name", "Lobby"))
	if name.strip_edges() == "":
		name = "DropOne Lobby"
	var version := str(lobby.get("version", ""))
	var players := int(lobby.get("players", 0))
	var max_players := int(lobby.get("max_players", 8))
	var info_text := "%s  |  %d/%d players" % [version, players, max_players]

	if _lobby_items.has(id):
		var item: Dictionary = _lobby_items[id]
		if item.has("name_label") and is_instance_valid(item["name_label"]):
			item["name_label"].text = name
		if item.has("detail_label") and is_instance_valid(item["detail_label"]):
			item["detail_label"].text = info_text
		return

	var row_data := _create_lobby_row(id, name, info_text)
	lobby_container.add_child(row_data["panel"])
	_lobby_items[id] = row_data


func _create_lobby_row(id: int, name: String, info_text: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = name
	info.add_child(name_label)

	var detail_label := Label.new()
	detail_label.text = info_text
	info.add_child(detail_label)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(func() -> void:
		if _ui_locked or SteamManager.is_lobby_busy():
			return
		if not Globals.has_customized_profile():
			status_label.text = "Please customize your profile first."
			return
		_set_ui_locked(true)
		status_label.text = "Joining lobby %d..." % id
		SteamManager.join_lobby(id)
	)
	hbox.add_child(join_btn)

	return {"panel": panel, "name_label": name_label, "detail_label": detail_label}


func _on_solo_pressed() -> void:
	if _ui_locked or SteamManager.is_lobby_busy():
		return
	if not Globals.has_customized_profile():
		status_label.text = "Please customize your profile first."
		return
	_set_ui_locked(true)
	status_label.text = "Starting singleplayer..."
	SteamManager.start_solo()


func _on_create_pressed() -> void:
	if _ui_locked or SteamManager.is_lobby_busy():
		return
	if not Globals.has_customized_profile():
		status_label.text = "Please customize your profile first."
		return
	_set_ui_locked(true)
	if use_steam:
		status_label.text = "Creating lobby..."
	else:
		status_label.text = "Starting local host..."
	SteamManager.create_lobby()


func _on_join_id_pressed() -> void:
	if _ui_locked or SteamManager.is_lobby_busy():
		return
	if not Globals.has_customized_profile():
		status_label.text = "Please customize your profile first."
		return
	_set_ui_locked(true)
	if not SteamManager.use_steam:
		status_label.text = "Connecting as client..."
		SteamManager.join_lobby(SteamManager.LOCAL_LOBBY_ID)
		return
	var text := lobby_id_input.text.strip_edges()
	if text == "":
		status_label.text = "Please enter a lobby ID."
		_set_ui_locked(false)
		return
	if not text.is_valid_int():
		status_label.text = "Lobby ID must be a number."
		_set_ui_locked(false)
		return
	var lobby_id := int(text)
	if lobby_id <= 0:
		status_label.text = "Invalid lobby ID."
		_set_ui_locked(false)
		return
	status_label.text = "Joining lobby %d..." % lobby_id
	SteamManager.join_lobby(lobby_id)


func _on_paste_pressed() -> void:
	if not use_steam:
		return
	lobby_id_input.text = DisplayServer.clipboard_get()


func _on_back_pressed() -> void:
	SteamManager.leave_lobby()
	Globals.change_scene_file(START_SCREEN)


func _exit_tree() -> void:
	if SteamManager.lobby_left.is_connected(_on_lobby_left_reset_ui):
		SteamManager.lobby_left.disconnect(_on_lobby_left_reset_ui)
	if SteamManager.steam_init_failed.is_connected(_on_steam_init_failed):
		SteamManager.steam_init_failed.disconnect(_on_steam_init_failed)
	if SteamManager.steam_ready_signal.is_connected(_on_steam_ready):
		SteamManager.steam_ready_signal.disconnect(_on_steam_ready)
	if SteamManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		SteamManager.lobby_join_failed.disconnect(_on_lobby_join_failed)
	if SteamManager.lobby_list_loaded.is_connected(_on_lobby_list_loaded):
		SteamManager.lobby_list_loaded.disconnect(_on_lobby_list_loaded)
