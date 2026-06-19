extends Control
class_name PlayerSelector

const PLAYER_PROFILE_CARD := preload("uid://h382lyh12543")

@export var queue_manager: QueueManager

@onready var profile_container: GridContainer = %profile_container
@onready var panel: Panel = %Panel

var _active := false
var _owner: HandCardHolder = null
var _allow_self := false
var _title_label: Label = null

func _ready() -> void:
	hide()
	_ensure_title_label()
	Signals.TARGET_request_target_select.connect(_on_request_target_select)
	Signals.TURN_changed.connect(_on_turn_changed)

func _ensure_title_label() -> void:
	if panel == null:
		return
	_title_label = panel.get_node_or_null("TitleLabel") as Label
	if _title_label != null:
		return
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "Choose a player to swap hands with"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title_label.add_theme_constant_override("outline_size", 5)
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top = 18.0
	_title_label.offset_bottom = 58.0
	panel.add_child(_title_label)

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

## Rebuilds target cards when target selection is requested or turn changes.
func _refresh() -> void:
	if queue_manager == null:
		return
	_ensure_title_label()

	for c in profile_container.get_children():
		c.queue_free()

	var targets: Array[HandCardHolder] = []
	if _owner != null:
		targets = queue_manager.get_valid_target_holders(_owner)
	else:
		for h in queue_manager.turn_order:
			if h != null and is_instance_valid(h):
				targets.append(h)

	if _title_label != null:
		if _owner != null and _owner.profile != null:
			_title_label.text = "%s — choose a player to swap hands with" % _owner.profile.player_name
		else:
			_title_label.text = "Choose a player to swap hands with"

	for holder in targets:
		if holder == null or !is_instance_valid(holder):
			continue
		if holder == _owner and !_allow_self:
			continue

		var profile := _resolve_profile(holder)
		var card: ProfileCardDisplay = PLAYER_PROFILE_CARD.instantiate()
		profile_container.add_child(card)

		var is_self := (holder == _owner)
		var count := 0
		for c in holder.get_children():
			if c is CardView and not c.get_meta("anim_temp", false):
				count += 1
		card.setup(profile, count, holder, is_self)

		if !is_self:
			card.pressed.connect(func(h):
				_on_target_clicked(h)
			)

func _resolve_profile(holder: HandCardHolder) -> PlayerProfile:
	var profile := holder.profile
	if profile == null:
		profile = PlayerProfile.new()
		holder.profile = profile
	profile.player_index = holder.player_index
	profile.is_bot = holder.is_bot
	profile.holder = holder
	if holder.is_bot:
		profile.apply_bot_avatar(holder.bot_difficulty)
	profile.ensure_picture()
	return profile

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
