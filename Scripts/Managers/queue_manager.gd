extends Node
class_name QueueManager


@export var player_container : Control


var player_count := 1
var bots_count := 3

func _ready() -> void:
	for p in player_count:
		player_container.add_child(HandCardHolder.create())
