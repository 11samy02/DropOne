extends HBoxContainer
class_name SteamLobbyPlayerRow

@onready var name_label: Label = %name_label
@onready var status_label: Label = %status_label
@onready var host_label: Label = %host_label

const DIFFICULTY_NAMES := ["Rookie", "Casual", "Smart", "Hard", "Master", "Omega"]
const PERSONALITY_NAMES := ["Balanced", "Aggressor", "Collector", "Chaos", "Punisher", "Color Monarch"]


## Populates name, ready state, host/bot badges from a lobby member dict.
func setup(member: Dictionary) -> void:
