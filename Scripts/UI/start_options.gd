extends Control

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"

@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var fullscreen_check: CheckButton = %FullscreenCheck


func _ready() -> void:
	_sync_settings_ui()


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


func _on_back_pressed() -> void:
	Globals.change_scene_file(START_SCREEN)
