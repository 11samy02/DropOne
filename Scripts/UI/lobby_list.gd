extends Control
class_name LobbyList

@onready var back: Button = %Back
@onready var titel: Label = %Titel
@onready var createe: Button = %Createe
@onready var lobby_container: VBoxContainer = %LobbyContainer

@export var limit: int = 50
@export var Lobby_scene: PackedScene

var _items_by_id: Dictionary = {}
var _lobby_meta_cache: Dictionary = {}
var _count_cache: Dictionary = {}

func _ready() -> void:
	SupabaseManager.lobby_list_loaded.connect(_on_lobby_list_loaded)
	SupabaseManager.lobby_created.connect(func(_lobby: Dictionary) -> void: refresh_list())
	SupabaseManager.lobby_deleted.connect(func(_id: String) -> void: refresh_list())

	SupabaseManager.lobby_player_counts_loaded.connect(_on_lobby_player_counts_loaded)

	SupabaseManager.lobby_joined.connect(_on_lobby_joined)
	SupabaseManager.lobby_left.connect(func(_id: String) -> void: refresh_counts())

	SupabaseManager.request_failed.connect(func(error: String, details: String) -> void:
		print(error, " | ", details)
	)

	refresh_list()

func refresh_list() -> void:
	SupabaseManager.load_lobbies(limit)

func refresh_counts() -> void:
	var ids: Array[String] = []
	for id in _items_by_id.keys():
		ids.append(str(id))
	SupabaseManager.load_lobby_player_counts(ids)

func _on_lobby_list_loaded(lobbies: Array) -> void:
	var new_ids: Dictionary = {}
	var ids: Array[String] = []

	for lobby in lobbies:
		if lobby is Dictionary:
			var id := str(lobby.get("id", ""))
			if id == "":
				continue

			new_ids[id] = true
			ids.append(id)

			var name := str(lobby.get("name", ""))
			var ver := str(lobby.get("game_version", ""))
			var meta := {"name": name, "version": ver}

			if not _items_by_id.has(id):
				var item := Lobby_detail.create(id, name, ver)
				item.join_requested.connect(_on_join_requested)
				lobby_container.add_child(item)
				_items_by_id[id] = item
			else:
				var old_meta = _lobby_meta_cache.get(id, null)
				if old_meta == null or old_meta["name"] != name or old_meta["version"] != ver:
					var item2: Lobby_detail = _items_by_id[id]
					item2._apply_data(name, ver)

			_lobby_meta_cache[id] = meta

			if _count_cache.has(id):
				var item3: Lobby_detail = _items_by_id[id]
				if is_instance_valid(item3):
					item3.set_player_count(int(_count_cache[id]))

	var to_remove: Array[String] = []
	for existing_id in _items_by_id.keys():
		if not new_ids.has(existing_id):
			to_remove.append(existing_id)

	for rid in to_remove:
		var item4: Lobby_detail = _items_by_id[rid]
		if is_instance_valid(item4):
			item4.queue_free()
		_items_by_id.erase(rid)
		_lobby_meta_cache.erase(rid)
		_count_cache.erase(rid)

	SupabaseManager.load_lobby_player_counts(ids)

func _on_lobby_player_counts_loaded(counts: Dictionary) -> void:
	for lobby_id in _items_by_id.keys():
		var new_count := int(counts.get(lobby_id, 0))
		var old_count := int(_count_cache.get(lobby_id, -1))

		_count_cache[lobby_id] = new_count

		if new_count != old_count:
			var item: Lobby_detail = _items_by_id[lobby_id]
			if is_instance_valid(item):
				item.set_player_count(new_count)

func _on_join_requested(lobby_id: String) -> void:
	SupabaseManager.switch_lobby(lobby_id)

func _on_lobby_joined(_id: String) -> void:
	if Lobby_scene != null:
		get_tree().change_scene_to_packed(Lobby_scene)

func _on_createe_pressed() -> void:
	SupabaseManager.lobby_created.connect(_on_lobby_created_once, CONNECT_ONE_SHOT)
	SupabaseManager.create_lobby("New Lobby")

func _on_lobby_created_once(_lobby: Dictionary) -> void:
	refresh_list()


func _on_refresh_list_timer_timeout() -> void:
	refresh_list()
