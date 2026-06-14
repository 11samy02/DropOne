extends Node

## Emitted when a wild card needs a color choice from the local human player.
signal COLOR_request_color_select
## Emitted when a color has been chosen for a wild or roulette pick.
signal COLOR_color_selected(color : CardResource.CardColor)
## Emitted when the color picker UI should close without a new selection.
signal COLOR_color_select_dismissed

## Emitted to open target selection UI; `multi` means all-other-players effects.
signal TARGET_request_target_select(from_holder: HandCardHolder, multi: bool)
## Emitted when the local player picked a target opponent holder.
signal TARGET_target_selected(target_holder: HandCardHolder)

## Emitted when the draw-deck button is pressed during a valid draw action.
signal DECK_draw_pressed
## Emitted whenever the active turn holder changes.
signal TURN_changed(holder)
## Emitted when play direction reverses (+1 forward, -1 reverse).
signal MATCH_direction_changed(direction: int)

enum FeedbackKind {
	BLOCKED,
	SKIPPED,
	INVALID,
	ELIMINATED,
	COLOR,
	WAIT,
	ALREADY_PLAYED,
}

## Short-lived popup with text and icon chosen from FeedbackKind.
signal FEEDBACK_show(text: String, kind: int)

## Emitted when the profile creator picks an avatar texture and index.
signal PROFILE_set_picture(texture: Texture2D, id: int)
