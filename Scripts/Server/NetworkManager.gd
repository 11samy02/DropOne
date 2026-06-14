extends Node

const DEFAULT_PORT := 4242
const MAX_CLIENTS := 16
const MAX_PLAYERS := 8
const DEV_MODE := true
const NM_VERSION := "0.3.0"
const BUILD_ID := "STEAM_BUILD_2026-06-14"

var _local_connecting := false
var _rejoin_from_match := false
var _session_had_remote_peers := false
var _host_alone_lobby_return_pending := false

## True when this peer is the authoritative server/host.
var is_server := false
var _signals_connected := false
var _connected := false

# Client-side
## Local player's seat index assigned by the server (-1 until known).
var my_slot: int = -1
var last_hand: Array = []
var last_match_state: Dictionary = {}
var last_players: Array = []
var last_slot: int = -1
## Incremented on every new match so clients can ignore stale hand/state snapshots.
var match_epoch: int = 0

# Server-side: profiles by peer id
var _server_profiles_by_peer: Dictionary = {} # { peer_id:int : {name, picture_id, peer_id} }
var _server_slot_order: Array[int] = []

# Lobby layer (persistente Verbindung Lobby -> Spiel)
var _ready_by_peer: Dictionary = {} # { peer_id:int : bool }
var last_lobby_players: Array = []   # Cache für Lobby-UI
var _lobby_bots: Array = []          # [{name, difficulty, personality}] (nur Host)
## Host-selected deck path synced to all lobby peers.
var lobby_deck_path: String = ""     # Vom Host gewähltes Deck (an alle gesynct)

enum LobbyEndMode {
	FIRST_WINNER,
	FULL_RANKING,
}

const DEFAULT_START_CARDS := 7
const ALLOWED_START_CARDS: Array[int] = [3, 5, 7, 9, 12]


func normalize_start_card_count(count: int) -> int:
	var best := DEFAULT_START_CARDS
	var best_dist := 999999
	for n in ALLOWED_START_CARDS:
		var dist := absi(int(n) - int(count))
		if dist < best_dist:
			best_dist = dist
			best = int(n)
	return best

## Cards dealt to each player at match start (host setting, synced to all peers).
var lobby_start_card_count: int = DEFAULT_START_CARDS
## FIRST_WINNER = lobby after first empty hand; FULL_RANKING = play until all places are set.
var lobby_end_mode: int = LobbyEndMode.FIRST_WINNER

signal status_changed(message: String)
signal match_state_received(state: Dictionary)
signal hand_received(hand: Array)
signal players_received(players: Array)
signal connected_ok
signal counts_received(hand_counts: Array, deck_count: int)
signal play_event_received(from_slot: int, card: Dictionary)
signal lobby_state_changed(players: Array)  # [{peer_id, name, is_ready, is_host, is_bot}]
signal lobby_start_game
signal lobby_disconnected
signal game_won(winner_name: String, winner_slot: int, place: int, is_final: bool, all_results: Array)
signal player_eliminated(slot: int)
signal return_to_lobby
signal lobby_deck_changed(deck_path: String)
signal lobby_settings_changed(start_cards: int, end_mode: int)



## Logs to console; includes sensitive detail only when DEV_MODE is true.
func _safe_log(msg: String, sensitive: String = "") -> void:
	if DEV_MODE and sensitive != "":
		print(msg, sensitive)
	else:
		print(msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("NetworkManager version:", NM_VERSION)
	print("NetworkManager BUILD_ID:", BUILD_ID)


## Closes the multiplayer peer and clears connection state.
func _reset_peer() -> void:
	_connected = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _connect_multiplayer_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _connect_server_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# -------------------------------------------------------------------
# LOBBY (persistente Verbindung: Lobby-Sync UND Spiel über einen Peer)
# -------------------------------------------------------------------
func enter_lobby_host(use_steam: bool, lobby_id: int = 0) -> bool:
	_reset_peer()
	_server_slot_order.clear()
	_server_profiles_by_peer.clear()
	_ready_by_peer.clear()
	is_server = true

	var peer: MultiplayerPeer = null
	if use_steam:
		var sp := SteamMultiplayerPeer.new()
		var err := sp.host_with_lobby(lobby_id)
		if err != OK:
			_emit_status("Steam host could not start.")
			_safe_log("host_with_lobby failed:", str(err))
			is_server = false
			return false
		peer = sp
	else:
		var ep := ENetMultiplayerPeer.new()
		var err := ep.create_server(DEFAULT_PORT, MAX_CLIENTS)
		if err != OK:
			_emit_status("Server port in use – is a host already running?")
			_safe_log("create_server failed:", str(err))
			is_server = false
			return false
		peer = ep

	multiplayer.multiplayer_peer = peer
	_connect_server_signals()
	_connected = true

	_ensure_server_profile()
	_ready_by_peer[1] = false
	_broadcast_lobby_state()
	_emit_status("Lobby host ready.")
	return true


## Lokal: explizit als Host starten (Button „Start Host“). Kein Auto-Join –
## dafür gibt es „Join as Client“.
func enter_local_as_host() -> bool:
	_reset_peer()
	_safe_log("LOCAL: Host startet auf 127.0.0.1:", str(DEFAULT_PORT))
	return enter_lobby_host(false)


## Lokal: explizit als Client verbinden (Instanz 2+ – Button "Client beitreten").
## Wiederholt den Verbindungsversuch, falls der Host noch startet.
func enter_local_as_client(max_wait_sec: float = 20.0) -> bool:
	_emit_status("Connecting to host 127.0.0.1:%d..." % DEFAULT_PORT)
	is_server = false
	_connect_multiplayer_signals()
	_local_connecting = true

	var deadline := Time.get_ticks_msec() + int(max_wait_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_reset_peer()
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client("127.0.0.1", DEFAULT_PORT) != OK:
			await get_tree().create_timer(0.5).timeout
			continue
		multiplayer.multiplayer_peer = peer

		var attempt_deadline := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < attempt_deadline:
			await get_tree().process_frame
			var st := peer.get_connection_status()
			if st == MultiplayerPeer.CONNECTION_CONNECTED:
				_local_connecting = false
				_connected = true
				await get_tree().process_frame
				await get_tree().process_frame
				send_profile_to_server()
				_emit_status("Connected to host.")
				_safe_log("LOCAL: Client verbunden, peer_id=", str(multiplayer.get_unique_id()))
				return true
			if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
				break

		_reset_peer()
		await get_tree().create_timer(0.4).timeout

	_local_connecting = false
	_emit_status("No host found. Start 'Start Host' in instance 1 first.")
	return false


func enter_lobby_client(use_steam: bool, lobby_id: int = 0, host_steam_id: int = 0) -> bool:
	is_server = false
	_reset_peer()
	_connect_multiplayer_signals()

	if not use_steam:
		_emit_status("Connecting to lobby...")
		var ep := ENetMultiplayerPeer.new()
		var e := ep.create_client("127.0.0.1", DEFAULT_PORT)
		if e != OK:
			_emit_status("Local connection failed.")
			_safe_log("create_client failed:", str(e))
			return false
		multiplayer.multiplayer_peer = ep
		return true

	# Steam P2P: the very first connect_to_lobby right after joining a Steam
	# lobby frequently fails to establish (the relay path and the host's listen
	# socket aren't fully ready yet), which is exactly why joining only worked
	# "on the second try". Retry the connection a few times until it sticks.
	if use_steam:
		await SteamManager.ensure_relay_ready(15.0)
		# Kurze Pause, damit der Host host_with_lobby abschließen kann.
		await get_tree().create_timer(0.75).timeout

	var total_deadline := Time.get_ticks_msec() + 30000
	var attempt := 0
	while Time.get_ticks_msec() < total_deadline:
		attempt += 1
		_emit_status("Connecting to lobby... (attempt %d)" % attempt)
		_reset_peer()

		var sp := SteamMultiplayerPeer.new()
		var err := OK
		if lobby_id != 0:
			err = sp.connect_to_lobby(lobby_id)
		else:
			err = sp.create_client(host_steam_id)
		if err != OK:
			_safe_log("connect_to_lobby failed (attempt %d):" % attempt, str(err))
			await get_tree().create_timer(1.0).timeout
			continue

		multiplayer.multiplayer_peer = sp

		# Give this attempt a few seconds to reach a connected state.
		var attempt_deadline := Time.get_ticks_msec() + 4500
		while Time.get_ticks_msec() < attempt_deadline:
			await get_tree().process_frame
			if use_steam:
				Steam.run_callbacks()
			if multiplayer.multiplayer_peer != sp:
				return _connected
			var st := sp.get_connection_status()
			if st == MultiplayerPeer.CONNECTION_CONNECTED:
				_connected = true
				await get_tree().process_frame
				await get_tree().process_frame
				send_profile_to_server()
				_emit_status("Connected!")
				return true
			if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
				break

		# This attempt did not connect; tear it down and try again.
		await get_tree().create_timer(0.5).timeout

	_emit_status("Could not reach the host (Steam).")
	_safe_log("enter_lobby_client: all attempts exhausted")
	return false


func leave_lobby() -> void:
	_ready_by_peer.clear()
	last_lobby_players = []
	_server_profiles_by_peer.clear()
	_server_slot_order.clear()
	_lobby_bots.clear()
	lobby_deck_path = ""
	lobby_start_card_count = DEFAULT_START_CARDS
	lobby_end_mode = LobbyEndMode.FIRST_WINNER
	is_server = false
	my_slot = -1
	last_slot = -1
	last_players = []
	clear_sync_buffers()
	_rejoin_from_match = false
	_session_had_remote_peers = false
	_host_alone_lobby_return_pending = false
	_reset_peer()


func mark_rejoin_from_match() -> void:
	_rejoin_from_match = true


## Nur nach Spielende: bestehende Verbindung in der Lobby weiterverwenden.
func consume_rejoin_from_match() -> bool:
	if not _rejoin_from_match or not has_active_connection():
		_rejoin_from_match = false
		return false
	_rejoin_from_match = false
	return true


func refresh_lobby_display() -> void:
	if not multiplayer.is_server():
		return
	_ensure_server_profile()
	_broadcast_lobby_state()


func _exit_tree() -> void:
	if _local_connecting:
		_local_connecting = false


func set_lobby_ready(ready: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_ready_by_peer[1] = ready
		_broadcast_lobby_state()
	else:
		rpc_id(1, "server_set_lobby_ready", ready)


# -------------------------------------------------------------------
# DECK (nur Host wählt das Deck; an alle synchronisiert)
# -------------------------------------------------------------------
func set_lobby_deck(deck_path: String) -> void:
	if not multiplayer.is_server():
		return
	lobby_deck_path = str(deck_path)
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_set_lobby_deck", lobby_deck_path)
	client_set_lobby_deck(lobby_deck_path)


@rpc("authority", "reliable", "call_local")
func client_set_lobby_deck(deck_path: String) -> void:
	lobby_deck_path = str(deck_path)
	lobby_deck_changed.emit(lobby_deck_path)


# -------------------------------------------------------------------
# GAME SETTINGS (nur Host wählt; an alle synchronisiert)
# -------------------------------------------------------------------
func set_lobby_settings(start_cards: int, end_mode: int) -> void:
	if not multiplayer.is_server():
		return
	lobby_start_card_count = normalize_start_card_count(int(start_cards))
	lobby_end_mode = clampi(int(end_mode), LobbyEndMode.FIRST_WINNER, LobbyEndMode.FULL_RANKING)
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_set_lobby_settings", lobby_start_card_count, lobby_end_mode)
	client_set_lobby_settings(lobby_start_card_count, lobby_end_mode)


@rpc("authority", "reliable", "call_local")
func client_set_lobby_settings(start_cards: int, end_mode: int) -> void:
	lobby_start_card_count = normalize_start_card_count(int(start_cards))
	lobby_end_mode = clampi(int(end_mode), LobbyEndMode.FIRST_WINNER, LobbyEndMode.FULL_RANKING)
	lobby_settings_changed.emit(lobby_start_card_count, lobby_end_mode)


# -------------------------------------------------------------------
# BOTS (nur Host verwaltet die Lobby-Bots)
# -------------------------------------------------------------------
func add_lobby_bot(difficulty: int, personality: int) -> bool:
	if not multiplayer.is_server():
		return false
	if participant_count() >= MAX_PLAYERS:
		return false
	var idx := _lobby_bots.size() + 1
	var diff := int(difficulty)
	var bot_name := "Omega" if diff == KIController.AIDifficulty.OMEGA else "Bot %d" % idx
	_lobby_bots.append({
		"name": bot_name,
		"difficulty": diff,
		"personality": int(personality),
	})
	_broadcast_lobby_state()
	return true


func remove_lobby_bot() -> void:
	if not multiplayer.is_server():
		return
	if _lobby_bots.is_empty():
		return
	_lobby_bots.pop_back()
	_broadcast_lobby_state()


func get_bot_count() -> int:
	return _lobby_bots.size()


func human_count() -> int:
	return _get_connected_peer_ids_including_server().size()


func participant_count() -> int:
	return human_count() + _lobby_bots.size()


func request_start_game() -> void:
	if not multiplayer.is_server():
		return
	if not all_lobby_ready():
		return
	match_epoch += 1
	_broadcast_players_to_all()
	call_deferred("_deferred_launch_game_scene")


func _deferred_launch_game_scene() -> void:
	if not multiplayer.is_server():
		return
	clear_sync_buffers()
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_prepare_match", match_epoch)
	_prepare_local_match(match_epoch)
	# Give peers time to receive player list + buffer clear before the scene swap.
	await get_tree().process_frame
	await get_tree().process_frame
	if not multiplayer.is_server():
		return
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_start_game")
	client_start_game()


func clear_sync_buffers() -> void:
	last_hand = []
	last_match_state = {}


func clear_match_buffers() -> void:
	clear_sync_buffers()
	last_players = []


@rpc("authority", "reliable")
func client_prepare_match(epoch: int) -> void:
	match_epoch = int(epoch)
	clear_sync_buffers()


func _prepare_local_match(epoch: int) -> void:
	match_epoch = int(epoch)
	clear_sync_buffers()


@rpc("authority", "reliable")
func client_clear_match_buffers() -> void:
	clear_sync_buffers()


func all_lobby_ready() -> bool:
	if participant_count() < 2:
		return false
	# Bots sind immer ready – nur Menschen müssen bestätigen.
	var connected := _get_connected_peer_ids_including_server()
	for id in connected:
		if not bool(_ready_by_peer.get(id, false)):
			return false
	return true


func get_lobby_players() -> Array:
	return last_lobby_players.duplicate(true)


func _build_lobby_player_array() -> Array:
	var connected := _get_connected_peer_ids_including_server()
	var arr: Array = []
	for id in connected:
		var prof: Dictionary = _server_profiles_by_peer.get(id, {})
		arr.append({
			"peer_id": id,
			"name": str(prof.get("name", "Player")),
			"is_ready": bool(_ready_by_peer.get(id, false)),
			"is_host": id == 1,
			"is_bot": false,
		})
	for bot in _lobby_bots:
		arr.append({
			"peer_id": 0,
			"name": str(bot.get("name", "Bot")),
			"is_ready": true,
			"is_host": false,
			"is_bot": true,
			"difficulty": int(bot.get("difficulty", 0)),
			"personality": int(bot.get("personality", 0)),
		})
	return arr


func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	_prune_ready_to_connected()
	var arr := _build_lobby_player_array()
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_lobby_state", arr)
		# Keep late joiners in sync with the host's chosen deck and game settings.
		rpc_id(int(pid), "client_set_lobby_deck", lobby_deck_path)
		rpc_id(int(pid), "client_set_lobby_settings", lobby_start_card_count, lobby_end_mode)
	client_lobby_state(arr)


func _prune_ready_to_connected() -> void:
	var connected := _get_connected_peer_ids_including_server()
	for key in _ready_by_peer.keys():
		if not connected.has(int(key)):
			_ready_by_peer.erase(key)


@rpc("any_peer", "reliable")
func server_set_lobby_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_ready_by_peer[sender] = ready
	_broadcast_lobby_state()


@rpc("authority", "reliable")
func client_lobby_state(players: Array) -> void:
	last_lobby_players = players
	lobby_state_changed.emit(players)


@rpc("authority", "reliable", "call_local")
func client_start_game() -> void:
	lobby_start_game.emit()
	call_deferred("_ensure_game_scene_if_needed")


const LOBBY_ROOM_SCENE := "res://Scenes/UI/steam_lobby_room.tscn"
const GAME_SCENE := "res://Scenes/Managers/card_manager.tscn"


func _ensure_game_scene_if_needed() -> void:
	if not has_active_connection():
		return
	var current := get_tree().current_scene
	if current == null:
		return
	if str(current.scene_file_path) != LOBBY_ROOM_SCENE:
		return
	var scene := load(GAME_SCENE)
	if scene == null:
		return
	Globals.change_scene_packed(scene)


# -------------------------------------------------------------------
# WIN / RÜCKKEHR ZUR LOBBY (Verbindung bleibt bestehen)
# -------------------------------------------------------------------
func has_active_connection() -> bool:
	return multiplayer.multiplayer_peer != null and _is_peer_connected()


func server_announce_winner(
	winner_name: String,
	winner_slot: int = -1,
	place: int = 1,
	is_final: bool = true,
	all_results: Array = []
) -> void:
	if not multiplayer.has_multiplayer_peer():
		game_won.emit(winner_name, int(winner_slot), int(place), bool(is_final), all_results)
		return
	if not multiplayer.is_server():
		return
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_on_winner", winner_name, int(winner_slot), int(place), bool(is_final), all_results)
	client_on_winner(winner_name, int(winner_slot), int(place), bool(is_final), all_results)


func server_return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	# Ready-States für die neue Runde zurücksetzen (Bots bleiben ready).
	for key in _ready_by_peer.keys():
		_ready_by_peer[key] = false
	match_epoch += 1
	clear_sync_buffers()
	for pid in multiplayer.get_peers():
		rpc_id(int(pid), "client_prepare_match", match_epoch)
		rpc_id(int(pid), "client_clear_match_buffers")
		rpc_id(int(pid), "client_return_to_lobby")
	_prepare_local_match(match_epoch)
	client_return_to_lobby()


## Client or host pressed "Back to Lobby" on the match results screen.
func request_return_to_lobby() -> void:
	if not has_active_connection():
		return
	if multiplayer.is_server():
		server_return_to_lobby()
	else:
		rpc_id(1, "server_request_return_to_lobby")


@rpc("any_peer", "reliable")
func server_request_return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	server_return_to_lobby()


## Wird vom Lobby-Raum aufgerufen, wenn nach einem Spiel die Verbindung
## wiederverwendet wird. Setzt Spiel-State zurück, behält den Peer.
func reset_for_lobby_return() -> void:
	my_slot = -1
	last_slot = -1
	clear_sync_buffers()
	_session_had_remote_peers = false
	_host_alone_lobby_return_pending = false
	if multiplayer.is_server():
		for key in _ready_by_peer.keys():
			_ready_by_peer[key] = false
		_ready_by_peer[1] = false
		_broadcast_lobby_state()


@rpc("authority", "reliable", "call_local")
func client_on_winner(
	winner_name: String,
	winner_slot: int = -1,
	place: int = 1,
	is_final: bool = true,
	all_results: Array = []
) -> void:
	game_won.emit(winner_name, int(winner_slot), int(place), bool(is_final), all_results)


@rpc("authority", "reliable", "call_local")
func client_on_player_eliminated(slot: int) -> void:
	player_eliminated.emit(int(slot))


@rpc("authority", "reliable", "call_local")
func client_return_to_lobby() -> void:
	return_to_lobby.emit()


## Server: show "Skipped" popup on the human peer that was skipped.
func server_notify_player_skipped(skipped_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := int(skipped_slot)
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm == null or not qm.has_method("_slot_to_peer_id"):
		return
	var peer_id: int = int(qm.call("_slot_to_peer_id", slot))
	if peer_id == 0:
		return
	if peer_id == multiplayer.get_unique_id():
		client_skip_feedback(slot)
	else:
		rpc_id(peer_id, "client_skip_feedback", slot)


@rpc("authority", "reliable")
func client_skip_feedback(skipped_slot: int) -> void:
	# RPC is peer-targeted; ignore stray deliveries if slot mapping drifted.
	if NetworkManager.my_slot >= 0 and int(NetworkManager.my_slot) != int(skipped_slot):
		return
	Signals.FEEDBACK_show.emit("Skipped", Signals.FeedbackKind.SKIPPED)


# -------------------------------------------------------------------
# STEAM P2P
# -------------------------------------------------------------------
func start_steam_host(lobby_id: int) -> void:
	_server_slot_order.clear()
	is_server = true
	_reset_peer()
	_emit_status("Starting Steam host...")

	var peer := SteamMultiplayerPeer.new()
	var err := peer.host_with_lobby(lobby_id)
	if err != OK:
		_emit_status("Host start failed.")
		_safe_log("host_with_lobby failed:", str(err))
		return

	multiplayer.multiplayer_peer = peer
	_connect_server_signals()

	_ensure_server_profile()
	_broadcast_players_to_all()

	_connected = true
	_emit_status("Steam host ready.")
	emit_signal("connected_ok")


func connect_steam_lobby(lobby_id: int) -> void:
	is_server = false
	_reset_peer()
	_emit_status("Connecting to lobby...")
	_connect_multiplayer_signals()

	var peer := SteamMultiplayerPeer.new()
	var err := peer.connect_to_lobby(lobby_id)
	if err != OK:
		_emit_status("Lobby connection failed.")
		_safe_log("connect_to_lobby failed:", str(err))
		return

	multiplayer.multiplayer_peer = peer


func connect_steam_client(host_steam_id: int) -> void:
	is_server = false
	_reset_peer()
	_emit_status("Connecting to host...")
	_connect_multiplayer_signals()

	var peer := SteamMultiplayerPeer.new()
	var err := peer.create_client(host_steam_id)
	if err != OK:
		_emit_status("Client connection failed.")
		_safe_log("create_client failed:", str(err))
		return

	multiplayer.multiplayer_peer = peer


# -------------------------------------------------------------------
# DEDICATED SERVER (optional, headless)
# -------------------------------------------------------------------
func start_server(port: int = DEFAULT_PORT) -> void:
	_server_slot_order.clear()
	is_server = true

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_emit_status("Server start failed.")
		_safe_log("create_server failed:", str(err))
		return

	multiplayer.multiplayer_peer = peer
	_connect_server_signals()

	_ensure_server_profile()
	_broadcast_players_to_all()

	_emit_status("Server started.")
	_safe_log("SERVER STARTED on port", str(port))
	_connected = true
	emit_signal("connected_ok")


func connect_local(host: String = "127.0.0.1", port: int = DEFAULT_PORT) -> void:
	is_server = false
	_reset_peer()
	_emit_status("Connecting locally...")
	_connect_multiplayer_signals()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		_emit_status("Local connection failed.")
		return
	multiplayer.multiplayer_peer = peer


func _on_peer_connected(id: int) -> void:
	_emit_status("A player joined.")
	_safe_log("Client connected (id)", str(id))
	_session_had_remote_peers = true
	if not _ready_by_peer.has(id):
		_ready_by_peer[id] = false
	rpc_id(id, "client_receive_message", "Welcome!")
	# Profil kommt per server_register_player; kurz warten und erneut broadcasten falls nötig.
	_deferred_profile_sync(int(id))


func _on_peer_disconnected(id: int) -> void:
	_emit_status("A player left the lobby.")
	_safe_log("Client disconnected (id)", str(id))

	if multiplayer.is_server():
		if _server_profiles_by_peer.has(id):
			_server_profiles_by_peer.erase(id)
		if _ready_by_peer.has(id):
			_ready_by_peer.erase(id)
		_prune_profiles_to_connected()
		_broadcast_players_to_all()
		_broadcast_lobby_state()
		_try_return_host_to_lobby_if_alone()


func _deferred_profile_sync(peer_id: int) -> void:
	await get_tree().create_timer(0.35).timeout
	if not multiplayer.is_server():
		return
	if not _get_connected_peer_ids_including_server().has(peer_id):
		return
	if not _server_profiles_by_peer.has(peer_id):
		rpc_id(peer_id, "client_request_send_profile")
	_broadcast_lobby_state()


@rpc("authority", "reliable")
func client_request_send_profile() -> void:
	send_profile_to_server()


func _ensure_server_profile() -> void:
	if not multiplayer.is_server():
		return
	var nm := _get_local_player_name()
	_server_profiles_by_peer[1] = {
		"name": nm,
		"picture_id": 0,
		"peer_id": 1
	}


func _get_local_player_name() -> String:
	if Globals != null and Globals.client_profile != null and str(Globals.client_profile.player_name).strip_edges() != "":
		return str(Globals.client_profile.player_name).strip_edges()
	if SteamManager != null and SteamManager.steam_ready:
		return SteamManager.get_persona_name()
	return "Player"


func _get_connected_peer_ids_including_server() -> Array[int]:
	var ids: Array[int] = []
	if not _is_dedicated_server():
		ids.append(1)
	if multiplayer.multiplayer_peer != null:
		for pid in multiplayer.get_peers():
			ids.append(int(pid))
	_refresh_slot_order(ids)
	return _server_slot_order.duplicate()

func _refresh_slot_order(connected: Array[int]) -> void:
	for pid in connected:
		if !_server_slot_order.has(pid):
			_server_slot_order.append(pid)
	for i in range(_server_slot_order.size() - 1, -1, -1):
		if not connected.has(_server_slot_order[i]):
			_server_slot_order.remove_at(i)
func _prune_profiles_to_connected() -> void:
	var connected := _get_connected_peer_ids_including_server()
	var keep := {}
	for id in connected:
		if _server_profiles_by_peer.has(id):
			keep[id] = _server_profiles_by_peer[id]
	_server_profiles_by_peer = keep


## Host-only: after the last remote peer leaves an active match, return to the lobby.
func _try_return_host_to_lobby_if_alone() -> void:
	if not multiplayer.is_server() or _is_dedicated_server():
		return
	if not _session_had_remote_peers:
		return
	if not multiplayer.get_peers().is_empty():
		return
	if _host_alone_lobby_return_pending:
		return

	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm == null or not qm.has_method("is_match_in_progress"):
		return
	if not bool(qm.call("is_match_in_progress")):
		return

	_host_alone_lobby_return_pending = true
	_emit_status("All players left – returning to lobby.")
	_safe_log("Host alone in active match – returning to lobby.")
	call_deferred("_finish_host_alone_lobby_return")


func _finish_host_alone_lobby_return() -> void:
	if not multiplayer.is_server():
		_host_alone_lobby_return_pending = false
		return
	server_return_to_lobby()
	_host_alone_lobby_return_pending = false


func _broadcast_players_to_all() -> void:
	if not multiplayer.is_server():
		return
	
	_ensure_server_profile()
	_prune_profiles_to_connected()
	
	var connected := _get_connected_peer_ids_including_server()
	
	var players: Array = []
	for id in connected:
		var p: Dictionary = {}
		if _server_profiles_by_peer.has(id):
			p = _server_profiles_by_peer[id].duplicate(true)
		else:
			p = {"name": "Player", "picture_id": 0, "peer_id": id}
		p["peer_id"] = id
		p["is_bot"] = false
		players.append(p)
	
	for bot in _lobby_bots:
		players.append({
			"name": str(bot.get("name", "Bot")),
			"picture_id": 0,
			"peer_id": 0,
			"is_bot": true,
			"difficulty": int(bot.get("difficulty", 0)),
			"personality": int(bot.get("personality", 0)),
		})
	
	for id in multiplayer.get_peers():
		var pid := int(id)
		var slot := connected.find(pid)
		if slot < 0:
			continue
		rpc_id(pid, "client_set_players", players, slot)
	
	if not _is_dedicated_server():
		client_set_players(players, connected.find(1))

	last_players = players
	players_received.emit(players)

func server_rebroadcast_players() -> void:
	if not multiplayer.is_server():
		return
	_broadcast_players_to_all()


# -------------------------------------------------------------------
# CLIENT CONNECTION
# -------------------------------------------------------------------
func _on_connected_to_server() -> void:
	_connected = true
	_emit_status("Connected!")
	_safe_log("CONNECTED TO HOST!")
	emit_signal("connected_ok")
	send_profile_to_server()


func _on_connection_failed() -> void:
	_safe_log("CONNECTION FAILED")
	if _local_connecting:
		return
	_emit_status("Connection failed.")
	lobby_disconnected.emit()


func _on_server_disconnected() -> void:
	if _local_connecting:
		return
	_emit_status("Disconnected.")
	_safe_log("DISCONNECTED FROM HOST")
	_connected = false
	lobby_disconnected.emit()


func _is_peer_connected() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var p := peer as ENetMultiplayerPeer
		return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if peer is SteamMultiplayerPeer:
		var sp := peer as SteamMultiplayerPeer
		return sp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return true


func send_profile_to_server() -> void:
	if not _is_peer_connected():
		_safe_log("send_profile_to_server() skipped - not connected")
		return

	var profile := {
		"name": _get_local_player_name(),
		"picture_id": 0
	}

	rpc_id(1, "server_register_player", profile)


# -------------------------------------------------------------------
# RPCs
# -------------------------------------------------------------------
func _emit_status(msg: String) -> void:
	status_changed.emit(msg)

@rpc("any_peer", "reliable")
func server_receive_ping(text: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	_safe_log("Ping received (from id)", str(sender_id))
	_safe_log("Message:", text)

@rpc("authority", "reliable")
func client_receive_message(text: String) -> void:
	_safe_log("Message from server:", text)
	_emit_status(text)

@rpc("any_peer", "reliable")
func server_register_player(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()

	profile["peer_id"] = sender
	_server_profiles_by_peer[sender] = profile
	if not _ready_by_peer.has(sender):
		_ready_by_peer[sender] = false

	_prune_profiles_to_connected()
	_broadcast_players_to_all()
	_broadcast_lobby_state()

@rpc("authority", "reliable")
func client_set_players(players: Array, your_slot: int) -> void:
	my_slot = int(your_slot)
	last_players = players
	last_slot = my_slot
	players_received.emit(players)

@rpc("authority", "reliable")
func client_set_hand(hand: Array, epoch: int = -1) -> void:
	if epoch >= 0 and epoch != match_epoch:
		return
	last_hand = hand
	hand_received.emit(hand)
	print("HAND RECEIVED size=", hand.size(), " first_type=", typeof(hand[0]) if hand.size() > 0 else -1)


@rpc("authority", "reliable")
func client_set_match_state(state: Dictionary, epoch: int = -1) -> void:
	if epoch >= 0 and epoch != match_epoch:
		return
	last_match_state = state
	match_state_received.emit(state)

@rpc("any_peer", "reliable")
func server_request_play(card_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("server_apply_play"):
		qm.call_deferred("server_apply_play", int(sender), int(card_id))

@rpc("any_peer", "reliable")
func server_request_draw() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("server_apply_draw"):
		qm.call_deferred("server_apply_draw", int(sender))

@rpc("authority", "reliable")
func client_play_event(from_slot: int, card: Dictionary) -> void:
	play_event_received.emit(int(from_slot), card)

@rpc("authority", "reliable")
func client_draw_sound(_from_slot: int, count: int = 1) -> void:
	if multiplayer.is_server():
		return
	SoundManager.play_draw_card(int(count))

@rpc("authority", "reliable", "call_local")
func client_set_counts(hand_counts: Array, deck_count: int) -> void:
	counts_received.emit(hand_counts, int(deck_count))


# -------------------------------------------------------------------
# Client snapshot helpers
# -------------------------------------------------------------------
func get_last_hand() -> Array:
	return last_hand

func clear_last_hand() -> void:
	last_hand = []

func get_last_match_state() -> Dictionary:
	return last_match_state

func clear_last_match_state() -> void:
	last_match_state = {}

func get_last_players() -> Array:
	return last_players

func clear_last_players() -> void:
	last_players = []

func get_last_slot() -> int:
	return last_slot

func _is_dedicated_server() -> bool:
	return multiplayer.is_server() and (OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless")

## Client requests the server to play a card by uid.
func request_play(card_id: int) -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_request_play", int(card_id))

## Client requests wild color selection on the server.
func request_wild_color(color: int) -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_set_wild_color", int(color))

## Client requests a draw from the server.
func request_draw() -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_request_draw")

## Client sends target slot for swap/target-draw resolution.
func request_target_select(target_slot: int) -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_select_target", int(target_slot))

@rpc("any_peer", "reliable")
func server_set_wild_color(color: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("server_apply_wild_color"):
		qm.call_deferred("server_apply_wild_color", int(sender), int(color))

@rpc("authority", "reliable")
func client_set_wild_color(color: int, owner_slot: int) -> void:
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("client_apply_wild_color"):
		qm.call_deferred("client_apply_wild_color", int(color), int(owner_slot))

@rpc("authority", "reliable")
func client_dismiss_color_select() -> void:
	Signals.COLOR_color_select_dismissed.emit()

@rpc("authority", "reliable")
func client_request_color(owner_slot: int) -> void:
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("client_request_color"):
		qm.call_deferred("client_request_color", int(owner_slot))

@rpc("authority", "reliable")
func client_request_target_select(owner_slot: int, allow_self: bool) -> void:
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("client_request_target_select"):
		qm.call_deferred("client_request_target_select", int(owner_slot), bool(allow_self))

@rpc("any_peer", "reliable")
func server_select_target(target_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var qm := get_tree().get_first_node_in_group("queue_manager")
	if qm != null and qm.has_method("server_apply_target_select"):
		qm.call_deferred("server_apply_target_select", int(sender), int(target_slot))


# -------------------------------------------------------------------
# Server slot management
# -------------------------------------------------------------------
func server_build_slots(peer_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	
	_ensure_server_profile()
	_prune_profiles_to_connected()
	_broadcast_players_to_all()
