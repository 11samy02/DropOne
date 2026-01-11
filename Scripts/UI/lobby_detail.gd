extends Panel
class_name Lobby_detail

const LOBBY_DETAIL := preload("uid://cw6no3dl40h5p")

signal join_requested(lobby_id: String)

@onready var lobby_name: Label = %lobby_name
@onready var version: Label = %version
@onready var join: Button = %join
@onready var current_playeres: Label = %current_playeres

var lobby_id: String = ""
var max_players: int = 8

static func create(lobby_id_: String, lobby_name_: String, version_: String) -> Lobby_detail:
	var item: Lobby_detail = LOBBY_DETAIL.instantiate()
	item.lobby_id = lobby_id_
	item.call_deferred("_apply_data", lobby_name_, version_)
	return item

func _apply_data(lobby_name_: String, version_: String) -> void:
	lobby_name.text = lobby_name_
	version.text = version_

func set_player_count(count: int) -> void:
	current_playeres.text = "%d/%d" % [count, max_players]

func _on_join_pressed() -> void:
	join_requested.emit(lobby_id)
