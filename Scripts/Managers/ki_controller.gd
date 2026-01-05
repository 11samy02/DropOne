extends Node
class_name KIController

@export var hand_card_holder: HandCardHolder
@export var queue_manager: QueueManager
@export var card_manager: CardManager
@export var think_time := 0.3

enum AIDifficulty { ROOKIE, CASUAL, SMART, HARD, MASTER, OMEGA }
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
##
## OMEGA:
## - Near-perfect play
## - Uses full information + mini simulation
## - Hard focuses next player threats
## - Prioritizes guaranteed win paths and denies opponent wins
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
			"neighbor_focus": 5,
			"endgame_focus": 5,
			"omega_depth": 0
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
			"avoid_help_opponents": 5,
			"neighbor_focus": 15,
			"endgame_focus": 15,
			"omega_depth": 0
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
			"avoid_help_opponents": 10,
			"neighbor_focus": 35,
			"endgame_focus": 35,
			"omega_depth": 0
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
			"avoid_help_opponents": 20,
			"neighbor_focus": 55,
			"endgame_focus": 55,
			"omega_depth": 0
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
			"avoid_help_opponents": 35,
			"neighbor_focus": 85,
			"endgame_focus": 85,
			"omega_depth": 0
		},
		AIDifficulty.OMEGA: {
			"punish_low": 95,
			"save_wild": 60,
			"save_wild_draw": 85,
			"prefer_normal": 0,
			"prefer_action": 60,
			"prefer_draw": 85,
			"prefer_skip_reverse": 95,
			"stack_skill": 100,
			"color_lock": 100,
			"hand_dump": 100,
			"avoid_help_opponents": 100,
			"neighbor_focus": 120,
			"endgame_focus": 140,
			"omega_depth": 2
		}
	}

	_pers_cfg = {
		AIPersonality.BALANCED: {
			"aggression": 0,
			"conserve": 0,
			"chaos": 0,
			"punish": 0,
			"color_focus": 0,
			"hand_dump": 0,
			"neighbor_focus": 0,
			"endgame_focus": 0
		},
		AIPersonality.AGGRESSOR: {
			"aggression": 35,
			"conserve": -10,
			"chaos": 0,
			"punish": 10,
			"color_focus": 0,
			"hand_dump": -10,
			"neighbor_focus": 10,
			"endgame_focus": 20
		},
		AIPersonality.COLLECTOR: {
			"aggression": -15,
			"conserve": 35,
			"chaos": 0,
			"punish": 0,
			"color_focus": 10,
			"hand_dump": -35,
			"neighbor_focus": 0,
			"endgame_focus": 10
		},
		AIPersonality.CHAOS: {
			"aggression": 10,
			"conserve": -5,
			"chaos": 45,
			"punish": 0,
			"color_focus": -10,
			"hand_dump": 20,
			"neighbor_focus": -10,
			"endgame_focus": 0
		},
		AIPersonality.PUNISHER: {
			"aggression": 15,
			"conserve": 10,
			"chaos": 0,
			"punish": 55,
			"color_focus": 0,
			"hand_dump": 5,
			"neighbor_focus": 25,
			"endgame_focus": 25
		},
		AIPersonality.COLOR_MONARCH: {
			"aggression": 0,
			"conserve": 15,
			"chaos": 0,
			"punish": 0,
			"color_focus": 65,
			"hand_dump": -15,
			"neighbor_focus": 10,
			"endgame_focus": 10
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
	
	if difficulty == AIDifficulty.OMEGA:
		return _omega_choose_best_card(playable)
	
	var best := playable[0]
	var best_score := -999999
	
	for c in playable:
		var s := score_card(c)
		if s > best_score:
			best_score = s
			best = c
	
	return best

## Score a card using weighted heuristics + neighbor awareness + endgame awareness
func score_card(card_view: CardView) -> int:
	if card_view == null or card_view.card_res == null:
		return -999999
	
	var card := card_view.card_res
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	var score := 0
	
	var my_count := hand_card_holder.get_child_count()
	var next_holder := get_next_holder()
	var prev_holder := get_prev_holder()
	
	var next_cards := (next_holder.get_child_count() if next_holder != null else 9999)
	var prev_cards := (prev_holder.get_child_count() if prev_holder != null else 9999)
	
	var global_threat_cards := get_most_threatening_opponent_cards()
	var global_low := global_threat_cards <= 2
	
	var next_is_threat := next_cards <= 2
	var prev_is_threat := prev_cards <= 2
	
	var my_colors := count_colors_in_hand()
	var my_best_color := get_best_color_from_counts(my_colors)
	var is_my_best_color := card.color == my_best_color and card.color != CardResource.CardColor.BLACK
	
	var endgame := my_count <= 4
	var endgame_bonus := int(cfg["endgame_focus"]) + int(pcfg["endgame_focus"])
	
	var neighbor_focus := int(cfg["neighbor_focus"]) + int(pcfg["neighbor_focus"])
	
	score += int(cfg["hand_dump"]) * int(pcfg["hand_dump"]) / 10
	score += int(cfg["punish_low"]) * (1 if global_low else 0)
	score += int(pcfg["punish"]) * (1 if global_low else 0) / 2
	
	if endgame:
		score += endgame_bonus * 2
		score += (5 - my_count) * 25
	
	match card.type:
		CardResource.CardType.NUMBER:
			score += int(cfg["prefer_normal"])
			score += (9 - card.value)
			if is_my_best_color:
				score += int(cfg["color_lock"]) + int(pcfg["color_focus"]) / 2
			else:
				score += int(pcfg["color_focus"]) / 4
			
			if endgame and is_my_best_color:
				score += endgame_bonus
		
		CardResource.CardType.SKIP:
			score += int(cfg["prefer_skip_reverse"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) / 2
			
			if next_is_threat:
				score += (neighbor_focus * 2) + int(cfg["punish_low"]) + int(pcfg["punish"])
			elif global_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
			
			if endgame:
				score += endgame_bonus
		
		CardResource.CardType.REVERSE:
			score += int(cfg["prefer_skip_reverse"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["chaos"]) / 2
			
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				score += int(cfg["prefer_skip_reverse"]) + neighbor_focus
			
			if global_low:
				if next_is_threat:
					score -= neighbor_focus
				if prev_is_threat:
					score += neighbor_focus
			
			if endgame:
				score += endgame_bonus
		
		CardResource.CardType.DRAW:
			score += int(cfg["prefer_draw"])
			score += int(cfg["prefer_action"])
			score += int(pcfg["aggression"])
			
			var draw_power := int(card.value) * 7
			
			if queue_manager != null and queue_manager.draw_stack_amount > 0:
				score += int(cfg["stack_skill"]) + int(card.value) * 10
			else:
				score += draw_power
			
			if next_is_threat:
				score += (neighbor_focus * 2) + int(cfg["punish_low"]) + int(pcfg["punish"])
			elif global_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
			
			if endgame:
				score += endgame_bonus
		
		CardResource.CardType.WILD:
			score += int(cfg["prefer_action"])
			score += int(cfg["save_wild"])
			score += int(pcfg["conserve"]) / 2
			
			if global_low:
				score += int(cfg["punish_low"]) / 2
			
			if my_colors.size() > 0:
				score += int(cfg["color_lock"]) / 2 + int(pcfg["color_focus"]) / 2
			
			if endgame:
				score += endgame_bonus
				if my_colors.size() > 0:
					score += 25
		
		CardResource.CardType.WILD_DRAW:
			score += int(cfg["prefer_draw"])
			score += int(cfg["prefer_action"])
			score += int(cfg["save_wild_draw"])
			score += int(pcfg["aggression"])
			score += 40
			
			if next_is_threat:
				score += (neighbor_focus * 2) + int(cfg["punish_low"]) * 2 + int(pcfg["punish"])
			elif global_low:
				score += int(cfg["punish_low"]) + int(pcfg["punish"]) / 2
			
			if endgame:
				score += endgame_bonus
		
		CardResource.CardType.PLACE_ALL:
			score += int(cfg["prefer_action"])
			score += int(cfg["hand_dump"]) * 2
			score += int(pcfg["hand_dump"]) * 2
			score += int(cfg["color_lock"]) / 2 + int(pcfg["color_focus"]) / 2
			
			var same_color_count = count_specific_color_in_hand(card.color)
			score += same_color_count * 14
			
			if next_is_threat:
				score += neighbor_focus
			elif global_low:
				score += int(cfg["punish_low"]) / 3
			
			if same_color_count <= 1:
				score -= 55
			
			if endgame:
				score += endgame_bonus + same_color_count * 10
	
	score += int(my_count) * int(cfg["hand_dump"]) / 6
	
	if personality == AIPersonality.CHAOS:
		score += randi_range(-25, 25)
	
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
	
	if difficulty == AIDifficulty.OMEGA:
		return _omega_choose_best_place_all_finisher(candidates)
	
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	if personality == AIPersonality.CHAOS:
		return candidates[randi() % candidates.size()]
	
	var next_holder := get_next_holder()
	var next_cards := (next_holder.get_child_count() if next_holder != null else 9999)
	var next_is_threat := next_cards <= 2
	
	var endgame := hand_card_holder.get_child_count() <= 4
	var endgame_bonus := int(cfg["endgame_focus"]) + int(pcfg["endgame_focus"])
	var neighbor_focus := int(cfg["neighbor_focus"]) + int(pcfg["neighbor_focus"])
	
	var best := candidates[0]
	var best_score := -999999
	
	for cv in candidates:
		var s = score_place_all_finisher(cv, cfg, pcfg)
		if next_is_threat and cv.card_res != null:
			if cv.card_res.type == CardResource.CardType.DRAW or cv.card_res.type == CardResource.CardType.SKIP:
				s += neighbor_focus * 2
		if endgame and cv.card_res != null:
			s += endgame_bonus
			if cv.card_res.type == CardResource.CardType.DRAW or cv.card_res.type == CardResource.CardType.SKIP:
				s += endgame_bonus
		if s > best_score:
			best_score = s
			best = cv
	
	return best

## Scores a place-all finisher card with special emphasis on only-last-effect rules
func score_place_all_finisher(card_view: CardView, cfg: Dictionary, pcfg: Dictionary) -> int:
	if card_view == null or card_view.card_res == null:
		return -999999
	
	var card := card_view.card_res
	var score := 0
	
	match card.type:
		CardResource.CardType.DRAW:
			score += int(cfg["prefer_draw"]) + int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) + int(pcfg["punish"]) / 2
			score += int(card.value) * 12
		
		CardResource.CardType.SKIP:
			score += int(cfg["prefer_skip_reverse"]) + int(cfg["prefer_action"])
			score += int(pcfg["aggression"]) / 2
		
		CardResource.CardType.REVERSE:
			score += int(cfg["prefer_skip_reverse"]) + int(cfg["prefer_action"])
			score += int(pcfg["chaos"]) / 2
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				score += int(cfg["prefer_skip_reverse"])
		
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

## Returns the next holder in current direction
func get_next_holder() -> HandCardHolder:
	if queue_manager == null:
		return null
	if queue_manager.turn_order.size() <= 1:
		return null
	var idx := queue_manager.turn_order.find(hand_card_holder)
	if idx < 0:
		return null
	var n := (idx + queue_manager.direction) % queue_manager.turn_order.size()
	if n < 0:
		n += queue_manager.turn_order.size()
	return queue_manager.turn_order[n]

## Returns the previous holder in current direction
func get_prev_holder() -> HandCardHolder:
	if queue_manager == null:
		return null
	if queue_manager.turn_order.size() <= 1:
		return null
	var idx := queue_manager.turn_order.find(hand_card_holder)
	if idx < 0:
		return null
	var p := (idx - queue_manager.direction) % queue_manager.turn_order.size()
	if p < 0:
		p += queue_manager.turn_order.size()
	return queue_manager.turn_order[p]

## Respond to color request only if this bot owns the wild selection
func _on_color_request() -> void:
	if queue_manager == null or hand_card_holder == null or card_manager == null:
		return
	if queue_manager.wild_color_owner != hand_card_holder:
		return
	await get_tree().create_timer(0.2).timeout
	Signals.COLOR_color_selected.emit(choose_best_wild_color())

## Choose wild color using difficulty+personality weighting and opponent weakness + neighbor awareness
func choose_best_wild_color() -> CardResource.CardColor:
	if difficulty == AIDifficulty.OMEGA:
		return _omega_choose_best_wild_color()
	
	var my_counts := count_colors_in_hand()
	var my_total := 0
	for k in my_counts.keys():
		my_total += int(my_counts[k])
	
	var cfg = _diff_cfg.get(difficulty, _diff_cfg[AIDifficulty.SMART])
	var pcfg = _pers_cfg.get(personality, _pers_cfg[AIPersonality.BALANCED])
	
	var next_holder := get_next_holder()
	var next_is_threat := next_holder != null and next_holder.get_child_count() <= 2
	
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
		
		if next_is_threat:
			score += (50 - opp) * (int(cfg["neighbor_focus"]) / 40)
		
		if personality == AIPersonality.COLOR_MONARCH and mine > 0:
			score += mine * (int(pcfg["color_focus"]) / 2)
		
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

func _omega_choose_best_card(playable: Array[CardView]) -> CardView:
	var best := playable[0]
	var best_score := -999999
	
	for cv in playable:
		var s := _omega_score_move(cv)
		if s > best_score:
			best_score = s
			best = cv
	
	return best

func _omega_score_move(card_view: CardView) -> int:
	if card_view == null or card_view.card_res == null:
		return -999999
	
	if _omega_is_immediate_win(card_view):
		return 999999999
	
	var force2 := _omega_can_force_win_in_two(card_view)
	var card := card_view.card_res
	
	var my_count := hand_card_holder.get_child_count()
	var endgame := my_count <= 4
	var hard_lock := my_count <= 2
	
	var next_holder := get_next_holder()
	var prev_holder := get_prev_holder()
	
	var next_cards := (next_holder.get_child_count() if next_holder != null else 9999)
	var prev_cards := (prev_holder.get_child_count() if prev_holder != null else 9999)
	
	var next_is_threat := next_cards <= 2
	var prev_is_threat := prev_cards <= 2
	
	var global_threat_cards := get_most_threatening_opponent_cards()
	var global_low := global_threat_cards <= 2
	
	var win_push := (20 - my_count) * 70
	var s := 0
	
	s += win_push
	
	if endgame:
		s += 900
		s += (5 - my_count) * 200
	
	if force2:
		s += 450000
	
	if global_low:
		s += 1800
	
	var same_color_count := count_specific_color_in_hand(card.color)
	
	match card.type:
		CardResource.CardType.NUMBER:
			s += 60
			s += (9 - card.value) * 8
			if endgame:
				s += 350
		
		CardResource.CardType.SKIP:
			s += 1200
			if next_is_threat:
				s += 5500
			elif global_low:
				s += 2400
			if endgame:
				s += 1800
		
		CardResource.CardType.REVERSE:
			s += 900
			
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				s += 4000
			
			if _omega_reverse_is_kill_move():
				s += 7000
			
			if global_low:
				if next_is_threat:
					s += 2500
				if prev_is_threat:
					s -= 2200
			
			if endgame:
				s += 1400
		
		CardResource.CardType.DRAW:
			s += 1500 + int(card.value) * 260
			
			if next_is_threat:
				s += 7000 + int(card.value) * 230
			elif global_low:
				s += 2800
			
			if queue_manager != null and queue_manager.draw_stack_amount > 0:
				if _omega_is_good_stack_extension(card):
					s += 12000 + int(card.value) * 1200
				else:
					s -= 14000
			
			if endgame:
				s += 2000
		
		CardResource.CardType.WILD:
			s += 1300
			
			if next_is_threat:
				s += 3800
			elif global_low:
				s += 2000
			
			if endgame:
				s += 2200
		
		CardResource.CardType.WILD_DRAW:
			s += 4200 + int(card.value) * 520
			
			if next_is_threat:
				s += 11000
			elif global_low:
				s += 4200
			
			if endgame:
				s += 3200
		
		CardResource.CardType.PLACE_ALL:
			s += 1600 + same_color_count * 480
			
			if next_is_threat:
				s += 4200
			elif global_low:
				s += 2400
			
			if same_color_count <= 1:
				s -= 20000
			
			if endgame:
				s += 3500 + same_color_count * 280
	
	if global_low:
		if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.WILD_DRAW:
			s += 12000
		if card.type == CardResource.CardType.SKIP:
			s += 9000
		if card.type == CardResource.CardType.REVERSE:
			s += 6000
	
	if hard_lock:
		if card.type == CardResource.CardType.SKIP:
			s += 40000
		if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.WILD_DRAW:
			s += 50000
		if card.type == CardResource.CardType.REVERSE:
			s += 25000
		if card.type == CardResource.CardType.WILD:
			s += 20000
		if card.type == CardResource.CardType.PLACE_ALL and same_color_count >= 2:
			s += 35000
	
	s += _omega_minimax_penalty_after_move(card_view)
	
	return s

func _omega_minimax_penalty_after_move(chosen: CardView) -> int:
	if queue_manager == null or hand_card_holder == null:
		return 0
	
	var next_holder := get_next_holder()
	if next_holder == null:
		return 0
	
	var opp_best := _omega_estimate_opponent_best_response(next_holder)
	return -opp_best

func _omega_estimate_opponent_best_response(holder: HandCardHolder) -> int:
	if holder == null or card_manager == null:
		return 0
	
	var playable: Array[CardResource] = []
	for c in holder.get_children():
		if c is CardView and c.card_res != null:
			if holder.can_play_card(c.card_res):
				playable.append(c.card_res)
	
	if playable.is_empty():
		return 0
	
	var best := 0
	for cr in playable:
		var s := _omega_estimate_threat_value(cr, holder)
		if s > best:
			best = s
	
	return best

func _omega_estimate_threat_value(card: CardResource, holder: HandCardHolder) -> int:
	if card == null:
		return 0
	
	var holder_count := holder.get_child_count()
	var is_threat := holder_count <= 2
	
	var s := 0
	
	match card.type:
		CardResource.CardType.DRAW:
			s += 700 + int(card.value) * 140
		CardResource.CardType.WILD_DRAW:
			s += 1000 + int(card.value) * 180
		CardResource.CardType.SKIP:
			s += 850
		CardResource.CardType.REVERSE:
			s += 550
		CardResource.CardType.WILD:
			s += 650
		CardResource.CardType.PLACE_ALL:
			s += 600
		_:
			s += 180
	
	if is_threat:
		s += 900
	
	return s

func _omega_choose_best_place_all_finisher(candidates: Array[CardView]) -> CardView:
	var best := candidates[0]
	var best_score := -999999
	
	var next_holder := get_next_holder()
	var next_threat := next_holder != null and next_holder.get_child_count() <= 2
	var endgame := hand_card_holder.get_child_count() <= 4
	
	for cv in candidates:
		if cv == null or cv.card_res == null:
			continue
		
		var s := 0
		var card := cv.card_res
		
		match card.type:
			CardResource.CardType.DRAW:
				s += 1600 + int(card.value) * 240
			CardResource.CardType.SKIP:
				s += 1800
			CardResource.CardType.REVERSE:
				s += 900
			CardResource.CardType.NUMBER:
				s += 200 + (9 - card.value) * 8
		
		if next_threat:
			if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.SKIP:
				s += 1500
		
		if endgame:
			s += 900
			if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.SKIP:
				s += 900
		
		if s > best_score:
			best_score = s
			best = cv
	
	return best

func _omega_choose_best_wild_color() -> CardResource.CardColor:
	if queue_manager == null:
		return CardResource.CardColor.RED
	
	var my_counts := count_colors_in_hand()
	
	var best_color := CardResource.CardColor.RED
	var best_score := -999999
	
	var next_holder := get_next_holder()
	var next_is_threat := next_holder != null and next_holder.get_child_count() <= 2
	
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var mine := int(my_counts.get(color, 0))
		var opp := get_opponent_color_count(color)
		
		var score := 0
		score += mine * 60
		score += (60 - opp) * 25
		
		if next_is_threat:
			score += (60 - opp) * 20
		
		if mine <= 0:
			score -= 100
		
		if score > best_score:
			best_score = score
			best_color = color
	
	return best_color

func _omega_is_immediate_win(card_view: CardView) -> bool:
	if hand_card_holder == null:
		return false
	if card_view == null or card_view.card_res == null:
		return false
	var my_count := hand_card_holder.get_child_count()
	return my_count <= 1

func _omega_can_force_win_in_two(chosen: CardView) -> bool:
	if chosen == null or chosen.card_res == null:
		return false
	if hand_card_holder == null or queue_manager == null or card_manager == null:
		return false
	
	var my_count := hand_card_holder.get_child_count()
	if my_count > 3:
		return false
	
	var state := _omega_simulate_after_move_state(chosen, hand_card_holder)
	if state.is_empty():
		return false
	
	var next_holder := get_next_holder()
	if next_holder == null:
		return false
	
	var opp_best_value := _omega_estimate_opponent_best_response(next_holder)
	if opp_best_value >= 1600:
		return false
	
	var still_my_turn_after := false
	if chosen.card_res.type == CardResource.CardType.SKIP:
		still_my_turn_after = true
	if chosen.card_res.type == CardResource.CardType.DRAW:
		still_my_turn_after = true
	if chosen.card_res.type == CardResource.CardType.WILD_DRAW:
		still_my_turn_after = true
	
	if still_my_turn_after:
		return _omega_holder_has_any_playable_card_for_state(hand_card_holder, state, true)
	
	return _omega_holder_has_any_playable_card_for_state(hand_card_holder, state, false)

func _omega_simulate_after_move_state(card_view: CardView, holder: HandCardHolder) -> Dictionary:
	if card_view == null or card_view.card_res == null:
		return {}
	if holder == null:
		return {}
	
	var res := card_view.card_res
	var top := card_manager.top_card
	var current_color := card_manager.current_color
	
	var new_top := res
	var new_color := current_color
	
	if res.type == CardResource.CardType.WILD or res.type == CardResource.CardType.WILD_DRAW:
		new_color = _omega_choose_best_wild_color()
	else:
		new_color = res.color
	
	var dict := {
		"top_type": new_top.type,
		"top_value": new_top.value,
		"top_color": new_top.color,
		"current_color": new_color
	}
	
	return dict

func _omega_holder_has_any_playable_card_for_state(holder: HandCardHolder, state: Dictionary, must_win_now: bool) -> bool:
	if holder == null:
		return false
	if typeof(state) != TYPE_DICTIONARY:
		return false
	
	var target_count := holder.get_child_count() - 1
	
	for c in holder.get_children():
		if c is CardView and c.card_res != null:
			if _omega_can_play_card_in_state(c.card_res, state):
				if must_win_now and target_count != 0:
					continue
				if target_count == 0:
					return true
				if target_count == 1:
					return true
	
	return false

func _omega_can_play_card_in_state(card_res: CardResource, state: Dictionary) -> bool:
	if card_res == null:
		return false
	
	var current_color = state.get("current_color", CardResource.CardColor.RED)
	var top_type := int(state.get("top_type", CardResource.CardType.NUMBER))
	var top_value := int(state.get("top_value", 0))
	
	if card_res.type == CardResource.CardType.WILD or card_res.type == CardResource.CardType.WILD_DRAW:
		return true
	
	if card_res.color == current_color and card_res.color != CardResource.CardColor.BLACK:
		return true
	
	if card_res.type == top_type and card_res.type != CardResource.CardType.NUMBER:
		if card_res.type == CardResource.CardType.DRAW:
			return card_res.color == current_color
		return true
	
	if card_res.type == CardResource.CardType.NUMBER and top_type == CardResource.CardType.NUMBER and card_res.value == top_value:
		return true
	
	return false

func _omega_is_good_stack_extension(card: CardResource) -> bool:
	if queue_manager == null:
		return false
	if queue_manager.draw_stack_amount <= 0:
		return false
	if queue_manager.draw_stack_is_wild:
		return false
	if card == null:
		return false
	if card.type != CardResource.CardType.DRAW:
		return false
	
	if card.color != queue_manager.draw_stack_color:
		return false
	
	if card.value < queue_manager.draw_stack_min_value:
		return false
	
	return true

func _omega_reverse_is_kill_move() -> bool:
	var next_holder := get_next_holder()
	var prev_holder := get_prev_holder()
	if next_holder == null or prev_holder == null:
		return false
	
	var next_cards := next_holder.get_child_count()
	var prev_cards := prev_holder.get_child_count()
	
	if next_cards <= 2 and prev_cards > 2:
		return true
	
	return false
