extends Node
class_name KIController

@export var hand_card_holder: HandCardHolder
@export var queue_manager: QueueManager
@export var card_manager: CardManager
@export var think_time := 0.3

enum AIDifficulty { ROOKIE, CASUAL, SMART, HARD, MASTER }
enum AIPersonality { BALANCED, AGGRESSOR, COLLECTOR, CHAOS, PUNISHER, COLOR_MONARCH }

## AI Difficulty
## 
## ROOKIE:
## - Plays the first valid card it finds
## - Uses specials randomly and wastes strong cards
## - Almost no strategy
##
## CASUAL:
## - Plays valid cards with basic logic
## - Sometimes uses specials to block
## - Small mistakes and no long-term planning
##
## SMART:
## - Uses specials at good moments
## - Tries to keep strong cards for later
## - Stacks + cards efficiently when possible
##
## HARD:
## - Plans ahead and avoids wasting wilds
## - Targets players with low cards more often
## - Actively tries to control the current color flow
##
## MASTER:
## - Highest strategic level
## - Optimizes hand management + color control
## - Always punishes low-card opponents
## - Uses special cards with near-optimal timing
@export var difficulty: AIDifficulty = AIDifficulty.MASTER

## AI Personality
##
## BALANCED:
## - General-purpose behavior
## - Mix of offense and defense
##
## AGGRESSOR:
## - Prioritizes attack cards early (skip/reverse/draw)
## - Tries to slow opponents down quickly
## - Less concerned about saving cards
##
## COLLECTOR:
## - Holds wild/draw cards as long as possible
## - Plays safer and keeps options open
## - Often aims to build powerful turns later
##
## CHAOS:
## - Still legal moves, but unpredictable decisions
## - Uses wilds and specials in unexpected moments
## - Feels random but still follows rules
##
## PUNISHER:
## - Focuses on punishing the strongest threat
## - Saves attacks for opponents with few cards
## - Plays counter-strategically
##
## COLOR_MONARCH:
## - Strong focus on controlling colors
## - Tries to force the color it has the most
## - Uses wilds mainly to lock advantage
@export var personality: AIPersonality = AIPersonality.COLOR_MONARCH


var _diff_cfg := {}
var _pers_cfg := {}

func _ready() -> void:
	_build_configs()
	Signals.TURN_changed.connect(_on_turn_changed)
	Signals.COLOR_request_color_select.connect(_on_color_request)

## Build difficulty and personality weight tables
func _build_configs() -> void:
	_diff_cfg = {
		AIDifficulty.ROOKIE: {
			"punish_low": 0,
			"save_wild": -35,
			"save_wild_draw": -30,
			"prefer_normal": 35,
			"prefer_action": 0,
			"prefer_draw": 5,
			"prefer_skip_reverse": 3,
			"stack_skill": 5,
			"color_lock": 5,
			"hand_dump": 35,
			"avoid_help_opponents": 0,
		},
		AIDifficulty.CASUAL: {
			"punish_low": 10,
			"save_wild": -15,
			"save_wild_draw": -10,
			"prefer_normal": 25,
			"prefer_action": 6,
			"prefer_draw": 10,
			"prefer_skip_reverse": 10,
			"stack_skill": 15,
			"color_lock": 15,
			"hand_dump": 30,
			"avoid_help_opponents": 5
		},
		AIDifficulty.SMART: {
			"punish_low": 25,
			"save_wild": 0,
			"save_wild_draw": 5,
			"prefer_normal": 15,
			"prefer_action": 12,
			"prefer_draw": 18,
			"prefer_skip_reverse": 16,
			"stack_skill": 30,
			"color_lock": 25,
			"hand_dump": 25,
			"avoid_help_opponents": 10
		},
		AIDifficulty.HARD: {
			"punish_low": 40,
			"save_wild": 15,
			"save_wild_draw": 25,
			"prefer_normal": 10,
			"prefer_action": 20,
			"prefer_draw": 30,
			"prefer_skip_reverse": 28,
			"stack_skill": 45,
			"color_lock": 40,
			"hand_dump": 18,
			"avoid_help_opponents": 20
		},
		AIDifficulty.MASTER: {
			"punish_low": 60,
			"save_wild": 35,
			"save_wild_draw": 55,
			"prefer_normal": 5,
			"prefer_action": 28,
			"prefer_draw": 40,
			"prefer_skip_reverse": 42,
			"stack_skill": 70,
			"color_lock": 70,
			"hand_dump": 12,
			"avoid_help_opponents": 35
		}
	}

	_pers_cfg = {
		AIPersonality.BALANCED: {
			"aggression": 0,
			"conserve": 0,
			"chaos": 0,
			"punish": 0,
			"color_focus": 0,
			"hand_dump": 0
		},
		AIPersonality.AGGRESSOR: {
			"aggression": 35,
			"conserve": -10,
			"chaos": 0,
			"punish": 10,
			"color_focus": 0,
			"hand_dump": -10
		},
		AIPersonality.COLLECTOR: {
			"aggression": -15,
			"conserve": 35,
			"chaos": 0,
			"punish": 0,
			"color_focus": 10,
			"hand_dump": -35
		},
		AIPersonality.CHAOS: {
			"aggression": 10,
			"conserve": -5,
			"chaos": 45,
			"punish": 0,
			"color_focus": -10,
			"hand_dump": 20
		},
		AIPersonality.PUNISHER: {
			"aggression": 15,
			"conserve": 10,
			"chaos": 0,
			"punish": 55,
			"color_focus": 0,
			"hand_dump": 5
		},
		AIPersonality.COLOR_MONARCH: {
			"aggression": 0,
			"conserve": 15,
			"chaos": 0,
			"punish": 0,
			"color_focus": 65,
			"hand_dump": -15
		}
	}

## Trigger KI turn when this holder becomes active
func _on_turn_changed(holder: HandCardHolder) -> void:
	if holder == null:
		return
	if hand_card_holder == null:
		return
	if holder != hand_card_holder:
		return
	if !hand_card_holder.is_bot:
		return
	play_turn()

## Handle KI playing a full turn (play / draw / pass) including place-all follow-up logic
func play_turn() -> void:
	if card_manager == null or queue_manager == null or hand_card_holder == null:
		return
	if card_manager.waiting_for_color:
		return
	if !_still_my_turn():
		return
	
	await get_tree().create_timer(think_time).timeout
	if !_still_my_turn():
		return
	
	if queue_manager.draw_stack_amount > 0 and !queue_manager.draw_stack_is_wild:
		var playable_stack := get_playable_cards()
		if playable_stack.size() > 0:
			var best_stack := choose_best_card(playable_stack)
			if best_stack != null:
				hand_card_holder.set_card(best_stack)
				return
		
		queue_manager.force_draw_stack_continue(hand_card_holder)
		await get_tree().create_timer(0.25).timeout
		if !_still_my_turn():
			return
		
		playable_stack = get_playable_cards()
		if playable_stack.size() > 0:
			var best_after := choose_best_card(playable_stack)
			if best_after != null:
				hand_card_holder.set_card(best_after)
				return
		
		if _still_my_turn():
			queue_manager.end_turn()
		return
	
	var playable := get_playable_cards()
	if playable.size() > 0:
		var best := choose_best_card(playable)
		if best != null:
			var played_res := best.card_res
			hand_card_holder.set_card(best)

			await get_tree().create_timer(0.05).timeout
			if !_still_my_turn():
				return

			if played_res != null and played_res.type == CardResource.CardType.PLACE_ALL:
				await get_tree().create_timer(0.35).timeout
				if !_still_my_turn():
					return
				
				var finisher := choose_best_place_all_finisher(played_res.color)
				if finisher != null:
					hand_card_holder.set_card(finisher)

					await get_tree().create_timer(0.05).timeout
					if !_still_my_turn():
						return

			return
	
	var drew := queue_manager.bot_draw_current()
	if drew:
		await get_tree().create_timer(0.25).timeout
		if !_still_my_turn():
			return
		
		playable = get_playable_cards()
		if playable.size() > 0:
			var best2 := choose_best_card(playable)
			if best2 != null:
				var played_res2 := best2.card_res
				hand_card_holder.set_card(best2)

				await get_tree().create_timer(0.05).timeout
				if !_still_my_turn():
					return

				if played_res2 != null and played_res2.type == CardResource.CardType.PLACE_ALL:
					await get_tree().create_timer(0.35).timeout
					if !_still_my_turn():
						return
					
					var finisher2 := choose_best_place_all_finisher(played_res2.color)
					if finisher2 != null:
						hand_card_holder.set_card(finisher2)

						await get_tree().create_timer(0.05).timeout
						if !_still_my_turn():
							return

				return
	
	if _still_my_turn():
		queue_manager.end_turn()

func _still_my_turn() -> bool:
	return queue_manager != null and queue_manager.get_current_holder() == hand_card_holder

## Collect all playable card views from this bot hand
func get_playable_cards() -> Array[CardView]:
	var arr: Array[CardView] = []
	for c in hand_card_holder.get_children():
		if c is CardView:
			if hand_card_holder.can_play_card(c.card_res):
				arr.append(c)
	return arr

## Choose the highest scoring card based on difficulty and personality
func choose_best_card(playable: Array[CardView]) -> CardView:
	if playable.is_empty():
		return null
	
	var best := playable[0]
	var best_score := -999999
	
	for c in playable:
		var s := score_card(c)
		if s > best_score:
			best_score = s
			best = c
	
	return best

## Score a card using weighted heuristics
func score_card(card_view: CardView) -> int:
	if card_view == null or card_view.card_res == null:
		return -999999
	
	var card := card_view.card_res
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	var score := 0
	var my_count := hand_card_holder.get_child_count()
	var opponent_low := is_any_opponent_low_cards(2)
	var threat := get_most_threatening_opponent_cards()
	
	var my_colors := count_colors_in_hand()
	var my_best_color := get_best_color_from_counts(my_colors)
	var is_my_best_color := card.color == my_best_color and card.color != CardResource.CardColor.BLACK
	
	score += int(cfg["hand_dump"]) * int(pcfg["hand_dump"]) / 10
	score += int(cfg["punish_low"]) * (1 if opponent_low else 0)
	score += int(pcfg["punish"]) * (1 if opponent_low else 0) / 2
	
	match card.type:
		CardResource.CardType.NUMBER:
			score += int(cfg["prefer_normal"])
			score += (9 - card.value)
			if is_my_best_color:
				score += int(cfg["color_lock"]) * 1 + int(pcfg["color_focus"]) / 2
			else:
				score += int(pcfg["color_focus"]) / 4
		
		CardResource.CardType.SKIP:
			score += int(cfg["prefer_skip_reverse"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) / 2
			if opponent_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
			if threat <= 2:
				score += int(cfg["punish_low"]) / 2
		
		CardResource.CardType.REVERSE:
			score += int(cfg["prefer_skip_reverse"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["chaos"]) / 2
			if opponent_low:
				score += int(cfg["punish_low"]) / 2
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				score += int(cfg["prefer_skip_reverse"]) + int(cfg["punish_low"]) / 2
		
		CardResource.CardType.DRAW:
			score += int(cfg["prefer_draw"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["aggression"])
			if opponent_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
			if queue_manager != null and queue_manager.draw_stack_amount > 0:
				score += int(cfg["stack_skill"]) + int(card.value) * 8
			else:
				score += int(card.value) * 6
		
		CardResource.CardType.WILD:
			score += int(cfg["prefer_action"])
			score += int(cfg["save_wild"])
			score += int(pcfg["conserve"]) / 2
			if opponent_low:
				score += int(cfg["punish_low"]) / 2
			if my_colors.size() > 0:
				score += int(cfg["color_lock"]) / 2 + int(pcfg["color_focus"]) / 2
		
		CardResource.CardType.WILD_DRAW:
			score += int(cfg["prefer_draw"])
			score += int(cfg["prefer_action"])
			score += int(cfg["save_wild_draw"])
			score += int(pcfg["aggression"])
			if opponent_low:
				score += int(cfg["punish_low"]) * 2 + int(pcfg["punish"])
			score += 30
		
		CardResource.CardType.PLACE_ALL:
			score += int(cfg["prefer_action"])
			score += int(cfg["hand_dump"]) * 2
			score += int(pcfg["hand_dump"]) * 2
			score += int(cfg["color_lock"]) / 2 + int(pcfg["color_focus"]) / 2
			
			var same_color_count = count_specific_color_in_hand(card.color)
			score += same_color_count * 12
			
			if opponent_low:
				score += int(cfg["punish_low"]) / 2 + int(pcfg["punish"]) / 3
			
			if same_color_count <= 1:
				score -= 40
	
	
	score += int(my_count) * int(cfg["hand_dump"]) / 6
	
	return score

## Chooses the best finisher card for place-all mode based on difficulty and personality
func choose_best_place_all_finisher(color: CardResource.CardColor) -> CardView:
	var candidates: Array[CardView] = []
	for c in hand_card_holder.get_children():
		if c is CardView and c.card_res != null:
			if c.card_res.color == color and c.card_res.type != CardResource.CardType.PLACE_ALL:
				candidates.append(c)
	
	if candidates.is_empty():
		return null
	
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	if personality == AIPersonality.CHAOS:
		return candidates[randi() % candidates.size()]
	
	var opponent_low := is_any_opponent_low_cards(2)
	var best := candidates[0]
	var best_score := -999999
	
	for cv in candidates:
		var s = score_place_all_finisher(cv, cfg, pcfg, opponent_low)
		if s > best_score:
			best_score = s
			best = cv
	
	return best


## Scores a place-all finisher card with special emphasis on only-last-effect rules
func score_place_all_finisher(card_view: CardView, cfg: Dictionary, pcfg: Dictionary, opponent_low: bool) -> int:
	if card_view == null or card_view.card_res == null:
		return -999999
	
	var card := card_view.card_res
	var score := 0
	
	match card.type:
		CardResource.CardType.DRAW:
			score += int(cfg["prefer_draw"]) + int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) + int(pcfg["punish"]) / 2
			score += int(card.value) * 10
			if opponent_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"])
		
		CardResource.CardType.SKIP:
			score += int(cfg["prefer_skip_reverse"]) + int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) / 2
			if opponent_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
		
		CardResource.CardType.REVERSE:
			score += int(cfg["prefer_skip_reverse"]) + int(cfg["prefer_action"])
			score += int(pcfg["chaos"]) / 2
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				score += int(cfg["prefer_skip_reverse"]) + int(cfg["punish_low"]) / 2
		
		CardResource.CardType.NUMBER:
			score += int(cfg["prefer_normal"])
			score += (9 - card.value)
			score += int(pcfg["conserve"]) / 2
	
	return score

## Counts how many cards of a specific color exist in the bot hand
func count_specific_color_in_hand(color: CardResource.CardColor) -> int:
	var count := 0
	for c in hand_card_holder.get_children():
		if c is CardView and c.card_res != null:
			if c.card_res.color == color:
				count += 1
	return count


## Find the smallest hand size among opponents
func get_most_threatening_opponent_cards() -> int:
	if queue_manager == null:
		return 9999
	var best := 9999
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		best = min(best, h.get_child_count())
	return best

## Count non-black colors in this hand
func count_colors_in_hand() -> Dictionary:
	var counts := {}
	for c in hand_card_holder.get_children():
		if c is CardView:
			var col = c.card_res.color
			if col == CardResource.CardColor.BLACK:
				continue
			counts[col] = counts.get(col, 0) + 1
	return counts

## Return the strongest color from a count dictionary
func get_best_color_from_counts(counts: Dictionary) -> CardResource.CardColor:
	var best_color := CardResource.CardColor.RED
	var best_count := -1
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var v := int(counts.get(color, 0))
		if v > best_count:
			best_count = v
			best_color = color
	return best_color

## Check if any opponent is near winning
func is_any_opponent_low_cards(max_cards: int = 2) -> bool:
	if queue_manager == null:
		return false
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		if h.get_child_count() <= max_cards:
			return true
	return false

## Respond to color request only if this bot owns the wild selection
func _on_color_request() -> void:
	if queue_manager == null or hand_card_holder == null or card_manager == null:
		return
	if queue_manager.wild_color_owner != hand_card_holder:
		return
	await get_tree().create_timer(0.2).timeout
	Signals.COLOR_color_selected.emit(choose_best_wild_color())

## Choose wild color using difficulty+personality weighting and opponent weakness
func choose_best_wild_color() -> CardResource.CardColor:
	var my_counts := count_colors_in_hand()
	var my_total := 0
	for k in my_counts.keys():
		my_total += int(my_counts[k])
	
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	if my_total <= 0:
		return choose_opponents_least_common_color()
	
	var best_color := CardResource.CardColor.RED
	var best_score := -999999
	
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var score := 0
		var mine := int(my_counts.get(color, 0))
		var opp := get_opponent_color_count(color)
		
		score += mine * (10 + int(cfg["color_lock"]) / 4 + int(pcfg["color_focus"]) / 3)
		score += (50 - opp) * (int(cfg["punish_low"]) / 10 + int(pcfg["punish"]) / 20)
		
		if score > best_score:
			best_score = score
			best_color = color
	
	return best_color

## Count how often opponents have a specific color in their hand
func get_opponent_color_count(color: CardResource.CardColor) -> int:
	if queue_manager == null:
		return 0
	var count := 0
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		for c in h.get_children():
			if c is CardView and c.card_res != null:
				if c.card_res.color == color:
					count += 1
	return count

## Fallback: choose the color opponents have least
func choose_opponents_least_common_color() -> CardResource.CardColor:
	if queue_manager == null:
		return CardResource.CardColor.RED
	
	var counts := {
		CardResource.CardColor.RED: 0,
		CardResource.CardColor.GREEN: 0,
		CardResource.CardColor.BLUE: 0,
		CardResource.CardColor.YELLOW: 0
	}
	
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		for c in h.get_children():
			if c is CardView and c.card_res != null:
				var col = c.card_res.color
				if col != CardResource.CardColor.BLACK:
					counts[col] += 1
	
	var best_color := CardResource.CardColor.RED
	var best_count := 999999
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var v := int(counts[color])
		if v < best_count:
			best_count = v
			best_color = color
	
	return best_color
