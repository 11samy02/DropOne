extends Panel
class_name Lobby_detail

const LOBBY_DETAIL := preload("uid://cw6no3dl40h5p")

## Emitted when the user clicks Join on this lobby list row.
signal join_requested(lobby_id: String)

@onready var lobby_name: Label = %lobby_name
@onready var version: Label = %version
@onready var join: Button = %join
@onready var current_playeres: Label = %current_playeres

## Steam lobby id string shown in the hub list.
var lobby_id: String = ""
## Max players for display as count/max in the row.
var max_players: int = 8

## Factory: creates a lobby row and defers name/version label setup.
static func create(lobby_id_: String, lobby_name_: String, version_: String) -> Lobby_detail:
	var item: Lobby_detail = LOBBY_DETAIL.instantiate()
	item.lobby_id = lobby_id_
	item.call_deferred("_apply_data", lobby_name_, version_)
	return item

## Sets lobby title and version labels after nodes are ready.
func _apply_data(lobby_name_: String, version_: String) -> void:
	lobby_name.text = lobby_name_
	version.text = version_

## Updates the player count label (e.g. "3/8").
func set_player_count(count: int) -> void:
	current_playeres.text = "%d/%d" % [count, max_players]

func _on_join_pressed() -> void:
	join_requested.emit(lobby_id)
