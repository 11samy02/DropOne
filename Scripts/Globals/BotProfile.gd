extends Resource
class_name BotProfile

@export var name: String = "Bot"

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
@export var difficulty: KIController.AIDifficulty = KIController.AIDifficulty.SMART
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
@export var personality: KIController.AIPersonality = KIController.AIPersonality.BALANCED
