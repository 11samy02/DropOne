extends Node

signal COLOR_request_color_select
signal COLOR_color_selected(color : CardResource.CardColor)

signal TARGET_request_target_select(from_holder: HandCardHolder, multi: bool)
signal TARGET_target_selected(target_holder: HandCardHolder)

signal DECK_draw_pressed
signal TURN_changed(holder)
