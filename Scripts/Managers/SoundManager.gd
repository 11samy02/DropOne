extends Node

const DRAW_CARD_SOUND := preload("res://Assets/sounds/draw_card.mp3")
const PLAY_CARD_SOUND := preload("res://Assets/sounds/play_card.mp3")
const PITCH_VARIANCE := 0.1
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
		_play(DRAW_CARD_SOUND)


func play_card_played(times: int = 1) -> void:
	var count := maxi(int(times), 1)
	for _i in count:
		_play(PLAY_CARD_SOUND)


func _play(stream: AudioStream) -> void:
	if _players.is_empty():
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = randf_range(1.0 - PITCH_VARIANCE, 1.0 + PITCH_VARIANCE)
	player.play()
