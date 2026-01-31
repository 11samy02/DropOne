extends Node

@export var stale_timeout_seconds: float = 30.0
@export var clean_interval_seconds: float = 30.0
@export var cleanup_empty_lobbies_enabled := true
@export var cleanup_stale_profiles_enabled := false
@export var profile_stale_timeout_seconds: float = 3600.0

var _cleanup_timer: Timer
var _warned_missing_service_role := false

func _ready() -> void:
	print("SupabaseCleanupServer ready")

	SupabaseManager.admin_cleanup_done.connect(func(cutoff: String) -> void:
		print("cleanup ok before:", cutoff)
	)
	SupabaseManager.admin_cleanup_failed.connect(func(err: String, details: String) -> void:
		print("cleanup failed:", err, details)
	)
	SupabaseManager.admin_cleanup_lobbies_done.connect(func(ids: Array) -> void:
		print("cleanup lobbies deleted:", ids.size())
	)
	SupabaseManager.admin_cleanup_profiles_done.connect(func(cutoff: String) -> void:
		print("cleanup profiles ok before:", cutoff)
	)

	_cleanup_timer = Timer.new()
	_cleanup_timer.wait_time = max(5.0, clean_interval_seconds)
	_cleanup_timer.one_shot = false
	_cleanup_timer.autostart = true
	add_child(_cleanup_timer)
	_cleanup_timer.timeout.connect(_on_cleanup_timer_timeout)

func cleanup_stale_players(stale_timeout_seconds_override: float = -1.0) -> void:
	var t := stale_timeout_seconds
	if stale_timeout_seconds_override >= 0.0:
		t = stale_timeout_seconds_override

	print("cleanup requested, timeout:", t)
	SupabaseManager.admin_cleanup_stale_players(t)

func cleanup_empty_lobbies() -> void:
	SupabaseManager.admin_cleanup_empty_lobbies()

func cleanup_stale_profiles(stale_timeout_seconds_override: float = -1.0) -> void:
	var t := profile_stale_timeout_seconds
	if stale_timeout_seconds_override >= 0.0:
		t = stale_timeout_seconds_override
	SupabaseManager.admin_cleanup_stale_profiles(t)

func _has_service_role() -> bool:
	var srk := OS.get_environment(SupabaseManager.service_role_env_var).strip_edges()
	return srk != ""

func _on_cleanup_timer_timeout() -> void:
	if not _has_service_role():
		if not _warned_missing_service_role:
			_warned_missing_service_role = true
			print("cleanup skipped: missing service role key")
		return
	cleanup_stale_players()
	if cleanup_empty_lobbies_enabled:
		cleanup_empty_lobbies()
	if cleanup_stale_profiles_enabled:
		cleanup_stale_profiles()
