extends Node

## Supabase project base URL, e.g. https://xxxx.supabase.co
@export var supabase_url: String = "https://fyybftpvgfkvsqmhdyau.supabase.co"

## Supabase anon public key (client-safe)
@export var supabase_anon_key: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ5eWJmdHB2Z2ZrdnNxbWhkeWF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5MTExNzMsImV4cCI6MjA4MzQ4NzE3M30.RasL0wESxSKDDf7wuTo5l06XLTBchy22QdxYVFhoKL0"

## PostgREST base path
@export var rest_path: String = "/rest/v1"

## Server-only service role key env var name
@export var service_role_env_var: String = "SUPABASE_SERVICE_ROLE_KEY"

## Default game version used to filter compatible lobbies
@export var game_version: String = ""

## Heartbeat interval while in a lobby
@export var heartbeat_seconds: float = 5.0

## Table name for lobby players
@export var lobby_players_table: String = "lobby_players"

## Local identity for no-auth mode
var player_id: String = "Admin"
var display_name: String = "Player"
var current_lobby_id: String = ""

var _heartbeat_timer: Timer

signal lobby_player_counts_loaded(counts: Dictionary)
signal lobby_created(lobby: Dictionary)
signal lobby_list_loaded(lobbies: Array)
signal lobby_deleted(lobby_id: String)
signal lobby_joined(lobby_id: String)
signal lobby_left(lobby_id: String)
signal lobby_players_loaded(lobby_id: String, players: Array)
signal request_failed(error: String, details: String)

signal admin_cleanup_done(deleted_before_iso: String)
signal admin_cleanup_failed(error: String, details: String)

func _ready() -> void:
	player_id = _get_or_create_local_player_id()
	game_version = _get_project_version()

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = max(1.0, heartbeat_seconds)
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.autostart = false
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_on_heartbeat_timer_timeout)

func _on_heartbeat_timer_timeout() -> void:
	if current_lobby_id != "":
		touch_last_seen(current_lobby_id)

func configure(url: String, anon_key: String) -> void:
	supabase_url = url.strip_edges()
	supabase_anon_key = anon_key.strip_edges()

func set_display_name(name: String) -> void:
	display_name = name.strip_edges()
	if display_name == "":
		display_name = "Player"

func create_lobby(lobby_name: String) -> void:
	var name := lobby_name.strip_edges()
	if name == "":
		request_failed.emit("Invalid lobby name", "Lobby name is empty.")
		return

	var payload := {
		"name": name,
		"host_id": player_id,
		"game_version": game_version,
		"status": "open"
	}

	_request_json(
		HTTPClient.METHOD_POST,
		"/lobbies",
		payload,
		{"Prefer": "return=representation"},
		func(result: Variant) -> void:
			if result is Array and result.size() > 0 and result[0] is Dictionary:
				lobby_created.emit(result[0])
			else:
				request_failed.emit("Create lobby failed", str(result))
	)

func load_lobbies(limit: int = 50) -> void:
	var q := "?select=id,name,host_id,game_version,status,created_at"
	q += "&game_version=eq.%s" % _url_encode(game_version)
	q += "&status=eq.open"
	q += "&order=created_at.desc"
	q += "&limit=%d" % limit

	_request_json(
		HTTPClient.METHOD_GET,
		"/lobbies" + q,
		null,
		{},
		func(result: Variant) -> void:
			if result is Array:
				lobby_list_loaded.emit(result)
			else:
				request_failed.emit("Load lobbies failed", str(result))
	)

func delete_lobby(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?id=eq.%s" % _url_encode(id)

	_request_json(
		HTTPClient.METHOD_DELETE,
		"/lobbies" + q,
		null,
		{},
		func(_result: Variant) -> void:
			lobby_deleted.emit(id)
	)

func leave_lobby(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?lobby_id=eq.%s&player_id=eq.%s" % [_url_encode(id), _url_encode(player_id)]

	_request_json(
		HTTPClient.METHOD_DELETE,
		"/%s%s" % [lobby_players_table, q],
		null,
		{},
		func(_result: Variant) -> void:
			if current_lobby_id == id:
				current_lobby_id = ""
				_stop_heartbeat()
			lobby_left.emit(id)
	)

func load_lobby_players(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?select=player_id,display_name,is_ready,joined_at,last_seen"
	q += "&lobby_id=eq.%s" % _url_encode(id)
	q += "&order=joined_at.asc"

	_request_json(
		HTTPClient.METHOD_GET,
		"/%s%s" % [lobby_players_table, q],
		null,
		{},
		func(result: Variant) -> void:
			if result is Array:
				lobby_players_loaded.emit(id, result)
			else:
				request_failed.emit("Load lobby players failed", str(result))
	)

func load_lobby_player_counts(lobby_ids: Array[String]) -> void:
	if lobby_ids.is_empty():
		lobby_player_counts_loaded.emit({})
		return

	var parts: Array[String] = []
	for i in range(lobby_ids.size()):
		var id := lobby_ids[i].strip_edges()
		if id == "":
			continue
		parts.append(_url_encode(id))

	if parts.is_empty():
		lobby_player_counts_loaded.emit({})
		return

	var q := "?select=lobby_id"
	q += "&lobby_id=in.(%s)" % ",".join(parts)

	_request_json(
		HTTPClient.METHOD_GET,
		"/%s%s" % [lobby_players_table, q],
		null,
		{},
		func(result: Variant) -> void:
			if not (result is Array):
				request_failed.emit("Load lobby counts failed", str(result))
				return

			var counts: Dictionary = {}
			for row in result:
				if row is Dictionary:
					var lid := str(row.get("lobby_id", ""))
					if lid == "":
						continue
					counts[lid] = int(counts.get(lid, 0)) + 1

			lobby_player_counts_loaded.emit(counts)
	)

func touch_last_seen(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		return

	var q := "?lobby_id=eq.%s&player_id=eq.%s" % [_url_encode(id), _url_encode(player_id)]
	var payload := {"last_seen": _iso_now()}

	_request_json(
		HTTPClient.METHOD_PATCH,
		"/%s%s" % [lobby_players_table, q],
		payload,
		{"Prefer": "return=minimal"},
		func(_result: Variant) -> void:
			pass
	)

func set_ready(lobby_id: String, ready: bool) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?lobby_id=eq.%s&player_id=eq.%s" % [_url_encode(id), _url_encode(player_id)]
	var payload := {"is_ready": ready}

	_request_json(
		HTTPClient.METHOD_PATCH,
		"/%s%s" % [lobby_players_table, q],
		payload,
		{"Prefer": "return=minimal"},
		func(_result: Variant) -> void:
			load_lobby_players(id)
	)

func switch_lobby(target_lobby_id: String) -> void:
	var target := target_lobby_id.strip_edges()
	if target == "":
		request_failed.emit("Invalid lobby id", "Target lobby id is empty.")
		return

	if current_lobby_id == target:
		lobby_joined.emit(target)
		return

	if current_lobby_id != "":
		var old := current_lobby_id
		lobby_left.connect(Callable(self, "_on_switch_left_then_join").bind(old, target), CONNECT_ONE_SHOT)
		leave_lobby(old)
	else:
		_join_lobby_checked(target)

func _on_switch_left_then_join(left_id: String, expected_old: String, target: String) -> void:
	if left_id != expected_old:
		return
	_join_lobby_checked(target)

func _join_lobby_checked(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?select=player_id"
	q += "&lobby_id=eq.%s" % _url_encode(id)

	_request_json(
		HTTPClient.METHOD_GET,
		"/%s%s" % [lobby_players_table, q],
		null,
		{},
		func(result: Variant) -> void:
			if not (result is Array):
				request_failed.emit("Join check failed", str(result))
				return

			var players: Array = result

			for row in players:
				if row is Dictionary and str(row.get("player_id", "")) == player_id:
					current_lobby_id = id
					_start_heartbeat()
					touch_last_seen(id)
					lobby_joined.emit(id)
					return

			if players.size() >= 8:
				request_failed.emit("Lobby full", "This lobby already has %d/8 players." % players.size())
				return

			var payload := {
				"lobby_id": id,
				"player_id": player_id,
				"display_name": display_name
			}

			_request_json(
				HTTPClient.METHOD_POST,
				"/%s" % lobby_players_table,
				payload,
				{"Prefer": "return=minimal"},
				func(_result: Variant) -> void:
					current_lobby_id = id
					_start_heartbeat()
					touch_last_seen(id)
					lobby_joined.emit(id)
			)
	)

func admin_cleanup_stale_players(stale_timeout_seconds: float) -> void:
	var srk := OS.get_environment(service_role_env_var).strip_edges()
	if srk == "":
		admin_cleanup_failed.emit("Supabase not configured", "Missing service role key env var: " + service_role_env_var)
		return

	var cutoff_iso := _iso_from_unix(Time.get_unix_time_from_system() - int(stale_timeout_seconds))

	var endpoint := "/%s?last_seen=lt.%s" % [lobby_players_table, _url_encode(cutoff_iso)]
	var url := supabase_url + rest_path + endpoint

	var headers := PackedStringArray()
	headers.append("apikey: " + srk)
	headers.append("Authorization: Bearer " + srk)
	headers.append("Content-Type: application/json")
	headers.append("Accept: application/json")

	var req := HTTPRequest.new()
	add_child(req)

	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		if is_instance_valid(req):
			req.queue_free()

		var text := body.get_string_from_utf8()

		if result != HTTPRequest.RESULT_SUCCESS:
			admin_cleanup_failed.emit("Network error", text)
			return
		if code < 200 or code >= 300:
			admin_cleanup_failed.emit("HTTP error " + str(code), text)
			return

		admin_cleanup_done.emit(cutoff_iso)
	)

	var err := req.request(url, headers, HTTPClient.METHOD_DELETE, "")
	if err != OK:
		if is_instance_valid(req):
			req.queue_free()
		admin_cleanup_failed.emit("HTTPRequest error", str(err))

func _start_heartbeat() -> void:
	if _heartbeat_timer != null:
		_heartbeat_timer.wait_time = max(1.0, heartbeat_seconds)
		if _heartbeat_timer.is_stopped():
			_heartbeat_timer.start()

func _stop_heartbeat() -> void:
	if _heartbeat_timer != null:
		_heartbeat_timer.stop()

func _request_json(method: int, endpoint: String, payload: Variant, extra_headers: Dictionary, on_success: Callable) -> void:
	if supabase_url.strip_edges() == "" or supabase_anon_key.strip_edges() == "":
		request_failed.emit("Supabase not configured", "Missing URL or anon key.")
		return

	var url := supabase_url + rest_path + endpoint

	var headers := PackedStringArray()
	headers.append("apikey: " + supabase_anon_key)
	headers.append("Authorization: Bearer " + supabase_anon_key)
	headers.append("Content-Type: application/json")
	headers.append("Accept: application/json")

	for k in extra_headers.keys():
		headers.append("%s: %s" % [str(k), str(extra_headers[k])])

	var req := HTTPRequest.new()
	add_child(req)

	req.request_completed.connect(func(result: int, response_code: int, _rh: PackedStringArray, body: PackedByteArray) -> void:
		_on_request_completed(req, result, response_code, body, on_success)
	)

	var body_str := ""
	if payload != null:
		body_str = JSON.stringify(payload)

	var err := req.request(url, headers, method, body_str)
	if err != OK:
		req.queue_free()
		request_failed.emit("HTTPRequest error", str(err))

func _on_request_completed(req: HTTPRequest, result: int, code: int, body: PackedByteArray, on_success: Callable) -> void:
	if req != null and is_instance_valid(req):
		req.queue_free()

	var text := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Network error", text)
		return

	if code < 200 or code >= 300:
		request_failed.emit("HTTP error " + str(code), text)
		return

	if text.strip_edges() == "":
		on_success.call([])
		return

	var parsed = JSON.parse_string(text)
	if parsed == null:
		request_failed.emit("JSON parse error", text)
		return

	on_success.call(parsed)

func _get_or_create_local_player_id() -> String:
	var cfg := ConfigFile.new()
	var path := "user://local_player.cfg"
	var err := cfg.load(path)

	if err == OK and cfg.has_section_key("player", "id"):
		var existing := str(cfg.get_value("player", "id"))
		if existing.strip_edges() != "":
			return existing

	var new_id := _make_uuid_like_id()
	cfg.set_value("player", "id", new_id)
	cfg.save(path)
	return new_id

func _make_uuid_like_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	var hex := ""
	for i in range(32):
		hex += "0123456789abcdef"[rng.randi_range(0, 15)]
	
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]

func _url_encode(s: String) -> String:
	return s.uri_encode()

func _get_project_version() -> String:
	var v = ProjectSettings.get_setting("application/config/version", "")
	v = str(v).strip_edges()

	if v == "":
		v = "v0.0.0"

	if not v.begins_with("v"):
		v = "v" + v

	return v

func _iso_now() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"])
	]

func _iso_from_unix(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"])
	]
