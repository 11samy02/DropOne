extends Control

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"
const LOBBY_HUB := "res://Scenes/UI/steam_lobby_hub.tscn"

@onready var customize_button: Button = %CustomizeButton
@onready var play_button: Button = %PlayButton
@onready var profile_panel: Panel = %ProfilePanel
@onready var profile_name: Label = %ProfileName
@onready var profile_picture: TextureRect = %ProfilePicture
@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	_update_ui()


## Refreshes play button state and profile preview from Globals.client_profile.
func _update_ui() -> void: