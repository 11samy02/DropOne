extends TextureButton
class_name PictureSelector

const PICTURE_SELECTOR = preload("uid://dxoj7bubo232y")

@export var picture_list : Array[Texture2D]
@export var picture_id := 0

@onready var picture: TextureRect = %picture


static func create(id: int) ->  PictureSelector:
	var ps : PictureSelector = PICTURE_SELECTOR.instantiate()
	ps.picture_id = id
	return ps


func _ready() -> void:
	picture.texture = picture_list[picture_id]

func _on_pressed() -> void:
	Signals.PROFILE_set_picture.emit(picture_list[picture_id], picture_id)
