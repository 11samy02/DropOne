extends Node

## Local player's profile created on the start/profile screens.
var client_profile: PlayerProfile

## Folder containing `.tres` deck resources.
const DECK_DIR := "res://Resources/Decks/"
const CLASSIC_DECK_PATH := "res://Resources/Decks/Classic.tres"
## Deck path chosen in lobby; empty uses the scene default deck.
var selected_deck_path: String = ""


## Default lobby deck: Classic when available, otherwise the first listed deck.
func get_default_deck_path() -> String:
	if ResourceLoader.exists(CLASSIC_DECK_PATH):
		return CLASSIC_DECK_PATH
	var paths := list_deck_paths()
	if paths.is_empty():
		return ""
	return paths[0]


## True when the local player has set a non-empty profile name.
func has_customized_profile() -> bool:
	return client_profile != null and str(client_profile.player_name).strip_edges() != ""


## List all available deck resource paths in the decks folder. Handles exported
## builds where resources may be remapped (.tres.remap / .res).
func list_deck_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(DECK_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var n := f
			if n.ends_with(".remap"):
				n = n.substr(0, n.length() - ".remap".length())
			if n.ends_with(".import"):
				n = ""
			if n.ends_with(".res"):
				n = n.substr(0, n.length() - 4) + ".tres"
			if n.ends_with(".tres"):
				var p := DECK_DIR + n
				if not paths.has(p):
					paths.append(p)
		f = dir.get_next()
	dir.list_dir_end()

	# Fallback for exported builds where res:// directory listing can come back
	# empty: probe known deck files directly.
	if paths.is_empty():
		for known in ["Breeze", "Classic", "Merciless", "Rapid"]:
			var p: String = DECK_DIR + str(known) + ".tres"
			if ResourceLoader.exists(p) and not paths.has(p):
				paths.append(p)

	paths.sort()
	return paths


## Human-readable name for a deck path (falls back to the file name).
## Human-readable deck title from resource or file basename.
func deck_display_name(path: String) -> String:
	var deck := load_deck(path)
	if deck != null and str(deck.deck_name).strip_edges() != "":
		return str(deck.deck_name)
	return path.get_file().get_basename()


## Loads a DeckResource from a res:// path; returns null if missing.
func load_deck(path: String) -> DeckResource:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as DeckResource


## Deferred scene swap using a preloaded PackedScene.
func change_scene_packed(scene: PackedScene) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneTree nicht verfügbar.")
		return
	tree.call_deferred("change_scene_to_packed", scene)


## Deferred scene swap using a scene file path.
func change_scene_file(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneTree nicht verfügbar.")
		return
	tree.call_deferred("change_scene_to_file", path)
