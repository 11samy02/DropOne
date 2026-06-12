extends Control
class_name ConnectPanel

@onready var status_label: Label = %status_label
@onready var create_game_button: Button = %create_game_button

func _ready() -> void:
	status_label.text = "Verwende die Steam-Lobby-Szene für Online-Spiele."
