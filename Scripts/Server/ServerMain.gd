extends Node
class_name ServerMain

@export var game_scene: PackedScene
@export var min_players := 2
@export var stale_timeout_seconds: float = 60.0
@export var clean_interval_seconds: float = 30.0

var _started := false
var _loading_scene := false

## Starts dedicated/local server and waits for enough players to load game scene.
func _ready() -> void:
	print("ServerMain started")
	NetworkManager.start_server(NetworkManager.DEFAULT_PORT)
	NetworkManager.players_received.connect(_on_players_received)

	var clean_timer := get_node_or_null("clean_players_timer") as Timer
	if clean_timer != null:
		clean_timer.stop()

func _on_players_received(players: Array) -> void:
	if _started:
		return

	var count := 0
	for p in players:
		if p is Dictionary and int(p.get("peer_id", 0)) != 0:
			count += 1

	print("ServerMain: Received %d players (min: %d)" % [count, min_players])

	if count < min_players:
		return

	_started = true

	# For dedicated server, we need to load the game scene to have QueueManager.
	if NetworkManager._is_dedicated_server():
		print("Dedicated server: Loading game scene for QueueManager...")
		if !_ensure_game_scene():
			return
		await _load_game_scene()
		return

	# For non-dedicated server (host), change to game scene.
	if !_ensure_game_scene():
		return
	await _load_game_scene()

## Loads fallback game scene if none assigned in the inspector.
func _ensure_game_scene() -> bool:
	if game_scene != null:
		return true

	game_scene = load("res://Scenes/Managers/card_manager.tscn")
	if game_scene == null:
		print("ServerMain: game_scene is null, cannot start game")
		print("Tried fallback: res://Scenes/Managers/card_manager.tscn")
		return false
	return true

## Deferred transition to the multiplayer game scene.
func _load_game_scene() -> void:
	if _loading_scene:
		return
	_loading_scene = true

	await get_tree().process_frame
	await get_tree().process_frame
	print("Changing to game scene...")
	get_tree().change_scene_to_packed(game_scene)

	_loading_scene = false

func _on_clean_players_timer_timeout() -> void:
	# Timer is disabled; dedicated server uses ENet directly.
	pass
