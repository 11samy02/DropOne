extends Control

@onready var picture_container: GridContainer = %Picture_container
@onready var player_name: LineEdit = %player_name
@onready var picture: TextureRect = %picture
@onready var save_button: Button = %Save

## Selected avatar index from the picture grid.
var picture_id: int = 0


func _ready() -> void:
	for i in range(PlayerProfile.get_avatar_pool().size()):
		picture_container.add_child(PictureSelector.create(i))

	Signals.PROFILE_set_picture.connect(change_picture)

	if Globals.has_customized_profile():
		player_name.text = Globals.client_profile.player_name
		if Globals.client_profile.picture != null:
			picture.texture = Globals.client_profile.picture
	elif SteamManager.steam_ready:
		player_name.text = SteamManager.get_persona_name()
	else:
		SteamManager.steam_ready_signal.connect(_on_steam_ready)


func _on_steam_ready() -> void:
	if player_name.text.strip_edges() == "":
		player_name.text = SteamManager.get_persona_name()


## Updates preview when user picks an avatar in the grid.
func change_picture(texture: Texture2D, id: int) -> void:
	picture.texture = texture
	picture_id = id


## Writes profile into Globals.client_profile; returns false if name empty.
func _save_profile() -> bool:
	var name := player_name.text.strip_edges()
	if name == "":
		return false

	var player_profile := PlayerProfile.new()
	player_profile.player_name = name
	player_profile.picture = picture.texture
	Globals.client_profile = player_profile
	return true


func _on_save_pressed() -> void:
	if not _save_profile():
		return
	Globals.change_scene_file("res://Scenes/UI/start_screen.tscn")


func _on_back_pressed() -> void:
	Globals.change_scene_file("res://Scenes/UI/start_screen.tscn")
