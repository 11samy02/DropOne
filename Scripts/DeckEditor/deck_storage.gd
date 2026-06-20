class_name DeckStorage
extends RefCounted

const USER_DECK_DIR := "user://Decks/"
const BUILTIN_DECK_DIR := "res://Resources/Decks/"


static func can_save_builtin_deck() -> bool:
	return OS.is_debug_build() or Engine.is_editor_hint()


static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DECK_DIR)


static func is_builtin_deck(path: String) -> bool:
	return path.begins_with("res://")


static func is_user_deck(path: String) -> bool:
	return path.begins_with("user://")


static func list_user_deck_paths() -> Array[String]:
	var paths: Array[String] = []
	ensure_user_dir()
	var dir := DirAccess.open(USER_DECK_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(USER_DECK_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


static func save_user_deck(deck: DeckResource, base_name: String) -> String:
	if deck == null:
		return ""
	ensure_user_dir()
	var safe_name := base_name.strip_edges().replace(" ", "_")
	if safe_name == "":
		safe_name = "UnnamedDeck"
	var path := USER_DECK_DIR + safe_name + ".tres"
	var err := ResourceSaver.save(deck, path)
	if err != OK:
		push_error("DeckStorage: save failed (%s)" % err)
		return ""
	return path


static func save_builtin_deck(deck: DeckResource, base_name: String) -> String:
	if deck == null or not can_save_builtin_deck():
		return ""
	var safe_name := base_name.strip_edges().replace(" ", "_")
	if safe_name == "":
		safe_name = "UnnamedDeck"
	var path := BUILTIN_DECK_DIR + safe_name + ".tres"
	var err := ResourceSaver.save(deck, path)
	if err != OK:
		push_error("DeckStorage: builtin save failed (%s)" % err)
		return ""
	return path


static func delete_user_deck(path: String) -> bool:
	if not is_user_deck(path):
		return false
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	return err == OK
