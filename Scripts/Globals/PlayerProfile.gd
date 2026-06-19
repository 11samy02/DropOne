@tool
extends Resource
class_name PlayerProfile

## Avatar source. Loaded lazily at runtime via res:// paths so the textures are
## resolved from the exported PCK reliably. Static `preload(...)` initializers can
## end up empty in exported builds, which left the picture grid blank.
const AVATAR_DIR := "res://Assets/ProfilePictures/"
const AVATAR_COUNT := 36
const OMEGA_AVATAR_PATH := "res://Assets/ProfilePictures/Omega.png"
const PICTURE_ID_NONE := -1

## Global avatar pool (built on first access)
static var _avatar_pool: Array[Texture2D] = []
static var _omega_avatar: Texture2D = null

## Returns lazily built list of all available avatar textures.
static func get_avatar_pool() -> Array[Texture2D]:
	if _avatar_pool.is_empty():
		_build_avatar_pool()
	return _avatar_pool

## Loads avatar PNGs from AVATAR_DIR into the static pool.
static func _build_avatar_pool() -> void:
	_avatar_pool.clear()
	for i in range(1, AVATAR_COUNT + 1):
		var path := AVATAR_DIR + str(i) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			_avatar_pool.append(tex)

static func get_omega_avatar() -> Texture2D:
	if _omega_avatar != null:
		return _omega_avatar
	if ResourceLoader.exists(OMEGA_AVATAR_PATH):
		_omega_avatar = load(OMEGA_AVATAR_PATH) as Texture2D
	return _omega_avatar

static func get_avatar_by_id(id: int) -> Texture2D:
	if id < 0:
		return null
	var pool := get_avatar_pool()
	if id < pool.size():
		return pool[id]
	return null

## Display name shown at seats and in the lobby.
@export var player_name: String = "Player"
## Avatar texture for UI profile cards.
@export var picture: Texture2D
## Index into the avatar pool (-1 = unset).
@export var picture_id: int = PICTURE_ID_NONE
## Seat/slot index assigned by QueueManager or NetworkManager.
@export var player_index: int = -1
## True for AI-controlled seats.
@export var is_bot: bool = false

## Runtime reference (not exported)
var holder: HandCardHolder = null

func apply_picture_from_id(id: int) -> void:
	picture_id = id
	if id < 0:
		return
	var tex := get_avatar_by_id(id)
	if tex != null:
		picture = tex

func apply_bot_avatar(difficulty: int) -> void:
	if difficulty == KIController.AIDifficulty.OMEGA:
		var omega := get_omega_avatar()
		if omega != null:
			picture = omega

## Assign avatar from id, bot rules, or a random fallback.
func ensure_picture() -> void:
	if picture != null:
		return
	if picture_id >= 0:
		apply_picture_from_id(picture_id)
		if picture != null:
			return
	var pool := get_avatar_pool()
	if pool.is_empty():
		return
	picture = pool[randi() % pool.size()]
