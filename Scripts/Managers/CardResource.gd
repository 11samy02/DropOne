@tool
extends Resource
class_name CardResource

enum CardColor { RED, GREEN, BLUE, YELLOW, BLACK }
enum CardType { NUMBER, SKIP, REVERSE, DRAW, WILD, WILD_DRAW }

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


@export var color: CardColor = CardColor.RED
@export var type: CardType = CardType.NUMBER
@export var value: int = 0

func get_background_texture(hidden_card : bool = false) -> Texture2D:
	if hidden_card:
		return BACKGROUND
	match color:
		CardColor.RED: return RED
		CardColor.GREEN: return GREEN
		CardColor.BLUE: return BLUE
		CardColor.YELLOW: return YELLOW
		CardColor.BLACK: return BLACK
	return RED

func get_display_text() -> String:
	match type:
		CardType.NUMBER:
			return str(value)
		CardType.DRAW:
			return "+" + str(value)
		CardType.WILD_DRAW:
			return "+" + str(value)
	return ""

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
	return null

func get_background_texture_for_color(c: CardColor) -> Texture2D:
	match c:
		CardColor.RED: return RED
		CardColor.GREEN: return GREEN
		CardColor.BLUE: return BLUE
		CardColor.YELLOW: return YELLOW
		CardColor.BLACK: return BLACK
	return RED
