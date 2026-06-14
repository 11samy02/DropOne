extends Control

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"
const LOBBY_HUB := "res://Scenes/UI/steam_lobby_hub.tscn"
const OPTIONS_SCREEN := "res://Scenes/UI/start_options.tscn"

@onready var customize_button: Button = %CustomizeButton
@onready var play_button: Button = %PlayButton
@onready var options_button: Button = %OptionsButton
@onready var exit_button: Button = %ExitButton
@onready var profile_panel: Panel = %ProfilePanel
@onready var profile_name: Label = %ProfileName
@onready var profile_picture: TextureRect = %ProfilePicture
@onready var hint_label: Label = %HintLabel


func _ready() -> void:
	_update_ui()


## Refreshes play button state and profile preview from Globals.client_profile.
func _update_ui() -> void:
	var ready := Globals.has_customized_profile()
	play_button.disabled = not ready

	if ready:
		hint_label.text = ""
		profile_panel.visible = true
		profile_name.text = Globals.client_profile.player_name
		if Globals.client_profile.picture != null:
			profile_picture.texture = Globals.client_profile.picture
		else:
			var pool := PlayerProfile.get_avatar_pool()
			if not pool.is_empty():
				profile_picture.texture = pool[0]
	else:
		hint_label.text = "Set up your profile before creating a lobby."
		profile_panel.visible = false


func _on_customize_pressed() -> void:
	Globals.change_scene_file("res://Scenes/UI/create_profile.tscn")


func _on_play_pressed() -> void:
	if not Globals.has_customized_profile():
		hint_label.text = "Please customize your profile first."
		return
	Globals.change_scene_file(LOBBY_HUB)


func _on_options_pressed() -> void:
	Globals.change_scene_file(OPTIONS_SCREEN)


func _on_exit_pressed() -> void:
	get_tree().quit()
