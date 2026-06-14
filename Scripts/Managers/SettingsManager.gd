extends Node

const SETTINGS_PATH := "user://settings.cfg"

var master_volume_linear := 1.0
var fullscreen := false


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume_linear = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume_linear)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func apply_all() -> void:
	apply_fullscreen()
	apply_volume()


func apply_fullscreen() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)


func apply_volume() -> void:
	SoundManager.set_master_volume_linear(master_volume_linear)


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_fullscreen()
	save_settings()


func set_master_volume_linear(value: float) -> void:
	master_volume_linear = clampf(value, 0.0, 1.0)
	apply_volume()
	save_settings()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
