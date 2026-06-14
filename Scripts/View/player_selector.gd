extends Control
class_name PlayerSelector

const PLAYER_PROFILE_CARD := preload("uid://h382lyh12543")

@export var queue_manager: QueueManager

@onready var profile_container: GridContainer = %profile_container

var _active := false
var _owner: HandCardHolder = null
var _allow_self := false

func _ready() -> void:
	hide()
	Signals.TARGET_request_target_select.connect(_on_request_target_select)
	Signals.TURN_changed.connect(_on_turn_changed)

func _on_request_target_select(owner: HandCardHolder, allow_self: bool) -> void:
	if queue_manager == null:
		return
	if !_can_local_owner_select(owner):
		return

	_owner = owner
	_allow_self = allow_self
	_active = true

	show()
	_refresh()

func _on_turn_changed(_holder: HandCardHolder) -> void:
	if !_active:
		return
	_refresh()

extends Control
class_name PlayerSelector

const PLAYER_PROFILE_CARD := preload("uid://h382lyh12543")

@export var queue_manager: QueueManager

@onready var profile_container: GridContainer = %profile_container

var _active := false
var _owner: HandCardHolder = null
var _allow_self := false

## Rebuilds target cards when target selection is requested or turn changes.
func _refresh() -> void:
	if queue_manager == null:
		return

	for c in profile_container.get_children():
		c.queue_free()

	var targets: Array[HandCardHolder] = []
	for h in queue_manager.turn_order:
		if h != null and is_instance_valid(h):
			targets.append(h)

	for holder in targets:
		if holder == null or !is_instance_valid(holder):
			continue

		var profile := holder.profile
		if profile == null:
			profile = PlayerProfile.new()
			holder.profile = profile

		profile.ensure_picture()

		var card: ProfileCardDisplay = PLAYER_PROFILE_CARD.instantiate()
		profile_container.add_child(card)

		var is_self := (holder == _owner)

		card.setup(profile, holder.get_child_count(), holder, is_self)

		if !is_self:
			card.pressed.connect(func(h):
				_on_target_clicked(h)
			)

## Confirms target selection locally or sends RPC to server.
func _on_target_clicked(holder: HandCardHolder) -> void:
	if !_active:
		return
	if queue_manager == null:
		return
	if holder == null or !is_instance_valid(holder):
		return

	_active = false
	hide()
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		NetworkManager.request_target_select(int(holder.player_index))
		return
	Signals.TARGET_target_selected.emit(holder)

## Only the human who played the targeting card may pick a target.
func _can_local_owner_select(owner: HandCardHolder) -> bool:
	if owner == null or owner.is_bot:
		return false
	if !multiplayer.has_multiplayer_peer():
		return true
	return int(owner.player_index) == int(NetworkManager.my_slot)
