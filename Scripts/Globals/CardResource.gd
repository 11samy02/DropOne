@tool
extends Resource
class_name CardResource

enum CardColor { RED, GREEN, BLUE, YELLOW, BLACK }
enum CardSymbol { HEART, CLUB, SPADE, DIAMOND }
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

@export var color: CardColor = CardColor.RED
@export var type: CardType = CardType.NUMBER
@export var value: int = 0
@export var uid: int = 0

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

## Localized color name for UI descriptions
func get_color_name() -> String:
	match color:
		CardColor.RED: return "Rot"
		CardColor.GREEN: return "Grün"
		CardColor.BLUE: return "Blau"
		CardColor.YELLOW: return "Gelb"
		CardColor.BLACK: return "Schwarz (Wild)"
	return "Unbekannt"

## Localized symbol name for colorblind accessibility text
func get_symbol_name() -> String:
	match color:
		CardColor.RED: return "Herz"
		CardColor.GREEN: return "Kreuz"
		CardColor.BLUE: return "Pik"
		CardColor.YELLOW: return "Karo"
		CardColor.BLACK: return ""
	return ""

## Full hover description: color, number/value, and card effect
func get_description() -> String:
	var color_line := get_color_name()
	var symbol := get_symbol_name()
	if symbol != "":
		color_line += " (" + symbol + ")"

	match type:
		CardType.NUMBER:
			return "%s – Zahl %d. Spielbar auf gleiche Farbe oder gleiche Zahl." % [color_line, value]
		CardType.DRAW:
			return "%s +%d – Der nächste Spieler muss %d Karte(n) ziehen. Stapelt mit anderen +Karten." % [color_line, value, value]
		CardType.TARGET_DRAW:
			return "%s +%d – Wähle einen Gegner, der %d Karte(n) ziehen muss." % [color_line, value, value]
		CardType.MULTI_TARGET_DRAW:
			return "%s +%d – Alle anderen Spieler ziehen jeweils %d Karte(n)." % [color_line, value, value]
		CardType.SKIP:
			return "%s – Überspringt den nächsten Spieler." % color_line
		CardType.REVERSE:
			return "%s – Kehrt die Spielrichtung um." % color_line
		CardType.PLACE_ALL:
			return "%s – Lege alle Karten dieser Farbe aus deiner Hand, dann wähle eine Farbe." % color_line
		CardType.WILD:
			return "Wild – Wähle eine Farbe. Spielbar jederzeit."
		CardType.WILD_DRAW:
			return "Wild +%d – Wähle eine Farbe. Nächster Spieler zieht %d Karte(n)." % [value, value]
		CardType.WILD_DRAW_REVERSE:
			return "Wild +%d & Richtungswechsel – Wähle eine Farbe. Nächster Spieler zieht %d Karte(n), Richtung kehrt um." % [value, value]
		CardType.SWAP_HANDS:
			return "Wild – Tausche deine Hand mit einem gewählten Gegner, dann wähle eine Farbe."
		CardType.WILD_COLOR_ROULET:
			return "Wild – Farbroulette: Der nächste Spieler muss die gewählte Farbe legen oder ziehen."
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
