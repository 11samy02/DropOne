@tool
extends Resource
class_name PlayerProfile

## Avatar source. Loaded lazily at runtime via res:// paths so the textures are
## resolved from the exported PCK reliably. Static `preload(...)` initializers can
## end up empty in exported builds, which left the picture grid blank.
const AVATAR_DIR := "res://Assets/ProfilePictures/"
const AVATAR_COUNT := 36

## Global avatar pool (built on first access)
static var _avatar_pool: Array[Texture2D] = []

static func get_avatar_pool() -> Array[Texture2D]:
	if _avatar_pool.is_empty():
		_build_avatar_pool()
	return _avatar_pool

static func _build_avatar_pool() -> void:
	_avatar_pool.clear()
	for i in range(1, AVATAR_COUNT + 1):
		var path := AVATAR_DIR + str(i) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			_avatar_pool.append(tex)

@export var player_name: String = "Player"
@export var picture: Texture2D
@export var player_index: int = -1
@export var is_bot: bool = false

## Runtime reference (not exported)
var holder: HandCardHolder = null

## Assign random picture if none set
func ensure_picture() -> void:
	if picture != null:
		return
	var pool := get_avatar_pool()
	if pool.is_empty():
		return
	picture = pool[randi() % pool.size()]
