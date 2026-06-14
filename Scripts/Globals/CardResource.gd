@tool
extends Resource
class_name CardResource

## Playable card colors including BLACK for wild cards.
enum CardColor { RED, GREEN, BLUE, YELLOW, BLACK }
## Colorblind symbol shapes mapped to each color.
enum CardSymbol { HEART, CLUB, SPADE, DIAMOND }
## All card effect types supported by the rules engine.
enum CardType {
	NUMBER, 
	SKIP, 
	REVERSE, 
	DRAW, 
	WILD, 
	WILD_DRAW, 
	PLACE_ALL, 
	WILD_DRAW_REVERSE, 
	SWAP_HANDS, 
	TARGET_DRAW, 
	WILD_COLOR_ROULET, 
	MULTI_TARGET_DRAW 
}

## Background texture for black/wild cards.
const BLACK: Texture2D = preload("uid://xspumfxdwrqn")
const BLUE: Texture2D = preload("uid://cxov74crw1ujc")
const GREEN: Texture2D = preload("uid://yywrx2q6xxab")
const RED: Texture2D = preload("uid://khc0k7ws2b0g")
const YELLOW: Texture2D = preload("uid://bu7wu3q2mvxsn")
const BACKGROUND: Texture2D = preload("uid://db8vqriaoo1oj")

const REVERSE_ICON: Texture2D = preload("uid://d0rbdll1ydx8e")
const SKIP_ICON: Texture2D = preload("uid://dmfqk7awjm070")
const WILD_ICON: Texture2D = preload("uid://bxv1k8rgyqe5j")
const WILDDRAW_ICON: Texture2D = preload("uid://tbva5m4rm4g4")
const PLACE_ALL_ICON: Texture2D = preload("uid://5lfp3wlw4ueu")
const WILD_REVERSE_ICON: Texture2D = preload("uid://cvvu8xdx8585x")
const SWAP_HANDS_ICON: Texture2D = preload("uid://6807rhm30km5")
const TARGET_ICON: Texture2D = preload("uid://dg7ale62lsylk")
const COLOR_ROULETTE_ICON: Texture2D = preload("uid://boyrnbacyt0pk")
const MULTI_TARGET: Texture2D = preload("uid://b7ru1auff4bah")

const CLUB: Texture2D = preload("uid://41e111jurgy5")
const HEART: Texture2D = preload("uid://8p7uyuv60l14")
const DIAMOND: Texture2D = preload("uid://d0buk1j22pbu1")
const SPADE: Texture2D = preload("uid://b7a4n3o1ildc7")

## Card face color on the resource.
@export var color: CardColor = CardColor.RED
## Effect type determining rules and visuals.
@export var type: CardType = CardType.NUMBER
## Number or +draw value; 0 for non-valued action cards.
@export var value: int = 0
## Unique runtime id used for multiplayer sync and hand reconciliation.
@export var uid: int = 0

## Wild-style cards always use BLACK on the resource; chosen color lives in game state.
static func is_neutral_wild_type(t: CardType) -> bool:
	return t in [
		CardType.WILD,
		CardType.WILD_DRAW,
		CardType.WILD_DRAW_REVERSE,
		CardType.SWAP_HANDS,
		CardType.WILD_COLOR_ROULET,
	]

## Resets wild card face color after discard recycle or bad deck data.
func ensure_neutral_wild_color() -> void:
	if is_neutral_wild_type(type):
		color = CardColor.BLACK

## Builds a runtime card from multiplayer sync data with wild color normalized.
static func from_sync_dict(data: Dictionary) -> CardResource:
	var r := CardResource.new()
	r.color = int(data.get("c", 0)) as CardColor
	r.type = int(data.get("t", 0)) as CardType
	r.value = int(data.get("v", 0))
	r.uid = int(data.get("id", 0))
	r.ensure_neutral_wild_color()
	return r

## Get background texture (or back side if hidden)
func get_background_texture(hidden_card: bool = false) -> Texture2D:
	if hidden_card:
		return BACKGROUND
	match color:
		CardColor.RED: return RED
		CardColor.GREEN: return GREEN
		CardColor.BLUE: return BLUE
		CardColor.YELLOW: return YELLOW
		CardColor.BLACK: return BLACK
	return RED

## Color name for UI descriptions
func get_color_name() -> String:
	match color:
		CardColor.RED: return "Red"
		CardColor.GREEN: return "Green"
		CardColor.BLUE: return "Blue"
		CardColor.YELLOW: return "Yellow"
		CardColor.BLACK: return "Black (Wild)"
	return "Unknown"

## Symbol name for colorblind accessibility text
func get_symbol_name() -> String:
	match color:
		CardColor.RED: return "Hearts"
		CardColor.GREEN: return "Clubs"
		CardColor.BLUE: return "Spades"
		CardColor.YELLOW: return "Diamonds"
		CardColor.BLACK: return ""
	return ""

## Full hover description: color, number/value, and card effect.
## participant_count: pass turn_order.size() so 1v1 rule text is accurate.
func get_description(participant_count: int = 0) -> String:
	var is_1v1 := participant_count == 2
	var color_line := get_color_name()
	var symbol := get_symbol_name()
	if symbol != "":
		color_line += " (" + symbol + ")"

	match type:
		CardType.NUMBER:
			return "%s – Number %d. Play on matching color or matching number." % [color_line, value]
		CardType.DRAW:
			return "%s +%d – Next player must draw %d card(s). Can stack on matching +draw cards." % [color_line, value, value]
		CardType.TARGET_DRAW:
			if is_1v1:
				return "%s +%d – Your opponent draws %d card(s)." % [color_line, value, value]
			return "%s +%d – Choose an opponent to draw %d card(s)." % [color_line, value, value]
		CardType.MULTI_TARGET_DRAW:
			if is_1v1:
				return "%s +%d – Your opponent draws %d card(s)." % [color_line, value, value]
			return "%s +%d – All other players each draw %d card(s)." % [color_line, value, value]
		CardType.SKIP:
			if is_1v1:
				return "%s – Skips your opponent's turn." % color_line
			return "%s – Skips the next player." % color_line
		CardType.REVERSE:
			if is_1v1:
				return "%s – Skips your opponent (Reverse acts as Skip in 1v1)." % color_line
			return "%s – Reverses play direction." % color_line
		CardType.PLACE_ALL:
			return "%s – Play all cards of this color from your hand." % color_line
		CardType.WILD:
			return "Wild – Choose a color. Playable at any time."
		CardType.WILD_DRAW:
			return "Wild +%d – Choose a color. Next player must draw %d card(s) or stack another wild +draw." % [value, value]
		CardType.WILD_DRAW_REVERSE:
			if is_1v1:
				return "Wild +%d – Choose a color. Next player must draw %d card(s) or stack another wild +draw." % [value, value]
			return "Wild +%d & Reverse – Choose a color. Next player must draw %d card(s) or stack; direction reverses." % [value, value]
		CardType.SWAP_HANDS:
			if is_1v1:
				return "Wild – Swap hands with your opponent, then choose a color."
			return "Wild – Swap your hand with a chosen opponent, then choose a color."
		CardType.WILD_COLOR_ROULET:
			return "Wild – Color roulette: the next player picks a color, draws until they draw that color, then may still play."
	return color_line

## Get display text for number and draw-like cards
func get_display_text() -> String:
	match type:
		CardType.NUMBER:
			return str(value)
		CardType.DRAW:
			return "+" + str(value)
		CardType.WILD_DRAW:
			return "+" + str(value)
		CardType.WILD_DRAW_REVERSE:
			return "+" + str(value)
		CardType.TARGET_DRAW:
			return "+" + str(value)
		CardType.MULTI_TARGET_DRAW:
			return "+" + str(value)
	return ""

## Get symbol texture for action cards
func get_symbol_texture() -> Texture2D:
	match type:
		CardType.SKIP:
			return SKIP_ICON
		CardType.REVERSE:
			return REVERSE_ICON
		CardType.WILD:
			return WILD_ICON
		CardType.WILD_DRAW:
			return WILDDRAW_ICON
		CardType.PLACE_ALL:
			return PLACE_ALL_ICON
		CardType.WILD_DRAW_REVERSE:
			return WILD_REVERSE_ICON
		CardType.SWAP_HANDS:
			return SWAP_HANDS_ICON
		CardType.TARGET_DRAW:
			return TARGET_ICON
		CardType.WILD_COLOR_ROULET:
			return COLOR_ROULETTE_ICON
		CardType.MULTI_TARGET_DRAW:
			return MULTI_TARGET
	return null

## Get colorblind symbol for a given color
func get_color_blind_symbol_texture_for_color(c: CardColor) -> Texture2D:
	match c:
		CardColor.RED: return HEART
		CardColor.GREEN: return CLUB
		CardColor.BLUE: return SPADE
		CardColor.YELLOW: return DIAMOND
		CardColor.BLACK: return null
	return HEART

## Get background texture for a specific color
func get_background_texture_for_color(c: CardColor) -> Texture2D:
	match c:
		CardColor.RED: return RED
		CardColor.GREEN: return GREEN
		CardColor.BLUE: return BLUE
		CardColor.YELLOW: return YELLOW
		CardColor.BLACK: return BLACK
	return RED
