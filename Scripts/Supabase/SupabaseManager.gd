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
@export var profiles_has_last_seen := false

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
signal lobby_loaded(lobby: Dictionary)
signal lobby_status_updated(lobby_id: String, status: String)

signal request_failed(error: String, details: String)

signal admin_cleanup_done(deleted_before_iso: String)
signal admin_cleanup_failed(error: String, details: String)
signal admin_cleanup_lobbies_done(deleted_ids: Array)
signal admin_cleanup_profiles_done(deleted_before_iso: String)

func _ready() -> void:
	player_id = _get_or_create_local_player_id()
	game_version = _get_project_version()

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = max(1.0, heartbeat_seconds)
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.autostart = false
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_on_heartbeat_timer_timeout)
	
	var win := get_window()
	if win != null:
		win.close_requested.connect(_on_close_requested)



func _on_heartbeat_timer_timeout() -> void:
	if current_lobby_id != "":
		touch_last_seen(current_lobby_id)
		touch_profile_last_seen()

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
				var lobby: Dictionary = result[0]
				lobby_created.emit(lobby)
				var lobby_id := str(lobby.get("id", ""))
				if lobby_id != "":
					switch_lobby(lobby_id)
			else:
				request_failed.emit("Create lobby failed", str(result))
	)

##Inserts a new row into profiles with name + picture_id, and default stats/role.
func create_profile(player_name: String, picture_id: int, on_created: Callable) -> void:
	var name := player_name.strip_edges()
	if name == "":
		request_failed.emit("Invalid player name", "Player name is empty.")
		return

	var payload := {
		"player_name": name,
		"picture_id": picture_id,
		"role": "user",
		"wins": 0,
		"looses": 0,
		"badges": []
	}

	_request_json(
		HTTPClient.METHOD_POST,
		"/profiles",
		payload,
		{"Prefer": "return=representation"},
		func(result: Variant) -> void:
			if result is Array and result.size() > 0 and result[0] is Dictionary:
				on_created.call(result[0])
			else:
				request_failed.emit("Create profile failed", str(result))
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

func load_lobby(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?select=id,name,host_id,game_version,status,created_at&id=eq.%s&limit=1" % _url_encode(id)

	_request_json(
		HTTPClient.METHOD_GET,
		"/lobbies" + q,
		null,
		{},
		func(result: Variant) -> void:
			if result is Array and result.size() > 0 and result[0] is Dictionary:
				lobby_loaded.emit(result[0])
			else:
				request_failed.emit("Load lobby failed", str(result))
	)

func set_lobby_status(lobby_id: String, status: String) -> void:
	var id := lobby_id.strip_edges()
	var st := status.strip_edges()
	if id == "" or st == "":
		request_failed.emit("Invalid lobby status", "Lobby id or status is empty.")
		return

	var q := "?id=eq.%s" % _url_encode(id)
	var payload := {"status": st}

	_request_json(
		HTTPClient.METHOD_PATCH,
		"/lobbies" + q,
		payload,
		{"Prefer": "return=minimal"},
		func(_result: Variant) -> void:
			lobby_status_updated.emit(id, st)
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

func touch_profile_last_seen() -> void:
	if not profiles_has_last_seen:
		return
	if player_id.strip_edges() == "":
		return

	var q := "?id=eq.%s" % _url_encode(player_id)
	var payload := {"last_seen": _iso_now()}

	_request_json(
		HTTPClient.METHOD_PATCH,
		"/profiles%s" % q,
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
	var endpoint := "/%s?or=(last_seen.is.null,last_seen.lt.%s)" % [
	lobby_players_table,
	_url_encode(cutoff_iso)
	]
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

func admin_cleanup_empty_lobbies() -> void:
	var srk := OS.get_environment(service_role_env_var).strip_edges()
	if srk == "":
		admin_cleanup_failed.emit("Supabase not configured", "Missing service role key env var: " + service_role_env_var)
		return

	var headers := PackedStringArray()
	headers.append("apikey: " + srk)
	headers.append("Authorization: Bearer " + srk)
	headers.append("Content-Type: application/json")
	headers.append("Accept: application/json")

	var lobbies_url := supabase_url + rest_path + "/lobbies?select=id"
	var req_lobbies := HTTPRequest.new()
	add_child(req_lobbies)

	req_lobbies.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		if is_instance_valid(req_lobbies):
			req_lobbies.queue_free()

		var text := body.get_string_from_utf8()
		if result != HTTPRequest.RESULT_SUCCESS:
			admin_cleanup_failed.emit("Network error", text)
			return
		if code < 200 or code >= 300:
			admin_cleanup_failed.emit("HTTP error " + str(code), text)
			return

		var parsed_var: Variant = JSON.parse_string(text)
		if not (parsed_var is Array):
			admin_cleanup_failed.emit("Parse error", text)
			return

		var parsed: Array = parsed_var
		var lobby_ids: Array[String] = []
		for row in parsed:
			if row is Dictionary and row.has("id"):
				lobby_ids.append(str(row.get("id", "")))

		if lobby_ids.is_empty():
			admin_cleanup_lobbies_done.emit([])
			return

		var players_url := supabase_url + rest_path + "/%s?select=lobby_id" % lobby_players_table
		var req_players := HTTPRequest.new()
		add_child(req_players)

		req_players.request_completed.connect(func(result2: int, code2: int, _h2: PackedStringArray, body2: PackedByteArray) -> void:
			if is_instance_valid(req_players):
				req_players.queue_free()

			var text2 := body2.get_string_from_utf8()
			if result2 != HTTPRequest.RESULT_SUCCESS:
				admin_cleanup_failed.emit("Network error", text2)
				return
			if code2 < 200 or code2 >= 300:
				admin_cleanup_failed.emit("HTTP error " + str(code2), text2)
				return

			var parsed2_var: Variant = JSON.parse_string(text2)
			if not (parsed2_var is Array):
				admin_cleanup_failed.emit("Parse error", text2)
				return

			var parsed2: Array = parsed2_var
			var active: Dictionary = {}
			for row in parsed2:
				if row is Dictionary:
					var lid := str(row.get("lobby_id", ""))
					if lid != "":
						active[lid] = true

			var to_delete: Array[String] = []
			for lid in lobby_ids:
				if not active.has(lid):
					to_delete.append(lid)

			if to_delete.is_empty():
				admin_cleanup_lobbies_done.emit([])
				return

			var encoded: Array[String] = []
			for lid in to_delete:
				encoded.append(_url_encode(lid))

			var delete_url := supabase_url + rest_path + "/lobbies?id=in.(%s)" % ",".join(encoded)
			var req_delete := HTTPRequest.new()
			add_child(req_delete)

			req_delete.request_completed.connect(func(result3: int, code3: int, _h3: PackedStringArray, body3: PackedByteArray) -> void:
				if is_instance_valid(req_delete):
					req_delete.queue_free()

				var text3 := body3.get_string_from_utf8()
				if result3 != HTTPRequest.RESULT_SUCCESS:
					admin_cleanup_failed.emit("Network error", text3)
					return
				if code3 < 200 or code3 >= 300:
					admin_cleanup_failed.emit("HTTP error " + str(code3), text3)
					return

				admin_cleanup_lobbies_done.emit(to_delete)
			)

			var err3 := req_delete.request(delete_url, headers, HTTPClient.METHOD_DELETE, "")
			if err3 != OK:
				if is_instance_valid(req_delete):
					req_delete.queue_free()
				admin_cleanup_failed.emit("HTTPRequest error", str(err3))
		)

		var err2 := req_players.request(players_url, headers, HTTPClient.METHOD_GET, "")
		if err2 != OK:
			if is_instance_valid(req_players):
				req_players.queue_free()
			admin_cleanup_failed.emit("HTTPRequest error", str(err2))
	)

	var err := req_lobbies.request(lobbies_url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		if is_instance_valid(req_lobbies):
			req_lobbies.queue_free()
		admin_cleanup_failed.emit("HTTPRequest error", str(err))

func admin_cleanup_stale_profiles(stale_timeout_seconds: float) -> void:
	if not profiles_has_last_seen:
		admin_cleanup_failed.emit("Profiles last_seen disabled", "profiles_has_last_seen is false")
		return
	var srk := OS.get_environment(service_role_env_var).strip_edges()
	if srk == "":
		admin_cleanup_failed.emit("Supabase not configured", "Missing service role key env var: " + service_role_env_var)
		return

	var cutoff_iso := _iso_from_unix(Time.get_unix_time_from_system() - int(stale_timeout_seconds))
	var endpoint := "/profiles?or=(last_seen.is.null,last_seen.lt.%s)" % _url_encode(cutoff_iso)
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

		admin_cleanup_profiles_done.emit(cutoff_iso)
	)

	var errp := req.request(url, headers, HTTPClient.METHOD_DELETE, "")
	if errp != OK:
		if is_instance_valid(req):
			req.queue_free()
		admin_cleanup_failed.emit("HTTPRequest error", str(errp))

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
	req.set_meta("url", url)
	req.set_meta("method", method)

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
	var url := ""
	if req != null and req.has_meta("url"):
		url = str(req.get_meta("url"))
	if req != null and is_instance_valid(req):
		req.queue_free()

	var text := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		var info := "result=%d code=%d url=%s" % [int(result), int(code), url]
		request_failed.emit("Network error", info if text.strip_edges() == "" else info + " | " + text)
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
	return _iso_from_unix(int(Time.get_unix_time_from_system()))

func _iso_from_unix(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"])
	]

func _on_close_requested() -> void:
	if current_lobby_id != "":
		leave_lobby(current_lobby_id)
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_close_requested()
