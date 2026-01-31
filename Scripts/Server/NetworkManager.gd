extends Node

const DEFAULT_SERVER_IP := "146.52.121.88"
const DEFAULT_LAN_IP := "192.168.0.4"
const DEFAULT_PORT := 4242
const MAX_CLIENTS := 16
const DEV_MODE := true
const NM_VERSION := "0.2.0"
const BUILD_ID := "SERVER_BUILD_2026-01-13_02"

var is_server := false
var _signals_connected := false
var _connected := false
var _trying_wan := false
var _trying_lan := false
var _target_port := DEFAULT_PORT
var _switch_timer: Timer

# Client-side
var my_slot: int = -1
var last_hand: Array = []
var last_match_state: Dictionary = {}
var last_players: Array = []
var last_slot: int = -1

# Server-side: profiles by peer id
var _server_profiles_by_peer: Dictionary = {} # { peer_id:int : {name, picture_id, peer_id} }
var _server_slot_order: Array[int] = []

signal status_changed(message: String)
signal match_state_received(state: Dictionary)
signal hand_received(hand: Array)
signal players_received(players: Array)
signal connected_ok
signal counts_received(hand_counts: Array, deck_count: int)
signal play_event_received(from_slot: int, card: Dictionary)



func _safe_log(msg: String, sensitive: String = "") -> void:
	if DEV_MODE and sensitive != "":
		print(msg, sensitive)
	else:
		print(msg)

func _ready() -> void:
	print("NetworkManager version:", NM_VERSION)
	print("NetworkManager BUILD_ID:", BUILD_ID)

	_switch_timer = Timer.new()
	_switch_timer.one_shot = true
	_switch_timer.timeout.connect(_try_lan_after_wan)
	add_child(_switch_timer)

	print("NM PATH:", get_path())
	print("NM SCRIPT:", get_script().resource_path)
	print("NM METHODS:", get_method_list().size())

	# Server should also clean up on disconnect and rebroadcast.
	# (Client won't have peer_connected signals fired anyway; only server does.)
	# Connections for client are in _connect_to()


func _reset_peer() -> void:
	_connected = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


# -------------------------------------------------------------------
# SERVER
# -------------------------------------------------------------------
func start_server(port: int = DEFAULT_PORT) -> void:
	_server_slot_order.clear()
	is_server = true

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_emit_status("❌ Failed to start server.")
		_safe_log("❌ Failed to start server. Error:", str(err))
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Ensure server itself exists as slot 0 always.
	_ensure_server_profile()
	_broadcast_players_to_all()

	_emit_status("✅ Server started!")
	_safe_log("✅ SERVER STARTED on port", str(port))


func _on_peer_connected(id: int) -> void:
	_emit_status("👤 A player joined.")
	_safe_log("👤 Client connected (id)", str(id))
	rpc_id(id, "client_receive_message", "Welcome!")
	# NOTE: We do NOT broadcast here yet; we broadcast when we actually have a profile (server_register_player).


func _on_peer_disconnected(id: int) -> void:
	_emit_status("👋 A player left.")
	_safe_log("👋 Client disconnected (id)", str(id))

	if multiplayer.is_server():
		# Remove stale profile so we never rpc to an old peer id again.
		if _server_profiles_by_peer.has(id):
			_server_profiles_by_peer.erase(id)
		_prune_profiles_to_connected()
		_broadcast_players_to_all()


func _ensure_server_profile() -> void:
	if not multiplayer.is_server():
		return
	if _server_profiles_by_peer.has(1):
		return

	var nm := "Server"
	if Globals != null and Globals.client_profile != null and str(Globals.client_profile.player_name).strip_edges() != "":
		nm = str(Globals.client_profile.player_name).strip_edges()
	elif SupabaseManager != null and str(SupabaseManager.display_name).strip_edges() != "":
		nm = str(SupabaseManager.display_name).strip_edges()

	_server_profiles_by_peer[1] = {
		"name": nm,
		"picture_id": 0,
		"peer_id": 1
	}


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
			p = _server_profiles_by_peer[id]
		else:
			p = {"name": "Player", "picture_id": 0, "peer_id": id}
		p["peer_id"] = id
		players.append(p)
	
	for id in multiplayer.get_peers():
		var pid := int(id)
		var slot := connected.find(pid)
		if slot < 0:
			continue
		rpc_id(pid, "client_set_players", players, slot)
	
	if not _is_dedicated_server():
		client_set_players(players, connected.find(1))
	
	
	players_received.emit(players)

func server_rebroadcast_players() -> void:
	if not multiplayer.is_server():
		return
	_broadcast_players_to_all()


# -------------------------------------------------------------------
# CLIENT
# -------------------------------------------------------------------
func connect_auto(port: int = DEFAULT_PORT) -> void:
	is_server = false
	_target_port = port
	_trying_wan = true
	_trying_lan = false
	_reset_peer()
	_emit_status("🔄 Connecting...")
	_safe_log("🔄 Trying WAN first")
	_connect_to(DEFAULT_SERVER_IP, _target_port)
	_switch_timer.start(1.2)


func _try_lan_after_wan() -> void:
	if _connected:
		return
	if not _trying_wan:
		return
	_trying_wan = false
	_trying_lan = true
	_reset_peer()
	_emit_status("🔄 Connecting...")
	_safe_log("🔄 WAN not ready, trying LAN")
	_connect_to(DEFAULT_LAN_IP, _target_port)


func _connect_to(ip: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_emit_status("❌ Connection failed.")
		_safe_log("❌ create_client failed. Error:", str(err))
		return

	multiplayer.multiplayer_peer = peer

	if not _signals_connected:
		_signals_connected = true
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connected_to_server() -> void:
	_connected = true
	_switch_timer.stop()
	_emit_status("✅ Connected!")
	_safe_log("✅ CONNECTED TO SERVER!")
	emit_signal("connected_ok")

	# Safe to RPC now.
	rpc_id(1, "server_receive_ping", "Hello Server! I am connected.")
	send_profile_to_server()


func _on_connection_failed() -> void:
	_safe_log("❌ CONNECTION FAILED")

	if _trying_wan and not _connected:
		_trying_wan = false
		_trying_lan = true
		_reset_peer()
		_emit_status("🔄 Connecting...")
		_safe_log("🔄 WAN failed, trying LAN")
		_connect_to(DEFAULT_LAN_IP, _target_port)
		return

	_emit_status("❌ Connection failed.")


func _on_server_disconnected() -> void:
	_emit_status("⚠️ Disconnected.")
	_safe_log("⚠️ DISCONNECTED FROM SERVER")


func _is_peer_connected() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var p := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		return p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	# fallback
	return true


func send_profile_to_server() -> void:
	# Prevent the classic: "Trying to call an RPC via a peer which is not connected"
	if not _is_peer_connected():
		_safe_log("⚠️ send_profile_to_server() called while not connected - skipped")
		return

	var name_value := "Player"
	if Globals != null and Globals.client_profile != null and str(Globals.client_profile.player_name).strip_edges() != "":
		name_value = str(Globals.client_profile.player_name).strip_edges()
	elif SupabaseManager != null and str(SupabaseManager.display_name).strip_edges() != "":
		name_value = str(SupabaseManager.display_name).strip_edges()

	var profile := {
		"name": name_value,
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
	_safe_log("📩 Ping received (from id)", str(sender_id))
	_safe_log("📩 Message:", text)

@rpc("authority", "reliable")
func client_receive_message(text: String) -> void:
	_safe_log("📩 Message from server:", text)
	_emit_status("📩 " + text)

@rpc("any_peer", "reliable")
func server_register_player(profile: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()

	# Store profile under the real peer id (sender).
	profile["peer_id"] = sender
	_server_profiles_by_peer[sender] = profile

	_prune_profiles_to_connected()
	_broadcast_players_to_all()

@rpc("authority", "reliable")
func client_set_players(players: Array, your_slot: int) -> void:
	my_slot = int(your_slot)
	last_players = players
	last_slot = my_slot
	players_received.emit(players)

@rpc("authority", "reliable")
func client_set_hand(hand: Array) -> void:
	last_hand = hand
	hand_received.emit(hand)
	print("🃏 HAND RECEIVED size=", hand.size(), " first_type=", typeof(hand[0]) if hand.size() > 0 else -1)


@rpc("authority", "reliable")
func client_set_match_state(state: Dictionary) -> void:
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

func request_play(card_id: int) -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_request_play", int(card_id))

func request_wild_color(color: int) -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_set_wild_color", int(color))

func request_draw() -> void:
	if not _is_peer_connected():
		return
	rpc_id(1, "server_request_draw")

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
	
	# Ensure server profile exists
	_ensure_server_profile()
	_prune_profiles_to_connected()
	
	# Get all connected peer IDs including server
	var connected := _get_connected_peer_ids_including_server()
	
	# Filter peer_ids to only include connected peers
	var valid_peer_ids: Array[int] = []
	for pid in peer_ids:
		if connected.has(pid):
			valid_peer_ids.append(pid)
	
	# Sort to ensure consistent slot assignment
	valid_peer_ids.sort()
	
	# Broadcast players with updated slot mapping
	_broadcast_players_to_all()
