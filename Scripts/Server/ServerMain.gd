extends Node

## Seconds until a player is considered offline
@export var stale_timeout_seconds: float = 30.0

@export var _clean_players_timer: Timer

func _ready() -> void:
	NetworkManager.start_server(NetworkManager.DEFAULT_PORT)

func _on_clean_players_timer_timeout() -> void:
	SupabaseCleanupServer.cleanup_stale_players(stale_timeout_seconds)
	print("Cleaned")
