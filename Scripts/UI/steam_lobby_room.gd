extends Control
class_name SteamLobbyRoom

const PLAYER_ROW := preload("res://Scenes/UI/steam_lobby_player_row.tscn")
const LOBBY_HUB := "res://Scenes/UI/steam_lobby_hub.tscn"
const GAME_SCENE_PATH := "res://Scenes/Managers/card_manager.tscn"

const DIFFICULTY_NAMES := ["Rookie", "Casual", "Smart", "Hard", "Master", "Omega"]
const PERSONALITY_NAMES := ["Balanced", "Aggressor", "Collector", "Chaos", "Punisher", "Color Monarch"]

## Wird vom Hub übernommen; hier nur falls Szene direkt gestartet wird.
@export var use_steam: bool = true
@export var game_scene: PackedScene

@onready var lobby_id_label: Label = %lobby_id_label
@onready var status_label: Label = %status_label
@onready var ready_button: Button = %ready_button
@onready var players_container: VBoxContainer = %players_container
@onready var mode_label: Label = %mode_label
@onready var poll_timer: Timer = %poll_timer
@onready var bot_controls: HBoxContainer = %bot_controls
@onready var difficulty_option: OptionButton = %difficulty_option
@onready var personality_option: OptionButton = %personality_option
@onready var add_bot_button: Button = %add_bot_button
@onready var remove_bot_button: Button = %remove_bot_button

var _is_ready := false
var _did_start := false
var _start_requested := false


func _ready() -> void:
	use_steam = SteamManager.use_steam
	_update_mode_label()
	_setup_bot_options()

	if SteamManager.current_lobby_id == 0:
		_go_to_hub()
		return

	lobby_id_label.text = str(SteamManager.current_lobby_id)

	NetworkManager.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkManager.lobby_start_game.connect(_on_start_game)
	NetworkManager.lobby_disconnected.connect(_on_lobby_disconnected)
	SteamManager.lobby_left.connect(_go_to_hub)

	var ok := false
	if NetworkManager.has_active_connection():
		# Rückkehr aus einem Spiel – bestehende Verbindung wiederverwenden.
		_did_start = false
		_start_requested = false
		_is_ready = false
		ready_button.text = "Ready"
		status_label.text = "Zurück in der Lobby."
		NetworkManager.reset_for_lobby_return()
		SteamManager.is_lobby_owner = NetworkManager.is_server
		ok = true
	elif not use_steam:
		if SteamManager.local_role == SteamManager.LocalRole.CLIENT:
			status_label.text = "Verbinde als Client mit Host..."
			ok = await NetworkManager.enter_local_as_client()
		elif SteamManager.local_role == SteamManager.LocalRole.SOLO:
			# Einzelspieler: immer eigener Host, keine Probe.
			status_label.text = "Einzelspieler – füge Bots hinzu."
			ok = NetworkManager.enter_lobby_host(false)
		else:
			# HOST: Probe -> falls schon ein Host läuft, automatisch Client.
			status_label.text = "Starte lokalen Host..."
			ok = await NetworkManager.enter_local_as_host()
		SteamManager.is_lobby_owner = NetworkManager.is_server
	elif SteamManager.is_host():
		status_label.text = "Lobby erstellt – warte auf Spieler..."
		ok = NetworkManager.enter_lobby_host(use_steam, SteamManager.current_lobby_id)
	else:
		status_label.text = "Verbinde mit Lobby..."
		ok = NetworkManager.enter_lobby_client(use_steam, SteamManager.current_lobby_id, SteamManager.host_steam_id)

	if not is_inside_tree():
		return

	if not ok:
		if not use_steam and SteamManager.local_role == SteamManager.LocalRole.CLIENT:
			status_label.text = "Kein Host gefunden. In Instanz 1 zuerst 'Host starten' klicken."
		elif not use_steam:
			status_label.text = "Host-Port belegt – andere Instanzen schließen."
		else:
			status_label.text = "Verbindung fehlgeschlagen."
		await get_tree().create_timer(3.0).timeout
		_leave_and_go_hub()
		return

	_update_bot_controls_visibility()

	if poll_timer:
		poll_timer.timeout.connect(_on_poll)
		poll_timer.start()

	_on_lobby_state_changed(NetworkManager.get_lobby_players())


func _update_mode_label() -> void:
	if mode_label:
		mode_label.text = "Steam" if use_steam else "Lokal (Test)"


func _setup_bot_options() -> void:
	if difficulty_option:
		difficulty_option.clear()
		for i in range(DIFFICULTY_NAMES.size()):
			difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
		difficulty_option.selected = 2  # Smart
	if personality_option:
		personality_option.clear()
		for i in range(PERSONALITY_NAMES.size()):
			personality_option.add_item(PERSONALITY_NAMES[i], i)
		personality_option.selected = 0  # Balanced


func _update_bot_controls_visibility() -> void:
	# Nur der Host darf Bots verwalten.
	if bot_controls:
		bot_controls.visible = NetworkManager.is_server


func _on_add_bot_pressed() -> void:
	if not NetworkManager.is_server:
		return
	if NetworkManager.participant_count() >= NetworkManager.MAX_PLAYERS:
		status_label.text = "Maximal %d Teilnehmer erreicht." % NetworkManager.MAX_PLAYERS
		return
	var diff := difficulty_option.get_selected_id() if difficulty_option != null else 2
	var pers := personality_option.get_selected_id() if personality_option != null else 0
	NetworkManager.add_lobby_bot(diff, pers)


func _on_remove_bot_pressed() -> void:
	if not NetworkManager.is_server:
		return
	NetworkManager.remove_lobby_bot()


func _on_lobby_state_changed(players: Array) -> void:
	_render_players(players)
	_sync_ready_button(players)
	_update_bot_controls_visibility()


func _sync_ready_button(players: Array) -> void:
	if ready_button == null:
		return
	var my_id := 1 if NetworkManager.is_server else multiplayer.get_unique_id()
	for p in players:
		if p is Dictionary and int(p.get("peer_id", 0)) == my_id:
			_is_ready = bool(p.get("is_ready", false))
			ready_button.text = "Unready" if _is_ready else "Ready"
			return


func _on_poll() -> void:
	# Host prüft regelmäßig, ob alle bereit sind (Fallback zum Signal).
	if NetworkManager.is_server:
		_try_start_as_host()


func _render_players(players: Array) -> void:
	if not is_instance_valid(players_container):
		return

	for child in players_container.get_children():
		child.queue_free()

	for member in players:
		if member is Dictionary:
			var row: SteamLobbyPlayerRow = PLAYER_ROW.instantiate()
			players_container.add_child(row)
			row.call_deferred("setup", member)

	_update_status(players)

	if NetworkManager.is_server:
		_try_start_as_host()


func _update_status(players: Array) -> void:
	var count := players.size()
	if count < 2:
		if NetworkManager.is_server:
			status_label.text = "Allein in der Lobby – füge Bots hinzu oder warte auf Spieler (%d/2)." % count
		else:
			status_label.text = "Warte auf weitere Teilnehmer (%d/2)..." % count
		return
	var ready_count := 0
	for p in players:
		if p is Dictionary and bool(p.get("is_ready", false)):
			ready_count += 1
	if ready_count < count:
		status_label.text = "Bereit: %d/%d – warte auf alle..." % [ready_count, count]
	else:
		status_label.text = "Alle bereit – Spiel startet..."


func _on_ready_button_pressed() -> void:
	_is_ready = not _is_ready
	ready_button.text = "Unready" if _is_ready else "Ready"
	NetworkManager.set_lobby_ready(_is_ready)


func _on_copy_id_pressed() -> void:
	DisplayServer.clipboard_set(str(SteamManager.current_lobby_id))
	status_label.text = "Lobby-ID kopiert!"


func _on_invite_pressed() -> void:
	if not use_steam:
		status_label.text = "Einladen nur im Steam-Modus."
		return
	SteamManager.invite_friends()


func _on_leave_pressed() -> void:
	_leave_and_go_hub()


func _try_start_as_host() -> void:
	if _start_requested or _did_start:
		return
	if not NetworkManager.is_server:
		return
	if not NetworkManager.all_lobby_ready():
		return
	_start_requested = true
	NetworkManager.request_start_game()


func _on_start_game() -> void:
	if _did_start:
		return
	_did_start = true
	var scene := game_scene
	if scene == null:
		scene = load(GAME_SCENE_PATH)
	if scene == null:
		status_label.text = "Spielszene fehlt."
		return
	# Peer bleibt bestehen – nur die Szene wechselt.
	Globals.change_scene_packed(scene)


func _on_lobby_disconnected() -> void:
	if _did_start:
		return
	status_label.text = "Verbindung zum Host verloren."
	_leave_and_go_hub()


func _leave_and_go_hub() -> void:
	SteamManager.leave_lobby()
	_go_to_hub()


func _go_to_hub() -> void:
	Globals.change_scene_file(LOBBY_HUB)


func _exit_tree() -> void:
	if NetworkManager.lobby_state_changed.is_connected(_on_lobby_state_changed):
		NetworkManager.lobby_state_changed.disconnect(_on_lobby_state_changed)
	if NetworkManager.lobby_start_game.is_connected(_on_start_game):
		NetworkManager.lobby_start_game.disconnect(_on_start_game)
	if NetworkManager.lobby_disconnected.is_connected(_on_lobby_disconnected):
		NetworkManager.lobby_disconnected.disconnect(_on_lobby_disconnected)
	if SteamManager.lobby_left.is_connected(_go_to_hub):
		SteamManager.lobby_left.disconnect(_go_to_hub)
