@tool
extends Resource
class_name PlayerProfile

## Global avatar pool (loaded once)
static var avatar_pool: Array[Texture2D] = [
	preload("uid://bsury0f65afv"),
	preload("uid://bt18evinn5aq8"),
	preload("uid://4fm5gi0gbhd6"),
	preload("uid://8c236sumsbxc"),
	preload("uid://b6xawt615iww0"),
	preload("uid://862os6wejet0"),
	preload("uid://b6mufjby2k2c6"),
	preload("uid://bmf2x4xruqveh"),
	preload("uid://b8l8s70j5tq5c"),
	preload("uid://srloclsw868q"),
	preload("uid://cipdt3gaq8vqc"),
	preload("uid://cna7axqr6ncgv"),
	preload("uid://clm80epdxb6bw"),
	preload("uid://kidbi2uoo4b3"),
	preload("uid://c5wo3w438h1xx"),
	preload("uid://cv62esdo6rp3o"),
	preload("uid://c2iom2lhtov6"),
	preload("uid://cqcjy2cgfo5s8"),
	preload("uid://dxchkrbj8wlso"),
	preload("uid://dy1qio7s8kyqk"),
	preload("uid://bkqf7fwn8wmfu"),
	preload("uid://bg8nnfle87btw"),
	preload("uid://cmpis20w2y7xb"),
	preload("uid://hyx58bmhig5p"),
	preload("uid://cq2arbjsdgtw8"),
	preload("uid://b7agr18yakxp4"),
	preload("uid://cslq8sikoojbi"),
	preload("uid://boa0ms5dfacvf"),
	preload("uid://csb0dmv6nmrxd"),
	preload("uid://b044jlgv4xyc8"),
	preload("uid://ulpt1stwbh3h"),
	preload("uid://ct3qfthnrw6y"),
	preload("uid://rim45p6urbc4"),
	preload("uid://nc51mng31p6t"),
	preload("uid://bff6a2q1ynpas"),
]

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
	if avatar_pool.is_empty():
		return
	picture = avatar_pool[randi() % avatar_pool.size()]
