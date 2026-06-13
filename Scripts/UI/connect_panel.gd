extends Control
class_name ConnectPanel

@onready var status_label: Label = %status_label
@onready var create_game_button: Button = %create_game_button

func _ready() -> void:
	status_label.text = "Use the Steam lobby scene for online games."
