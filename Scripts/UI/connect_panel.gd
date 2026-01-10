extends Control
class_name ConnectPanel

@onready var status_label: Label = %status_label
@onready var create_game_button: Button = %create_game_button

func _ready() -> void:
	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.connect_auto()

func _on_status_changed(msg: String) -> void:
	status_label.set_text(msg)


func _on_create_game_button_pressed() -> void:
	SupabaseManager.create_lobby("My Lobby")
