extends Node

const DEFAULT_SERVER_IP := "146.52.121.88"
const DEFAULT_LAN_IP := "192.168.0.4"
const DEFAULT_PORT := 4242
const MAX_CLIENTS := 16
const DEV_MODE := true

var is_server := false
var _signals_connected := false
var _connected := false
var _trying_wan := false
var _trying_lan := false
var _target_port := DEFAULT_PORT
var _switch_timer: Timer

signal status_changed(message: String)

func _safe_log(msg: String, sensitive: String = "") -> void:
	if DEV_MODE and sensitive != "":
		print(msg, sensitive)
	else:
		print(msg)

func _ready() -> void:
	_switch_timer = Timer.new()
	_switch_timer.one_shot = true
	_switch_timer.timeout.connect(_try_lan_after_wan)
	add_child(_switch_timer)

func _reset_peer() -> void:
	_connected = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func start_server(port: int = DEFAULT_PORT) -> void:
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

	_emit_status("✅ Server started!")
	_safe_log("✅ SERVER STARTED on port", str(port))

func connect_auto(port: int = DEFAULT_PORT) -> void:
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
	rpc_id(1, "server_receive_ping", "Hello Server! I am connected.")

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

func _on_peer_connected(id: int) -> void:
	_emit_status("👤 A player joined.")
	_safe_log("👤 Client connected (id)", str(id))
	rpc_id(id, "client_receive_message", "Welcome!")

func _on_peer_disconnected(id: int) -> void:
	_emit_status("👋 A player left.")
	_safe_log("👋 Client disconnected (id)", str(id))

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
