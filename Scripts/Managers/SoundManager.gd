extends Node

const DRAW_CARD_SOUND := preload("res://Assets/sounds/draw_card.mp3")
const PLAY_CARD_SOUND := preload("res://Assets/sounds/play_card.mp3")
const DRAW_PITCH := 1.25
const DRAW_PITCH_VARIANCE := 0.05
const DRAW_VOLUME_DB := -5.0
const PLAY_PITCH := 1.0
const PLAY_PITCH_VARIANCE := 0.1
const PLAY_VOLUME_DB := 0.0
const POOL_SIZE := 8

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play_draw_card(times: int = 1) -> void:
	var count := maxi(int(times), 1)
	for _i in count:
		_play(DRAW_CARD_SOUND, DRAW_PITCH, DRAW_PITCH_VARIANCE, DRAW_VOLUME_DB)


func play_card_played(times: int = 1) -> void:
	var count := maxi(int(times), 1)
	for _i in count:
		_play(PLAY_CARD_SOUND, PLAY_PITCH, PLAY_PITCH_VARIANCE, PLAY_VOLUME_DB)


func _play(stream: AudioStream, pitch: float, variance: float, volume_db: float) -> void:
	if _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = pitch + randf_range(-variance, variance)
	player.volume_db = volume_db
	player.play()
