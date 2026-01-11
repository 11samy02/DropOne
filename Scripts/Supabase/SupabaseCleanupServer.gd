extends Node

## Cleanup timeout seconds
@export var stale_timeout_seconds: float = 30.0

func cleanup_stale_players(stale_timeout_seconds_override: float = -1.0) -> void:
	var t := stale_timeout_seconds
	if stale_timeout_seconds_override >= 0.0:
		t = stale_timeout_seconds_override
	SupabaseManager.admin_cleanup_stale_players(t)
