extends HBoxContainer
class_name SteamLobbyPlayerRow

@onready var name_label: Label = %name_label
@onready var status_label: Label = %status_label
@onready var host_label: Label = %host_label

const DIFFICULTY_NAMES := ["Rookie", "Casual", "Smart", "Hard", "Master", "Omega"]
const PERSONALITY_NAMES := ["Balanced", "Aggressor", "Collector", "Chaos", "Punisher", "Color Monarch"]


## Populates name, ready state, host/bot badges from a lobby member dict.
func setup(member: Dictionary) -> void:
	if not is_node_ready():
		await ready

	var player_name := str(member.get("name", "Player"))
	var is_ready := bool(member.get("is_ready", false))
	var is_host := bool(member.get("is_host", false))
	var is_bot := bool(member.get("is_bot", false))

	var diff := int(member.get("difficulty", 0)) if is_bot else -1
	var is_omega := is_bot and diff == KIController.AIDifficulty.OMEGA

	if name_label:
		name_label.text = "Omega" if is_omega else player_name

	if status_label:
		if is_bot:
			var diff_name = DIFFICULTY_NAMES[diff] if diff >= 0 and diff < DIFFICULTY_NAMES.size() else "?"
			if is_omega:
				status_label.text = ""
			else:
				var pers := int(member.get("personality", 0))
				var pers_name = PERSONALITY_NAMES[pers] if pers >= 0 and pers < PERSONALITY_NAMES.size() else "?"
				status_label.text = "%s / %s" % [diff_name, pers_name]
			status_label.modulate = Color(0.6, 0.8, 1.0)
		else:
			status_label.text = "Ready" if is_ready else "Not Ready"
			status_label.modulate = Color(0.4, 1.0, 0.5) if is_ready else Color(0.7, 0.7, 0.7)

	if host_label:
		if is_bot and not is_omega:
			host_label.visible = true
			host_label.text = "Bot"
		elif is_host:
			host_label.visible = true
			host_label.text = "Host"
		else:
			host_label.visible = false
			host_label.text = ""
