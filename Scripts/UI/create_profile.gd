extends Control

@onready var picture_container: GridContainer = %Picture_container
@onready var player_name: LineEdit = %player_name

@onready var picture: TextureRect = %picture

var picture_id : int = 0

@export var Lobby_list_scene : PackedScene

func _ready() -> void:
	for i in range(0,PlayerProfile.avatar_pool.size()):
		picture_container.add_child(PictureSelector.create(i))
	
	Signals.PROFILE_set_picture.connect(change_picture)
	
	SupabaseManager.request_failed.connect(func(error: String, details: String) -> void:
		print(error, " | ", details)
	)

func change_picture(texture: Texture2D, id: int) -> void:
	picture.texture = texture
	picture_id = id

func _on_create_pressed() -> void:
	var name := player_name.text.strip_edges()
	if name == "":
		return

	SupabaseManager.create_profile(name, picture_id, func(profile: Dictionary) -> void:
		SupabaseManager.player_id = str(profile.get("id", SupabaseManager.player_id))
		SupabaseManager.set_display_name(name)
	)
	
	var player_profile := PlayerProfile.new()
	player_profile.player_name = name
	player_profile.picture = picture.texture
	
	Globals.client_profile = player_profile
	
	get_tree().change_scene_to_packed(Lobby_list_scene)
