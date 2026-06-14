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
@onready var deck_option: OptionButton = %deck_option

var _is_ready := false
var _did_start := false
var _start_requested := false
var _deck_paths: Array[String] = []
var _applying_deck_selection := false


func _ready() -> void:
	use_steam = SteamManager.use_steam
	_update_mode_label()
	_setup_bot_options()
	_setup_deck_options()

	NetworkManager.lobby_deck_changed.connect(_on_lobby_deck_changed)

	if SteamManager.current_lobby_id == 0:
		_go_to_hub()
		return

	lobby_id_label.text = str(SteamManager.current_lobby_id)

	NetworkManager.lobby_state_changed.connect(_on_lobby_state_changed)
	NetworkManager.lobby_start_game.connect(_on_start_game)
	NetworkManager.lobby_disconnected.connect(_on_lobby_disconnected)
	SteamManager.lobby_left.connect(_go_to_hub)

	var ok := false
	if NetworkManager.consume_rejoin_from_match():
		# Rückkehr aus einem Spiel – bestehende Verbindung wiederverwenden.
		_did_start = false
		_start_requested = false
		_is_ready = false
		ready_button.text = "Ready"
		status_label.text = "Back in the lobby."
		NetworkManager.reset_for_lobby_return()
		SteamManager.is_lobby_owner = NetworkManager.is_server
		ok = true
	elif not use_steam:
		if SteamManager.local_role == SteamManager.LocalRole.CLIENT:
			status_label.text = "Connecting to host..."
			ok = await NetworkManager.enter_local_as_client()
		elif SteamManager.local_role == SteamManager.LocalRole.SOLO:
			# Einzelspieler: immer eigener Host, keine Probe.
			status_label.text = "Singleplayer – add bots."
			ok = NetworkManager.enter_lobby_host(false)
		elif SteamManager.local_role == SteamManager.LocalRole.HOST:
			status_label.text = "Starting local host..."
			ok = await NetworkManager.enter_local_as_host()
		else:
			status_label.text = "Invalid lobby state – please try again."
			ok = false
		SteamManager.is_lobby_owner = NetworkManager.is_server
	elif SteamManager.is_host():
		status_label.text = "Preparing Steam network..."
		await SteamManager.ensure_relay_ready(15.0)
		if not is_inside_tree():
			return
		status_label.text = "Lobby created – waiting for players..."
		ok = NetworkManager.enter_lobby_host(use_steam, SteamManager.current_lobby_id)
	else:
		status_label.text = "Preparing Steam network..."
		# Best-effort wait for the relay network; the client connect below also
		# retries on its own, so we proceed even if this times out.
		await SteamManager.ensure_relay_ready()
		if not is_inside_tree():
			return
		status_label.text = "Connecting to lobby..."
		# enter_lobby_client retries the P2P connect internally and only returns
		# once connected (true) or after exhausting its attempts (false).
		ok = await NetworkManager.enter_lobby_client(use_steam, SteamManager.current_lobby_id, SteamManager.host_steam_id)

	if not is_inside_tree():
		return

	if not ok:
		if not use_steam and SteamManager.local_role == SteamManager.LocalRole.CLIENT:
			status_label.text = "No host found. Click 'Start Host' in instance 1 first."
		elif not use_steam:
			status_label.text = "Port 4242 in use – close other hosts or use 'Join as Client'."
		else:
			status_label.text = "Connection failed."
		await get_tree().create_timer(3.0).timeout
		_leave_and_go_hub()
		return

	_finalize_lobby_ui()

	if poll_timer:
		poll_timer.timeout.connect(_on_poll)
		poll_timer.start()


func _finalize_lobby_ui() -> void:
	if NetworkManager.is_server:
		NetworkManager.refresh_lobby_display()
	_update_bot_controls_visibility()
	_init_deck_state()
	_on_lobby_state_changed(NetworkManager.get_lobby_players())


func _update_mode_label() -> void:
	if mode_label:
		mode_label.text = "Steam" if use_steam else "Local (Test)"


func _setup_bot_options() -> void:
	if difficulty_option:
		difficulty_option.clear()
		for i in range(DIFFICULTY_NAMES.size()):
			difficulty_option.add_item(DIFFICULTY_NAMES[i], i)
		difficulty_option.selected = 2  # Smart
		if not difficulty_option.item_selected.is_connected(_on_difficulty_selected):
			difficulty_option.item_selected.connect(_on_difficulty_selected)
	if personality_option:
		personality_option.clear()
		for i in range(PERSONALITY_NAMES.size()):
			personality_option.add_item(PERSONALITY_NAMES[i], i)
		personality_option.selected = 0  # Balanced
	_update_personality_option_state()


func _on_difficulty_selected(_index: int) -> void:
	_update_personality_option_state()


func _update_personality_option_state() -> void:
	if personality_option == null or difficulty_option == null:
		return
	var is_omega := difficulty_option.get_selected_id() == KIController.AIDifficulty.OMEGA
	personality_option.disabled = is_omega


func _setup_deck_options() -> void:
	if deck_option == null:
		return
	deck_option.clear()
	_deck_paths = Globals.list_deck_paths()
	for i in range(_deck_paths.size()):
		deck_option.add_item(Globals.deck_display_name(_deck_paths[i]), i)
	if _deck_paths.is_empty():
		deck_option.add_item("Default", 0)
		deck_option.disabled = true


## Once connected we know our role: the host picks the deck (and seeds the
## default), everyone else sees a read-only selection.
func _init_deck_state() -> void:
	if deck_option == null:
		return
	var is_host := NetworkManager.is_server or (not use_steam and SteamManager.local_role == SteamManager.LocalRole.HOST) or (use_steam and SteamManager.is_host())
	if is_host:
		deck_option.disabled = _deck_paths.is_empty()
		# Seed a default deck if none chosen yet, then broadcast it.
		var path := str(NetworkManager.lobby_deck_path)
		if path == "" and not _deck_paths.is_empty():
			path = _deck_paths[deck_option.selected if deck_option.selected >= 0 else 0]
		if path != "":
			Globals.selected_deck_path = path
			NetworkManager.set_lobby_deck(path)
	else:
		# Clients can see the deck but not change it.
		deck_option.disabled = true
	_select_deck_in_ui(str(NetworkManager.lobby_deck_path))


func _select_deck_in_ui(path: String) -> void:
	if deck_option == null or path == "":
		return
	var idx := _deck_paths.find(path)
	if idx < 0:
		return
	_applying_deck_selection = true
	deck_option.selected = idx
	_applying_deck_selection = false


func _on_deck_selected(index: int) -> void:
	if _applying_deck_selection:
		return
	if not NetworkManager.is_server:
		return
	if index < 0 or index >= _deck_paths.size():
		return
	var path := _deck_paths[index]
	Globals.selected_deck_path = path
	NetworkManager.set_lobby_deck(path)


func _on_lobby_deck_changed(deck_path: String) -> void:
	Globals.selected_deck_path = str(deck_path)
	_select_deck_in_ui(str(deck_path))


func _update_bot_controls_visibility() -> void:
	var is_host := NetworkManager.is_server or (not use_steam and SteamManager.local_role == SteamManager.LocalRole.HOST) or (use_steam and SteamManager.is_host())
	# Nur der Host darf Bots verwalten.
	if bot_controls:
		bot_controls.visible = is_host
	if deck_option:
		# Everyone sees the deck; only the host can change it.
		deck_option.disabled = (not is_host) or _deck_paths.is_empty()


func _on_add_bot_pressed() -> void:
	if not NetworkManager.is_server:
		return
	if NetworkManager.participant_count() >= NetworkManager.MAX_PLAYERS:
		status_label.text = "Maximum of %d participants reached." % NetworkManager.MAX_PLAYERS
		return
	var diff := difficulty_option.get_selected_id() if difficulty_option != null else 2
	var pers := KIController.AIPersonality.BALANCED
	if diff != KIController.AIDifficulty.OMEGA and personality_option != null:
		pers = personality_option.get_selected_id()
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
		if NetworkManager.is_server or SteamManager.is_host():
			status_label.text = "Alone in the lobby – add bots or wait for players (%d/2)." % count
		else:
			status_label.text = "Waiting for more players (%d/2)..." % count
		return
	var ready_count := 0
	for p in players:
		if p is Dictionary and bool(p.get("is_ready", false)):
			ready_count += 1
	if ready_count < count:
		status_label.text = "Ready: %d/%d – waiting for everyone..." % [ready_count, count]
	else:
		status_label.text = "Everyone ready – starting game..."


func _on_ready_button_pressed() -> void:
	_is_ready = not _is_ready
	ready_button.text = "Unready" if _is_ready else "Ready"
	NetworkManager.set_lobby_ready(_is_ready)


func _on_copy_id_pressed() -> void:
	DisplayServer.clipboard_set(str(SteamManager.current_lobby_id))
	status_label.text = "Lobby ID copied!"


func _on_invite_pressed() -> void:
	if not use_steam:
		status_label.text = "Invites only available in Steam mode."
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
		status_label.text = "Game scene missing."
		return
	# Peer bleibt bestehen – nur die Szene wechselt.
	Globals.change_scene_packed(scene)


func _on_lobby_disconnected() -> void:
	if _did_start:
		return
	status_label.text = "Lost connection to host."
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
	if NetworkManager.lobby_deck_changed.is_connected(_on_lobby_deck_changed):
		NetworkManager.lobby_deck_changed.disconnect(_on_lobby_deck_changed)
