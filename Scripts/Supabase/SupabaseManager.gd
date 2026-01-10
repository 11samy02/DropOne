extends Node

## Supabase project base URL, e.g. https://xxxx.supabase.co
@export var supabase_url: String = ""

## Supabase anon public key
@export var supabase_anon_key: String = ""

## PostgREST base path
@export var rest_path: String = "/rest/v1"

## Default game version used to filter compatible lobbies
@export var game_version: String = "0.1.0"

## Local identity for no-auth mode
var player_id: String = ""
var display_name: String = "Player"

signal lobby_created(lobby: Dictionary)
signal lobby_list_loaded(lobbies: Array)
signal lobby_deleted(lobby_id: String)
signal lobby_joined(lobby_id: String)
signal lobby_left(lobby_id: String)
signal lobby_players_loaded(lobby_id: String, players: Array)
signal request_failed(error: String, details: String)

func _ready() -> void:
	player_id = _get_or_create_local_player_id()

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

func join_lobby(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var payload := {
		"lobby_id": id,
		"player_id": player_id,
		"display_name": display_name
	}

	_request_json(
		HTTPClient.METHOD_POST,
		"/lobby_players",
		payload,
		{"Prefer": "return=minimal"},
		func(_result: Variant) -> void:
			lobby_joined.emit(id)
	)

func leave_lobby(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?lobby_id=eq.%s&player_id=eq.%s" % [_url_encode(id), _url_encode(player_id)]

	_request_json(
		HTTPClient.METHOD_DELETE,
		"/lobby_players" + q,
		null,
		{},
		func(_result: Variant) -> void:
			lobby_left.emit(id)
	)

func load_lobby_players(lobby_id: String) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?select=player_id,display_name,is_ready,joined_at"
	q += "&lobby_id=eq.%s" % _url_encode(id)
	q += "&order=joined_at.asc"

	_request_json(
		HTTPClient.METHOD_GET,
		"/lobby_players" + q,
		null,
		{},
		func(result: Variant) -> void:
			if result is Array:
				lobby_players_loaded.emit(id, result)
			else:
				request_failed.emit("Load lobby players failed", str(result))
	)

func set_ready(lobby_id: String, ready: bool) -> void:
	var id := lobby_id.strip_edges()
	if id == "":
		request_failed.emit("Invalid lobby id", "Lobby id is empty.")
		return

	var q := "?lobby_id=eq.%s&player_id=eq.%s" % [_url_encode(id), _url_encode(player_id)]

	var payload := {
		"is_ready": ready
	}

	_request_json(
		HTTPClient.METHOD_PATCH,
		"/lobby_players" + q,
		payload,
		{"Prefer": "return=minimal"},
		func(_result: Variant) -> void:
			load_lobby_players(id)
	)

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

	req.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
		_on_request_completed(req, result, response_code, response_headers, body, on_success)
	)

	var body_str := ""
	if payload != null:
		body_str = JSON.stringify(payload)

	var err := req.request(url, headers, method, body_str)
	if err != OK:
		req.queue_free()
		request_failed.emit("HTTPRequest error", str(err))

func _on_request_completed(req: HTTPRequest, result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, on_success: Callable) -> void:
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
