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


func _ready() -> void:
	SteamManager.configure(use_steam)
	_update_mode_label()

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
		status_label.text = "Verbinde..." if use_steam else "Lokaler Modus bereit."


func _update_mode_label() -> void:
	if mode_label:
		mode_label.text = "Modus: Steam" if use_steam else "Modus: Lokal (127.0.0.1:4242)"

	if not use_steam:
		if create_button:
			create_button.text = "Host starten (Instanz 1)"
		if join_button:
			join_button.text = "Client beitreten (Instanz 2+)"
		if lobby_id_input:
			lobby_id_input.placeholder_text = "ID nicht nötig im Lokalmodus"
			lobby_id_input.editable = false
		if list_title:
			list_title.text = "Lokalmodus: keine öffentliche Liste"
		if join_row:
			join_row.visible = true
	else:
		if create_button:
			create_button.text = "Lobby erstellen"
		if join_button:
			join_button.text = "Beitreten"
		if lobby_id_input:
			lobby_id_input.placeholder_text = "Lobby-ID eingeben"
			lobby_id_input.editable = true
		if list_title:
			list_title.text = "Öffentliche Lobbies"


func _on_steam_ready() -> void:
	if use_steam:
		status_label.text = "Steam verbunden als %s" % SteamManager.get_persona_name()
	else:
		status_label.text = "Schritt 1: Instanz 1 → 'Host starten'. Schritt 2: Instanz 2+ → 'Client beitreten'."
	_refresh_lobby_list()
	if use_steam:
		refresh_timer.start()


func _on_steam_init_failed(reason: String) -> void:
	status_label.text = reason


func _on_lobby_join_failed(reason: String) -> void:
	status_label.text = reason


func _refresh_lobby_list() -> void:
	if SteamManager.steam_ready and use_steam:
		SteamManager.request_lobby_list()


func _on_lobby_list_loaded(lobbies: Array) -> void:
	var seen: Dictionary = {}
	for lobby in lobbies:
		if lobby is Dictionary:
			var id := int(lobby.get("id", 0))
			if id == 0:
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
	var info_text := "%s  |  %d/%d Spieler" % [version, players, max_players]

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
	join_btn.text = "Beitreten"
	join_btn.pressed.connect(func() -> void:
		if not Globals.has_customized_profile():
			status_label.text = "Bitte zuerst dein Profil anpassen."
			return
		status_label.text = "Trete Lobby %d bei..." % id
		SteamManager.join_lobby(id)
	)
	hbox.add_child(join_btn)

	return {"panel": panel, "name_label": name_label, "detail_label": detail_label}


func _on_solo_pressed() -> void:
	if not Globals.has_customized_profile():
		status_label.text = "Bitte zuerst dein Profil anpassen."
		return
	status_label.text = "Starte Einzelspieler..."
	SteamManager.start_solo()


func _on_create_pressed() -> void:
	if not Globals.has_customized_profile():
		status_label.text = "Bitte zuerst dein Profil anpassen."
		return
	if use_steam:
		status_label.text = "Erstelle Lobby..."
	else:
		status_label.text = "Starte lokalen Host..."
	SteamManager.create_lobby()


func _on_join_id_pressed() -> void:
	if not Globals.has_customized_profile():
		status_label.text = "Bitte zuerst dein Profil anpassen."
		return
	if not SteamManager.use_steam:
		status_label.text = "Verbinde als Client..."
		SteamManager.join_lobby(SteamManager.LOCAL_LOBBY_ID)
		return
	var text := lobby_id_input.text.strip_edges()
	if text == "":
		status_label.text = "Bitte Lobby-ID eingeben."
		return
	if not text.is_valid_int():
		status_label.text = "Lobby-ID muss eine Zahl sein."
		return
	var lobby_id := int(text)
	status_label.text = "Trete Lobby %d bei..." % lobby_id
	SteamManager.join_lobby(lobby_id)


func _on_paste_pressed() -> void:
	if not use_steam:
		return
	lobby_id_input.text = DisplayServer.clipboard_get()


func _on_back_pressed() -> void:
	Globals.change_scene_file(START_SCREEN)


func _exit_tree() -> void:
	if SteamManager.steam_init_failed.is_connected(_on_steam_init_failed):
		SteamManager.steam_init_failed.disconnect(_on_steam_init_failed)
	if SteamManager.steam_ready_signal.is_connected(_on_steam_ready):
		SteamManager.steam_ready_signal.disconnect(_on_steam_ready)
	if SteamManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		SteamManager.lobby_join_failed.disconnect(_on_lobby_join_failed)
	if SteamManager.lobby_list_loaded.is_connected(_on_lobby_list_loaded):
		SteamManager.lobby_list_loaded.disconnect(_on_lobby_list_loaded)
