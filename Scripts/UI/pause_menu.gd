extends Control

const START_SCREEN := "res://Scenes/UI/start_screen.tscn"

enum PendingAction { NONE, MAIN_MENU, QUIT_GAME }

@export var queue_manager: QueueManager

@onready var main_panel: PanelContainer = %MainPanel
@onready var confirm_panel: PanelContainer = %ConfirmPanel
@onready var confirm_label: Label = %ConfirmLabel
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var resume_button: Button = %ResumeButton

var _is_open := false
var _pending_action := PendingAction.NONE


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	confirm_panel.visible = false
	_sync_settings_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _blocks_pause_menu():
		return
	if confirm_panel.visible:
		_hide_confirm()
		get_viewport().set_input_as_handled()
		return
	toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _blocks_pause_menu() or _is_open:
		return
	_is_open = true
	_hide_confirm()
	_sync_settings_ui()
	visible = true
	if not _is_results_screen_visible():
		get_tree().paused = true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_hide_confirm()
	visible = false
	if not _is_results_screen_visible():
		get_tree().paused = false


func _blocks_pause_menu() -> bool:
	if queue_manager == null:
		queue_manager = _find_queue_manager()
	if queue_manager == null:
		return false
	if queue_manager.has_method("is_results_screen_visible"):
		return bool(queue_manager.call("is_results_screen_visible"))
	return false


func _is_results_screen_visible() -> bool:
	return _blocks_pause_menu()


func _find_queue_manager() -> QueueManager:
	var root := get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("QueueManager") as QueueManager


func _sync_settings_ui() -> void:
	fullscreen_check.set_block_signals(true)
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	fullscreen_check.set_block_signals(false)

	volume_slider.set_block_signals(true)
	volume_slider.value = SettingsManager.master_volume_linear * 100.0
	volume_slider.set_block_signals(false)
	_update_volume_label(volume_slider.value)


func _update_volume_label(percent: float) -> void:
	volume_value_label.text = "%d%%" % int(round(percent))


func _show_confirm(action: PendingAction) -> void:
	_pending_action = action
	match action:
		PendingAction.MAIN_MENU:
			confirm_label.text = "Return to the main menu?\nYour current match will be left."
		PendingAction.QUIT_GAME:
			confirm_label.text = "Quit DropOne?\nUnsaved progress in this match will be lost."
	main_panel.visible = false
	confirm_panel.visible = true


func _hide_confirm() -> void:
	_pending_action = PendingAction.NONE
	confirm_panel.visible = false
	main_panel.visible = true


func _leave_session() -> void:
	get_tree().paused = false
	SteamManager.leave_lobby()


func _on_resume_pressed() -> void:
	close()


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	SettingsManager.set_fullscreen(toggled_on)
	fullscreen_check.set_block_signals(true)
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	fullscreen_check.set_block_signals(false)


func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)
	SettingsManager.set_master_volume_linear(value / 100.0)


func _on_main_menu_pressed() -> void:
	_show_confirm(PendingAction.MAIN_MENU)


func _on_quit_game_pressed() -> void:
	_show_confirm(PendingAction.QUIT_GAME)


func _on_confirm_yes_pressed() -> void:
	var action := _pending_action
	_hide_confirm()
	_is_open = false
	visible = false
	_leave_session()
	match action:
		PendingAction.MAIN_MENU:
			Globals.change_scene_file(START_SCREEN)
		PendingAction.QUIT_GAME:
			get_tree().quit()


func _on_confirm_no_pressed() -> void:
	_hide_confirm()
