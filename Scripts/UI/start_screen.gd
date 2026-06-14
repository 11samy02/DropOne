extends Control

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"
const LOBBY_HUB := "res://Scenes/UI/steam_lobby_hub.tscn"

@onready var customize_button: Button = %CustomizeButton
@onready var play_button: Button = %PlayButton
@onready var exit_button: Button = %ExitButton
@onready var profile_panel: Panel = %ProfilePanel
@onready var profile_name: Label = %ProfileName
@onready var profile_picture: TextureRect = %ProfilePicture
@onready var hint_label: Label = %HintLabel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var fullscreen_check: CheckButton = %FullscreenCheck


func _ready() -> void:
	_sync_settings_ui()
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


func _on_exit_pressed() -> void:
	get_tree().quit()


func _sync_settings_ui() -> void:
	volume_slider.set_block_signals(true)
	volume_slider.value = SettingsManager.master_volume_linear * 100.0
	volume_slider.set_block_signals(false)
	_update_volume_label(volume_slider.value)

	fullscreen_check.set_block_signals(true)
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	fullscreen_check.set_block_signals(false)


func _update_volume_label(percent: float) -> void:
	volume_value_label.text = "%d%%" % int(round(percent))


func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)
	SettingsManager.set_master_volume_linear(value / 100.0)


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	SettingsManager.set_fullscreen(toggled_on)
