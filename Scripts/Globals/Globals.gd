extends Node


var client_profile: PlayerProfile


func has_customized_profile() -> bool:
	return client_profile != null and str(client_profile.player_name).strip_edges() != ""


func change_scene_packed(scene: PackedScene) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneTree nicht verfügbar.")
		return
	tree.call_deferred("change_scene_to_packed", scene)


func change_scene_file(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("SceneTree nicht verfügbar.")
		return
	tree.call_deferred("change_scene_to_file", path)
