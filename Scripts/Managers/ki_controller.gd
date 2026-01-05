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
## - Uses full information + peek + opponent scanning
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
			"punish_low": 999,
			"save_wild": 250,
			"save_wild_draw": 450,
			"prefer_normal": 0,
			"prefer_action": 250,
			"prefer_draw": 450,
			"prefer_skip_reverse": 550,
			"stack_skill": 1000,
			"color_lock": 850,
			"hand_dump": 900,
			"avoid_help_opponents": 1000,
			"neighbor_focus": 1200,
			"endgame_focus": 2000,
			"omega_depth": 4
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

func get_playable_cards() -> Array[CardView]:
	var arr: Array[CardView] = []
	for c in hand_card_holder.get_children():
		if c is CardView:
			if hand_card_holder.can_play_card(c.card_res):
				arr.append(c)
	return arr

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

func count_specific_color_in_hand(color: CardResource.CardColor) -> int:
	var count := 0
	for c in hand_card_holder.get_children():
		if c is CardView and c.card_res != null:
			if c.card_res.color == color:
				count += 1
	return count

func get_most_threatening_opponent_cards() -> int:
	if queue_manager == null:
		return 9999
	var best := 9999
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		best = min(best, h.get_child_count())
	return best

func count_colors_in_hand() -> Dictionary:
	var counts := {}
	for c in hand_card_holder.get_children():
		if c is CardView:
			var col = c.card_res.color
			if col == CardResource.CardColor.BLACK:
				continue
			counts[col] = counts.get(col, 0) + 1
	return counts

func get_best_color_from_counts(counts: Dictionary) -> CardResource.CardColor:
	var best_color := CardResource.CardColor.RED
	var best_count := -1
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var v := int(counts.get(color, 0))
		if v > best_count:
			best_count = v
			best_color = color
	return best_color

func is_any_opponent_low_cards(max_cards: int = 2) -> bool:
	if queue_manager == null:
		return false
	for h in queue_manager.turn_order:
		if h == hand_card_holder:
			continue
		if h.get_child_count() <= max_cards:
			return true
	return false

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

func _on_color_request() -> void:
	if queue_manager == null or hand_card_holder == null or card_manager == null:
		return
	if queue_manager.wild_color_owner != hand_card_holder:
		return
	await get_tree().create_timer(0.2).timeout
	Signals.COLOR_color_selected.emit(choose_best_wild_color())

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
	
	var card := card_view.card_res
	
	var my_count := hand_card_holder.get_child_count()
	var endgame := my_count <= 4
	var hard_lock := my_count <= 2
	var early_game := my_count >= 6
	
	var next_holder := get_next_holder()
	var prev_holder := get_prev_holder()
	
	var next_cards := (next_holder.get_child_count() if next_holder != null else 9999)
	var next_is_one := next_cards == 1
	var prev_cards := (prev_holder.get_child_count() if prev_holder != null else 9999)
	
	var next_is_threat := next_cards <= 2

	var prev_is_threat := prev_cards <= 2
	
	var global_threat_cards := get_most_threatening_opponent_cards()
	var global_low := global_threat_cards <= 2
	
	var my_colors := count_colors_in_hand()
	var my_best_color := get_best_color_from_counts(my_colors)
	var is_my_best_color := card.color == my_best_color and card.color != CardResource.CardColor.BLACK
	var same_color_count := count_specific_color_in_hand(card.color)
	
	var s := 0
	
	
	if next_is_one:
		if card.type == CardResource.CardType.NUMBER:
			s -= 120000
		if card.type == CardResource.CardType.SKIP:
			s += 250000
		if card.type == CardResource.CardType.DRAW:
			s += 300000 + int(card.value) * 25000
		if card.type == CardResource.CardType.WILD_DRAW:
			s += 450000 + int(card.value) * 50000
		if card.type == CardResource.CardType.WILD:
			s += 200000
		if card.type == CardResource.CardType.REVERSE:
			s += 150000
	
	s += (25 - my_count) * 75
	
	if endgame:
		s += 3500
		s += (6 - my_count) * 900
	
	if global_low:
		s += 5000
	
	var peek_bonus := _omega_peek_bonus_for_card(card)
	s += peek_bonus
	
	match card.type:
		CardResource.CardType.NUMBER:
			s += 800
			s += (9 - card.value) * 30
			if is_my_best_color:
				s += 2200
			if early_game and is_my_best_color:
				s += 1800
			if endgame:
				s += 1600
		
		CardResource.CardType.SKIP:
			s += 6000
			if next_is_threat:
				s += 22000
			elif global_low:
				s += 12000
			if endgame:
				s += 15000
		
		CardResource.CardType.REVERSE:
			s += 4200
			
			if queue_manager != null and queue_manager.turn_order.size() == 2:
				s += 15000
			
			if _omega_reverse_is_kill_move():
				s += 22000
			
			if global_low:
				if next_is_threat:
					s += 12000
				if prev_is_threat:
					s -= 10000
			
			if endgame:
				s += 8000
		
		CardResource.CardType.DRAW:
			s += 12000 + int(card.value) * 2500
			
			if early_game:
				s -= 2500
			
			if next_is_threat:
				s += 32000 + int(card.value) * 3500
			elif global_low:
				s += 14000
			
			if queue_manager != null and queue_manager.draw_stack_amount > 0:
				if _omega_stack_move_is_valid_by_rules(card):
					s += 60000
					s += int(card.value) * 9000
				else:
					s -= 250000
			
			if endgame:
				s += 25000
		
		CardResource.CardType.WILD:
			s += 15000
			
			if early_game:
				s -= 6000
			
			if next_is_one:
				s += 200000
			
			if next_is_threat:
				s += 24000
			elif global_low:
				s += 15000
			
			if is_my_best_color:
				s += 3500
			
			if endgame:
				s += 32000
			
			

		
		CardResource.CardType.WILD_DRAW:
			s += 35000 + int(card.value) * 8000
			
			if early_game:
				s -= 12000
				
			if next_is_one:
				s += 400000

			
			if next_is_threat:
				s += 55000
			elif global_low:
				s += 22000
			
			if endgame:
				s += 65000
		
		CardResource.CardType.PLACE_ALL:
			if same_color_count >= 2 and _omega_has_place_all_finisher(card.color):
				s += 75000 + same_color_count * 15000
			else:
				s -= 50000
			
			if next_is_threat:
				s += 18000
			elif global_low:
				s += 9000
			
			if endgame:
				s += 35000 + same_color_count * 12000
	
	if hard_lock:
		if card.type == CardResource.CardType.SKIP:
			s += 150000
		if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.WILD_DRAW:
			s += 200000
		if card.type == CardResource.CardType.REVERSE:
			s += 90000
		if card.type == CardResource.CardType.WILD:
			s += 85000
		if card.type == CardResource.CardType.PLACE_ALL and same_color_count >= 2:
			s += 120000
	
	return s

func _omega_peek_bonus_for_card(card: CardResource) -> int:
	if card_manager == null:
		return 0
	if !card_manager.has_method("peek_next_cards"):
		return 0
	
	var peek := card_manager.peek_next_cards(4)
	var bonus := 0
	
	for c in peek:
		if c == null:
			continue
		
		if c.type == CardResource.CardType.WILD_DRAW or c.type == CardResource.CardType.DRAW:
			if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.WILD_DRAW:
				bonus += 6500
			if card.type == CardResource.CardType.SKIP or card.type == CardResource.CardType.REVERSE:
				bonus += 3200
		
		if c.type == CardResource.CardType.WILD:
			if card.type == CardResource.CardType.WILD:
				bonus += 2800
	
	return bonus

func _omega_has_place_all_finisher(color: CardResource.CardColor) -> bool:
	for c in hand_card_holder.get_children():
		if c is CardView and c.card_res != null:
			if c.card_res.color == color:
				if c.card_res.type == CardResource.CardType.DRAW or c.card_res.type == CardResource.CardType.SKIP or c.card_res.type == CardResource.CardType.REVERSE:
					return true
	return false

func _omega_stack_move_is_valid_by_rules(card: CardResource) -> bool:
	if queue_manager == null:
		return true
	if queue_manager.draw_stack_amount <= 0:
		return true
	if queue_manager.draw_stack_is_wild:
		return true
	if card == null:
		return false
	if card.type != CardResource.CardType.DRAW:
		return false
	
	var stack_color := queue_manager.draw_stack_color
	var stack_min := queue_manager.draw_stack_min_value
	
	if card.value == stack_min:
		return true
	
	if card.color == stack_color and card.value >= stack_min:
		return true
	
	return false

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
				s += 65000 + int(card.value) * 9000
			CardResource.CardType.SKIP:
				s += 72000
			CardResource.CardType.REVERSE:
				s += 48000
				if queue_manager != null and queue_manager.turn_order.size() == 2:
					s += 42000
			CardResource.CardType.NUMBER:
				s += 8000 + (9 - card.value) * 800
		
		if next_threat:
			if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.SKIP:
				s += 55000
		
		if endgame:
			s += 45000
			if card.type == CardResource.CardType.DRAW or card.type == CardResource.CardType.SKIP:
				s += 35000
		
		if s > best_score:
			best_score = s
			best = cv
	
	return best

func _omega_choose_best_wild_color() -> CardResource.CardColor:
	if _omega_next_player_has_one_card():
		return _omega_choose_blocking_color_against_next_player()

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
		score += mine * 220
		score += (70 - opp) * 130

		if next_is_threat:
			score += (70 - opp) * 200

		if mine <= 0:
			score -= 5000

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
	return my_count == 1

func _omega_reverse_is_kill_move() -> bool:
	var next_holder := get_next_holder()
	var prev_holder := get_prev_holder()
	if next_holder == null or prev_holder == null:
		return false
	
	var next_cards := next_holder.get_child_count()
	var prev_cards := prev_holder.get_child_count()
	
	if next_cards == 1 and prev_cards > 1:
		return true
	
	if next_cards <= 2 and prev_cards > 2:
		return true
	
	return false


func _omega_next_player_card_count() -> int:
	var next_holder := get_next_holder()
	if next_holder == null:
		return 9999
	return next_holder.get_child_count()

func _omega_next_player_has_one_card() -> bool:
	return _omega_next_player_card_count() == 1

func _omega_get_next_player_color_counts() -> Dictionary:
	var next_holder := get_next_holder()
	var counts := {
		CardResource.CardColor.RED: 0,
		CardResource.CardColor.GREEN: 0,
		CardResource.CardColor.BLUE: 0,
		CardResource.CardColor.YELLOW: 0
	}
	if next_holder == null:
		return counts
	
	for c in next_holder.get_children():
		if c is CardView and c.card_res != null:
			var col = c.card_res.color
			if col != CardResource.CardColor.BLACK:
				counts[col] += 1

	return counts

func _omega_choose_blocking_color_against_next_player() -> CardResource.CardColor:
	var counts := _omega_get_next_player_color_counts()
	var best_color := CardResource.CardColor.RED
	var best_count := 999999
	for color in [CardResource.CardColor.RED, CardResource.CardColor.GREEN, CardResource.CardColor.BLUE, CardResource.CardColor.YELLOW]:
		var v := int(counts[color])
		if v < best_count:
			best_count = v
			best_color = color

	return best_color
