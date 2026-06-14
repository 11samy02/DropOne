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
	Signals.COLOR_color_select_dismissed.connect(func():
		hide()
	)

## Checks if the human is allowed to pick a wild color now
func _can_human_pick() -> bool:
	if queue_manager == null:
		return false
	if queue_manager.roulette_active and queue_manager.roulette_waiting_for_color:
		return queue_manager.is_local_roulette_color_picker()
	if !queue_manager.is_human_turn():
		return false
	var owner: HandCardHolder = queue_manager.wild_color_owner
	if owner == null:
		return false
	if owner.is_bot:
		return false
	if owner != queue_manager.get_current_holder():
		return false
	# In multiplayer ONLY the peer who actually played the wild may pick its
	# color. Without this the host could choose colors for clients' cards.
	if multiplayer.has_multiplayer_peer():
		if int(owner.player_index) != int(NetworkManager.my_slot):
			return false
	return true

## Sends color to server or applies locally, then hides the picker.
func _pick_color(color: CardResource.CardColor) -> void:
	if !_can_human_pick():
		return
	hide()
	if multiplayer.has_multiplayer_peer():
		if !multiplayer.is_server():
			NetworkManager.request_wild_color(int(color))
			return
		if queue_manager != null and queue_manager.has_method("server_apply_local_wild_color"):
			queue_manager.server_apply_local_wild_color(int(color))
			return
	Signals.COLOR_color_selected.emit(color)


func _on_red_pressed() -> void:
	_pick_color(CardResource.CardColor.RED)

func _on_yellow_pressed() -> void:
	_pick_color(CardResource.CardColor.YELLOW)

func _on_green_pressed() -> void:
	_pick_color(CardResource.CardColor.GREEN)

func _on_blue_pressed() -> void:
	_pick_color(CardResource.CardColor.BLUE)
