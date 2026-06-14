@tool
extends Node
class_name DeckIO

## JSON deck definition edited in the inspector for editor-time export.
@export_multiline var deck_json: String = ""
## Output file name (without path); spaces become underscores on save.
@export var file_name: String = ""
## Append a timestamp suffix to file_name when saving from the editor.
@export var auto_suffix_timestamp := false

## Inspector toggle that triggers _save() once when set true in the editor.
@export var run_save := false : set = _set_run_save


## Editor setter: runs save once and resets the toggle.
func _set_run_save(value: bool) -> void:
	run_save = false
	if !Engine.is_editor_hint():
		return
	if value:
		_save()


## Writes deck_json to res://Resources/Decks/ using file_name settings.
func _save() -> void:
	if deck_json.strip_edges() == "":
		push_error("DeckIO: deck_json is empty")
		return
	
	var safe_name := file_name.strip_edges()
	if safe_name == "":
		safe_name = "UnnamedDeck"
	
	if auto_suffix_timestamp:
		var t := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		safe_name += "_" + t
	
	var ok := save_deck_from_json(deck_json, safe_name)
	if ok:
		print("DeckIO: Saved deck to res://Resources/Decks/" + safe_name + ".tres")


## Parses JSON and saves a DeckResource .tres; returns false on failure.
static func save_deck_from_json(json_string: String, file_name: String = "") -> bool:
	var data = JSON.parse_string(json_string)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("DeckIO: Invalid JSON")
		return false
	
	var deck := deck_from_dict(data)
	if deck == null:
		push_error("DeckIO: deck_from_dict failed")
		return false
	
	var safe_name := file_name.strip_edges()
	if safe_name == "":
		safe_name = deck.deck_name.strip_edges()
	if safe_name == "":
		safe_name = "UnnamedDeck"
	
	safe_name = safe_name.replace(" ", "_")
	
	var dir := "res://Resources/Decks/"
	DirAccess.make_dir_recursive_absolute(dir)
	
	var path := dir + safe_name + ".tres"
	var err := ResourceSaver.save(deck, path)
	if err != OK:
		push_error("DeckIO: Save failed: " + str(err))
		return false
	
	return true


## Builds a DeckResource from a parsed JSON dictionary.
static func deck_from_dict(data: Dictionary) -> DeckResource:
	if !data.has("deck_name") or !data.has("entries"):
		push_error("DeckIO: Missing deck_name or entries")
		return null
	
	var deck := DeckResource.new()
	deck.deck_name = str(data.get("deck_name", "UnnamedDeck"))
	
	if data.has("number_rules") and typeof(data["number_rules"]) == TYPE_DICTIONARY:
		deck.number_rules = number_rules_from_dict(data["number_rules"])
	else:
		deck.number_rules = DeckNumberRuleResource.new()
	
	var entries_arr = data["entries"]
	if typeof(entries_arr) != TYPE_ARRAY:
		push_error("DeckIO: entries must be array")
		return null
	
	for e in entries_arr:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		
		var entry := DeckEntryResource.new()
		
		entry.color = _parse_color(e.get("color", "RED"))
		entry.type = _parse_type(e.get("type", "NUMBER"))
		entry.value = int(e.get("value", 0))
		entry.count = int(e.get("count", 1))
		
		entry.duplicate_for_all_colors = bool(e.get("duplicate_for_all_colors", false))
		
		if e.has("colors") and typeof(e["colors"]) == TYPE_ARRAY:
			var cols: Array[CardResource.CardColor] = []
			for c in e["colors"]:
				cols.append(_parse_color(str(c)))
			entry.colors = cols
		
		deck.entries.append(entry)
	
	return deck


## Builds DeckNumberRuleResource from a JSON number_rules object.
static func number_rules_from_dict(data: Dictionary) -> DeckNumberRuleResource:
	var rules := DeckNumberRuleResource.new()
	rules.min_number = int(data.get("min_number", rules.min_number))
	rules.max_number = int(data.get("max_number", rules.max_number))
	rules.default_copies = int(data.get("default_copies", rules.default_copies))
	
	if data.has("overrides") and typeof(data["overrides"]) == TYPE_DICTIONARY:
		rules.overrides = data["overrides"]
	
	return rules


## Maps a color string from JSON to CardResource.CardColor.
static func _parse_color(s: String) -> CardResource.CardColor:
	match s.to_upper():
		"RED": return CardResource.CardColor.RED
		"GREEN": return CardResource.CardColor.GREEN
		"BLUE": return CardResource.CardColor.BLUE
		"YELLOW": return CardResource.CardColor.YELLOW
		"BLACK": return CardResource.CardColor.BLACK
	return CardResource.CardColor.RED


## Maps a type string from JSON to CardResource.CardType.
static func _parse_type(s: String) -> CardResource.CardType:
	match s.to_upper():
		"NUMBER": return CardResource.CardType.NUMBER
		"SKIP": return CardResource.CardType.SKIP
		"REVERSE": return CardResource.CardType.REVERSE
		"DRAW": return CardResource.CardType.DRAW
		"WILD": return CardResource.CardType.WILD
		"WILD_DRAW": return CardResource.CardType.WILD_DRAW
		"PLACE_ALL": return CardResource.CardType.PLACE_ALL
		"WILD_DRAW_REVERSE": return CardResource.CardType.WILD_DRAW_REVERSE
		"SWAP_HANDS": return CardResource.CardType.SWAP_HANDS
		"TARGET_DRAW": return CardResource.CardType.TARGET_DRAW
		"MULTI_TARGET_DRAW": return CardResource.CardType.MULTI_TARGET_DRAW
		"WILD_COLOR_ROULET": return CardResource.CardType.WILD_COLOR_ROULET
	return CardResource.CardType.NUMBER
