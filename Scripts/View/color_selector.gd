extends HBoxContainer
class_name ColorSelector

@export var queue_manager: QueueManager

func _ready() -> void:
	hide()
	Signals.COLOR_request_color_select.connect(func():
		if _can_human_pick():
			show()
		else:
			hide()
	)
	Signals.COLOR_color_selected.connect(func(_color):
		hide()
	)

## Checks if the human is allowed to pick a wild color now
func _can_human_pick() -> bool:
	if queue_manager == null:
		return false
	if !queue_manager.is_human_turn():
		return false
	if queue_manager.wild_color_owner == null:
		return false
	if queue_manager.wild_color_owner.is_bot:
		return false
	if queue_manager.wild_color_owner != queue_manager.get_current_holder():
		return false
	return true

func _on_red_pressed() -> void:
	if !_can_human_pick():
		return
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_wild_color(int(CardResource.CardColor.RED))
		Signals.COLOR_color_selected.emit(CardResource.CardColor.RED)
		return
	Signals.COLOR_color_selected.emit(CardResource.CardColor.RED)

func _on_yellow_pressed() -> void:
	if !_can_human_pick():
		return
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_wild_color(int(CardResource.CardColor.YELLOW))
		Signals.COLOR_color_selected.emit(CardResource.CardColor.YELLOW)
		return
	Signals.COLOR_color_selected.emit(CardResource.CardColor.YELLOW)

func _on_green_pressed() -> void:
	if !_can_human_pick():
		return
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_wild_color(int(CardResource.CardColor.GREEN))
		Signals.COLOR_color_selected.emit(CardResource.CardColor.GREEN)
		return
	Signals.COLOR_color_selected.emit(CardResource.CardColor.GREEN)

func _on_blue_pressed() -> void:
	if !_can_human_pick():
		return
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_wild_color(int(CardResource.CardColor.BLUE))
		Signals.COLOR_color_selected.emit(CardResource.CardColor.BLUE)
		return
	Signals.COLOR_color_selected.emit(CardResource.CardColor.BLUE)
