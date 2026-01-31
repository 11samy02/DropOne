extends Control
class_name CurrentLobby

@onready var ready_button: Button = %Ready_button
@onready var players_in_lobby: Label = %players_in_lobby

@export var Game_Scene: PackedScene

var _poll_timer: Timer
var _is_ready: bool = false
var _did_go_game: bool = false

func _ready() -> void:
	SupabaseManager.request_failed.connect(func(error: String, details: String) -> void:
		print(error, " | ", details)
	)

	SupabaseManager.lobby_players_loaded.connect(_on_lobby_players_loaded)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.one_shot = false
	add_child(_poll_timer)
	_poll_timer.timeout.connect(_poll_tick)
	_poll_timer.start()

	_poll_tick()

func _poll_tick() -> void:
	var lobby_id := str(SupabaseManager.current_lobby_id)
	if lobby_id == "":
		return
	SupabaseManager.load_lobby_players(lobby_id)

func _on_lobby_players_loaded(_lobby_id: String, players: Array) -> void:
	var count := players.size()
	players_in_lobby.text = "%d players" % count

	var all_ready := true
	for p in players:
		if p is Dictionary:
			if not bool(p.get("is_ready", false)):
				all_ready = false
				break
		else:
			all_ready = false
			break

	if count >= 2 and all_ready:
		_go_to_game()

func _go_to_game() -> void:
	if _did_go_game:
		return
	_did_go_game = true
	
	# Connect to server and wait for connection
	NetworkManager.connect_auto()
	
	# Wait for connection to be established
	if not NetworkManager._connected:
		await NetworkManager.connected_ok
	
	# Give it a moment for the connection to fully establish
	await get_tree().create_timer(0.2).timeout

	if Game_Scene == null:
		return
	get_tree().change_scene_to_packed(Game_Scene)

func _on_ready_button_pressed() -> void:
	var lobby_id := str(SupabaseManager.current_lobby_id)
	if lobby_id == "":
		return

	_is_ready = not _is_ready
	ready_button.text = "Unready" if _is_ready else "Ready"
	SupabaseManager.set_ready(lobby_id, _is_ready)
	_poll_tick()
