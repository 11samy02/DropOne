extends Node

## Reines Matchmaking: Steam-Lobbies erstellen/finden/beitreten.
## Die eigentliche Spieler-/Ready-/Spiel-Synchronisation läuft über NetworkManager
## (eine persistente Verbindung von der Lobby bis ins Spiel).
##
## Im Inspector der Lobby-Hub-Szene use_steam auf false setzen für lokalen Test
## ohne Steam (mehrere Instanzen über 127.0.0.1).

enum LocalRole { NONE, HOST, CLIENT, SOLO }

var use_steam: bool = true

const GAME_VERSION := "v0.1.1"
const MAX_LOBBY_PLAYERS := 8
const LOCAL_LOBBY_ID := 4242
const LOBBY_ROOM_SCENE := preload("res://Scenes/UI/steam_lobby_room.tscn")

var steam_ready := false
var current_lobby_id: int = 0
var is_lobby_owner := false
var host_steam_id: int = 0
var local_role: LocalRole = LocalRole.NONE

signal steam_init_failed(reason: String)
signal steam_ready_signal
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_left
signal lobby_list_loaded(lobbies: Array)

var _pending_lobby_name := "DropOne Lobby"
var _configured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(use_steam_enabled: bool) -> void:
	if _configured and use_steam == use_steam_enabled:
		return
	use_steam = use_steam_enabled
	_configured = true
	if use_steam:
		_connect_steam_signals()
		_init_steam()
	else:
		_init_local_mode()


func set_use_steam(enabled: bool) -> void:
	configure(enabled)


func _process(_delta: float) -> void:
	if use_steam and steam_ready:
		Steam.run_callbacks()


func _init_local_mode() -> void:
	steam_ready = true
	steam_ready_signal.emit()
	print("Local-Lobby-Modus aktiv (use_steam=false)")


func _connect_steam_signals() -> void:
	if Steam.lobby_created.is_connected(_on_lobby_created):
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)


func _init_steam() -> void:
	if steam_ready:
		steam_ready_signal.emit()
		return
	var init_result: Dictionary = Steam.steamInitEx(480, true)
	var status: int = int(init_result.get("status", 1))
	if status != Steam.STEAM_API_INIT_RESULT_OK:
		var verbal := str(init_result.get("verbal", "Unbekannter Fehler"))
		steam_init_failed.emit("Steam could not be initialized: %s" % verbal)
		return
	# ZWINGEND für P2P: ohne Relay-Netzwerkzugang können sich Host und Client
	# über SteamMultiplayerPeer nicht verbinden (Client bleibt auf "Connecting",
	# der Host sieht den Beitritt nie).
	Steam.initRelayNetworkAccess()
	steam_ready = true
	steam_ready_signal.emit()
	print("Steam initialisiert. Steam ID: ", Steam.getSteamID())


func get_local_player_name() -> String:
	if Globals != null and Globals.has_customized_profile():
		return str(Globals.client_profile.player_name).strip_edges()
	if use_steam and steam_ready:
		return str(Steam.getPersonaName())
	return "Player"


func get_persona_name(steam_id: int = 0) -> String:
	if use_steam and steam_ready and steam_id != 0:
		return str(Steam.getFriendPersonaName(steam_id))
	return get_local_player_name()


# -------------------------------------------------------------------
# Lobby erstellen / beitreten / verlassen
# -------------------------------------------------------------------
func create_lobby(lobby_name: String = "DropOne Lobby", max_players: int = MAX_LOBBY_PLAYERS) -> void:
	if not steam_ready:
		steam_init_failed.emit("Network is not ready.")
		return
	_pending_lobby_name = lobby_name
	if use_steam:
		Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, max_players)
	else:
		local_role = LocalRole.HOST
		_create_local_lobby(lobby_name)


## Einzelspieler gegen Bots – immer eigener lokaler Host, ohne Steam.
func start_solo() -> void:
	use_steam = false
	steam_ready = true
	local_role = LocalRole.SOLO
	current_lobby_id = LOCAL_LOBBY_ID
	is_lobby_owner = true
	host_steam_id = 0
	lobby_created.emit(current_lobby_id)
	_go_to_lobby_room()


func join_lobby(lobby_id: int) -> void:
	if not steam_ready:
		steam_init_failed.emit("Network is not ready.")
		return
	if use_steam:
		if lobby_id <= 0:
			lobby_join_failed.emit("Invalid lobby ID.")
			return
		current_lobby_id = lobby_id
		is_lobby_owner = false
		Steam.joinLobby(lobby_id)
	else:
		# Lokal: immer Client zu 127.0.0.1 – ID ist nur Anzeige.
		local_role = LocalRole.CLIENT
		current_lobby_id = LOCAL_LOBBY_ID
		is_lobby_owner = false
		host_steam_id = 0
		lobby_joined.emit(current_lobby_id)
		_go_to_lobby_room()


func leave_lobby() -> void:
	if current_lobby_id == 0 and local_role == LocalRole.NONE:
		return
	if use_steam and current_lobby_id != 0:
		Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	is_lobby_owner = false
	host_steam_id = 0
	local_role = LocalRole.NONE
	if NetworkManager != null:
		NetworkManager.leave_lobby()
	lobby_left.emit()


func request_lobby_list() -> void:
	if not steam_ready:
		return
	if use_steam:
		Steam.addRequestLobbyListDistanceFilter(Steam.LobbyDistanceFilter.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		Steam.addRequestLobbyListStringFilter("version", GAME_VERSION, Steam.LobbyComparison.LOBBY_COMPARISON_EQUAL)
		Steam.requestLobbyList()
	else:
		lobby_list_loaded.emit([])


func invite_friends() -> void:
	if current_lobby_id == 0 or not use_steam:
		return
	Steam.activateGameOverlayInviteDialog(current_lobby_id)


func is_host() -> bool:
	return is_lobby_owner


# -------------------------------------------------------------------
# Steam callbacks
# -------------------------------------------------------------------
func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		lobby_join_failed.emit("Could not create lobby (code %d)." % result)
		return
	current_lobby_id = lobby_id
	is_lobby_owner = true
	host_steam_id = int(Steam.getSteamID())
	Steam.setLobbyData(lobby_id, "name", _pending_lobby_name)
	Steam.setLobbyData(lobby_id, "version", GAME_VERSION)
	Steam.setLobbyData(lobby_id, "host_id", str(host_steam_id))
	Steam.setLobbyJoinable(lobby_id, true)
	lobby_created.emit(lobby_id)
	_go_to_lobby_room()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_join_failed.emit("Failed to join lobby (code %d)." % response)
		current_lobby_id = 0
		return
	current_lobby_id = lobby_id
	is_lobby_owner = (int(Steam.getLobbyOwner(lobby_id)) == int(Steam.getSteamID()))
	host_steam_id = int(Steam.getLobbyOwner(lobby_id))
	lobby_joined.emit(lobby_id)
	_go_to_lobby_room()


func _on_lobby_match_list(lobby_ids: Array) -> void:
	var result: Array = []
	for lobby_id in lobby_ids:
		var id := int(lobby_id)
		if id == 0:
			continue
		result.append({
			"id": id,
			"name": str(Steam.getLobbyData(id, "name")),
			"version": str(Steam.getLobbyData(id, "version")),
			"players": Steam.getNumLobbyMembers(id),
			"max_players": Steam.getLobbyMemberLimit(id),
		})
	lobby_list_loaded.emit(result)


func _create_local_lobby(lobby_name: String) -> void:
	current_lobby_id = LOCAL_LOBBY_ID
	is_lobby_owner = true
	host_steam_id = 0
	_pending_lobby_name = lobby_name
	print("LOCAL: Host-Lobby wird gestartet (ID %d)" % LOCAL_LOBBY_ID)
	lobby_created.emit(current_lobby_id)
	_go_to_lobby_room()


func _go_to_lobby_room() -> void:
	Globals.change_scene_packed(LOBBY_ROOM_SCENE)
